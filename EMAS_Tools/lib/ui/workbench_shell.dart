import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'issues_tab.dart';
import 'overview_workspace_page.dart';
import 'resizable_vertical_splitter.dart';

/// 工作台内导航：实时概览 / 崩溃分析（四子项）/ 性能分析（启动·页面·网络，数据均来自 EMAS）。
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
  block,
  exception,
  perfStartup,
  perfPage,
  perfNetwork,
}

class _WorkbenchShellState extends State<WorkbenchShell> {
  _Nav _nav = _Nav.overview;
  bool _crashExpanded = false;
  bool _perfExpanded = false;

  /// 启动分析：与 SegmentedButton 联动（7 / 30 / 60 天）。
  int _startupDays = 7;

  final _perfStartupBizCtrl = TextEditingController(text: 'startup');
  final _perfStartupVersionCtrl = TextEditingController();
  final _perfPageBizCtrl = TextEditingController(text: 'page');
  final _perfNetworkBizCtrl = TextEditingController(text: 'network');

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
    _perfStartupBizCtrl.dispose();
    _perfStartupVersionCtrl.dispose();
    _perfPageBizCtrl.dispose();
    _perfNetworkBizCtrl.dispose();
    super.dispose();
  }

  bool get _isPerfNav {
    return _nav == _Nav.perfStartup || _nav == _Nav.perfPage || _nav == _Nav.perfNetwork;
  }

  void _selectCrashChild(_Nav n) {
    setState(() => _nav = n);
    final c = widget.controller;
    c.setPerfStartupLaunchKind('all');
    c.setListNameQuery(c.config.emasListNameQuery);
    switch (n) {
      case _Nav.crash:
        c.setWorkspaceBizOverride('crash');
        break;
      case _Nav.anr:
        c.setWorkspaceBizOverride('anr');
        break;
      case _Nav.block:
        c.setWorkspaceBizOverride('block');
        break;
      case _Nav.exception:
        c.setWorkspaceBizOverride('exception');
        break;
      default:
        break;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) c.refreshIssues();
    });
  }

  void _selectOverview() {
    setState(() => _nav = _Nav.overview);
    widget.controller.clearWorkspaceBizOverride();
    widget.controller.setListNameQuery(widget.controller.config.emasListNameQuery);
  }

  /// 将当前性能子项的 BizModule、Name、时间写入控制器（不自动请求列表）。
  void _syncPerfContextToController() {
    final c = widget.controller;
    switch (_nav) {
      case _Nav.perfStartup:
        final biz = _perfStartupBizCtrl.text.trim().isEmpty ? 'startup' : _perfStartupBizCtrl.text.trim();
        c.setWorkspaceBizOverride(biz);
        c.setListNameQuery(_perfStartupVersionCtrl.text.trim());
        c.setTimeRangeBack(Duration(days: _startupDays));
        break;
      case _Nav.perfPage:
        final biz = _perfPageBizCtrl.text.trim().isEmpty ? 'page' : _perfPageBizCtrl.text.trim();
        c.setWorkspaceBizOverride(biz);
        c.setListNameQuery('');
        break;
      case _Nav.perfNetwork:
        final biz = _perfNetworkBizCtrl.text.trim().isEmpty ? 'network' : _perfNetworkBizCtrl.text.trim();
        c.setWorkspaceBizOverride(biz);
        c.setListNameQuery('');
        break;
      default:
        break;
    }
  }

  void _selectPerfNav(_Nav n) {
    setState(() => _nav = n);
    if (n == _Nav.perfPage || n == _Nav.perfNetwork) {
      widget.controller.setPerfStartupLaunchKind('all');
    }
    _syncPerfContextToController();
  }

  void _selectPerfStartupEntry() {
    setState(() => _nav = _Nav.perfStartup);
    _syncPerfContextToController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.refreshIssues();
    });
  }

  void _applyPerformanceFetch() {
    _syncPerfContextToController();
    widget.controller.refreshIssues();
  }

  Widget _perfWorkspace({
    required _PerfToolBarMode mode,
    required bool hideTimeRangeQuickChips,
    required String title,
  }) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PerfToolBar(
              controller: widget.controller,
              mode: mode,
              startupDays: _startupDays,
              onStartupDaysChanged: (d) {
                setState(() => _startupDays = d);
                widget.controller.setTimeRangeBack(Duration(days: d));
              },
              startupBizCtrl: _perfStartupBizCtrl,
              startupVersionCtrl: _perfStartupVersionCtrl,
              pageBizCtrl: _perfPageBizCtrl,
              networkBizCtrl: _perfNetworkBizCtrl,
              onFetch: _applyPerformanceFetch,
            ),
            Expanded(
              child: IssuesTab(
                controller: widget.controller,
                onOpenSettings: widget.onOpenSettings,
                moduleTitle: title,
                moduleSubtitle: '',
                hideHeroFetchCard: true,
                hideTimeRangeQuickChips: hideTimeRangeQuickChips,
                hideDigestAndTop15Section: true,
                listIntroduction: '',
              ),
            ),
          ],
        );
      },
    );
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
                                  _nav == _Nav.block ||
                                  _nav == _Nav.exception
                              ? FontWeight.w700
                              : FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                  ),
                  children: [
                    _SubTile(label: '崩溃', selected: _nav == _Nav.crash, onTap: () => _selectCrashChild(_Nav.crash)),
                    _SubTile(label: 'ANR', selected: _nav == _Nav.anr, onTap: () => _selectCrashChild(_Nav.anr)),
                    _SubTile(label: '卡顿', selected: _nav == _Nav.block, onTap: () => _selectCrashChild(_Nav.block)),
                    _SubTile(label: '异常', selected: _nav == _Nav.exception, onTap: () => _selectCrashChild(_Nav.exception)),
                  ],
                ),
                ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                  initiallyExpanded: _perfExpanded,
                  onExpansionChanged: (v) => setState(() => _perfExpanded = v),
                  leading: Icon(Icons.speed_outlined, color: cs.primary, size: 20),
                  title: Text(
                    '性能分析',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: _isPerfNav ? FontWeight.w700 : FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                  ),
                  children: [
                    _SubTile(
                      label: '启动分析',
                      selected: _nav == _Nav.perfStartup,
                      onTap: _selectPerfStartupEntry,
                    ),
                    _SubTile(
                      label: '页面分析',
                      selected: _nav == _Nav.perfPage,
                      onTap: () => _selectPerfNav(_Nav.perfPage),
                    ),
                    _SubTile(
                      label: '网络分析',
                      selected: _nav == _Nav.perfNetwork,
                      onTap: () => _selectPerfNav(_Nav.perfNetwork),
                    ),
                  ],
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
      case _Nav.perfStartup:
        return _perfWorkspace(
          mode: _PerfToolBarMode.startup,
          hideTimeRangeQuickChips: true,
          title: '性能分析 · 启动分析',
        );
      case _Nav.perfPage:
        return _perfWorkspace(
          mode: _PerfToolBarMode.page,
          hideTimeRangeQuickChips: false,
          title: '性能分析 · 页面分析',
        );
      case _Nav.perfNetwork:
        return _perfWorkspace(
          mode: _PerfToolBarMode.network,
          hideTimeRangeQuickChips: false,
          title: '性能分析 · 网络分析',
        );
      case _Nav.crash:
        return IssuesTab(
          controller: widget.controller,
          onOpenSettings: widget.onOpenSettings,
          moduleTitle: '崩溃分析 · 崩溃',
          moduleSubtitle: 'BizModule=crash（与阿里云控制台「崩溃」一致；若你方取值不同请在配置中改默认或联系管理员）。',
        );
      case _Nav.anr:
        return IssuesTab(
          controller: widget.controller,
          onOpenSettings: widget.onOpenSettings,
          moduleTitle: '崩溃分析 · ANR',
          moduleSubtitle: 'BizModule=anr，列表与详情、AI、GitLab 与崩溃相同流程。',
        );
      case _Nav.block:
        return IssuesTab(
          controller: widget.controller,
          onOpenSettings: widget.onOpenSettings,
          moduleTitle: '崩溃分析 · 卡顿',
          moduleSubtitle: 'BizModule=block（若接口返回不支持，请改为控制台实际 BizModule 字符串）。',
        );
      case _Nav.exception:
        return IssuesTab(
          controller: widget.controller,
          onOpenSettings: widget.onOpenSettings,
          moduleTitle: '崩溃分析 · 异常',
          moduleSubtitle: 'BizModule=exception（自定义异常以控制台为准）。',
        );
    }
  }
}

