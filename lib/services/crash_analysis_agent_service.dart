import 'dart:convert';

import '../models/tool_config.dart';
import 'agent_engine.dart';
import 'agent_tool_registry.dart';
import 'http_retry_policy.dart';
import 'llm_client.dart';
import 'outbound_http_client_for_config.dart';

/// 崩溃分析 Agent 结果（结构化 JSON，供报告生成消费）。
class CrashAnalysisResult {
  CrashAnalysisResult({
    required this.summary,
    required this.rootCause,
    required this.possibleCauses,
    required this.fixSuggestions,
    this.investigation = '',
    this.sourceAnalysis = '',
    this.conclusion = '',
    this.toolTrace = '',
    this.raw,
    this.error,
  });

  final String summary;
  final String rootCause;
  final List<CauseAnalysis> possibleCauses;
  final List<FixSuggestion> fixSuggestions;

  /// 分析过程/思路（模型如何逐步排查）。
  final String investigation;

  /// 结合源码的分析（关键类/方法/代码位置）。
  final String sourceAnalysis;

  /// 最终结论。
  final String conclusion;

  /// Agent 实际调用的工具轨迹（grep/read 了哪些源码文件），用于报告追溯。
  String toolTrace;

  final String? raw;

  /// 非空表示分析失败（如 LLM 认证失败/调用异常），summary 内为可展示的错误说明。
  final String? error;

  bool get isError => error != null && error!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'root_cause': rootCause,
        'investigation': investigation,
        'source_analysis': sourceAnalysis,
        'conclusion': conclusion,
        'possible_causes': possibleCauses.map((e) => e.toJson()).toList(),
        'fix_suggestions': fixSuggestions.map((e) => e.toJson()).toList(),
      };
}

class CauseAnalysis {
  CauseAnalysis({required this.cause, required this.detail, required this.evidence});
  final String cause;
  final String detail;
  final List<String> evidence;

  Map<String, dynamic> toJson() => {
        'cause': cause,
        'detail': detail,
        'evidence': evidence,
      };
}

class FixSuggestion {
  FixSuggestion({
    required this.suggestion,
    required this.priority,
    required this.implementation,
    this.file,
    this.codeDiff,
  });
  final String suggestion;
  final String priority;
  final String implementation;
  final String? file;
  final String? codeDiff;

  Map<String, dynamic> toJson() => {
        'suggestion': suggestion,
        'priority': priority,
        'implementation': implementation,
        if (file != null && file!.isNotEmpty) 'file': file,
        if (codeDiff != null && codeDiff!.isNotEmpty) 'code_diff': codeDiff,
      };
}

/// 崩溃分析 Agent 服务。
///
/// 将「单一 LLM 调用」升级为「自主 Agent」：投喂堆栈 + 分段 tombstone 日志，
/// 指向本地源码仓库（[ToolConfig.localProjectPath]），模型可自主调用
/// read_file / grep / search_files / list_directory 获取源码，最终产出结构化报告。
class CrashAnalysisAgentService {
  CrashAnalysisAgentService({required this.config});

  final ToolConfig config;

