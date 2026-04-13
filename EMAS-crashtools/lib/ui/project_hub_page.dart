import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';

/// 多项目管理：选择、新建、重命名、删除；本地持久化由 [AppController] 负责。
class ProjectHubPage extends StatelessWidget {
  const ProjectHubPage({super.key, required this.controller});

  final AppController controller;

  Future<void> _promptName(
    BuildContext context, {
    required String title,
    required String hint,
    required ValueChanged<String> onSubmit,
  }) async {
    final textCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: textCtrl,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (_) => Navigator.pop(ctx, true),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
          ],
        ),
      );
      if (ok == true && context.mounted) {
        onSubmit(textCtrl.text);
      }
    } finally {
      textCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final entries = controller.projectEntriesUnmodifiable;
        final selected = controller.hubSelectedProjectId;
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  t.colorScheme.surface,
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '选择项目',
                          style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '每个项目拥有独立的 EMAS、GitLab、大模型与 Agent 配置，数据保存在本机。点击列表中的项目即可进入工作台。',
                          style: t.textTheme.bodyMedium?.copyWith(
                            color: t.colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: Material(
                            elevation: 0,
                            color: t.colorScheme.surface.withValues(alpha: 0.92),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: t.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: entries.length,
                              separatorBuilder: (_, index) => Divider(
                                height: 1,
                                color: t.colorScheme.outlineVariant.withValues(alpha: 0.35),
                              ),
                              itemBuilder: (context, i) {
                                final e = entries[i];
                                final isSel = e.id == selected;
                                return ListTile(
                                  selected: isSel,
                                  leading: Icon(
                                    isSel ? Icons.folder_special_rounded : Icons.folder_outlined,
                                    color: isSel ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant,
                                  ),
                                  title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                    'AppKey：${e.config.appKey.trim().isEmpty ? "未填写" : e.config.appKey.trim()}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.textTheme.bodySmall?.copyWith(
                                      color: t.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  onTap: () {
                                    unawaited(controller.commitHubSelectionAndEnterWithId(e.id));
                                  },
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: '重命名',
                                        icon: const Icon(Icons.edit_outlined, size: 20),
                                        onPressed: () => _promptName(
                                          context,
                                          title: '重命名项目',
                                          hint: '项目名称',
                                          onSubmit: (s) => controller.renameProject(e.id, s),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: '删除',
                                        icon: Icon(
                                          Icons.delete_outline_rounded,
                                          size: 20,
                                          color: entries.length <= 1
                                              ? t.colorScheme.outline
                                              : t.colorScheme.error,
                                        ),
                                        onPressed: entries.length <= 1
                                            ? null
                                            : () async {
                                                final ok = await showDialog<bool>(
                                                  context: context,
                                                  builder: (ctx) => AlertDialog(
                                                    title: const Text('删除项目'),
                                                    content: Text(
                                                      '确定删除「${e.name}」？该项目的本地配置将删除且不可恢复。',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () => Navigator.pop(ctx, false),
                                                        child: const Text('取消'),
                                                      ),
                                                      FilledButton(
                                                        onPressed: () => Navigator.pop(ctx, true),
                                                        child: const Text('删除'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (ok == true && context.mounted) {
                                                  await controller.deleteProject(e.id);
                                                }
                                              },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('启动时显示项目选择'),
                          subtitle: const Text('关闭后下次启动将直接进入上次打开的项目'),
                          value: controller.openProjectHubOnLaunch,
                          onChanged: (v) => controller.setOpenProjectHubOnLaunch(v),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () => _promptName(
                              context,
                              title: '新建项目',
                              hint: '例如：网校安卓主站',
                              onSubmit: (s) => controller.createProject(s),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 20),
                            label: const Text('新建项目'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
