import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'app_wallpaper_backdrop.dart';
import 'resizable_vertical_splitter.dart';
import 'settings_tab.dart';
import 'wallpaper_top_bar.dart';
import 'workbench_shell.dart';
import 'unified_report_hub.dart';
import 'analysis_report_tab.dart';
import 'html_report_analysis_tab.dart';
import 'scheduled_background_tasks_tab.dart';

/// 主导航：工作台 / 报告 / HTML分析 / 后台定时任务 / 配置。
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
    widget.controller.addListener(_onControllerForChatTab);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerForChatTab);
    super.dispose();
  }

  void _onControllerForChatTab() {
    if (!mounted) return;
    // Chat tab 已移除，保持兼容性
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
          onOpenSettings: () => setState(() => _index = 4),
        );
      case 1:
        return AnalysisReportTab(controller: widget.controller);
      case 2:
        return HtmlReportAnalysisTab(controller: widget.controller);
      case 3:
        return ScheduledBackgroundTasksTab(controller: widget.controller);
      case 4:
        return SettingsTab(controller: widget.controller);
      default:
        return WorkbenchShell(
          controller: widget.controller,
          onOpenSettings: () => setState(() => _index = 4),
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
                                    child: Image.asset('lib/assets/border_collie.png', width: 24, height: 24),
                                  ),
                                  selectedIcon: Image.asset('lib/assets/border_collie.png', width: 24, height: 24),
                                  label: const Text('工作台'),
                                ),
                                NavigationRailDestination(
                                  icon: Image.asset('lib/assets/orange_cat.png', width: 24, height: 24),
                                  selectedIcon: Image.asset('lib/assets/orange_cat.png', width: 24, height: 24),
                                  label: const Text('报告'),
                                ),
                                NavigationRailDestination(
                                  icon: Image.asset('lib/assets/shiba.png', width: 24, height: 24),
                                  selectedIcon: Image.asset('lib/assets/shiba.png', width: 24, height: 24),
                                  label: const Text('HTML分析'),
                                ),
                                NavigationRailDestination(
                                  icon: Image.asset('lib/assets/duck.png', width: 24, height: 24),
                                  selectedIcon: Image.asset('lib/assets/duck.png', width: 24, height: 24),
                                  label: const Text('定时任务'),
                                ),
                                NavigationRailDestination(
                                  icon: Image.asset('lib/assets/hamster.png', width: 24, height: 24),
                                  selectedIcon: Image.asset('lib/assets/hamster.png', width: 24, height: 24),
                                  label: const Text('配置'),
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
