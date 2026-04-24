import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'app_wallpaper_backdrop.dart';
import 'resizable_vertical_splitter.dart';
import 'gitlab_settings_tab.dart';
import 'mcp_settings_tab.dart';
import 'settings_tab.dart';
import 'wallpaper_top_bar.dart';
import 'chat_tab.dart';
import 'workbench_shell.dart';

/// 主导航：工作台 / 对话 / 配置 / GitLab / MCP。
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const double _railMin = 76;
  static const double _railMax = 132;
  static const double _railDefault = 88;

  late double _primaryRailWidth;
  bool _primaryRailHydratedFromDisk = false;

  @override
  void initState() {
    super.initState();
    _primaryRailWidth = _railDefault;
  }

  void _hydratePrimaryRailWidthOnce() {
    if (_primaryRailHydratedFromDisk || widget.controller.loadingConfig) return;
    _primaryRailHydratedFromDisk = true;
    final w = widget.controller.config.uiPrimaryRailWidth;
    if (w == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _primaryRailWidth = w.clamp(_railMin, _railMax));
    });
  }

  void _onPrimaryRailDragEnd() {
    widget.controller.config.uiPrimaryRailWidth = _primaryRailWidth;
    widget.controller.persistLayoutWidthsOnly();
  }

  Widget _shellBodyForIndex(int i) {
    switch (i) {
      case 0:
        return WorkbenchShell(
          controller: widget.controller,
          onOpenSettings: () => setState(() => _index = 2),
        );
      case 1:
        return ChatTab(controller: widget.controller);
      case 2:
        return SettingsTab(controller: widget.controller);
      case 3:
        return GitLabSettingsTab(controller: widget.controller);
      case 4:
        return McpSettingsTab(controller: widget.controller);
      default:
        return WorkbenchShell(
          controller: widget.controller,
          onOpenSettings: () => setState(() => _index = 2),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        _hydratePrimaryRailWidthOnce();
        final miss = widget.controller.config.validateEmas();
        final needConfig = miss.isNotEmpty;
        final t = Theme.of(context);
        final cs = t.colorScheme;
        final hasWallpaper = widget.controller.config.wallpaperId.trim().isNotEmpty;
        final railBg = hasWallpaper ? cs.surface.withValues(alpha: 0.92) : cs.surface;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: AppWallpaperBackdrop(
                wallpaperId: widget.controller.config.wallpaperId,
                baseColor: cs.surface,
              ),
            ),
            Scaffold(
              backgroundColor: Colors.transparent,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  WallpaperTopBar(controller: widget.controller),
                  Expanded(
                    child: Row(
                      children: [
                        SizedBox(
                          width: _primaryRailWidth,
                          child: ClipRect(
                            child: NavigationRail(
                              selectedIndex: _index,
                              onDestinationSelected: (i) => setState(() => _index = i),
                              labelType: NavigationRailLabelType.all,
                              backgroundColor: railBg,
                              indicatorColor: cs.primaryContainer.withValues(alpha: 0.55),
                              indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              minWidth: _primaryRailWidth,
                              groupAlignment: -1,
                              selectedIconTheme: IconThemeData(color: cs.primary, size: 24),
                              unselectedIconTheme: IconThemeData(color: cs.onSurfaceVariant, size: 24),
                              selectedLabelTextStyle: t.textTheme.labelSmall?.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.15,
                              ),
                              unselectedLabelTextStyle: t.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                              destinations: [
                                NavigationRailDestination(
                                  icon: Badge(
                                    isLabelVisible: needConfig,
                                    child: const Icon(Icons.dashboard_customize_outlined),
                                  ),
                                  selectedIcon: const Icon(Icons.dashboard_customize),
                                  label: const Text('工作台'),
                                ),
                                const NavigationRailDestination(
                                  icon: Icon(Icons.chat_bubble_outline_rounded),
                                  selectedIcon: Icon(Icons.chat_bubble_rounded),
                                  label: Text('对话'),
                                ),
                                const NavigationRailDestination(
                                  icon: Icon(Icons.tune_outlined),
                                  selectedIcon: Icon(Icons.tune),
                                  label: Text('配置'),
                                ),
                                const NavigationRailDestination(
                                  icon: Icon(Icons.code_outlined),
                                  selectedIcon: Icon(Icons.code_rounded),
                                  label: Text('GitLab'),
                                ),
                                const NavigationRailDestination(
                                  icon: Icon(Icons.hub_outlined),
                                  selectedIcon: Icon(Icons.hub_rounded),
                                  label: Text('MCP'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        ResizableVerticalSplitter(
                          color: cs.outlineVariant.withValues(alpha: 0.45),
                          onDragDelta: (dx) {
                            setState(() {
                              _primaryRailWidth = (_primaryRailWidth + dx).clamp(_railMin, _railMax);
                            });
                          },
                          onDragEnd: _onPrimaryRailDragEnd,
                        ),
                        Expanded(
                          child: _shellBodyForIndex(_index),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
