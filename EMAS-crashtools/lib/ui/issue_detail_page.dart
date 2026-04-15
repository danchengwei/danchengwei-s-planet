import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
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
import 'llm_output_sections.dart';

/// 单条问题：信息总览、堆栈、原始 JSON、AI 分块、GitLab、去修改（Agent / 协议）。
class IssueDetailPage extends StatefulWidget {
  const IssueDetailPage({
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
  State<IssueDetailPage> createState() => _IssueDetailPageState();
}

class _IssueDetailPageState extends State<IssueDetailPage> {
  Map<String, dynamic>? _issueJson;
  String? _loadErr;
  bool _loading = true;

  final _llmOut = StringBuffer();
  bool _llmBusy = false;
  List<GitLabBlobHit> _blobHits = const [];
  List<GitLabCommitInfo> _commits = const [];
  bool _gitlabBusy = false;
  String? _gitlabErr;

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

  Future<void> _runGitlab() async {
    final miss = _cfg.validateGitlab();
    if (miss.isNotEmpty) {
      setState(() => _gitlabErr = '请先在配置中填写：${miss.join('、')}');
      return;
    }
    setState(() {
      _gitlabBusy = true;
      _gitlabErr = null;
      _blobHits = const [];
      _commits = const [];
    });
    try {
      final kw = extractStackKeywords(_stackText());
      if (kw.isEmpty) {
        setState(() {
          _gitlabBusy = false;
          _gitlabErr = '未能从堆栈提取关键词';
        });
        return;
      }
      final q = kw.first;
      final out = await searchGitlabMergedForKeyword(
        config: _cfg,
        searchKeyword: q,
        maxTotalHits: 16,
        perProjectLimit: 8,
      );
      if (!mounted) return;
      setState(() {
        _blobHits = out.hits;
        _commits = out.commits;
        _gitlabBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gitlabErr = userFacingNetworkError(e);
        _gitlabBusy = false;
      });
    }
  }

  Future<void> _runLlm() async {
    final miss = _cfg.validateLlm();
    if (miss.isNotEmpty) {
      setState(() => _llmOut.writeln('缺少：${miss.join('、')}'));
      return;
    }
    final stackFull = widget.listStack ?? _stackText();
    final clarity = analyzeStackClarity(stackFull);

    var gh = _blobHits;
    var gc = _commits;
    final tryAutoGitlab = clarity.level == StackClarityLevel.businessLikely &&
        _cfg.validateGitlab().isEmpty &&
        extractStackKeywords(stackFull).isNotEmpty;

    setState(() => _llmBusy = true);
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
        _llmOut.writeln('错误：${userFacingNetworkError(e)}');
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      sliver: SliverToBoxAdapter(
                        child: _DigestSummaryCard(
                          digest: widget.digestHash,
                          errorCount: widget.errorCount,
                          deviceCount: widget.errorDeviceCount,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverToBoxAdapter(
                        child: _FixActionPanel(
                          onCopyPrompt: _copyPrompt,
                          onRunAgent: _runAgentCli,
                          agentMode: _cfg.agentMode,
                          agentConfigured: _cfg.agentMode.trim() == 'clipboard' || _cfg.agentExecutable.trim().isNotEmpty,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      sliver: SliverToBoxAdapter(
                        child: Text('堆栈与原始数据', style: Theme.of(context).textTheme.titleMedium),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverToBoxAdapter(
                        child: _ExpandableCodeCard(
                          title: '堆栈摘要',
                          subtitle: '用于 GitLab 关键词与 AI 分析',
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
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '堆栈可识别业务代码时，将先尝试 GitLab 检索并把命中片段写入提示词；'
                                '若仅为系统/框架栈，模型将侧重可能原因与修改思路，不臆造业务文件路径。',
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
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            Icon(Icons.integration_instructions_outlined, color: cs.tertiary, size: 22),
                            const SizedBox(width: 8),
                            Text('代码仓库（GitLab）', style: Theme.of(context).textTheme.titleMedium),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverToBoxAdapter(
                        child: _GitlabSection(
                          keywordsText: extractStackKeywords(_stackText()).join('、'),
                          stackHint: analyzeStackClarity(_stackText()).summaryForPrompt,
                          busy: _gitlabBusy,
                          err: _gitlabErr,
                          hits: _blobHits,
                          commits: _commits,
                          onSearch: _runGitlab,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                      sliver: SliverToBoxAdapter(
                        child: _ProtocolHintCard(),
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

/// 顶部强调：去修改（复制 / 唤醒 Agent）。
class _FixActionPanel extends StatelessWidget {
  const _FixActionPanel({
    required this.onCopyPrompt,
    required this.onRunAgent,
    required this.agentMode,
    required this.agentConfigured,
  });

  final VoidCallback onCopyPrompt;
  final VoidCallback onRunAgent;
  final String agentMode;
  final bool agentConfigured;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            cs.primary.withValues(alpha: 0.12),
            cs.tertiary.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, color: cs.primary, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '去修改',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '将本条崩溃上下文交给 Claude Code CLI 或剪贴板：请在「配置」填写工程目录并选择 Claude Code / 剪贴板。完整 HTML 报告里的「去处理」可通过 crash-tools:// 唤起本应用。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onCopyPrompt,
                  icon: const Icon(Icons.content_copy),
                  label: const Text('复制提示词'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: agentConfigured ? onRunAgent : null,
                  icon: const Icon(Icons.terminal),
                  label: Text('启动 Agent（$agentMode）'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
          if (!agentConfigured && agentMode != 'clipboard')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '非 clipboard 模式需在配置中填写可执行文件路径',
                style: TextStyle(fontSize: 12, color: cs.error),
              ),
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
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
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

class _GitlabSection extends StatelessWidget {
  const _GitlabSection({
    required this.keywordsText,
    required this.stackHint,
    required this.busy,
    required this.err,
    required this.hits,
    required this.commits,
    required this.onSearch,
  });

  final String keywordsText;
  final String stackHint;
  final bool busy;
  final String? err;
  final List<GitLabBlobHit> hits;
  final List<GitLabCommitInfo> commits;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('关键词：${keywordsText.isEmpty ? "（暂无）" : keywordsText}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(
              '堆栈解读：$stackHint',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: busy ? null : onSearch,
              icon: busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                    )
                  : const Icon(Icons.search),
              label: Text(busy ? '搜索中…' : '搜索 Blob 并拉最近提交'),
            ),
            if (err != null) ...[
              const SizedBox(height: 10),
              Text(err!, style: TextStyle(color: cs.error, fontSize: 13)),
            ],
            if (hits.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Blob 命中', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...hits.map((h) {
                final raw = (h.data ?? '').replaceAll('\n', ' ');
                final sub = raw.length > 100 ? '${raw.substring(0, 100)}…' : raw;
                final lab = h.configRepoLabel?.trim();
                final titleText = lab != null && lab.isNotEmpty
                    ? '[$lab] ${h.path ?? h.basename ?? '-'}'
                    : (h.path ?? h.basename ?? '-');
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(titleText, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
                );
              }),
            ],
            if (commits.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('最近提交', style: Theme.of(context).textTheme.titleSmall),
              ...commits.map((c) {
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.title ?? '-', maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${c.authorName ?? ''} ${c.committedDate ?? ''}'),
                  trailing: c.webUrl != null
                      ? IconButton(
                          icon: const Icon(Icons.link),
                          onPressed: () async {
                            final u = Uri.tryParse(c.webUrl!);
                            if (u != null && await canLaunchUrl(u)) {
                              await launchUrl(u, mode: LaunchMode.externalApplication);
                            }
                          },
                        )
                      : null,
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProtocolHintCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: cs.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '从工作台导出「完整报告包」后，HTML 内「去处理」会使用 crash-tools://open?path= 将 payload 交给本应用，从而复用上方「去修改」同一套 Agent 逻辑。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