enum _PerfToolBarMode { startup, page, network }

/// 性能分析顶部工具区：突出「拉取列表」；启动分析含 7/30/60 天与版本关键字。
class _PerfToolBar extends StatelessWidget {
  const _PerfToolBar({
    required this.controller,
    required this.mode,
    required this.startupDays,
    required this.onStartupDaysChanged,
    required this.startupBizCtrl,
    required this.startupVersionCtrl,
    required this.pageBizCtrl,
    required this.networkBizCtrl,
    required this.onFetch,
  });

  final AppController controller;
  final _PerfToolBarMode mode;
  final int startupDays;
  final ValueChanged<int> onStartupDaysChanged;
  final TextEditingController startupBizCtrl;
  final TextEditingController startupVersionCtrl;
  final TextEditingController pageBizCtrl;
  final TextEditingController networkBizCtrl;
  final VoidCallback onFetch;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final needConfig = controller.config.validateEmas().isNotEmpty;
    final hw = controller.config.wallpaperId.trim().isNotEmpty;
    final barColor = hw ? cs.surface.withValues(alpha: 0.88) : cs.surface;

    return Container(
      decoration: BoxDecoration(
        color: barColor,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (mode == _PerfToolBarMode.startup) ...[
              Text(
                '启动类型',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'all',
                    label: Text('全部'),
                    icon: Icon(Icons.apps_outlined, size: 16),
                  ),
                  ButtonSegment<String>(
                    value: 'cold',
                    label: Text('冷启动'),
                  ),
                  ButtonSegment<String>(
                    value: 'hot',
                    label: Text('热启动'),
                  ),
                ],
                selected: {controller.perfStartupLaunchKind},
                onSelectionChanged: (s) => controller.setPerfStartupLaunchKind(s.first),
              ),
              const SizedBox(height: 14),
              Text(
                '时间范围',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(
                    value: 7,
                    label: Text('近 7 天'),
                    icon: Icon(Icons.calendar_view_week_outlined, size: 18),
                  ),
                  ButtonSegment<int>(
                    value: 30,
                    label: Text('近 30 天'),
                  ),
                  ButtonSegment<int>(
                    value: 60,
                    label: Text('近 60 天'),
                  ),
                ],
                selected: {startupDays},
                onSelectionChanged: (s) {
                  final v = s.first;
                  onStartupDaysChanged(v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: startupVersionCtrl,
                decoration: const InputDecoration(
                  labelText: '版本 / 名称关键字',
                  hintText: '对应 GetIssues 的 Name，可选',
                  border: OutlineInputBorder(),
                  isDense: true,
                  filled: true,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onFetch(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: startupBizCtrl,
                decoration: const InputDecoration(
                  labelText: 'BizModule',
                  helperText: '须与 EMAS 控制台启动模块一致（如 startup）；数据均来自 OpenAPI',
                  border: OutlineInputBorder(),
                  isDense: true,
                  filled: true,
                ),
              ),
            ] else ...[
              Text(
                'BizModule',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: mode == _PerfToolBarMode.page ? pageBizCtrl : networkBizCtrl,
                decoration: InputDecoration(
                  labelText: mode == _PerfToolBarMode.page ? '页面分析' : '网络分析',
                  helperText: mode == _PerfToolBarMode.page
                      ? '默认 page；时间范围在下方列表卡片中选取'
                      : '默认 network；时间范围在下方列表卡片中选取',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  filled: true,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: needConfig || controller.loadingIssues ? null : onFetch,
              icon: controller.loadingIssues
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                    )
                  : const Icon(Icons.cloud_download_rounded, size: 24),
              label: Text(
                controller.loadingIssues ? '拉取中…' : '拉取列表',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
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