  /// 运行崩溃分析 Agent。
  ///
  /// [stackInfo] 原始堆栈；[tombstoneContent] 整个 tombstone 文件内容；
  /// [userSample] 用户样本信息；[crashLogFileData] 华佗 crashLogFile 数据。
  /// [enableSourceAnalysis] 为 true 时启用本地源码检索工具（源码智能分析），
  /// 默认 false：HTML 报告生成阶段只基于堆栈/tombstone 分析，不读源码。
  Future<CrashAnalysisResult> analyze({
    required String digestHash,
    required String stackInfo,
    required String tombstoneContent,
    Map<String, dynamic>? userSample,
    Map<String, dynamic>? crashLogFileData,
    bool enableSourceAnalysis = false,
  }) async {
    if (!_isConfigured) {
      return _fallbackResult();
    }

    final projectPath = config.localProjectPath.trim();
    final canUseSource = enableSourceAnalysis && projectPath.isNotEmpty;

    // 仅在源码分析模式下挂载本地源码工具；基础分析不读源码。
    final registry = canUseSource
        ? AgentToolRegistry.createStandard(
            config: config,
            projectPath: projectPath,
          )
        : AgentToolRegistry(config: config, projectPath: projectPath.isEmpty ? '.' : projectPath);

    final client = LlmClient(
      baseUrl: config.llmBaseUrl.trim(),
      apiKey: config.llmApiKey.trim(),
      model: config.llmModel.trim(),
      chatCompletionsPath: config.effectiveLlmChatPath,
      httpClient: newOutboundHttpClient(),
    );

    final engine = AgentEngine(
      llmClient: client,
      toolRegistry: registry,
      systemPrompt: _buildSystemPrompt(sourceMode: canUseSource),
      maxToolIterations: canUseSource ? 16 : 6,
      temperature: 0.3,
    );

    final userMessage = _buildUserMessage(
      digestHash: digestHash,
      stackInfo: stackInfo,
      tombstoneContent: tombstoneContent,
      userSample: userSample,
      crashLogFileData: crashLogFileData,
      sourceMode: canUseSource,
    );

    try {
      final finalContent = StringBuffer();
      final traceBuf = StringBuffer();
      await for (final step in engine.chat(userMessage)) {
        if (step.type == 'tool_call') {
          final p = step.toolParams ?? const {};
          traceBuf.writeln('- 调用 ${step.toolName}: ${const JsonEncoder().convert(p)}');
        } else if (step.type == 'tool_result') {
          final r = step.toolResult ?? '';
          traceBuf.writeln('  → ${r.length > 200 ? r.substring(0, 200) : r}');
        } else if (step.type == 'response' && step.content != null) {
          finalContent.write(step.content);
        }
      }

      final response = finalContent.toString();
      final result = _parseResult(response);
      result.toolTrace = traceBuf.toString();
      return result;
    } catch (e) {
      // 不静默返回假分析：把真实失败原因透传到报告，便于定位（认证失败、网络、解析等）。
      return _errorResult('智能分析调用失败：${_friendlyError(e)}');
    } finally {
      client.close();
    }
  }

  /// 源码智能分析：基于已有崩溃报告 + 本地源码仓库做进一步分析。
  ///
  /// [reportContent] 为已生成的崩溃报告（markdown），模型会提取其中的堆栈与结论，
  /// 再结合源码检索给出源码级原因与代码修改建议。
  Future<CrashAnalysisResult> analyzeSource({
    required String digestHash,
    required String reportContent,
  }) async {
    if (!_isConfigured) {
      return _fallbackResult();
    }
    final projectPath = config.localProjectPath.trim();
    if (projectPath.isEmpty) {
      return _errorResult('未配置本地源码仓库路径（配置 → 源码分析 → 本地项目路径），无法进行源码分析。');
    }

    final registry = AgentToolRegistry.createReadOnlySourceTools(
      config: config,
      projectPath: projectPath,
    );

    final client = LlmClient(
      baseUrl: config.llmBaseUrl.trim(),
      apiKey: config.llmApiKey.trim(),
      model: config.llmModel.trim(),
      chatCompletionsPath: config.effectiveLlmChatPath,
      httpClient: newOutboundHttpClient(),
    );

    final engine = AgentEngine(
      llmClient: client,
      toolRegistry: registry,
      systemPrompt: _buildSystemPrompt(sourceMode: true),
      maxToolIterations: 5,
      temperature: 0.3,
    );

    // 只投喂崩溃关键信息（堆栈/tombstone/结论），避免整篇报告导致请求体过大、超时。
    final digest = _extractCrashDigest(reportContent);
    final userMessage = StringBuffer()
      ..writeln('## 崩溃信息（来自已生成报告）')
      ..writeln()
      ..writeln('**Digest Hash**: `$digestHash`')
      ..writeln()
      ..writeln('以下是崩溃的堆栈与 tombstone 关键信息：')
      ..writeln()
      ..writeln('```')
      ..writeln(digest)
      ..writeln('```')
      ..writeln()
      ..writeln('请务必结合本地源码仓库做深度分析：先用 list_directory/grep/search_files 定位相关源码，'
          '再 read_file 阅读关键代码，给出具体的根因、源码证据和代码修改建议。'
          '每个字段都要写充实、具体，不允许只写一句话敷衍。最后输出严格 JSON（源码分析协议）。')
      ..toString();

    try {
      final finalContent = StringBuffer();
      final traceBuf = StringBuffer();
      await for (final step in engine.chat(userMessage.toString())) {
        if (step.type == 'tool_call') {
          final p = step.toolParams ?? const {};
          traceBuf.writeln('- 调用 ${step.toolName}: ${const JsonEncoder().convert(p)}');
        } else if (step.type == 'tool_result') {
          final r = step.toolResult ?? '';
          traceBuf.writeln('  → ${r.length > 200 ? r.substring(0, 200) : r}');
        } else if (step.type == 'response' && step.content != null) {
          finalContent.write(step.content);
        }
      }
      final result = _parseResult(finalContent.toString());
      result.toolTrace = traceBuf.toString();
      return result;
    } catch (e) {
      return _errorResult('源码智能分析调用失败：${_friendlyError(e)}');
    } finally {
      client.close();
    }
  }

