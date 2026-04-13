import 'package:flutter/material.dart';

import '../app_controller.dart';

/// 实时概览：时间范围 + 拉取列表统计 + 可选 AI 简报（使用当前配置默认 Biz，不覆盖工作台子模块）。
class OverviewWorkspacePage extends StatelessWidget {
  const OverviewWorkspacePage({
    super.key,
    required this.controller,
    required this.onOpenSettings,
  });

  final AppController controller;
  final VoidCallback onOpenSettings;

  void _setRange(Duration d) {
    controller.clearWorkspaceBizOverride();
    controller.setListNameQuery(controller.config.emasListNameQuery);
    controller.setTimeRangeBack(d);
  }

  Future<void> _refresh() async {
    controller.clearWorkspaceBizOverride();
    controller.setListNameQuery(controller.config.emasListNameQuery);
    await controller.refreshIssues();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final needConfig = controller.config.validateEmas().isNotEmpty;
        final total = controller.lastIssues?.total ?? 0;
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
              const SizedBox(height: 8),
              Text(
                '使用「配置」中的 BizModule 与密钥，不按左侧崩溃子模块覆盖；适合先看整体聚合规模。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 24),
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
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
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
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: 260,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: needConfig || controller.loadingIssues ? null : _refresh,
                          icon: controller.loadingIssues
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                                )
                              : const Icon(Icons.sync),
                          label: Text(controller.loadingIssues ? '拉取中…' : '拉取概览数据'),
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
              const SizedBox(height: 20),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('聚合规模', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Text(
                        '配置 BizModule：${controller.config.bizModule}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '时间范围内聚合条数（约）：$total',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (controller.lastIssues != null && controller.lastIssues!.items.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('本页前几条摘要', style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 8),
                        ...controller.lastIssues!.items.take(5).map(
                              (it) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(it.errorName ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  'digest: ${it.digestHash ?? '-'}',
                                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                ),
                              ),
                            ),
                      ] else if (!controller.loadingIssues && !needConfig)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '点击「拉取概览数据」后在此展示统计与摘要。',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '更细维度请使用左侧「崩溃分析」各子项或「性能分析」。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }
}
