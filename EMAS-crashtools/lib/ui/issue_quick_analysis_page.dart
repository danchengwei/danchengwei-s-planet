import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../models/analysis_report_record.dart';
import '../models/agent_payload.dart';
import '../models/tool_config.dart';
import '../services/agent_launcher.dart';
import '../services/analysis_prompt_builder.dart';
import '../services/console_links.dart';
import '../services/gitlab_client.dart';
import '../services/gitlab_stack_search.dart';
import '../services/llm_client.dart';
import '../services/outbound_http_client_for_config.dart';
import '../services/security_redaction.dart';
import '../services/stack_clarity.dart';
import '../services/stack_keywords.dart';
import 'issue_detail_page.dart';
import 'llm_output_sections.dart';

/// 列表「查看」入口：拉取单条详情后自动调用大模型，分块展示原因 / 方案等，并提供去处理（Agent）。
class IssueQuickAnalysisPage extends StatefulWidget {
  const IssueQuickAnalysisPage({
    super.key,
    required this.controller,
    required this.digestHash,
    required this.title,
    this.listStack,
    this.errorCount,
    this.errorDeviceCount,
  });

  final AppController controller;
  final String digestHash;
  final String title;
  final String? listStack;
  final int? errorCount;
  final int? errorDeviceCount;

  @override
  State<IssueQuickAnalysisPage> createState() => _IssueQuickAnalysisPageState();
}

class _IssueQuickAnalysisPageState extends State<IssueQuickAnalysisPage> {
  Map<String, dynamic>? _issueJson;
  String? _loadErr;
  bool _loading = true;

  final StringBuffer _llmOut = StringBuffer();
  bool _llmBusy = false;
  String? _llmErr;
  List<GitLabBlobHit> _blobHits = const [];
  List<GitLabCommitInfo> _commits = const [];
  bool _gitlabBusy = false;
  String? _gitlabErr;

  @override
  void initState() {
    super.initState();
    _loadThenAnalyze();
  }

  Future<void> _loadThenAnalyze() async {
    setState(() {
      _loading = true;
      _loadErr = null;
    });
    try {
      final j = await widget.controller.fetchIssueDetail(widget.digestHash);
      if (!mounted) return;
      if (j == null) {
        final miss = widget.controller.config.validateEmas();
        final errMsg = miss.isNotEmpty
            ? '请先完成 EMAS 配置：${miss.join('、')}'
            : (widget.controller.config.appKeyAsInt == null
                ? 'AppKey 须为数字'
                : '无法拉取详情（请检查配置）');
        setState(() {
          _issueJson = null;
          _loadErr = errMsg;
          _loading = false;
        });
        return;
      }
      setState(() {
        _issueJson = j;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runLlm();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadErr = userFacingNetworkError(e);
        _loading = false;
      });
    }
  }

  ToolConfig get _cfg => widget.controller.config;

  String _stackText() {
    final j = _issueJson;
    if (j == null) return widget.listStack ?? '';
    String walk(dynamic x) {
      if (x is Map) {
        final st = x['Stack'] ?? x['stack'];
        if (st != null && st.toString().trim().isNotEmpty) return st.toString();
        for (final v in x.values) {
          final r = walk(v);
          if (r.isNotEmpty) return r;
        }
      } else if (x is List) {
        for (final e in x) {
          final r = walk(e);
          if (r.isNotEmpty) return r;
        }
      }
      return '';
    }

    final s = walk(j);
    if (s.isNotEmpty) return s;
    return widget.listStack ?? '';
  }

