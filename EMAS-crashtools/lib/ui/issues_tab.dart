import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../aliyun/emas_appmonitor_client.dart';
import '../app_controller.dart';
import 'issue_detail_page.dart';
import 'issue_quick_analysis_page.dart';
import 'top_issues_llm_page.dart';

String _launchTypeBannerSuffix(AppController c) {
  switch (c.perfStartupLaunchKind) {
    case 'cold':
      return ' · 启动类型：冷启动';
    case 'hot':
      return ' · 启动类型：热启动';
    default:
      return '';
  }
}

const String _kDefaultListIntroduction =
    '列表为与控制台类似的纵向条目：每条含堆栈摘要；点「查看」将拉取详情并自动调用大模型，分块展示原因、分析、如何处理；底部「去处理」可按配置调用 Claude Code CLI 或仅复制到剪贴板（须填写本地工程目录）。「详情」进入完整堆栈、JSON、GitLab 与手动分析。';

/// 列表工作台：一键拉取、HTML 导出/浏览器预览、列表卡片与详情入口（各功能模块复用）。
class IssuesTab extends StatelessWidget {
  const IssuesTab({
    super.key,
    required this.controller,
    required this.onOpenSettings,
    this.moduleTitle = '数据列表',
    this.moduleSubtitle = '从阿里云 EMAS 拉取当前时间范围内的聚合问题',
    this.hideHeroFetchCard = false,
    this.hideTimeRangeQuickChips = false,
    this.hideDigestAndTop15Section = false,
    this.listIntroduction,
  });

  final AppController controller;
  final VoidCallback onOpenSettings;
  final String moduleTitle;
  final String moduleSubtitle;
  /// 为 true 时不展示顶部大卡片「一键获取」（由外层工具条负责拉取）。
  final bool hideHeroFetchCard;
  /// 为 true 时隐藏「24 小时 / 7 天 / 30 天」快捷时间片（时间仍显示，由外层控制范围）。
  final bool hideTimeRangeQuickChips;
  /// 为 true 时隐藏按 Digest 直达与 Top15 说明块，减轻性能类列表干扰。
  final bool hideDigestAndTop15Section;
  /// 列表上方说明：`null` 用默认长文案；空字符串则不展示该段。
  final String? listIntroduction;

  Future<void> _exportBundle(BuildContext context) async {
    final dirPath = await getDirectoryPath(confirmButtonText: '选择导出目录');
    if (dirPath == null) return;
    if (!context.mounted) return;
    await controller.exportReportBundleTo(Directory(dirPath));
  }

  Future<void> _saveHtmlToDisk(BuildContext context) async {
    final location = await getSaveLocation(
      suggestedName: 'emas_report_${DateTime.now().millisecondsSinceEpoch}.html',
      acceptedTypeGroups: [const XTypeGroup(label: 'HTML', extensions: ['html', 'htm'])],
    );
    if (location == null) return;
    if (!context.mounted) return;
    await controller.exportHtmlReportToFile(location.path);
  }

  Future<void> _openHtmlInBrowser(BuildContext context) async {
    final r = await controller.writePreviewHtmlAndPath();
    if (!context.mounted) return;
    if (r.startsWith('err')) {
      return;
    }
    final filePath = r.substring(3);
    final uri = Uri.file(filePath);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openTop15AnalysisList(BuildContext context) {
    if (controller.config.validateLlm().isNotEmpty) {
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TopIssuesLlmPage(controller: controller, topN: TopIssuesLlmPage.kDefaultTopN),
      ),
    );
  }

