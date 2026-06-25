import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../models/agent_payload.dart';
import '../models/tool_config.dart';
import '../services/agent_launcher.dart';
import '../services/analysis_prompt_builder.dart';
import '../services/console_links.dart';
import '../services/crash_analysis_report_generator.dart';
import '../services/gitlab_client.dart';
import '../services/security_redaction.dart';
import '../services/stack_clarity.dart';
import 'issue_detail_page.dart';
import '../constants/app_constants.dart';

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
    this.bizModule = 'crash',
  });

  final AppController controller;
  final String digestHash;
  final String title;
  final String? listStack;
  final int? errorCount;
  final int? errorDeviceCount;
  /// 业务类型：crash / lag / anr / exception / custom / network / pageload / startup / memory_leak / memory_alloc
  final String bizModule;

  @override
  State<IssueQuickAnalysisPage> createState() => _IssueQuickAnalysisPageState();
}

class _IssueQuickAnalysisPageState extends State<IssueQuickAnalysisPage> {
  Map<String, dynamic>? _issueJson;
  String? _loadErr;
  bool _loading = true;

  List<GitLabBlobHit> _blobHits = const [];
  List<GitLabCommitInfo> _commits = const [];

  /// 完整 Markdown 报告（业务模块 + 项目路径 + Git blame 三件套齐备时一次性生成）。
  final StringBuffer _fullReport = StringBuffer();
  bool _fullReportBusy = false;
  String? _fullReportErr;
  String? _fullReportPath;

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
        if (mounted) _generateFullReport(useLlm: _cfg.validateLlm().isEmpty);
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