  Future<void> _runLlm() async {
    if (_issueJson == null) {
      setState(() {
        _llmErr = _loadErr ?? '缺少 GetIssue 数据，无法分析';
        _llmOut.clear();
      });
      return;
    }
    final miss = _cfg.validateLlm();
    if (miss.isNotEmpty) {
      setState(() {
        _llmErr = '请先在「配置」中填写：${miss.join('、')}';
        _llmOut.clear();
      });
      return;
    }

    final stackFull = widget.listStack ?? _stackText();
    final clarity = analyzeStackClarity(stackFull);

    var gh = _blobHits;
    var gc = _commits;
    final tryAutoGitlab = clarity.level == StackClarityLevel.businessLikely &&
        _cfg.validateGitlab().isEmpty &&
        extractStackKeywords(stackFull).isNotEmpty;

    setState(() {
      _llmBusy = true;
      _llmErr = null;
    });

    if (tryAutoGitlab) {
      setState(() {
        _gitlabBusy = true;
        _gitlabErr = null;
      });
      try {
        final r = await searchGitlabForStack(config: _cfg, stack: stackFull);
        if (!mounted) return;
        gh = r.hits;
        gc = r.commits;
        setState(() {
          _blobHits = gh;
          _commits = gc;
          if (r.skippedReason != null && gh.isEmpty) {
            _gitlabErr = r.skippedReason;
          }
        });
      } catch (e) {
        if (mounted) setState(() => _gitlabErr = userFacingNetworkError(e));
      } finally {
        if (mounted) setState(() => _gitlabBusy = false);
      }
    }

    final client = LlmClient(
      baseUrl: _cfg.llmBaseUrl.trim(),
      apiKey: _cfg.llmApiKey.trim(),
      model: _cfg.llmModel.trim(),
      chatCompletionsPath: _cfg.effectiveLlmChatPath,
      httpClient: newOutboundHttpClient(),
    );
    try {
      final userMsg = buildAnalysisUserPrompt(
        digestHash: widget.digestHash,
        getIssueBody: _issueJson,
        listTitle: widget.title,
        listStack: stackFull,
        clarity: clarity,
        gitlabHits: gh,
        gitlabCommits: gc,
      );
      final reply = await client.chat([
        {'role': 'system', 'content': _cfg.effectiveLlmSystemPrompt},
        {'role': 'user', 'content': userMsg},
      ]);
      if (!mounted) return;
      setState(() {
        _llmOut.clear();
        _llmOut.writeln(reply);
        _llmBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _llmOut.clear();
        _llmOut.writeln('请求失败：${userFacingNetworkError(e)}');
        _llmBusy = false;
      });
    } finally {
      client.close();
    }
  }

  Future<void> _copyPrompt() async {
    final stackFull = widget.listStack ?? _stackText();
    final clarity = analyzeStackClarity(stackFull);
    final prompt = buildAnalysisUserPrompt(
      digestHash: widget.digestHash,
      getIssueBody: _issueJson,
      listTitle: widget.title,
      listStack: stackFull,
      clarity: clarity,
      gitlabHits: _blobHits,
      gitlabCommits: _commits,
      prependGitlabMcpHint: true,
    );
    final p = AgentLauncher.payloadFromConfig(
      config: _cfg,
      digestHash: widget.digestHash,
      prompt: prompt,
    );
    await AgentLauncher.runFromPayload(AgentPayload(
      version: p.version,
      digestHash: p.digestHash,
      prompt: p.prompt,
      workingDirectory: p.workingDirectory,
      executable: p.executable,
      mode: 'clipboard',
      fixedArgs: p.fixedArgs,
    ));
  }

  Future<void> _runAgentCli() async {
    final cliErr = _cfg.validateAgentCliLaunch();
    if (cliErr != null) {
      return;
    }
    final stackFull = widget.listStack ?? _stackText();
    final clarity = analyzeStackClarity(stackFull);
    final prompt = buildAnalysisUserPrompt(
      digestHash: widget.digestHash,
      getIssueBody: _issueJson,
      listTitle: widget.title,
      listStack: stackFull,
      clarity: clarity,
      gitlabHits: _blobHits,
      gitlabCommits: _commits,
      prependGitlabMcpHint: true,
    );
    final p = AgentLauncher.payloadFromConfig(
      config: _cfg,
      digestHash: widget.digestHash,
      prompt: prompt,
    );
    try {
      await AgentLauncher.runFromPayload(p);
    } catch (e) {
      debugPrint('Agent: $e');
    }
  }