  Future<void> _batchLlm(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('批量 LLM'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: FutureBuilder<String>(
              future: controller.batchAnalyzeSelected(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final text = snap.data ?? '';
                final ok = text.startsWith('ok:');
                final body = ok ? text.substring(3) : text.substring(4);
                return SelectableText(
                  body,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final n = controller.selectedDigestHashes.length;
        final theme = Theme.of(context);
        final needConfig = controller.config.validateEmas().isNotEmpty;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: CustomScrollView(
            slivers: [
              if (!hideHeroFetchCard)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  sliver: SliverToBoxAdapter(
                    child: _HeroFetchCard(
                      controller: controller,
                      needConfig: needConfig,
                      onOpenSettings: onOpenSettings,
                      title: moduleTitle,
                      subtitle: moduleSubtitle,
                    ),
                  ),
                ),
              if (hideHeroFetchCard)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      moduleTitle,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                sliver: SliverToBoxAdapter(child: _ApiContextBanner(controller: controller)),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child: _TimeAndExportRow(
                    controller: controller,
                    needConfig: needConfig,
                    onOpenSettings: onOpenSettings,
                    onSaveHtml: () => _saveHtmlToDisk(context),
                    onOpenBrowser: () => _openHtmlInBrowser(context),
                    onExportBundle: () => _exportBundle(context),
                    selectedCount: n,
                    onBatchLlm: n > 0 ? () => _batchLlm(context) : null,
                    onClearSelection: n > 0 ? () => controller.clearDigestSelection() : null,
                    onOpenTop15List: () => _openTop15AnalysisList(context),
                    hideTimeRangeQuickChips: hideTimeRangeQuickChips,
                    hideDigestAndTop15Section: hideDigestAndTop15Section,
                  ),
                ),
              ),
              if (controller.issuesError != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  sliver: SliverToBoxAdapter(
                    child: _ErrorBanner(message: controller.issuesError!, onOpenSettings: onOpenSettings),
                  ),
                ),
              if (controller.loadingIssues)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if ((listIntroduction ?? _kDefaultListIntroduction).isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        listIntroduction ?? _kDefaultListIntroduction,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                      ),
                    ),
                  ),
                _IssueListSliver(controller: controller),
              ],
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                sliver: SliverToBoxAdapter(child: _PaginationBar(controller: controller)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ApiContextBanner extends StatelessWidget {
  const _ApiContextBanner({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.alt_route, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '当前 OpenAPI：BizModule = ${controller.activeBizModule}'
              '${controller.listNameQuery.isEmpty ? '' : ' · Name 含「${controller.listNameQuery}」'}'
              '${_launchTypeBannerSuffix(controller)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroFetchCard extends StatelessWidget {
  const _HeroFetchCard({
    required this.controller,
    required this.needConfig,
    required this.onOpenSettings,
    required this.title,
    required this.subtitle,
  });

  final AppController controller;
  final bool needConfig;
  final VoidCallback onOpenSettings;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer.withValues(alpha: 0.55),
            cs.surfaceContainerHigh.withValues(alpha: 0.9),
            cs.tertiaryContainer.withValues(alpha: 0.4),
          ],
        ),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.07),
            blurRadius: 32,
            offset: const Offset(0, 12),
            spreadRadius: -4,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, size: 38, color: cs.primary),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.35,
                  color: cs.onSurface,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            needConfig ? '请先在「配置」页填写 EMAS 密钥与 AppKey' : subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: 280,
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                elevation: 0,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: needConfig || controller.loadingIssues
                  ? null
                  : () => controller.refreshIssues(),
              icon: controller.loadingIssues
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                    )
                  : const Icon(Icons.cloud_download_rounded, size: 24),
              label: Text(
                controller.loadingIssues ? '拉取中…' : '一键获取',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.15,
                    ),
              ),
            ),
          ),
          if (needConfig) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('去配置'),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimeAndExportRow extends StatelessWidget {
  const _TimeAndExportRow({
    required this.controller,
    required this.needConfig,
    required this.onOpenSettings,
    required this.onSaveHtml,
    required this.onOpenBrowser,
    required this.onExportBundle,
    required this.selectedCount,
    required this.onOpenTop15List,
    this.onBatchLlm,
    this.onClearSelection,
    this.hideTimeRangeQuickChips = false,
    this.hideDigestAndTop15Section = false,
  });

  final AppController controller;
  final bool needConfig;
  final VoidCallback onOpenSettings;
  final VoidCallback onSaveHtml;
  final VoidCallback onOpenBrowser;
  final VoidCallback onExportBundle;
  final int selectedCount;
  final VoidCallback onOpenTop15List;
  final VoidCallback? onBatchLlm;
  final VoidCallback? onClearSelection;
  final bool hideTimeRangeQuickChips;
  final bool hideDigestAndTop15Section;

  void _setRange(Duration d) => controller.setTimeRangeBack(d);

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MM-dd HH:mm');
    final start = DateTime.fromMillisecondsSinceEpoch(controller.rangeStartMs);
    final end = DateTime.fromMillisecondsSinceEpoch(controller.rangeEndMs);
    final hasRows = (controller.lastIssues?.items ?? const []).isNotEmpty;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${fmt.format(start)}  —  ${fmt.format(end)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (selectedCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('已选 $selectedCount 条', style: Theme.of(context).textTheme.labelLarge),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!hideTimeRangeQuickChips) ...[
                  FilterChip(
                    label: const Text('24 小时'),
                    onSelected: (_) => _setRange(const Duration(hours: 24)),
                  ),
                  FilterChip(
                    label: const Text('7 天'),
                    onSelected: (_) => _setRange(const Duration(days: 7)),
                  ),
                  FilterChip(
                    label: const Text('30 天'),
                    onSelected: (_) => _setRange(const Duration(days: 30)),
                  ),
                ],
                TextButton.icon(
                  onPressed: () => controller.selectAllOnPage(),
                  icon: const Icon(Icons.select_all, size: 18),
                  label: const Text('本页全选'),
                ),
                if (onBatchLlm != null)
                  FilledButton.tonalIcon(
                    onPressed: onBatchLlm,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('批量 LLM'),
                  ),
                if (onClearSelection != null)
                  IconButton(
                    tooltip: '清空选择',
                    onPressed: onClearSelection,
                    icon: const Icon(Icons.deselect),
                  ),
              ],
            ),
            if (!hideDigestAndTop15Section) ...[
              const Divider(height: 28),
              Text('按 Digest 打开单条', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Text(
                '适用于崩溃、ANR（与配置中 BizModule 一致）。请保证上方时间范围覆盖该问题的上报时间，否则 GetIssue 可能无数据。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 10),
              _DigestDirectOpenRow(
                controller: controller,
                needConfig: needConfig,
                onOpenSettings: onOpenSettings,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: hasRows ? onOpenTop15List : null,
                  icon: const Icon(Icons.view_list_outlined),
                  label: const Text('Top15 逐条分析列表'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '对当前已拉取列表按接口排序后的前 15 条（有 digest）分别独立请求 AI；与勾选后「批量 LLM」的串联摘要不同。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                ),
              ),
            ],
            const Divider(height: 28),
            Text('简报与导出', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  onPressed: hasRows ? onSaveHtml : null,
                  icon: const Icon(Icons.save_alt_outlined),
                  label: const Text('下载 HTML'),
                ),
                FilledButton.tonalIcon(
                  onPressed: hasRows ? onOpenBrowser : null,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('浏览器中查看'),
                ),
                OutlinedButton.icon(
                  onPressed: hasRows ? onExportBundle : null,
                  icon: const Icon(Icons.folder_zip_outlined),
                  label: const Text('完整报告包'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 输入 DigestHash 直接进入详情页，走与列表相同的单条分析（AI / GitLab / 去修改）。
class _DigestDirectOpenRow extends StatefulWidget {
  const _DigestDirectOpenRow({
    required this.controller,
    required this.needConfig,
    required this.onOpenSettings,
  });

  final AppController controller;
  final bool needConfig;
  final VoidCallback onOpenSettings;

  @override
  State<_DigestDirectOpenRow> createState() => _DigestDirectOpenRowState();
}

class _DigestDirectOpenRowState extends State<_DigestDirectOpenRow> {
  final _digestCtrl = TextEditingController();

  @override
  void dispose() {
    _digestCtrl.dispose();
    super.dispose();
  }

  void _openDetail(BuildContext context) {
    if (widget.needConfig) {
      return;
    }
    final raw = _digestCtrl.text.trim();
    if (raw.isEmpty) {
      return;
    }
    final digest = raw.replaceAll(RegExp(r'\s+'), '');
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => IssueDetailPage(
          controller: widget.controller,
          digestHash: digest,
          title: 'Digest $digest',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _digestCtrl,
            decoration: InputDecoration(
              hintText: '例如 27K6TFXQ64X90',
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _openDetail(context),
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: FilledButton(
            onPressed: () => _openDetail(context),
            child: const Text('打开并分析'),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onOpenSettings});

  final String message;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.errorContainer.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        leading: Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
        title: Text(message, style: TextStyle(color: cs.onErrorContainer, height: 1.35)),
        trailing: FilledButton.tonal(
          onPressed: onOpenSettings,
          child: const Text('去配置'),
        ),
      ),
    );
  }
}

class _IssueListSliver extends StatelessWidget {
  const _IssueListSliver({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final list = controller.lastIssues?.items ?? const <IssueListItem>[];
    if (list.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                controller.config.validateEmas().isEmpty ? '暂无数据，点击上方「一键获取」' : '请先完成侧栏「配置」',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final it = list[index];
            return Padding(
              padding: EdgeInsets.only(bottom: index == list.length - 1 ? 0 : 12),
              child: _IssueEmasListCard(controller: controller, item: it),
            );
          },
          childCount: list.length,
        ),
      ),
    );
  }
}

String _stackPreviewOneLine(String? stack) {
  if (stack == null || stack.trim().isEmpty) return '—';
  final t = stack.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length > 200) return '${t.substring(0, 200)}…';
  return t;
}

/// 与 EMAS 控制台类似的单条列表卡片：摘要、指标、堆栈预览、「查看」触发模型分析。
class _IssueEmasListCard extends StatelessWidget {
  const _IssueEmasListCard({required this.controller, required this.item});

  final AppController controller;
  final IssueListItem item;

  @override
  Widget build(BuildContext context) {
    final digest = item.digestHash;
    final selected = digest != null && controller.selectedDigestHashes.contains(digest);
    final cs = Theme.of(context).colorScheme;

    void openQuick() {
      if (digest == null) return;
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => IssueQuickAnalysisPage(
            controller: controller,
            digestHash: digest,
            title: item.errorName ?? '问题',
            listStack: item.stack,
            errorCount: item.errorCount,
            errorDeviceCount: item.errorDeviceCount,
          ),
        ),
      );
    }

    void openDetail() {
      if (digest == null) return;
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => IssueDetailPage(
            controller: controller,
            digestHash: digest,
            title: item.errorName ?? '详情',
            listStack: item.stack,
            errorCount: item.errorCount,
            errorDeviceCount: item.errorDeviceCount,
          ),
        ),
      );
    }

    return Material(
      color: selected ? cs.primaryContainer.withValues(alpha: 0.28) : cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 4, top: 2),
                    child: Checkbox(
                      value: selected,
                      onChanged: digest == null
                          ? null
                          : (_) {
                              controller.toggleDigestSelection(digest);
                            },
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.errorName ?? '(无标题)',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _ListMetricChip(icon: Icons.repeat, label: '次数', value: '${item.errorCount ?? '—'}'),
                            _ListMetricChip(icon: Icons.devices, label: '设备', value: '${item.errorDeviceCount ?? '—'}'),
                            if (digest != null)
                              SelectableText(
                                digest,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      fontFamily: 'monospace',
                                      color: cs.onSurfaceVariant,
                                    ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '堆栈',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _stackPreviewOneLine(item.stack),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.35,
                        color: cs.onSurface,
                      ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton(
                    onPressed: digest == null ? null : openQuick,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    child: const Text('查看'),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: digest == null ? null : openDetail,
                    child: const Text('详情'),
                  ),
                  const Spacer(),
                  Text(
                    '勾选参与批量 LLM',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.outline),
                  ),
                ],
              ),
            ],
          ),
      ),
    );
  }
}

class _ListMetricChip extends StatelessWidget {
  const _ListMetricChip({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            '$label $value',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final total = controller.lastIssues?.total ?? 0;
    final rawPages = controller.lastIssues?.pages ?? 1;
    final pages = rawPages < 1 ? 1 : rawPages;
    final list = controller.lastIssues?.items ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        Text('共 $total 条 · 第 ${controller.pageIndex} / $pages 页'),
        const Spacer(),
        FilledButton.tonal(
          onPressed: controller.pageIndex <= 1 || controller.loadingIssues
              ? null
              : () {
                  controller.pageIndex--;
                  controller.refreshIssues();
                },
          child: const Text('上一页'),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: controller.loadingIssues || controller.pageIndex >= pages
              ? null
              : () {
                  controller.pageIndex++;
                  controller.refreshIssues();
                },
          child: const Text('下一页'),
        ),
      ],
    );
  }
}
