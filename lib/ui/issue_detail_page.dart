import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../constants/app_constants.dart';
import '../models/tool_config.dart';
import '../services/ai_source_code_analyzer.dart';
import '../services/analysis_prompt_builder.dart';
import '../services/console_links.dart';
import '../services/llm_client.dart';
import '../services/outbound_http_client_for_config.dart';
import '../services/report_manager.dart';
import '../services/security_redaction.dart';
import '../services/stack_clarity.dart';
import 'llm_output_sections.dart';

/// 单条问题：信息总览、堆栈、原始 JSON、AI 分析。
class IssueDetailPage extends StatefulWidget {
  const IssueDetailPage({
    super.key,
    required this.controller,
    required this.digestHash,
    required this.title,
    this.listStack,
    this.errorCount,
    this.errorDeviceCount,
    this.pageNum = 1,
  });

  final AppController controller;
  final String digestHash;
  final String title;
  final String? listStack;
  final int? errorCount;
  final int? errorDeviceCount;
  final int pageNum;

  @override
  State<IssueDetailPage> createState() => _IssueDetailPageState();
}

class _IssueDetailPageState extends State<IssueDetailPage> {
  Map<String, dynamic>? _issueJson;
  String? _loadErr;
  bool _loading = true;

  final _llmOut = StringBuffer();
  bool _llmBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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

