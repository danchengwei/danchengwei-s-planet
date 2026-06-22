import 'package:flutter/material.dart';

import '../app_controller.dart';

/// 窗口顶部个性化条：无文字提示的壁纸切换（仅图标）。
class WallpaperTopBar extends StatelessWidget {
  const WallpaperTopBar({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final hasWp = controller.config.wallpaperId.trim().isNotEmpty;
    final barBg = hasWp ? cs.surface.withValues(alpha: 0.78) : cs.surface.withValues(alpha: 0.92);

    return Material(
      color: barBg,
      elevation: 0,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primaryContainer.withValues(alpha: hasWp ? 0.22 : 0.12),
              cs.tertiaryContainer.withValues(alpha: hasWp ? 0.14 : 0.08),
            ],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 20, color: cs.primary.withValues(alpha: 0.9)),
            const SizedBox(width: 8),
            Text(
              '个性背景',
              style: t.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: cs.onSurface.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(width: 16),
            TextButton.icon(
              onPressed: () => controller.openProjectHub(),
              icon: Icon(Icons.folder_open_outlined, size: 18, color: cs.primary),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  controller.activeProjectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
            const Spacer(),
            InkWell(
              excludeFromSemantics: true,
              onTap: () async => controller.cycleWallpaper(),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.18),
                      cs.tertiary.withValues(alpha: 0.14),
                    ],
                  ),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.32)),
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.palette_rounded, size: 17, color: cs.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
