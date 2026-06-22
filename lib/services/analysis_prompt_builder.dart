import '../aliyun/emas_appmonitor_client.dart';
import 'agent_launcher.dart';
import 'gitlab_client.dart';
import 'stack_clarity.dart';

/// 复制/CLI 等仅携带 user 消息时前置，避免缺少 system 中的 MCP 说明。
const String kStandaloneGitlabMcpUserHint = '【GitLab】若当前环境已启用 GitLab MCP，请优先用 MCP 查仓库；'
    '下文「GitLab 内置检索」仅为本工具 REST 补充。\n\n';

String _trimForPrompt(String s, int max) {
  final t = s.trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max)}…';
}

/// 将 GitLab 命中压缩进提示词（避免过长）。
String formatGitlabContextForPrompt(List<GitLabBlobHit> hits, List<GitLabCommitInfo> commits) {
  if (hits.isEmpty && commits.isEmpty) return '';

  final buf = StringBuffer();
  buf.writeln('\n【GitLab 内置检索补充（非 MCP；对照业务代码；片段可能不完整）】');
  var i = 0;
  for (final h in hits) {
    if (i >= 6) break;
    i++;
    final repo = h.configRepoLabel?.trim();
    final repoBit = (repo != null && repo.isNotEmpty) ? '[$repo] ' : '';
    buf.writeln('- $repoBit文件：${h.path ?? h.basename ?? '-'}');
    final snippet = (h.data ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (snippet.isNotEmpty) {
      buf.writeln('  命中片段：${_trimForPrompt(snippet, 420)}');
    }
  }
  if (commits.isNotEmpty) {
    final devLine = gitCommitAuthorsSummaryLine(commits);
    if (devLine.isNotEmpty) {
      buf.writeln('\n$devLine（以下提交摘自 GitLab 该路径近期历史）');
    }
    buf.writeln('\n首命中文件近期提交（供判断变更背景）：');
    for (final c in commits.take(4)) {
      buf.writeln('- ${c.title ?? '-'} · ${c.authorName ?? ''} ${c.committedDate ?? ''}');
    }
  }
  return buf.toString();
}

String _trimForAggregatePrompt(String? s, int max) {
  final t = (s ?? '').trim();
  if (t.isEmpty) return '';
  if (t.length <= max) return t;
  return '${t.substring(0, max)}…';
}

/// 当前列表前 N 条合并为**单次**大模型请求的 user 消息（堆栈取自列表接口摘录）。
String buildTopNAggregateUserMessage({
  required List<IssueListItem> issues,
  required String bizModule,
  required int rangeStartMs,
  required int rangeEndMs,
  int maxStackCharsPerItem = 720,
}) {
  if (issues.isEmpty) return '';
  final buf = StringBuffer();
  buf.writeln(
    '【输入说明】以下为 EMAS 聚合列表中按**当前列表顺序**取出的前 ${issues.length} 条（通常为次数/影响降序；以接口返回为准）。'
    '堆栈文本来自列表侧摘录，可能短于单条 GetIssue。BizModule=$bizModule，时间范围(ms)：$rangeStartMs ~ $rangeEndMs。\n',
  );
  for (var i = 0; i < issues.length; i++) {
    final it = issues[i];
    final d = it.digestHash?.trim() ?? '';
    buf.writeln('======== 第 ${i + 1} / ${issues.length} 条 ========');
    buf.writeln('Digest: $d');
    buf.writeln('ErrorName: ${it.errorName ?? ''}');
    final et = it.errorType?.trim();
    if (et != null && et.isNotEmpty) buf.writeln('ErrorType: $et');
    if (it.errorCount != null) buf.writeln('ErrorCount: ${it.errorCount}');
    if (it.errorDeviceCount != null) buf.writeln('ErrorDeviceCount: ${it.errorDeviceCount}');
    final fv = it.firstVersion?.trim();
    if (fv != null && fv.isNotEmpty) buf.writeln('FirstVersion: $fv');
    final st = _trimForAggregatePrompt(it.stack, maxStackCharsPerItem);
    buf.writeln('Stack（摘录）:\n${st.isEmpty ? '（无）' : st}');
    buf.writeln();
  }
  buf.writeln('''
----------
【总览分析任务】
请基于以上 ${issues.length} 条聚合问题输出**一份合并总览报告**（简体中文）。严格使用下列二级标题（字面一致），小节内可用列表与短代码；**不要编造**未出现在摘录中的类路径或文件名。

## 概览
（本批条数、时间口径、Biz 含义；若堆栈偏少请说明）

## 共性与聚类
（异常类型、可疑公共根因、模块/包层面线索）

## 单条要点速览
（每条 1–3 行，**必须带 Digest**，突出差异点）

## 优先级与行动建议
（排查/修复优先级、建议补充的信息、验证与回归要点）

## 局限与待补充
（若需单条 GetIssue 深度与代码仓对照，请列出建议动作）
''');
  return buf.toString();
}

String analysisDirectiveForClarity(StackClarity clarity, {required bool hasGitlabHits}) {
  switch (clarity.level) {
    case StackClarityLevel.businessLikely:
      if (hasGitlabHits) {
        return '当前判断堆栈**较可能定位业务代码**，且已提供上文「GitLab 内置检索」摘录。**若你具备 GitLab MCP 工具，请优先用 MCP 再核实路径与实现**；再结合摘录，在「原因说明」「修复方案」「建议代码变更」中给出**可落地的模块/类/方法级**推断与修改建议；若行号不确定，说明需补充的日志或断点。不要编造未出现在堆栈/GitLab 中的类名。';
      }
      return '当前判断堆栈**较可能包含业务包/类**，且未带内置检索命中。**若已启用 GitLab MCP，请优先用 MCP 在仓库中搜索栈内类名/包路径**；否则根据堆栈推断**可能责任模块与修改思路**，并写出建议的**搜索关键词**；**禁止**虚构项目内文件路径。';
    case StackClarityLevel.systemFrameworkDominant:
      return '当前堆栈**以系统或框架代码为主**，缺少明确业务源。请**不要**编造具体业务文件名。在「原因说明」归纳疑似触发场景（生命周期、线程、Binder、资源、系统回调等）；「修复方案」给出业务侧排查清单、配置与容错；「建议代码变更」可用伪代码或防护模式，并注明需结合业务代码再落地。';
    case StackClarityLevel.unknown:
      return '堆栈信息不足或格式未识别。请基于 GetIssue JSON 其它字段保守推断，并列出为定位需补充的信息（复现步骤、符号表、自定义日志点等）。不要虚构路径。';
  }
}

/// 生成「生成 AI 分析」/复制提示词用的完整 user 消息。
String buildAnalysisUserPrompt({
  required String digestHash,
  required Map<String, dynamic>? getIssueBody,
  String? listTitle,
  String? listStack,
  required StackClarity clarity,
  List<GitLabBlobHit> gitlabHits = const [],
  List<GitLabCommitInfo> gitlabCommits = const [],
  /// 为 true 时在开头附加 [kStandaloneGitlabMcpUserHint]（复制到剪贴板 / 仅发 user 给 CLI 时使用；走 Chat API 且已带 [ToolConfig.effectiveLlmSystemPrompt] 时请为 false）。
  bool prependGitlabMcpHint = false,
}) {
  final base = AgentLauncher.buildPromptFromIssue(
    digestHash: digestHash,
    getIssueBody: getIssueBody,
    listTitle: listTitle,
    listStack: listStack,
  );
  final buf = StringBuffer();
  if (prependGitlabMcpHint) buf.write(kStandaloneGitlabMcpUserHint);
  buf.write(base);
  buf.writeln('\n----------\n【堆栈可解读性（工具自动判断，供你参考）】\n${clarity.summaryForPrompt}');
  if (clarity.appFrameSamples.isNotEmpty) {
    buf.writeln('\n业务相关栈线索示例：');
    for (final s in clarity.appFrameSamples) {
      buf.writeln('- $s');
    }
  }
  final gl = formatGitlabContextForPrompt(gitlabHits, gitlabCommits);
  if (gl.isNotEmpty) buf.write(gl);
  buf.writeln('\n----------\n【分析要求】\n${analysisDirectiveForClarity(clarity, hasGitlabHits: gitlabHits.isNotEmpty)}');
  return buf.toString();
}
