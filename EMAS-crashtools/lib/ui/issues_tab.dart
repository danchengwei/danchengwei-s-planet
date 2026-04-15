import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../aliyun/emas_appmonitor_client.dart';
import '../app_controller.dart';
import 'issue_detail_page.dart';
import 'issue_quick_analysis_page.dart';


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

/// 列表工作台：一键拉取、HTML 导出/浏览器预览、列表卡片与详情入口（各功能模块复用）。
class IssuesTab extends StatelessWidget {
  const IssuesTab({
    super.key,
    required this.controller,
    required this.onOpenSettings,
    this.moduleTitle = '数据列表',
    this.moduleSubtitle = '',
    this.hideHeroFetchCard = false,
    this.hideTimeRangeQuickChips = false,
    this.listIntroduction,
  });

  final AppController controller;
  final VoidCallback onOpenSettings;
  final String moduleTitle;
  final String moduleSubtitle;
  /// 为 true 时不展示顶部大卡片「一键获取」（由外层工具条负责拉取）。
  final bool hideHeroFetchCard;
  /// 为 true 时隐藏「最近 / 7 天 / 30 天」快捷时间片（时间仍显示，由外层控制范围）。
  final bool hideTimeRangeQuickChips;
  /// 列表上方可选说明；非空且 trim 后非空才展示。
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
        final listIntro = listIntroduction?.trim();

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
                      showQuickTimeChips: !hideTimeRangeQuickChips,
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
                    onSaveHtml: () => _saveHtmlToDisk(context),
                    onOpenBrowser: () => _openHtmlInBrowser(context),
                    onExportBundle: () => _exportBundle(context),
                    selectedCount: n,
                    onBatchLlm: n > 0 ? () => _batchLlm(context) : null,
                    onClearSelection: n > 0 ? () => controller.clearDigestSelection() : null,
                    hideTimeRangeQuickChips: hideTimeRangeQuickChips,
                    timeRangeEmbeddedInHero: !hideHeroFetchCard && !hideTimeRangeQuickChips,
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
                if (listIntro != null && listIntro.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        listIntro,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.tune_rounded, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'BizModule=${controller.activeBizModule}'
              '${controller.listNameQuery.isEmpty ? ' · 应用版本(Name)：未设置' : ' · 应用版本(Name)：${controller.listNameQuery}'}'
              '${_launchTypeBannerSuffix(controller)}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
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
    this.showQuickTimeChips = true,
  });

  final AppController controller;
  final bool needConfig;
  final VoidCallback onOpenSettings;
  final String title;
  final String subtitle;
  final bool showQuickTimeChips;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showSubtitle = needConfig || subtitle.trim().isNotEmpty;
    final fmt = DateFormat('MM-dd HH:mm');
    final start = DateTime.fromMillisecondsSinceEpoch(controller.rangeStartMs);
    final end = DateTime.fromMillisecondsSinceEpoch(controller.rangeEndMs);
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_download_rounded, size: 22, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                  ),
                ),
              ],
            ),
            if (showSubtitle) ...[
              const SizedBox(height: 8),
              Text(
                needConfig ? '请先在「配置」填写 EMAS 与 AppKey' : subtitle.trim(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ],
            if (showQuickTimeChips) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${fmt.format(start)}  —  ${fmt.format(end)}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('最近'),
                    selected: controller.matchesQuickCalendarDays(1),
                    onSelected: (_) => controller.setTimeRangeLastCalendarDays(1),
                  ),
                  FilterChip(
                    label: const Text('7 天'),
                    selected: controller.matchesQuickCalendarDays(7),
                    onSelected: (_) => controller.setTimeRangeLastCalendarDays(7),
                  ),
                  FilterChip(
                    label: const Text('30 天'),
                    selected: controller.matchesQuickCalendarDays(30),
                    onSelected: (_) => controller.setTimeRangeLastCalendarDays(30),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: needConfig || controller.loadingIssues
                    ? null
                    : () => controller.refreshIssues(),
                icon: controller.loadingIssues
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                      )
                    : const Icon(Icons.sync_rounded, size: 20),
                label: Text(
                  controller.loadingIssues ? '拉取中…' : '一键获取',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            if (needConfig) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('去配置'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: cs.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimeAndExportRow extends StatelessWidget {
  const _TimeAndExportRow({
    required this.controller,
    required this.onSaveHtml,
    required this.onOpenBrowser,
    required this.onExportBundle,
    required this.selectedCount,
    this.onBatchLlm,
    this.onClearSelection,
    this.hideTimeRangeQuickChips = false,
    this.timeRangeEmbeddedInHero = false,
  });

  final AppController controller;
  final VoidCallback onSaveHtml;
  final VoidCallback onOpenBrowser;
  final VoidCallback onExportBundle;
  final int selectedCount;
  final VoidCallback? onBatchLlm;
  final VoidCallback? onClearSelection;
  final bool hideTimeRangeQuickChips;
  /// 为 true 时时间与「最近/7 天/30 天」已在顶部「一键获取」卡片中展示。
  final bool timeRangeEmbeddedInHero;

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
            if (!timeRangeEmbeddedInHero) ...[
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
            ] else if (selectedCount > 0) ...[
              Row(
                children: [
                  Expanded(
                    child: Text('已选 $selectedCount 条', style: Theme.of(context).textTheme.labelLarge),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!hideTimeRangeQuickChips && !timeRangeEmbeddedInHero) ...[
                  FilterChip(
                    label: const Text('最近'),
                    selected: controller.matchesQuickCalendarDays(1),
                    onSelected: (_) => controller.setTimeRangeLastCalendarDays(1),
                  ),
                  FilterChip(
                    label: const Text('7 天'),
                    selected: controller.matchesQuickCalendarDays(7),
                    onSelected: (_) => controller.setTimeRangeLastCalendarDays(7),
                  ),
                  FilterChip(
                    label: const Text('30 天'),
                    selected: controller.matchesQuickCalendarDays(30),
                    onSelected: (_) => controller.setTimeRangeLastCalendarDays(30),
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

/// 与 EMAS 列表表头一致；崩溃 / ANR / 卡顿 / 异常共用同一套列语义。
({String count, String rate, String device, String deviceRate}) _issueMetricColumnLabels(String bizModule) {
  switch (bizModule.trim().toLowerCase()) {
    case 'crash':
      return (count: '崩溃数', rate: '崩溃率', device: '影响设备数', deviceRate: '影响设备率');
    case 'anr':
      return (count: 'ANR 数', rate: 'ANR 率', device: '影响设备数', deviceRate: '影响设备率');
    case 'block':
      return (count: '卡顿数', rate: '卡顿率', device: '影响设备数', deviceRate: '影响设备率');
    case 'exception':
      return (count: '异常数', rate: '异常率', device: '影响设备数', deviceRate: '影响设备率');
    default:
      return (count: '次数', rate: '比率', device: '影响设备数', deviceRate: '影响设备率');
  }
}

String _formatIssuePercent(double? p) {
  if (p == null || p.isNaN) return '—';
  final t = p == p.roundToDouble() ? '${p.toInt()}' : p.toStringAsFixed(2);
  return '$t%';
}

/// 与 EMAS 控制台列表行一致：Digest+复制、类型标题、摘要/堆栈、指标列、状态（ANR/卡顿/异常布局相同）。
class _IssueEmasListCard extends StatelessWidget {
  const _IssueEmasListCard({required this.controller, required this.item});

  final AppController controller;
  final IssueListItem item;

  @override
  Widget build(BuildContext context) {
    final digest = item.digestHash;
    final selected = digest != null && controller.selectedDigestHashes.contains(digest);
    final cs = Theme.of(context).colorScheme;
    final labels = _issueMetricColumnLabels(controller.activeBizModule);
    final titles = item.displayTitles();
    final primaryTitle = titles.$1;
    final secondaryLine = titles.$2;

    void openQuick() {
      if (digest == null) return;
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => IssueQuickAnalysisPage(
            controller: controller,
            digestHash: digest,
            title: primaryTitle,
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
            title: primaryTitle,
            listStack: item.stack,
            errorCount: item.errorCount,
            errorDeviceCount: item.errorDeviceCount,
          ),
        ),
      );
    }

    void copyDigest() {
      if (digest == null) return;
      Clipboard.setData(ClipboardData(text: digest));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制 Digest'), behavior: SnackBarBehavior.floating),
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
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 2, top: 2),
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
                      if (digest != null)
                        Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                digest,
                                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurfaceVariant,
                                    ),
                              ),
                            ),
                            IconButton(
                              tooltip: '复制 Digest',
                              visualDensity: VisualDensity.compact,
                              onPressed: copyDigest,
                              icon: Icon(Icons.copy_rounded, size: 18, color: cs.primary),
                            ),
                          ],
                        ),
                      Text(
                        primaryTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                      ),
                      if (secondaryLine != null && secondaryLine.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          secondaryLine,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.35,
                              ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _stackPreviewOneLine(item.stack),
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                height: 1.35,
                                color: cs.onSurface.withValues(alpha: 0.88),
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IssueTableMetric(label: labels.count, value: '${item.errorCount ?? '—'}'),
                  _IssueTableMetric(label: labels.rate, value: _formatIssuePercent(item.errorRatePercent)),
                  _IssueTableMetric(label: labels.device, value: '${item.errorDeviceCount ?? '—'}'),
                  _IssueTableMetric(label: labels.deviceRate, value: _formatIssuePercent(item.deviceRatePercent)),
                  _IssueTableMetric(label: '首现版本', value: item.firstVersion ?? '—'),
                  _IssueTableMetric(
                    label: '状态',
                    value: '',
                    minWidth: 120,
                    child: _IssueStatusBadge(status: item.issueStatus),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  onPressed: digest == null ? null : openQuick,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  ),
                    child: const Text('智能分析'),
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

class _IssueTableMetric extends StatelessWidget {
  const _IssueTableMetric({
    required this.label,
    required this.value,
    this.child,
    this.minWidth = 88,
  });

  final String label;
  final String value;
  final Widget? child;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: SizedBox(
        width: minWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
            ),
            const SizedBox(height: 6),
            if (child != null)
              child!
            else
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IssueStatusBadge extends StatelessWidget {
  const _IssueStatusBadge({this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = status?.trim();
    if (t == null || t.isEmpty) {
      return Text('—', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700));
    }
    final pending = t.contains('未处理') || t.contains('待处理') || t.contains('待办');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: pending ? cs.errorContainer.withValues(alpha: 0.65) : cs.surfaceContainerHighest.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pending) ...[
            Icon(Icons.circle, size: 7, color: cs.error),
            const SizedBox(width: 6),
          ],
          Text(
            t,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: pending ? cs.onErrorContainer : cs.onSurface,
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
