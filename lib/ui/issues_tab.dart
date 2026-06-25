import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../aliyun/emas_appmonitor_client.dart';
import '../app_controller.dart';
import '../constants/app_constants.dart';
import 'batch_analysis_page.dart';
import 'issue_detail_page.dart';
import 'issue_quick_analysis_page.dart';
import 'widgets/version_filter_widget.dart';


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

/// 列表工作台：一键拉取、TOP10 总览、列表卡片与详情入口（各功能模块复用）。
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

  /// 先拉列表第 1 页 10 条，再大模型生成 TOP10 合并总览（无其它筛选）。
  Future<void> _openPullTop10AggregateReport(BuildContext context, String moduleTitle) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: Text('$moduleTitle · TOP10 总览'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          body: Padding(
            padding: EdgeInsets.all(kSpacing16),
            child: FutureBuilder<String>(
              future: controller.pullTop10AggregateReportMarkdown(),
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
        final theme = Theme.of(context);
        final needConfig = controller.config.validateEmas().isNotEmpty;
        final listIntro = listIntroduction?.trim();

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: CustomScrollView(
            slivers: [
              if (!hideHeroFetchCard)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(kSpacing24, kSpacing20, kSpacing24, kSpacing8),
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
                  padding: EdgeInsets.fromLTRB(kSpacing24, kSpacing16, kSpacing24, kSpacing4),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      moduleTitle,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(kSpacing24, 0, kSpacing24, kSpacing8),
                sliver: SliverToBoxAdapter(child: _ApiContextBanner(controller: controller)),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: kSpacing24),
                sliver: SliverToBoxAdapter(
                  child: _TimeAndExportRow(
                    controller: controller,
                    onPullTop10Aggregate: () => _openPullTop10AggregateReport(context, moduleTitle),
                    hideTimeRangeQuickChips: hideTimeRangeQuickChips,
                    timeRangeEmbeddedInHero: !hideHeroFetchCard && !hideTimeRangeQuickChips,
                    showSessionQueryFields: hideHeroFetchCard,
                  ),
                ),
              ),
              if (controller.issuesError != null)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(kSpacing24, kSpacing12, kSpacing24, 0),
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
                    padding: EdgeInsets.fromLTRB(kSpacing24, kSpacing8, kSpacing24, 0),
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
                // 批量操作栏
                if (controller.selectedDigestHashes.isNotEmpty)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(kSpacing24, kSpacing12, kSpacing24, kSpacing8),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '已选中 ${controller.selectedDigestHashes.length} 个问题',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: () {
                              final hashes = controller.selectedDigestHashes.toList();
                              if (hashes.isEmpty) return;
                              Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => BatchAnalysisPage(
                                    controller: controller,
                                    digestHashes: hashes,
                                    bizModule: controller.activeBizModule,
                                    startTimeMs: controller.rangeStartMs,
                                    endTimeMs: controller.rangeEndMs,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.psychology_rounded, size: 18),
                            label: const Text('智能分析'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: controller.clearSelectedDigestHashes,
                            child: const Text('清空'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              SliverPadding(
                padding: EdgeInsets.fromLTRB(kSpacing24, kSpacing8, kSpacing24, kSpacing24),
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
      padding: EdgeInsets.symmetric(horizontal: kSpacing12, vertical: kSpacing8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: kOpacityHeavy),
        borderRadius: AppBorderRadius.sm,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: kOpacityLight)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.tune_rounded, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'BizModule=${getBizModuleDisplayName(controller.activeBizModule)}'
              '${controller.listVersionFilter.isEmpty ? ' · 首现版本：未传' : ' · 首现版本：${controller.listVersionFilter}'}'
              '${controller.effectiveEmasPackageNameForRequest == null ? ' · 包名：未传' : ' · 包名：${controller.effectiveEmasPackageNameForRequest}'}'
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
      color: cs.surfaceContainerHighest.withValues(alpha: kOpacitySemiTransparent),
      elevation: 0,
      borderRadius: AppBorderRadius.lg,
      child: Container(
        padding: EdgeInsets.fromLTRB(kSpacing20, kSpacing18, kSpacing20, kSpacing18),
        decoration: BoxDecoration(
          borderRadius: AppBorderRadius.lg,
          border: Border.all(color: cs.outlineVariant.withValues(alpha: kOpacityLight)),
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
                    label: const Text('全部'),
                    selected: controller.matchesQuickCalendarDays(90),
                    onSelected: (_) => controller.setTimeRangeLastCalendarDays(90),
                  ),
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
            SizedBox(height: showQuickTimeChips ? 14 : 12),
            _WorkbenchQueryTwoFields(controller: controller),
            const SizedBox(height: 14),
            FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(vertical: kSpacing12),
                  shape: RoundedRectangleBorder(borderRadius: AppBorderRadius.md),
                ),
                onPressed: needConfig || controller.loadingIssues
                    ? null
                    : () => controller.refreshIssues(resetPageSizeToDefault: true),
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

/// 工作台：应用版本（Name）与应用包名（PackageName）两个会话字段，无长说明。
class _WorkbenchQueryTwoFields extends StatefulWidget {
  const _WorkbenchQueryTwoFields({required this.controller});

  final AppController controller;

  @override
  State<_WorkbenchQueryTwoFields> createState() => _WorkbenchQueryTwoFieldsState();
}

class _WorkbenchQueryTwoFieldsState extends State<_WorkbenchQueryTwoFields> {
  late final TextEditingController _pkgCtrl;
  final FocusNode _pkgFocus = FocusNode();
  late List<String> _availableFirstVersions;    // FirstVersion 列表（问题首次出现版本）
  late List<String> _availableAppVersions;      // AppVersion 列表（应用版本）
  late bool _loadingVersions;

  @override
  void initState() {
    super.initState();
    _pkgCtrl = TextEditingController(text: widget.controller.listPackageNameQuery);
    _availableFirstVersions = [];
    _availableAppVersions = [];
    _loadingVersions = false;
    _loadVersions();
  }

  @override
  void dispose() {
    _pkgCtrl.dispose();
    _pkgFocus.dispose();
    super.dispose();
  }

  Future<void> _loadVersions() async {
    setState(() => _loadingVersions = true);
    try {
      final versions = await widget.controller.fetchAvailableVersions(
        bizModule: widget.controller.activeBizModule,
        startTimeMs: widget.controller.rangeStartMs,
        endTimeMs: widget.controller.rangeEndMs,
      );
      setState(() {
        // 首现版本列表（通过 get-issues 获取）
        _availableFirstVersions = versions;
        // 应用版本列表（与首现版本相同来源，也可后续从样本补充）
        _availableAppVersions = versions;
        _loadingVersions = false;
      });
    } catch (e) {
      setState(() {
        _availableFirstVersions = [];
        _availableAppVersions = [];
        _loadingVersions = false;
      });
    }
  }

  void _apply() {
    widget.controller.setListPackageNameQuery(_pkgCtrl.text);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        if (!_pkgFocus.hasFocus) {
          final want = widget.controller.listPackageNameQuery;
          if (_pkgCtrl.text != want) {
            _pkgCtrl.value = TextEditingValue(
              text: want,
              selection: TextSelection.collapsed(offset: want.length),
            );
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 第一行：首现版本（左）+ 应用版本（右）
            Row(
              children: [
                // 首现版本筛选（左侧）
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '首现版本',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 8),
                      VersionFilterWidget(
                        versions: _availableFirstVersions,
                        selectedVersion: widget.controller.listFirstVersionFilter.isEmpty
                          ? null
                          : widget.controller.listFirstVersionFilter,
                        onVersionChanged: (version) {
                          widget.controller.setListFirstVersionFilter(version ?? '');
                          widget.controller.refreshIssues(resetPageSizeToDefault: true);
                        },
                        isLoading: _loadingVersions,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // 应用版本筛选（右侧）
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '应用版本',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 8),
                      VersionFilterWidget(
                        versions: _availableAppVersions,
                        selectedVersion: widget.controller.listVersionFilter.isEmpty
                          ? null
                          : widget.controller.listVersionFilter,
                        onVersionChanged: (version) {
                          widget.controller.setListVersionFilter(version ?? '');
                          widget.controller.refreshIssues(resetPageSizeToDefault: true);
                        },
                        isLoading: _loadingVersions,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 应用包名输入
            TextField(
              controller: _pkgCtrl,
              focusNode: _pkgFocus,
              decoration: const InputDecoration(
                labelText: '应用包名',
                hintText: '可空',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _apply(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: _apply,
                child: const Text('应用'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TimeAndExportRow extends StatelessWidget {
  const _TimeAndExportRow({
    required this.controller,
    required this.onPullTop10Aggregate,
    this.hideTimeRangeQuickChips = false,
    this.timeRangeEmbeddedInHero = false,
    this.showSessionQueryFields = false,
  });

  final AppController controller;
  final VoidCallback onPullTop10Aggregate;
  final bool hideTimeRangeQuickChips;
  /// 为 true 时顶部大卡片已含时间快捷片；本卡片仅保留 TOP10 与（可选）查询输入。
  final bool timeRangeEmbeddedInHero;
  /// 性能分析等无大卡片时：展示应用版本 / 包名输入。
  final bool showSessionQueryFields;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final emasMiss = controller.config.validateEmas();
    final emasOk = emasMiss.isEmpty;
    final llmMiss = controller.config.validateLlm();
    final llmOk = llmMiss.isEmpty;
    final canRun = emasOk && llmOk;
    final tip = !emasOk
        ? '请先完成 EMAS：${emasMiss.join('、')}'
        : (!llmOk ? '请先完成大模型：${llmMiss.join('、')}' : '按当前时间范围与 Biz 拉第 1 页 10 条并生成合并总览（不依赖勾选）');

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: kOpacityMedium),
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.lg,
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: kOpacityLight)),
      ),
      child: Padding(
        padding: EdgeInsets.all(kSpacing16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hideTimeRangeQuickChips && !timeRangeEmbeddedInHero) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('全部'),
                    selected: controller.matchesQuickCalendarDays(90),
                    onSelected: (_) => controller.setTimeRangeLastCalendarDays(90),
                  ),
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
              const SizedBox(height: 12),
            ],
            if (showSessionQueryFields) ...[
              _WorkbenchQueryTwoFields(controller: controller),
              const SizedBox(height: 12),
            ],
            Tooltip(
              message: tip,
              child: FilledButton.icon(
                onPressed: canRun ? onPullTop10Aggregate : null,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: kSpacing14),
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
                icon: const Icon(Icons.filter_9_plus, size: 22),
                label: const Text('拉取 TOP10 总览'),
              ),
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
      color: cs.errorContainer.withValues(alpha: kOpacityHeavy),
      borderRadius: AppBorderRadius.lg,
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
              padding: EdgeInsets.only(bottom: index == list.length - 1 ? 0 : kSpacing12),
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
/// 
/// 支持的业务模块：
/// - crash: 崩溃分析
/// - anr: ANR（Application Not Responding）
/// - startup: 启动性能
/// - exception: 自定义异常
/// - h5WhiteScreen: H5 白屏
/// - lag: 卡顿
/// - h5JsError: H5 JS 错误
/// - custom: 自定义监控
({String count, String rate, String device, String deviceRate}) _issueMetricColumnLabels(String bizModule) {
  switch (bizModule.trim().toLowerCase()) {
    case 'crash':
      return (count: '崩溃数', rate: '崩溃率', device: '影响设备数', deviceRate: '影响设备率');
    case 'anr':
      return (count: 'ANR 数', rate: 'ANR 率', device: '影响设备数', deviceRate: '影响设备率');
    case 'startup':
      return (count: '启动次数', rate: '启动率', device: '影响设备数', deviceRate: '影响设备率');
    case 'lag':
      return (count: '卡顿数', rate: '卡顿率', device: '影响设备数', deviceRate: '影响设备率');
    case 'exception':
      return (count: '异常数', rate: '异常率', device: '影响设备数', deviceRate: '影响设备率');
    case 'h5whitescreen':
      return (count: '白屏数', rate: '白屏率', device: '影响设备数', deviceRate: '影响设备率');
    case 'h5jserror':
      return (count: 'JS错误数', rate: 'JS错误率', device: '影响设备数', deviceRate: '影响设备率');
    case 'custom':
      return (count: '自定义数', rate: '自定义率', device: '影响设备数', deviceRate: '影响设备率');
    default:
      return (count: '次数', rate: '比率', device: '影响设备数', deviceRate: '影响设备率');
  }
}

/// 获取 BizModule 的友好中文名称
/// 
/// 用于 UI 展示，将技术性的 BizModule 转换为易读的中文名称
String getBizModuleDisplayName(String bizModule) {
  switch (bizModule.trim().toLowerCase()) {
    case 'crash':
      return '崩溃分析';
    case 'anr':
      return 'ANR';
    case 'startup':
      return '启动性能';
    case 'exception':
      return '自定义异常';
    case 'h5whitescreen':
      return 'H5 白屏';
    case 'lag':
    case 'h5jserror':
      return 'H5 JS 错误';
    case 'custom':
      return '自定义监控';
    default:
      return bizModule;
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
            bizModule: controller.activeBizModule,
            pageNum: controller.pageIndex,
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
            pageNum: controller.pageIndex,
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
      color: selected ? cs.primaryContainer.withValues(alpha: kOpacityVeryLight) : cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.lg,
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: kOpacitySemiTransparent)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(kSpacing12, kSpacing12, kSpacing12, kSpacing10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(right: kSpacing2, top: kSpacing2),
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
                        padding: EdgeInsets.fromLTRB(kSpacing10, kSpacing8, kSpacing10, kSpacing8),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: kOpacityMedium),
                          borderRadius: AppBorderRadius.sm,
                        ),
                        child: Text(
                          _stackPreviewOneLine(item.stack),
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                height: 1.35,
                                color: cs.onSurface.withValues(alpha: kOpacityStrong),
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
                  if (item.errorType != null && item.errorType!.isNotEmpty)
                    _IssueTableMetric(label: '问题类型', value: item.errorType ?? '—'),
                  if (item.eventTime != null && item.eventTime!.isNotEmpty)
                    _IssueTableMetric(label: '事件时间', value: item.eventTime ?? '—'),
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
                    padding: EdgeInsets.symmetric(horizontal: kSpacing18, vertical: kSpacing10),
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
      padding: EdgeInsets.only(right: kSpacing20),
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
      padding: EdgeInsets.symmetric(horizontal: kSpacing10, vertical: kSpacing6),
      decoration: BoxDecoration(
        color: pending ? cs.errorContainer.withValues(alpha: kOpacityHeavy) : cs.surfaceContainerHighest.withValues(alpha: kOpacityHeavy),
        borderRadius: AppBorderRadius.lg,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: kOpacityMedium)),
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