  Future<void> _runLlm() async {
    final miss = _cfg.validateLlm();
    if (miss.isNotEmpty) {
      setState(() => _llmOut.writeln('缺少：${miss.join('、')}'));
      return;
    }
    final stackFull = widget.listStack ?? _stackText();
    final clarity = analyzeStackClarity(stackFull);

    setState(() => _llmBusy = true);
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
        gitlabHits: const [],
        gitlabCommits: const [],
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
        _llmOut.writeln('错误：${userFacingNetworkError(e)}');
        _llmBusy = false;
      });
    } finally {
      client.close();
    }
  }

  Future<void> _runLocalAiAnalysis() async {
    final projectPath = _cfg.localProjectPath.trim();
    if (projectPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在配置中填写本地项目路径')),
      );
      return;
    }

    setState(() => _llmBusy = true);

    try {
      final issueData = <String, dynamic>{
        'digestHash': widget.digestHash,
        'issueType': widget.title,
        'errorCount': widget.errorCount ?? 0,
        'affectedDevices': widget.errorDeviceCount ?? 0,
        'stackTrace': _stackText(),
        'versionDistribution': _issueJson?['VersionDistribution'] ?? [],
      };

      final analyzer = AiSourceCodeAnalyzer(
        reportManager: ReportManager(),
        config: _cfg,
      );
      final report = await analyzer.performAnalysis(
        issueData: issueData,
        projectPath: projectPath,
        bizModule: widget.controller.activeBizModule,
        llmBaseUrl: _cfg.llmBaseUrl.trim(),
        llmApiKey: _cfg.llmApiKey.trim(),
        llmModel: _cfg.llmModel.trim(),
        projectId: widget.controller.activeProject.id,
      );

      if (!mounted) return;

      setState(() {
        _llmOut.clear();
        _llmOut.writeln(report);
        _llmBusy = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('分析报告已保存到报告中心')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _llmOut.clear();
        _llmOut.writeln('本地源码AI分析失败：${userFacingNetworkError(e)}');
        _llmBusy = false;
      });
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

  String _buildDetailConsoleUrl() {
    final spaceId = '3711937';
    final appId = _cfg.appKey;
    final osCode = _cfg.os.toLowerCase() == 'ios' ? '1' : '2';

    final bizModule = widget.controller.activeBizModule.toLowerCase();
    int pageNum = widget.pageNum;

    if (_issueJson != null) {
      // 从 Model 层级获取分页信息
      final model = (_issueJson!['Model'] is Map ? _issueJson!['Model'] : _issueJson) as Map<String, dynamic>;
      pageNum = model['PageNum'] as int? ?? widget.pageNum;
    }

    return 'https://emas.console.aliyun.com/apm/$spaceId/$appId/$osCode/crashAnalysis/$bizModule/detail?fromType=$bizModule&storeName=$bizModule&digestId=${widget.digestHash}&pageNum=$pageNum';
    // 注：URL 路径中 crashAnalysis 是固定的，只有后面的 $bizModule 会根据业务模块变化
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final consoleLink = _buildDetailConsoleUrl();

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadErr != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('加载失败：$_loadErr')))
              : CustomScrollView(
                  slivers: [
                    SliverAppBar.large(
                      title: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      actions: [
                        IconButton(
                          tooltip: '控制台',
                          icon: const Icon(Icons.open_in_new),
                          onPressed: _openConsole,
                        ),
                      ],
                    ),
                    if (consoleLink.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                        sliver: SliverToBoxAdapter(
                          child: Material(
                            color: cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () async {
                                final uri = Uri.tryParse(consoleLink);
                                if (uri != null && await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Icon(Icons.link, size: 18, color: cs.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: SelectableText(
                                        consoleLink,
                                        style: TextStyle(
                                          color: cs.primary,
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 2,
                                      ),
                                    ),
                                    Icon(Icons.arrow_outward, size: 16, color: cs.primary),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      sliver: SliverToBoxAdapter(
                        child: _IssueInfoCard(
                          model: _modelMap(),
                          digest: widget.digestHash,
                          fallbackErrorCount: widget.errorCount,
                          fallbackDeviceCount: widget.errorDeviceCount,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      sliver: SliverToBoxAdapter(
                        child: Text('堆栈与原始数据', style: Theme.of(context).textTheme.titleMedium),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverToBoxAdapter(
                        child: _ExpandableCodeCard(
                          title: '堆栈摘要',
                          subtitle: '用于 AI 分析',
                          child: SelectableText(
                            _stackText().isEmpty ? '（无）' : _stackText(),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4),
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      sliver: SliverToBoxAdapter(
                        child: _ExpandableCodeCard(
                          title: 'GetIssue 原始 JSON',
                          subtitle: '调试或复制给外部工具',
                          initiallyExpanded: false,
                          child: _prettyJson(_issueJson),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            Icon(Icons.auto_awesome, color: cs.primary, size: 22),
                            const SizedBox(width: 8),
                            Text('智能分析', style: Theme.of(context).textTheme.titleMedium),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.icon(
                              onPressed: _llmBusy ? null : _runLlm,
                              icon: _llmBusy
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                                    )
                                  : const Icon(Icons.psychology_outlined),
                              label: Text(_llmBusy ? '分析中…' : '生成 AI 分析'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: AppBorderRadius.md),
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.tonalIcon(
                              onPressed: _llmBusy ? null : _runLocalAiAnalysis,
                              icon: _llmBusy
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: cs.onTertiaryContainer,
                                      ),
                                    )
                                  : const Icon(Icons.source_outlined),
                              label: Text(_llmBusy ? '分析中…' : '本地源码 AI 分析'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: AppBorderRadius.md),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '本地源码 AI 分析会结合配置的本地项目路径与堆栈信息，从源码中提取相关代码片段进行深度分析。',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      height: 1.35,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            buildLlmSectionCards(context, _llmOut.toString()),
                          ],
                        ),
                      ),
                    ),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                  ],
                ),
    );
  }

  Widget _prettyJson(Map<String, dynamic>? j) {
    if (j == null) return const SelectableText('null');
    String pretty;
    try {
      pretty = const JsonEncoder.withIndent('  ').convert(j);
    } catch (_) {
      pretty = j.toString();
    }
    return SelectableText(pretty, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.35));
  }
}

/// 崩溃信息总览卡片：展示 GetIssue 返回的所有字段，自动按类别分组。
class _IssueInfoCard extends StatelessWidget {
  const _IssueInfoCard({
    required this.model,
    required this.digest,
    this.fallbackErrorCount,
    this.fallbackDeviceCount,
  });

  final Map<String, dynamic> model;
  final String digest;
  final int? fallbackErrorCount;
  final int? fallbackDeviceCount;

  static const _labelOverrides = <String, String>{
    'DigestHash': 'Digest',
    'ErrorName': '错误名称',
    'Name': '错误名称',
    'ErrorType': '错误类型',
    'Type': '错误类型',
    'ErrorCount': '上报次数',
    'Count': '上报次数',
    'ErrorDeviceCount': '影响设备',
    'DeviceCount': '影响设备',
    'AffectedDeviceCount': '影响设备',
    'ErrorRate': '错误率',
    'CrashRate': '错误率',
    'Rate': '错误率',
    'DeviceRate': '设备率',
    'ErrorDeviceRate': '设备率',
    'FirstVersion': '首现版本',
    'FirstSeenVersion': '首现版本',
    'LatestVersion': '最新版本',
    'FirstTime': '首次时间',
    'FirstSeenTime': '首次时间',
    'LatestTime': '最近时间',
    'EventTime': '发生时间',
    'Os': '系统',
    'OsVersion': '系统版本',
    'BizModule': '业务模块',
    'Status': '状态',
    'IssueStatus': '状态',
    'HandleStatus': '处理状态',
    'AppVersion': '应用版本',
    'Version': '版本',
    'Brand': '品牌',
    'DeviceModel': '机型',
    'Model': '机型',
    'ProcessName': '进程名',
    'ThreadName': '线程名',
    'PackageName': '包名',
    'AppKey': 'AppKey',
    'Channel': '渠道',
  };

  static const _countKeys = <String>{
    'ErrorCount', 'Count', 'ErrorDeviceCount', 'DeviceCount',
    'AffectedDeviceCount', 'ErrorVersionCount', 'VersionCount',
  };

  static const _rateKeys = <String>{
    'ErrorRate', 'CrashRate', 'Rate', 'DeviceRate', 'ErrorDeviceRate',
    'AffectedDeviceRate',
  };

  String _label(String key) {
    final lower = key.trim();
    return _labelOverrides[lower] ?? _labelOverrides[lower[0].toUpperCase() + lower.substring(1)] ?? key;
  }

  String _formatValue(String key, dynamic v) {
    if (v == null) return '-';
    if (v is List || v is Map) {
      try {
        return const JsonEncoder.withIndent('  ').convert(v);
      } catch (_) {
        return v.toString();
      }
    }
    final s = v.toString().trim();
    if (s.isEmpty) return '-';
    if (_rateKeys.contains(key)) {
      final d = double.tryParse(s);
      if (d != null) {
        if (d <= 1) return '${(d * 100).toStringAsFixed(3)}%';
        return '${d.toStringAsFixed(3)}%';
      }
    }
    if (key == 'ErrorCount' || key == 'Count' || key == 'ErrorDeviceCount' || key == 'DeviceCount' || key == 'AffectedDeviceCount') {
      if (int.tryParse(s) != null) return s;
    }
    return s;
  }

  bool _isDisplayKey(String key) {
    final lower = key.toLowerCase();
    if (lower.contains('stack') || lower == 'stack') return false;
    if (lower.contains('distribution') || lower == 'versions') return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = <MapEntry<String, dynamic>>[];
    if (model.isNotEmpty) {
      for (final e in model.entries) {
        if (_isDisplayKey(e.key)) entries.add(e);
      }
    } else {
      if (fallbackErrorCount != null) entries.add(MapEntry('ErrorCount', fallbackErrorCount));
      if (fallbackDeviceCount != null) entries.add(MapEntry('ErrorDeviceCount', fallbackDeviceCount));
    }

    // 字段分组排序：核心指标在前，时间在后，其他按字母
    final primaryKeys = <String>[
      'DigestHash', 'ErrorName', 'Name', 'ErrorType', 'Type',
      'ErrorCount', 'Count', 'ErrorDeviceCount', 'DeviceCount', 'AffectedDeviceCount',
      'ErrorRate', 'CrashRate', 'Rate',
      'FirstVersion', 'FirstSeenVersion', 'LatestVersion',
    ];
    final timeKeys = <String>[
      'FirstTime', 'FirstSeenTime', 'LatestTime', 'EventTime', 'CreateTime', 'UpdateTime',
    ];
    final primary = <MapEntry<String, dynamic>>[];
    final time = <MapEntry<String, dynamic>>[];
    final other = <MapEntry<String, dynamic>>[];
    for (final e in entries) {
      if (primaryKeys.contains(e.key)) {
        primary.add(e);
      } else if (timeKeys.contains(e.key) || e.key.toLowerCase().contains('time') || e.key.toLowerCase().contains('date')) {
        time.add(e);
      } else {
        other.add(e);
      }
    }
    primary.sort((a, b) => primaryKeys.indexOf(a.key).compareTo(primaryKeys.indexOf(b.key)));
    other.sort((a, b) => a.key.compareTo(b.key));
    final sorted = [...primary, ...time, ...other];

    // Digest 单独放第一行（全宽）
    final digestEntry = sorted.firstWhere(
      (e) => e.key == 'DigestHash',
      orElse: () => MapEntry('DigestHash', digest),
    );
    final rest = sorted.where((e) => e.key != 'DigestHash').toList();

    // 前 6 个核心字段做大 pill，其余做两列详情行
    final topPills = <MapEntry<String, dynamic>>[];
    final detailRows = <MapEntry<String, dynamic>>[];
    for (final e in rest) {
      if (topPills.length < 6 && (_countKeys.contains(e.key) || _rateKeys.contains(e.key) || e.key.contains('Version'))) {
        topPills.add(e);
      } else {
        detailRows.add(e);
      }
    }

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
            SelectableText(digestEntry.value.toString(), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            if (topPills.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: topPills.map((e) => _StatPill(
                  icon: _iconForKey(e.key),
                  label: _label(e.key),
                  value: _formatValue(e.key, e.value),
                )).toList(),
              ),
            ],
            if (detailRows.isNotEmpty) ...[
              const SizedBox(height: 16),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: kOpacityLight)),
              const SizedBox(height: 12),
              ...detailRows.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        _label(e.key),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                      child: _valueWidget(e.key, e.value),
                    ),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _valueWidget(String key, dynamic value) {
    final formatted = _formatValue(key, value);
    if (formatted.length > 80 || formatted.contains('\n')) {
      return SelectableText(
        formatted,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4),
      );
    }
    return SelectableText(
      formatted,
      style: const TextStyle(fontSize: 13, height: 1.4),
    );
  }

  IconData _iconForKey(String key) {
    final k = key.toLowerCase();
    if (k.contains('count')) return Icons.repeat;
    if (k.contains('device') || k.contains('brand') || k.contains('model')) return Icons.devices;
    if (k.contains('rate')) return Icons.trending_up;
    if (k.contains('version')) return Icons.label_outline;
    if (k.contains('time') || k.contains('date')) return Icons.schedule;
    if (k.contains('type')) return Icons.category_outlined;
    if (k.contains('name')) return Icons.short_text;
    return Icons.info_outline;
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

class _ExpandableCodeCard extends StatelessWidget {
  const _ExpandableCodeCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.initiallyExpanded = true,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.lg,
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: kOpacityLight)),
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(child: child),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
