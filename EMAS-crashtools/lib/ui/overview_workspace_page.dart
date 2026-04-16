import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';

/// 实时概览：参照控制台「实时大盘」常见指标，用 GetIssues 各 Biz 的 Total 近似展示（脚注说明口径）。
class OverviewWorkspacePage extends StatelessWidget {
  const OverviewWorkspacePage({
    super.key,
    required this.controller,
    required this.onOpenSettings,
  });

  final AppController controller;
  final VoidCallback onOpenSettings;

  static String _bizTitle(String k) {
    switch (k) {
      case 'crash':
        return '崩溃';
      case 'anr':
        return 'ANR';
      case 'startup':
        return '启动';
      case 'exception':
        return '异常';
      default:
        return k;
    }
  }

  static String? _bizHint(String k) {
    switch (k) {
      case 'startup':
        return '聚合条数，非耗时';
      case 'exception':
        return '含 OOM 等';
      default:
        return null;
    }
  }

  void _setCalendarDays(int days) {
    controller.clearWorkspaceBizOverride();
    controller.setTimeRangeLastCalendarDays(days);
  }

  Future<void> _refresh() => controller.refreshOverviewDashboard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final needConfig = controller.config.validateEmas().isNotEmpty;
        final snap = controller.overviewMetrics;
        final fmt = DateFormat('yyyy/MM/dd HH:mm');
        final start = DateTime.fromMillisecondsSinceEpoch(controller.rangeStartMs);
        final end = DateTime.fromMillisecondsSinceEpoch(controller.rangeEndMs);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '实时概览',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.35,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '筛选：工作台「应用版本（可选，对应 GetIssues Name）」+ 时间范围「最近 / 7 天 / 30 天」（自然日，最新完整日为昨天）。指标为 GetIssues 聚合条数，非控制台图表次数/率。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 20),
              Card(
                elevation: 0,
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('时间范围', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Text(
                        '${fmt.format(start)} — ${fmt.format(end)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('最近'),
                            selected: controller.matchesQuickCalendarDays(1),
                            onSelected: (_) => _setCalendarDays(1),
                          ),
                          FilterChip(
                            label: const Text('7 天'),
                            selected: controller.matchesQuickCalendarDays(7),
                            onSelected: (_) => _setCalendarDays(7),
                          ),
                          FilterChip(
                            label: const Text('30 天'),
                            selected: controller.matchesQuickCalendarDays(30),
                            onSelected: (_) => _setCalendarDays(30),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: 280,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: needConfig || controller.loadingOverviewMetrics ? null : _refresh,
                          icon: controller.loadingOverviewMetrics
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                                )
                              : const Icon(Icons.sync),
                          label: Text(controller.loadingOverviewMetrics ? '拉取中…' : '拉取概览数据'),
                        ),
                      ),
                      if (needConfig) ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: onOpenSettings,
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('去配置 EMAS'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (controller.overviewDashboardError != null) ...[
                const SizedBox(height: 12),
                Material(
                  color: cs.errorContainer.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      controller.overviewDashboardError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onErrorContainer),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                '所选时间范围内',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  final cols = w >= 900 ? 4 : (w >= 520 ? 2 : 1);
                  final tileW = cols == 1 ? w : (w - 12 * (cols - 1)) / cols;
                  const keys = ['crash', 'anr', 'startup', 'exception'];
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: keys.map((k) {
                      final err = snap?.perBizError[k];
                      final v = snap?.byBizTotal[k];
                      return SizedBox(
                        width: tileW,
                        child: _OverviewMetricCard(
                          title: _bizTitle(k),
                          hint: _bizHint(k),
                          valueText: err != null ? '—' : '${v ?? '—'}',
                          errorText: err,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                '今日（本地 0 点—此刻）',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  final cols = w >= 520 ? 2 : 1;
                  final tileW = cols == 1 ? w : (w - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: tileW,
                        child: _OverviewMetricCard(
                          title: '今日崩溃聚合',
                          hint: 'crash · GetIssues Total',
                          valueText: snap?.todayError != null ? '—' : '${snap?.todayCrashTotal ?? '—'}',
                          errorText: snap?.todayError,
                        ),
                      ),
                      SizedBox(
                        width: tileW,
                        child: _OverviewMetricCard(
                          title: '今日影响设备',
                          hint: '控制台有此项；当前 OpenAPI 未提供',
                          valueText: '—',
                          errorText: null,
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (snap != null && snap.crashPreviewItems.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  '崩溃摘要（前几条）',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    children: snap.crashPreviewItems.map((it) {
                      return ListTile(
                        dense: true,
                        title: Text(it.errorName ?? '-', maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          'digest ${it.digestHash ?? '-'} · 次数 ${it.errorCount ?? '—'} · 设备 ${it.errorDeviceCount ?? '—'}',
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ] else if (!controller.loadingOverviewMetrics && !needConfig && snap == null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    '选择时间范围后点击「拉取概览数据」。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                '趋势图、崩溃率、启动耗时等请以阿里云控制台为准。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OverviewMetricCard extends StatelessWidget {
  const _OverviewMetricCard({
    required this.title,
    required this.valueText,
    this.hint,
    this.errorText,
  });

  final String title;
  final String valueText;
  final String? hint;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
            const SizedBox(height: 10),
            Text(
              valueText,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: errorText != null ? cs.onSurfaceVariant : cs.primary,
                  ),
            ),
            if (errorText != null) ...[
              const SizedBox(height: 6),
              Text(
                errorText!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
