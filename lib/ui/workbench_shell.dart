import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'issues_tab.dart';
import 'overview_workspace_page.dart';
import 'resizable_vertical_splitter.dart';
import 'anr_time_range_analysis_page.dart';
import 'top10_logs_analysis_tab.dart';

/// 工作台内导航：实时概览 / 崩溃分析（四子项）/ Top10日志分析 / ANR时间段分析。
class WorkbenchShell extends StatefulWidget {
  const WorkbenchShell({super.key, required this.controller, required this.onOpenSettings});

  final AppController controller;
  final VoidCallback onOpenSettings;

  @override
  State<WorkbenchShell> createState() => _WorkbenchShellState();
}

enum _Nav {
  overview,
  crash,
  anr,
  lag,
  exception,
  top10Logs,
  anrTimeRange,
}

class _WorkbenchShellState extends State<WorkbenchShell> {
  _Nav _nav = _Nav.overview;
  bool _crashExpanded = false;

  static const double _wbsMin = 152;
  static const double _wbsMax = 440;
  static const double _wbsDefault = 200;

  late double _workbenchSidebarWidth;
  bool _workbenchSidebarHydratedFromDisk = false;

  @override
  void initState() {
    super.initState();
    _workbenchSidebarWidth = _wbsDefault;
  }