  Future<void> _openConsole() async {
    final link = consoleLinkForIssue(
      _cfg,
      widget.digestHash,
      bizModuleForConsole: widget.controller.activeBizModule,
    );
    final u = link != null ? Uri.tryParse(link) : Uri.tryParse(_cfg.consoleBaseUrl.trim());
    if (u != null && await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  /// clipboard 始终可点（复制）；stdin / args 需同时配置可执行文件与项目目录。
  bool _agentPrimaryActionEnabled() {
    final mode = _cfg.agentMode.trim().isEmpty ? 'clipboard' : _cfg.agentMode.trim();
    if (mode == 'clipboard') return true;
    return _cfg.agentExecutable.trim().isNotEmpty && _cfg.agentWorkDir.trim().isNotEmpty;
  }

  void _openFullDetail() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => IssueDetailPage(
          controller: widget.controller,
          digestHash: widget.digestHash,
          title: widget.title,
          listStack: widget.listStack,
          errorCount: widget.errorCount,
          errorDeviceCount: widget.errorDeviceCount,
        ),
      ),
    );
  }

  String _stackSnippet(int max) {
    final s = _stackText().trim();
    if (s.isEmpty) return '';
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }

  String _gitlabContextSummary() {
    if (_blobHits.isEmpty && _commits.isEmpty) return '';
    final buf = StringBuffer();
    if (_blobHits.isNotEmpty) {
      buf.writeln('GitLab 检索命中（工具内 REST，可在 MCP 中继续查仓库）：');
      for (final h in _blobHits.take(12)) {
        final label = (h.configRepoLabel?.trim().isNotEmpty ?? false)
            ? h.configRepoLabel!.trim()
            : (h.searchProjectId ?? '${h.projectId ?? ''}');
        buf.writeln('- [$label] ${h.path ?? h.basename ?? '?'}');
      }
    }
    if (_commits.isNotEmpty) {
      buf.writeln('相关提交摘录：');
      for (final c in _commits.take(6)) {
        buf.writeln('- ${c.title ?? c.id ?? ''}');
      }
    }
    return buf.toString().trim();
  }

  AnalysisReportRecord _buildReportRecord() {
    final git = _gitlabContextSummary();
    return AnalysisReportRecord(
      id: AnalysisReportRecord.newId(),
      projectId: widget.controller.activeProject.id,
      digestHash: widget.digestHash,
      title: widget.title,
      bizModule: widget.controller.activeBizModule,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      reportBody: _llmOut.toString().trim(),
      stackSnippet: _stackSnippet(800),
      gitlabContext: git.isEmpty ? null : git,
    );
  }

  Future<void> _saveAnalysisReport() async {
    final body = _llmOut.toString().trim();
    if (body.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无分析内容可保存'), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }
    await widget.controller.addAnalysisReport(_buildReportRecord());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存到报告库（对话页可继续挂载）'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _attachReportToChat() {
    final body = _llmOut.toString().trim();
    if (body.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请等待分析完成'), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }
    final rec = _buildReportRecord();
    widget.controller.attachReportToChat(rec);
    widget.controller.requestOpenChatTab();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已挂载到「对话」上下文，并切换到对话页；可直接让模型结合 Claude Code / MCP 改代码'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _saveAndOpenChat() async {
    final body = _llmOut.toString().trim();
    if (body.isEmpty) return;
    final rec = _buildReportRecord();
    await widget.controller.addAnalysisReport(rec);
    widget.controller.attachReportToChat(rec);
    widget.controller.requestOpenChatTab();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已保存并挂载报告，已打开对话页'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'EMAS 控制台',
            icon: const Icon(Icons.open_in_new),
            onPressed: _openConsole,
          ),
          TextButton(
            onPressed: _openFullDetail,
            child: const Text('完整详情'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadErr != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('加载失败：$_loadErr', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadThenAnalyze,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (_llmBusy || _gitlabBusy)
                      LinearProgressIndicator(
                        minHeight: 3,
                        color: cs.primary,
                      ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        children: [
                          _DigestSummaryCard(
                            digest: widget.digestHash,
                            errorCount: widget.errorCount,
                            deviceCount: widget.errorDeviceCount,
                          ),
                          const SizedBox(height: 12),
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
                            ),
                            child: ExpansionTile(
                              initiallyExpanded: false,
                              title: Text(
                                '堆栈（列表 / 详情）',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                '「查看」与模型分析均基于以下文本；可展开查看完整内容',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  child: SelectableText(
                                    _stackText().isEmpty ? '（无）' : _stackText(),
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(Icons.auto_awesome, color: cs.primary, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                '智能分析（原因 · 分析 · 如何处理）',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              if (!_llmBusy && _cfg.validateLlm().isEmpty)
                                TextButton.icon(
                                  onPressed: _runLlm,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('重新分析'),
                                ),
                            ],
                          ),
                          if (_llmErr != null) ...[
                            const SizedBox(height: 8),
                            Material(
                              color: cs.errorContainer.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(_llmErr!, style: TextStyle(color: cs.onErrorContainer, height: 1.35)),
                              ),
                            ),
                          ],
                          if (_gitlabBusy)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '正在根据堆栈检索 GitLab…',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ),
                          if (_gitlabErr != null && _blobHits.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'GitLab：$_gitlabErr',
                                style: TextStyle(fontSize: 12, color: cs.outline),
                              ),
                            ),
                          const SizedBox(height: 12),
                          if (_llmBusy && _llmOut.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: Column(
                                  children: [
                                    SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: CircularProgressIndicator(strokeWidth: 3, color: cs.primary),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      '正在调用模型分析堆栈…',
                                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else ...[
                            buildLlmSectionCards(context, _llmOut.toString()),
                            if (_llmErr == null && _llmOut.toString().trim().isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Card(
                                elevation: 0,
                                color: cs.primaryContainer.withValues(alpha: 0.35),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.article_outlined, size: 20, color: cs.primary),
                                          const SizedBox(width: 8),
                                          Text(
                                            '报告与后续开发',
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '可保存到本地报告库、删除在「对话」页管理；挂载后对话中的模型会带上完整分析，便于你要求结合 Claude Code / GitLab MCP 改代码。',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: cs.onSurfaceVariant,
                                              height: 1.35,
                                            ),
                                      ),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          FilledButton.tonalIcon(
                                            onPressed: _llmBusy ? null : _saveAnalysisReport,
                                            icon: const Icon(Icons.save_outlined, size: 18),
                                            label: const Text('保存到报告库'),
                                          ),
                                          FilledButton.icon(
                                            onPressed: _llmBusy ? null : _attachReportToChat,
                                            icon: const Icon(Icons.chat_bubble_outline, size: 18),
                                            label: const Text('加入对话上下文'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: _llmBusy ? null : _saveAndOpenChat,
                                            icon: const Icon(Icons.merge_type, size: 18),
                                            label: const Text('保存并打开对话'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _loading || _loadErr != null
          ? null
          : Material(
              elevation: 8,
              color: cs.surfaceContainerHigh,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomPad),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '去处理',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '将本条上下文交给 Claude Code CLI 或剪贴板（需在配置中填写工程目录；剪贴板模式仅复制）。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.35,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: _agentPrimaryActionEnabled() ? _runAgentCli : null,
                              icon: const Icon(Icons.terminal),
                              label: Text(
                                _cfg.agentMode.trim() == 'clipboard' || _cfg.agentMode.trim().isEmpty
                                    ? '复制提示词（去处理）'
                                    : '启动 Agent 去处理',
                              ),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _copyPrompt,
                              child: const Text('仅复制'),
                            ),
                          ),
                        ],
                      ),
                      if (_cfg.agentMode.trim() != 'clipboard' &&
                          (_cfg.agentExecutable.trim().isEmpty || _cfg.agentWorkDir.trim().isEmpty))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'stdin / args 模式需填写可执行文件与本地项目目录；仅复制可选 clipboard。',
                            style: TextStyle(fontSize: 12, color: cs.error),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _DigestSummaryCard extends StatelessWidget {
  const _DigestSummaryCard({
    required this.digest,
    required this.errorCount,
    required this.deviceCount,
  });

  final String digest;
  final int? errorCount;
  final int? deviceCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Digest', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            SelectableText(digest, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _StatPill(icon: Icons.repeat, label: '上报次数', value: '${errorCount ?? '-'}'),
                _StatPill(icon: Icons.devices, label: '影响设备', value: '${deviceCount ?? '-'}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: cs.onPrimaryContainer),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onPrimaryContainer)),
              Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}