  Map<String, dynamic> _modelMap() {
    final j = _issueJson;
    if (j == null) return const {};
    if (j['Model'] is Map) return Map<String, dynamic>.from(j['Model'] as Map);
    return j;
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

  /// 生成并保存「完整分析报告」（对应 skill 的 analyzeCrash 输出结构）。
  ///
  /// [useLlm] 为 true 且配置了 LLM 时，调用大模型生成原因分析/修改建议/代码示例。
  Future<void> _generateFullReport({bool useLlm = false}) async {
    if (_issueJson == null) {
      setState(() => _fullReportErr = '缺少 GetIssue 数据');
      return;
    }
    setState(() {
      _fullReportBusy = true;
      _fullReportErr = null;
    });
    try {
      final generator = CrashAnalysisReportGenerator(config: _cfg);
      final input = ReportInput(
        digestHash: widget.digestHash,
        title: widget.title,
        issueDetailJson: _issueJson!,
        listStack: widget.listStack,
      );
      final result = await generator.generateForIssue(
        input: input,
        bizModule: widget.bizModule,
        projectPath: _cfg.localProjectPath,
        useLlm: useLlm,
      );
      final path = await generator.saveReport(result);
      if (!mounted) return;
      setState(() {
        _fullReport.clear();
        _fullReport.writeln(result.markdown);
        _fullReportPath = path;
        _fullReportBusy = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('分析报告已生成，可在报告Tab页查看'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fullReportErr = userFacingNetworkError(e);
        _fullReportBusy = false;
      });
    }
  }

  Future<void> _openFullReportInFinder() async {
    final path = _fullReportPath;
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('报告文件不存在'), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }
    // macOS: 用 `open -R` 在 Finder 中定位文件
    try {
      await Process.run('open', ['-R', path]);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: path));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制报告路径到剪贴板'), behavior: SnackBarBehavior.floating),
        );
      }
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
                    if (_fullReportBusy)
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
                            model: _modelMap(),
                          ),
                          const SizedBox(height: 12),
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppBorderRadius.md,
                              side: BorderSide(color: cs.outlineVariant.withValues(alpha: kOpacitySemiTransparent)),
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
                                '智能分析报告',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              if (!_fullReportBusy)
                                TextButton.icon(
                                  onPressed: () => _generateFullReport(useLlm: _cfg.validateLlm().isEmpty),
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('重新生成'),
                                ),
                            ],
                          ),
                          if (_fullReportErr != null) ...[
                            const SizedBox(height: 8),
                            Material(
                              color: cs.errorContainer.withValues(alpha: 0.6),
                              borderRadius: AppBorderRadius.md,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(_fullReportErr!, style: TextStyle(color: cs.onErrorContainer, height: 1.35)),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          if (_fullReportBusy && _fullReport.isEmpty)
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
                                      '正在生成分析报告…',
                                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else if (_fullReport.isNotEmpty || _fullReportErr != null)
                            _FullReportSection(
                              busy: _fullReportBusy,
                              err: _fullReportErr,
                              markdown: _fullReport.toString(),
                              path: _fullReportPath,
                              onOpen: _openFullReportInFinder,
                              onRegenerate: () => _generateFullReport(useLlm: _cfg.validateLlm().isEmpty),
                            ),
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

/// 完整分析报告展示区（对应 skill 输出的全部分析章节）。
class _FullReportSection extends StatelessWidget {
  const _FullReportSection({
    required this.busy,
    required this.err,
    required this.markdown,
    required this.path,
    required this.onOpen,
    required this.onRegenerate,
  });

  final bool busy;
  final String? err;
  final String markdown;
  final String? path;
  final VoidCallback onOpen;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHigh.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_outlined, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  '完整分析报告',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                if (path != null)
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('在 Finder 中查看'),
                  ),
                TextButton.icon(
                  onPressed: busy ? null : onRegenerate,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重新生成'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '参照 emas-intelligent-analysis 技能输出，包含基本信息 / 分布 / 堆栈分析 / 源码分析（Git blame）/ 修复建议与代码示例。已保存到本机 Application Support 目录。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
            if (path != null) ...[
              const SizedBox(height: 6),
              SelectableText(
                path!,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(strokeWidth: 3, color: cs.primary),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '正在生成完整报告（拉取分布 / 本地源码 / Git blame）…',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              )
            else if (err != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  err!,
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                ),
              )
            else if (markdown.trim().isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '点击「重新生成」开始',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 480),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Scrollbar(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      markdown,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),
          ],
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
    required this.model,
  });

  final String digest;
  final int? errorCount;
  final int? deviceCount;
  final Map<String, dynamic> model;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final errorRate = _readRate(model['ErrorRate'] ?? model['CrashRate']);
    final firstVersion = (model['FirstVersion']?.toString() ?? '-').trim();
    final firstTime = model['FirstTime']?.toString();
    final latestTime = model['LatestTime']?.toString();
    final errorName = (model['Name']?.toString() ?? model['ErrorName']?.toString() ?? '-').trim();
    final errorType = (model['Type']?.toString() ?? model['ErrorType']?.toString() ?? '-').trim();

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: kOpacitySemiTransparent)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Digest', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            SelectableText(digest, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _StatPill(icon: Icons.repeat, label: '上报次数', value: '${errorCount ?? '-'}'),
                _StatPill(icon: Icons.devices, label: '影响设备', value: '${deviceCount ?? '-'}'),
                if (errorRate != null)
                  _StatPill(icon: Icons.trending_up, label: '错误率', value: '${errorRate.toStringAsFixed(3)}%'),
                if (firstVersion.isNotEmpty && firstVersion != '-')
                  _StatPill(icon: Icons.label_outline, label: '首现版本', value: firstVersion),
                if (firstTime != null && firstTime.isNotEmpty)
                  _StatPill(icon: Icons.schedule, label: '首次时间', value: firstTime.split('.')[0]),
                if (latestTime != null && latestTime.isNotEmpty)
                  _StatPill(icon: Icons.update, label: '最近时间', value: latestTime.split('.')[0]),
              ],
            ),
            if (errorName.isNotEmpty || errorType.isNotEmpty) ...[
              const SizedBox(height: 16),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: kOpacityLight)),
              const SizedBox(height: 12),
              if (errorName.isNotEmpty && errorName != '-')
                _DetailRow(label: '错误名称', value: errorName),
              if (errorType.isNotEmpty && errorType != '-')
                _DetailRow(label: '错误类型', value: errorType),
            ],
          ],
        ),
      ),
    );
  }

  double? _readRate(dynamic v) {
    if (v == null) return null;
    if (v is num) {
      final d = v.toDouble();
      return d <= 1 ? d * 100 : d;
    }
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final cleaned = s.endsWith('%') ? s.substring(0, s.length - 1).trim() : s;
    final d = double.tryParse(cleaned);
    if (d == null) return null;
    return d <= 1 ? d * 100 : d;
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
        color: cs.primaryContainer.withValues(alpha: kOpacityMedium),
        borderRadius: AppBorderRadius.md,
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