  void _hydrateWorkbenchSidebarWidthOnce() {
    if (_workbenchSidebarHydratedFromDisk || widget.controller.loadingConfig) return;
    _workbenchSidebarHydratedFromDisk = true;
    final w = widget.controller.config.uiWorkbenchSidebarWidth;
    if (w == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _workbenchSidebarWidth = w.clamp(_wbsMin, _wbsMax));
    });
  }

  void _onWorkbenchSidebarDragEnd() {
    widget.controller.config.uiWorkbenchSidebarWidth = _workbenchSidebarWidth;
    widget.controller.persistLayoutWidthsOnly();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _selectCrashChild(_Nav n) {
    setState(() => _nav = n);
    final c = widget.controller;
    c.setPerfStartupLaunchKind('all');
    switch (n) {
      case _Nav.crash:
        c.setWorkspaceBizOverride('crash');
        break;
      case _Nav.anr:
        c.setWorkspaceBizOverride('anr');
        break;
      case _Nav.lag:
        c.setWorkspaceBizOverride('lag');
        break;
      case _Nav.exception:
        c.setWorkspaceBizOverride('exception');
        break;
      default:
        break;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) c.refreshIssues(resetPageSizeToDefault: true);
    });
  }

  void _selectOverview() {
    setState(() => _nav = _Nav.overview);
    widget.controller.clearWorkspaceBizOverride();
  }

  void _selectTop10Logs() {
    setState(() => _nav = _Nav.top10Logs);
  }

  void _selectAnrTimeRange() {
    setState(() => _nav = _Nav.anrTimeRange);
  }

  @override
  Widget build(BuildContext context) {
    _hydrateWorkbenchSidebarWidthOnce();
    final cs = Theme.of(context).colorScheme;
    final hasWallpaper = widget.controller.config.wallpaperId.trim().isNotEmpty;
    final sideBg = hasWallpaper ? cs.surface.withValues(alpha: 0.92) : cs.surface;
    return Row(
      children: [
        SizedBox(
          width: _workbenchSidebarWidth,
          child: Material(
            color: sideBg,
            elevation: 0,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(6, 16, 6, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
                  child: Text(
                    '功能',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                  ),
                ),
                _SideTile(
                  icon: Icons.dashboard_outlined,
                  label: '实时概览',
                  selected: _nav == _Nav.overview,
                  onTap: _selectOverview,
                ),
                ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                  initiallyExpanded: _crashExpanded,
                  onExpansionChanged: (v) => setState(() => _crashExpanded = v),
                  leading: Icon(Icons.bug_report_outlined, color: cs.primary, size: 20),
                  title: Text(
                    '崩溃分析',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: _nav == _Nav.crash ||
                                  _nav == _Nav.anr ||
                                  _nav == _Nav.lag ||
                                  _nav == _Nav.exception
                              ? FontWeight.w700
                              : FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                  ),
                  children: [
                    _SubTile(label: '崩溃', selected: _nav == _Nav.crash, onTap: () => _selectCrashChild(_Nav.crash)),
                    _SubTile(label: 'ANR', selected: _nav == _Nav.anr, onTap: () => _selectCrashChild(_Nav.anr)),
                    _SubTile(label: '卡顿', selected: _nav == _Nav.lag, onTap: () => _selectCrashChild(_Nav.lag)),
                    _SubTile(label: '异常', selected: _nav == _Nav.exception, onTap: () => _selectCrashChild(_Nav.exception)),
                  ],
                ),
                _SideTile(
                  icon: Icons.analytics_outlined,
                  label: 'Top10 日志分析',
                  selected: _nav == _Nav.top10Logs,
                  onTap: _selectTop10Logs,
                ),
                _SideTile(
                  icon: Icons.trending_down_outlined,
                  label: 'ANR 时间段统计',
                  selected: _nav == _Nav.anrTimeRange,
                  onTap: _selectAnrTimeRange,
                ),
              ],
            ),
          ),
        ),
        ResizableVerticalSplitter(
          color: cs.outlineVariant.withValues(alpha: 0.4),
          onDragDelta: (dx) {
            setState(() {
              _workbenchSidebarWidth = (_workbenchSidebarWidth + dx).clamp(_wbsMin, _wbsMax);
            });
          },
          onDragEnd: _onWorkbenchSidebarDragEnd,
        ),
        Expanded(child: _buildContent(context)),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (_nav) {
      case _Nav.overview:
        return OverviewWorkspacePage(
          controller: widget.controller,
          onOpenSettings: widget.onOpenSettings,
        );
      case _Nav.top10Logs:
        return Top10LogsAnalysisTab(
          controller: widget.controller,
          onOpenSettings: widget.onOpenSettings,
        );
      case _Nav.anrTimeRange:
        return AnrTimeRangeAnalysisPage(
          controller: widget.controller,
        );
      case _Nav.crash:
        return IssuesTab(
          controller: widget.controller,
          onOpenSettings: widget.onOpenSettings,
          moduleTitle: '崩溃',
          moduleSubtitle: '',
        );
      case _Nav.anr:
        return IssuesTab(
          controller: widget.controller,
          onOpenSettings: widget.onOpenSettings,
          moduleTitle: 'ANR',
          moduleSubtitle: '',
        );
      case _Nav.lag:
        return IssuesTab(
          controller: widget.controller,
          onOpenSettings: widget.onOpenSettings,
          moduleTitle: '卡顿',
          moduleSubtitle: '',
        );
      case _Nav.exception:
        return IssuesTab(
          controller: widget.controller,
          onOpenSettings: widget.onOpenSettings,
          moduleTitle: '异常',
          moduleSubtitle: '',
        );
    }
  }
}

class _SideTile extends StatelessWidget {
  const _SideTile({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        horizontalTitleGap: 8,
        minLeadingWidth: 28,
        leading: Icon(icon, size: 20, color: selected ? cs.primary : cs.onSurfaceVariant),
        title: Text(
          label,
          style: t.textTheme.bodyMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.12,
          ),
        ),
        selected: selected,
        selectedTileColor: cs.primaryContainer.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: onTap,
      ),
    );
  }
}

class _SubTile extends StatelessWidget {
  const _SubTile({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.only(left: 26, right: 8),
      title: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: t.textTheme.bodyMedium?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? cs.primary : cs.onSurface,
          letterSpacing: 0.08,
        ),
      ),
      selected: selected,
      selectedTileColor: cs.primaryContainer.withValues(alpha: 0.28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }
}