  /// 将底层异常转为可读的中文错误。
  String _friendlyError(Object e) {
    // 从重试耗尽异常中提取真实状态码。
    var cause = e;
    if (e is ApiRetryExhaustedException) {
      cause = e.cause;
    }
    final s = cause.toString();
    if (cause is TransientHttpStatusException) {
      final code = cause.statusCode;
      if (code == 429) {
        return '大模型限流（HTTP 429）：当前网关配额/频率已达上限，请等待约 1 分钟后重试。'
            '源码分析涉及多轮请求，短时间内频繁点击容易触发限流。';
      }
      return '大模型网关暂态错误（HTTP $code），请稍后重试。';
    }
    if (e is ApiRetryExhaustedException) {
      return '大模型多次请求均失败（网络超时或网关 5xx/限流）。请稍后重试。';
    }
    if (s.contains('401')) return '大模型认证失败（HTTP 401）：请检查配置里的 API Key / Base URL / 模型名是否匹配。';
    if (s.contains('429')) {
      return '大模型限流（HTTP 429）：请求过于频繁，请稍后重试。';
    }
    return s;
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}\n…(报告截断)';

  /// 从已生成报告中提取崩溃关键信息（堆栈、tombstone、崩溃标题/结论），
  /// 去掉概览表格、分布统计、链接等与源码定位无关的内容，控制请求体大小。
  /// 从已生成报告中截取崩溃详情段（堆栈、样本、tombstone、初步分析），
  /// 去掉概览表格/分布统计和历史「源码分析结果」段；按标题边界截取，不做逐行关键词过滤，避免漏内容。
  String _extractCrashDigest(String report) {
    final lines = report.split('\n');
    var start = 0;
    var end = lines.length;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i].toLowerCase();
      if (l.startsWith('##') && l.contains('崩溃详情')) {
        start = i;
      }
      // 历史源码分析结果段：之前的产物，不重复喂
      if (l.startsWith('##') && l.contains('源码分析结果')) {
        end = i;
        break;
      }
    }
    var text = lines.sublist(start, end).join('\n').trim();
    if (text.isEmpty) text = report;
    return _truncate(text, 12000);
  }

  bool get _isConfigured =>
      config.llmBaseUrl.trim().isNotEmpty &&
      config.llmApiKey.trim().isNotEmpty &&
      config.llmModel.trim().isNotEmpty;

  String _buildSystemPrompt({required bool sourceMode}) {
    final projectPath = config.localProjectPath.trim();

    if (!sourceMode) {
      // 基础分析模式：仅基于堆栈 + tombstone，不读源码。
      return '''
你是一名资深的 Android / iOS 移动应用崩溃分析专家。请仅根据提供的崩溃堆栈和 tombstone 崩溃主日志进行**深入、细致**的分析（本次不检索源码）。

**所有分析内容必须使用简体中文回复。**

## 分析要点

1. 通读堆栈与 tombstone，识别异常类型、崩溃线程、信号、关键系统/第三方库帧。
2. 从堆栈提取最可能出错的业务代码位置（包名/类名/方法名/行号）。
3. 结合 tombstone 崩溃现场（线程状态、内存、寄存器、调用栈、logcat 关键行、用户操作时间线）判断直接原因与触发条件。
4. 仔细推理崩溃发生的代码机理（什么调用了什么、为什么会抛异常/卡死）。
5. 给出基于日志和堆栈可得出的具体修复方向（不臆造源码细节，但要具体、可操作）。

## 输出要求（极其重要）

- 每个字段都必须**充实、具体、有深度**，结合堆栈/tombstone 中的真实信息（类名、方法名、行号、日志行）展开分析。
- 严禁只写一句话敷衍，严禁泛泛而谈。root_cause 至少 4 句话，possible_causes 给 2-3 个并附证据，fix_suggestions 具体可落地。

## 输出协议（严格 JSON）

最后一条回复只能是一个 JSON 对象，直接以 `{` 开头、以 `}` 结尾，不要 Markdown 代码块或额外文字：

{
  "summary": "一句话总结崩溃直接原因（具体到类名/方法）",
  "investigation": "排查思路与过程：从堆栈/tombstone 中看到了哪些关键信息、如何一步步定位（详细分点，引用真实类名/日志）",
  "root_cause": "根本原因分析（结合堆栈与 tombstone 详细说明崩溃机理、触发条件、代码层面发生了什么，至少 4 句）",
  "possible_causes": [
    {"cause": "可能原因", "detail": "详细解释该原因如何导致崩溃", "evidence": ["引用堆栈/tombstone 中的具体证据"]}
  ],
  "fix_suggestions": [
    {"suggestion": "具体修复方案（标题式）", "priority": "high|medium|low", "implementation": "详细修改建议：改什么、怎么改、为什么（源码级细节留待源码分析）"}
  ],
  "conclusion": "结论：崩溃本质、责任模块、修复方向与验证建议"
}
''';
    }

    // 源码深度分析模式：挂载本地源码工具。
    final repoHint = projectPath.isEmpty
        ? '（未配置本地仓库路径）'
        : '（本地仓库根目录：`$projectPath`）';

    // 未自定义提示词时使用内置的学而思项目默认说明。
    final projectHint = config.sourceAnalysisPrompt.trim().isNotEmpty
        ? config.sourceAnalysisPrompt.trim()
        : ToolConfig.defaultSourceAnalysisPrompt;
    final projectSection = projectHint.isEmpty
        ? ''
        : '''

## 项目说明（用户配置，务必据此检索）

$projectHint
''';

    return '''
你是一名资深的 Android / iOS 移动应用崩溃分析专家。你将拿到一份**已有初步分析的崩溃报告**，
任务是结合本地源码仓库 $repoHint，对崩溃做进一步的源码级分析，给出可落地的代码修改建议。

**所有分析内容必须使用简体中文回复。**

$projectSection
## 可用工具（支持项目搜索、文件搜索、内容搜索与读取）

- list_directory(path, recursive, maxDepth)：列出目录/项目结构，先据此了解项目布局
- search_files(pattern, directory)：按文件名/通配符搜索文件（如 *.kt、*Activity*）
- grep(query, path, fileTypes, maxResults)：按关键词/正则在文件**内容**中搜索（类名、方法名、字符串）
- read_file(path)：读取定位到的文件内容做代码级分析

## 分析流程（自主执行，注意高效）

**重要：工具调用要精简高效，总工具调用控制在 3-5 次内，不要反复搜索。**
直接用 grep 搜堆栈中的关键类名/方法名定位（一次 grep 用对关键词即可，通常无需 list_directory 逐层浏览），
找到目标文件后直接 read_file 读取关键片段，随即给出分析结论。

1. 从报告/堆栈中提取应用自身的关键类名、方法名、异常类型（如 StreakFlameCalendarBinder、playTodayTickPag）。
2. 用 grep 搜索该类名（fileTypes 限定 .kt/.java）定位源码文件。
3. 用 read_file 读取目标文件的关键方法，分析缺陷逻辑（空指针、生命周期、并发、跨线程/资源释放等）。
4. 给出具体的代码修改方案，尽量给出修复前后对比。
5. 检索不到时如实说明，不要反复搜索。

## 输出要求（极其重要）

- 你**必须真正调用工具检索和阅读源码**，不能仅凭堆栈臆测；source_analysis 要引用真实读到的代码。
- 每个字段都要**充实、具体、有深度**，结合真实文件路径、类名、方法、代码片段展开。
- 严禁只写一句话敷衍。root_cause 至少 5 句讲清代码机理；source_analysis 要引用具体代码；fix_suggestions 给出可直接落地的实现说明和代码对比。

## 输出协议（严格 JSON）

最后一条回复只能是一个 JSON 对象，直接以 `{` 开头、以 `}` 结尾，不要 Markdown 代码块或额外文字：

{
  "summary": "结合源码后对崩溃原因的一句话总结（具体到类名/方法）",
  "investigation": "源码排查过程：检索了哪些关键词/文件、读到哪些代码、如何一步步定位到缺陷（详细分点）",
  "root_cause": "源码层面的根本原因：具体是哪个文件/类/方法、什么逻辑缺陷导致崩溃，触发链路是什么（至少 5 句）",
  "source_analysis": "定位到的文件/类/方法、关键代码片段及其问题，引用真实读到的源码并标注文件路径",
  "possible_causes": [
    {"cause": "可能原因", "detail": "详细解释", "evidence": ["源码证据", "堆栈证据"]}
  ],
  "fix_suggestions": [
    {
      "suggestion": "修复方案（标题式）",
      "priority": "high|medium|low",
      "implementation": "详细代码级实现说明：改哪个文件/方法、怎么改、为什么",
      "file": "涉及文件路径",
      "code_diff": "修复前后代码对比"
    }
  ],
  "conclusion": "结论：责任模块、缺陷本质、修复要点与验证方法"
}

## 注意事项

- 不确定时优先调用工具读真实源码，不要编造业务文件路径或代码。
- 检索不到源码时如实说明，不要虚构。
- 修改建议要具体到类/方法/代码片段。
''';
  }

  String _buildUserMessage({
    required String digestHash,
    required String stackInfo,
    required String tombstoneContent,
    Map<String, dynamic>? userSample,
    Map<String, dynamic>? crashLogFileData,
    bool sourceMode = false,
  }) {
    final buf = StringBuffer();

    buf.writeln('## 崩溃任务');
    buf.writeln();
    buf.writeln('**Digest Hash**: `$digestHash`');
    buf.writeln();

    buf.writeln('## 1. 崩溃堆栈');
    buf.writeln('```');
    buf.writeln(stackInfo);
    buf.writeln('```');
    buf.writeln();

    if (userSample != null && userSample.isNotEmpty) {
      buf.writeln('## 2. 设备与应用信息');
      buf.writeln('- 用户 ID: ${userSample['user_id'] ?? ''}');
      buf.writeln('- 设备型号: ${userSample['device_model'] ?? ''}');
      buf.writeln('- 应用版本: ${userSample['app_version'] ?? ''}');
      buf.writeln('- 系统版本: ${userSample['system_version'] ?? ''}');
      buf.writeln('- 异常消息: ${userSample['exception_msg'] ?? ''}');
      buf.writeln();
    }

    if (crashLogFileData != null && crashLogFileData.isNotEmpty) {
      buf.writeln('## 3. 华佗 crashLogFile 数据');
      buf.writeln('```json');
      buf.writeln(const JsonEncoder.withIndent('  ').convert(crashLogFileData));
      buf.writeln('```');
      buf.writeln();
    }

    buf.writeln('## 4. tombstone 崩溃主日志');
    if (tombstoneContent.trim().isEmpty) {
      buf.writeln('（本次未下载到 tombstone 日志，请主要依据崩溃堆栈分析）');
    } else {
      // 完整投喂 tombstone；内容过大时分段，避免做激进关键词过滤导致漏信息。
      _writeSegmentedContent(buf, 'tombstone', tombstoneContent);
    }
    buf.writeln();

    if (sourceMode) {
      buf.writeln('请先按需调用工具检索本地源码，完成分析后，'
          '你的最后一条回复只能是一个 JSON 对象（以 { 开头、} 结尾，不要 Markdown 代码块或额外文字）。');
    } else {
      buf.writeln('请基于以上堆栈和 tombstone 仔细、深入地分析，明确结合 tombstone 中的崩溃现场'
          '（崩溃类型、线程、信号、logcat 关键行、用户操作时间线）展开。'
          '务必完整填写所有字段，尤其是 fix_suggestions（至少 2 条具体修复建议）和 possible_causes，不要留空。'
          '你的最后一条回复只能是一个 JSON 对象（以 { 开头、} 结尾，不要 Markdown 代码块或额外文字）。');
    }
    return buf.toString();
  }

  /// 写入 tombstone：完整内容优先；超过单段阈值时分段投喂（不做关键词过滤，避免漏掉关键信息）。
  void _writeSegmentedContent(StringBuffer buf, String label, String content) {
    const segmentSize = 12000;
    if (content.length <= segmentSize) {
      buf.writeln('```');
      buf.writeln(content.trim());
      buf.writeln('```');
      return;
    }

    final chunks = <String>[];
    for (int i = 0; i < content.length; i += segmentSize) {
      final end = (i + segmentSize).clamp(0, content.length);
      chunks.add(content.substring(i, end));
    }

    buf.writeln('（$label 内容较大，共 ${content.length} 字符，分 ${chunks.length} 段投喂，请综合所有片段分析）');
    for (int i = 0; i < chunks.length; i++) {
      buf.writeln();
      buf.writeln('### $label 第 ${i + 1}/${chunks.length} 段');
      buf.writeln('```');
      buf.writeln(chunks[i]);
      buf.writeln('```');
    }
  }


  /// 解析 Agent 返回的结构化 JSON。
  ///
  /// 容忍模型在 JSON 外包裹 ```json 代码块或附带说明文字：剥离代码块标记，
  /// 取最后一个平衡的 JSON 对象（模型常在末尾给出结论）。
  CrashAnalysisResult _parseResult(String response) {
    try {
      var text = response.trim();

      // 剥离 ```json ... ``` / ``` ... ``` 代码块
      final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
      final fenceMatches = fence.allMatches(text).toList();
      if (fenceMatches.isNotEmpty) {
        // 优先用代码块内容
        final inner = fenceMatches.map((m) => m.group(1)?.trim() ?? '').join('\n');
        if (inner.contains('{')) text = inner;
      }

      final data = _extractJsonObject(text);
      if (data == null) {
        throw Exception('未在回复中找到 JSON 对象');
      }
      final parsed = data;

      String pick(List<String> keys) {
        for (final k in keys) {
          final v = parsed[k];
          if (v != null && v.toString().trim().isNotEmpty) return v.toString();
        }
        return '';
      }

      // possible_causes / causes：兼容 List<Map>、List<String>、Map
      final causes = <CauseAnalysis>[];
      final rawCauses = parsed['possible_causes'] ?? parsed['causes'] ?? parsed['possible_reasons'];
      if (rawCauses is List) {
        for (final c in rawCauses) {
          if (c is Map) {
            causes.add(CauseAnalysis(
              cause: (c['cause'] ?? c['reason'] ?? c['title'] ?? '').toString(),
              detail: (c['detail'] ?? c['description'] ?? c['analysis'] ?? '').toString(),
              evidence: _asStringList(c['evidence'] ?? c['evidences'] ?? c['signs']),
            ));
          } else if (c != null && c.toString().trim().isNotEmpty) {
            causes.add(CauseAnalysis(cause: c.toString(), detail: '', evidence: const []));
          }
        }
      }

      // fix_suggestions / suggestions / fixes：兼容 List<Map>、List<String>
      final fixes = <FixSuggestion>[];
      final rawFixes = parsed['fix_suggestions'] ?? parsed['fixes'] ?? parsed['suggestions'] ?? parsed['solutions'];
      if (rawFixes is List) {
        for (final s in rawFixes) {
          if (s is Map) {
            fixes.add(FixSuggestion(
              suggestion: (s['suggestion'] ?? s['title'] ?? s['action'] ?? s['fix'] ?? '').toString(),
              priority: (s['priority'] ?? s['level'] ?? 'medium').toString(),
              implementation: (s['implementation'] ?? s['detail'] ?? s['description'] ?? s['how'] ?? '').toString(),
              file: s['file']?.toString() ?? s['file_path']?.toString(),
              codeDiff: s['code_diff']?.toString() ?? s['codeDiff']?.toString() ?? s['diff']?.toString(),
            ));
          } else if (s != null && s.toString().trim().isNotEmpty) {
            fixes.add(FixSuggestion(suggestion: s.toString(), priority: 'medium', implementation: ''));
          }
        }
      }

      var summary = pick(['summary', 'crash_summary', 'conclusion_summary', 'title']);
      var rootCause = pick(['root_cause', 'rootCause', 'root_cause_analysis', 'cause_analysis', 'stack_trace_analysis']);
      var investigation = pick(['investigation', 'analysis_process', 'troubleshooting', 'analysis']);
      var sourceAnalysis = pick(['source_analysis', 'sourceAnalysis', 'code_analysis']);
      var conclusion = pick(['conclusion', 'final_conclusion', 'verdict']);

      // 兜底：模型用了非标准字段名且 causes/fixes 为空时，把其余有内容的字段汇总，避免报告空白。
      if (causes.isEmpty && fixes.isEmpty && rootCause.isEmpty && investigation.isEmpty) {
        final known = {'summary','crash_summary','crash_type','signal_info','faulting_thread','root_cause',
          'rootCause','investigation','source_analysis','conclusion','possible_causes','causes',
          'fix_suggestions','fixes','suggestions','solutions'};
        final extra = StringBuffer();
        parsed.forEach((k, v) {
          if (known.contains(k)) return;
          final s = v is String ? v.trim() : jsonEncode(v);
          if (s.isNotEmpty && s != 'null' && s != '[]' && s != '{}') {
            extra.writeln('**$k**：$s');
            extra.writeln();
          }
        });
        if (extra.isNotEmpty) {
          rootCause = '以下为模型返回的分析内容：\n\n${extra.toString().trim()}';
        }
      }

      return CrashAnalysisResult(
        summary: summary,
        rootCause: rootCause,
        investigation: investigation,
        sourceAnalysis: sourceAnalysis,
        conclusion: conclusion,
        possibleCauses: causes,
        fixSuggestions: fixes,
        raw: response,
      );
    } catch (e) {
      // 解析失败：返回模型原始回复作为摘要，便于排查（而非误报“未配置”）。
      final snippet = response.trim();
      final preview = snippet.length > 500 ? '${snippet.substring(0, 500)}…' : snippet;
      return _errorResult('模型返回内容无法解析为结构化报告。解析错误：$e\n\n模型原始回复（前 500 字）：\n$preview');
    }
  }

  /// 将 evidence 等字段安全转为字符串列表（兼容 List / String / 单值）。
  List<String> _asStringList(dynamic v) {
    if (v == null) return const [];
    if (v is List) return v.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
    final s = v.toString().trim();
    return s.isEmpty ? const [] : [s];
  }

  /// 从文本中提取最后一个平衡的 JSON 对象（模型可能在 JSON 外附加说明文字）。
  Map<String, dynamic>? _extractJsonObject(String text) {
    var start = -1;
    var depth = 0;
    var inStr = false;
    var esc = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (ch == '\\') {
          esc = true;
        } else if (ch == '"') {
          inStr = false;
        }
        continue;
      }
      if (ch == '"') {
        inStr = true;
      } else if (ch == '{') {
        if (depth == 0) start = i;
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0 && start >= 0) {
          final candidate = text.substring(start, i + 1);
          try {
            final obj = jsonDecode(candidate);
            if (obj is Map<String, dynamic>) {
              // 记录候选，继续找后面可能的结论性 JSON
              return obj;
            }
          } catch (_) {
            start = -1;
          }
        }
      }
    }
    return null;
  }

  CrashAnalysisResult _fallbackResult() {
    return _errorResult('未能生成智能分析：LLM 未配置（请在「配置」中填写 Base URL、API Key、模型）。');
  }

  /// 分析失败结果：把真实错误作为摘要返回（不再返回写死的“内存压力/兼容性”模板）。
  CrashAnalysisResult _errorResult(String message) {
    return CrashAnalysisResult(
      summary: message,
      rootCause: '',
      possibleCauses: const [],
      fixSuggestions: const [],
      error: message,
    );
  }
}
