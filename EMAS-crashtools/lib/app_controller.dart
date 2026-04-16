import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'aliyun/emas_appmonitor_client.dart';
import 'models/agent_payload.dart';
import 'models/issue_individual_llm_result.dart';
import 'models/analysis_report_record.dart';
import 'models/overview_metrics.dart';
import 'models/projects_workspace.dart';
import 'models/tool_config.dart';
import 'models/wallpaper_catalog.dart';
import 'services/analysis_report_storage.dart';
import 'services/agent_launcher.dart';
import 'services/analysis_prompt_builder.dart';
import 'services/stack_clarity.dart';
import 'services/config_repository.dart';
import 'services/emas_crash_mock_data.dart';
import 'services/test_local_config_loader.dart';
import 'services/gitlab_client.dart';
import 'services/llm_client.dart';
import 'services/outbound_http_client_for_config.dart';
import 'services/report_bundle.dart';
import 'services/report_html.dart';
import 'services/security_redaction.dart';
import 'services/wallpaper_theme_seeder.dart';

/// 全局状态：多项目工作区、当前项目配置、列表、多选、协议回调。
class AppController extends ChangeNotifier {
  AppController() {
    final bounds = calendarInclusiveRangeBounds(calendarDaysInclusive: 1);
    rangeStartMs = bounds.$1;
    rangeEndMs = bounds.$2;
    _bootstrap();
  }

  /// 自然日窗口（共 [calendarDaysInclusive] 天）：**最新一天为「昨天」**（本地时区）。
  /// 起点为「昨天 0 点」往前 `n-1` 天的 0 点，终点为昨天 23:59:59.999（不含今天数据）。
  static (int startMs, int endMs) calendarInclusiveRangeBounds({
    required int calendarDaysInclusive,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final todayStart = DateTime(clock.year, clock.month, clock.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    if (calendarDaysInclusive < 1) {
      final e = DateTime(yesterdayStart.year, yesterdayStart.month, yesterdayStart.day, 23, 59, 59, 999);
      final t = e.millisecondsSinceEpoch;
      return (t, t);
    }
    final rangeStart = yesterdayStart.subtract(Duration(days: calendarDaysInclusive - 1));
    final rangeEnd = DateTime(yesterdayStart.year, yesterdayStart.month, yesterdayStart.day, 23, 59, 59, 999);
    return (rangeStart.millisecondsSinceEpoch, rangeEnd.millisecondsSinceEpoch);
  }

  final ConfigRepository _configRepo = ConfigRepository();
  ProjectsWorkspace _workspace = ProjectsWorkspace.empty();

  /// 冷启动是否先显示项目选择页（可在该页关闭「启动时显示」）。
  bool showProjectHub = false;

  /// 项目中心当前高亮项（进入工作台前可切换）。
  String _hubSelectedProjectId = '';

  bool loadingConfig = true;
  String? bootstrapError;

  /// 若启动时加载了 [TestLocalConfigLoader] 指向的本地测试 JSON，此处为所用文件路径。
  String? testLocalConfigAppliedPath;
  TestConfigApplyMode? testLocalConfigApplyMode;

  /// 当前选中项目的配置（读写即落在该项目上）。
  ToolConfig get config => activeProject.config;

  ProjectEntry get activeProject {
    _workspace.ensureValidActive();
    final id = _workspace.activeProjectId!;
    return _workspace.projects.firstWhere((p) => p.id == id);
  }

  String get activeProjectName => activeProject.name;

  bool get openProjectHubOnLaunch => _workspace.openProjectHubOnLaunch;

  List<ProjectEntry> get projectEntriesUnmodifiable =>
      List<ProjectEntry>.unmodifiable(_workspace.projects);

  /// 随当前壁纸从资源取色得到的浅色主题种子；无壁纸时为 [AppTheme.defaultSeed]。
  Color _wallpaperThemeSeed = AppTheme.defaultSeed;

  Color get wallpaperThemeSeed => _wallpaperThemeSeed;

  late int rangeStartMs;
  late int rangeEndMs;

  /// 工作台子模块临时覆盖的 BizModule（如 anr、performance）；空则使用 [config.bizModule]。
  String _workspaceBizOverride = '';

  /// GetIssues 的可选 `Name`：**仅表示应用版本**（versionName / 版本号等），由工作台填写，**不入配置**；与 Digest 拉单条同为会话参数。
  String listNameQuery = '';

  /// GetIssues/GetIssue 可选 `PackageName`：工作台会话；**非空时优先于** [config.appPackageName]。
  String listPackageNameQuery = '';

  /// 实际传给 OpenAPI 的包名：会话非空用 [listPackageNameQuery]，否则 [ToolConfig.appPackageNameForOpenApi]。
  String? get effectiveEmasPackageNameForRequest {
    if (listPackageNameQuery.trim().isNotEmpty) return listPackageNameQuery.trim();
    return config.appPackageNameForOpenApi;
  }

  /// 性能 · 启动分析：冷/热启动筛选；`all` 表示不传附加参数。离开启动分析或非 GetIssues 场景时应置回 `all`。
  String _perfStartupLaunchKind = 'all';

  String get perfStartupLaunchKind => _perfStartupLaunchKind;

  void setPerfStartupLaunchKind(String kind) {
    final k = kind.trim().toLowerCase();
    if (k == 'cold' || k == 'hot') {
      _perfStartupLaunchKind = k;
    } else {
      _perfStartupLaunchKind = 'all';
    }
    pageIndex = 1;
    notifyListeners();
  }

  Map<String, dynamic>? get _emasStartupLaunchExtra =>
      EmasAppMonitorClient.startupLaunchKindToExtra(_perfStartupLaunchKind);

  /// 配置开启且当前聚合 Biz 为 crash 时，列表走本地 Mock（不校验 AK / 不请求网络）。
  bool get _useEmasCrashMock =>
      config.emasUseMockCrashData &&
      activeBizModule.trim().toLowerCase() == 'crash';

  /// 实际调用 EMAS 时使用的 BizModule。
  String get activeBizModule {
    final o = _workspaceBizOverride.trim();
    if (o.isNotEmpty) return o;
    return config.bizModule.trim();
  }

  void setWorkspaceBizOverride(String biz) {
    _workspaceBizOverride = biz.trim();
    pageIndex = 1;
    notifyListeners();
  }

  /// 清空工作台对 Biz 的覆盖，恢复为配置中的默认值。
  void clearWorkspaceBizOverride() {
    _workspaceBizOverride = '';
    _perfStartupLaunchKind = 'all';
    pageIndex = 1;
    notifyListeners();
  }

  void setListNameQuery(String q) {
    listNameQuery = q.trim();
    pageIndex = 1;
    notifyListeners();
  }

  void setListPackageNameQuery(String q) {
    listPackageNameQuery = q.trim();
    pageIndex = 1;
    notifyListeners();
  }

  void setTimeRangeBack(Duration back) {
    final now = DateTime.now();
    rangeEndMs = now.millisecondsSinceEpoch;
    rangeStartMs = now.subtract(back).millisecondsSinceEpoch;
    pageIndex = 1;
    _listPageSizeForApi = pageSize;
    notifyListeners();
  }

  /// 与「7 天 / 30 天」芯片一致：自然日，**最新一天为昨天**，终点为昨天末。
  void setTimeRangeLastCalendarDays(int calendarDaysInclusive) {
    final bounds = calendarInclusiveRangeBounds(calendarDaysInclusive: calendarDaysInclusive);
    rangeStartMs = bounds.$1;
    rangeEndMs = bounds.$2;
    pageIndex = 1;
    _listPageSizeForApi = pageSize;
    notifyListeners();
  }

  /// 与列表「最近 / 7 天 / 30 天」芯片一致（自然日、最新日为昨天；**最近 = 1 天**）。
  bool matchesQuickCalendarDays(int calendarDaysInclusive) {
    if (calendarDaysInclusive != 1 && calendarDaysInclusive != 7 && calendarDaysInclusive != 30) {
      return false;
    }
    const tol = 120000;
    return _matchesCalendarInclusiveStart(calendarDaysInclusive, tol);
  }

  bool _matchesCalendarInclusiveStart(int calendarDaysInclusive, int tol) {
    final expected = calendarInclusiveRangeBounds(calendarDaysInclusive: calendarDaysInclusive);
    return (rangeStartMs - expected.$1).abs() <= tol && (rangeEndMs - expected.$2).abs() <= tol;
  }

  bool loadingIssues = false;
  String? issuesError;
  GetIssuesResult? lastIssues;
  int pageIndex = 1;
  final int pageSize = 20;

  /// 列表 GetIssues 的 `PageSize`；「拉取 TOP10 总览」会暂改为 10，常规「一键获取」通过 [refreshIssues] 的 [resetPageSizeToDefault] 恢复为 [pageSize]。
  int _listPageSizeForApi = 20;

  /// 实时概览：多 Biz GetIssues 汇总（不写入 [lastIssues]，避免干扰左侧子模块列表）。
  OverviewMetricsSnapshot? overviewMetrics;
  bool loadingOverviewMetrics = false;
  String? overviewDashboardError;

  static const List<String> _overviewBizOrder = ['crash', 'anr', 'startup', 'exception'];

  /// 按项目 id 存本地分析报告（非 Web 落盘）。
  Map<String, List<AnalysisReportRecord>> _analysisReportsByProject = {};

  /// 对话页挂载：后续每条 Chat 请求会在 system 中附带该报告全文（有长度截断）。
  AnalysisReportRecord? _chatAttachedReport;
  AnalysisReportRecord? get chatAttachedReport => _chatAttachedReport;

  bool _openChatTabPending = false;

  /// 批量大模型分析勾选
  final Set<String> selectedDigestHashes = <String>{};

  StreamSubscription<Uri>? _appLinkSub;

  void listenAppLinks(Stream<Uri> stream) {
    _appLinkSub?.cancel();
    _appLinkSub = stream.listen(handleProtocolUri);
  }

  void toggleDigestSelection(String digest) {
    if (selectedDigestHashes.contains(digest)) {
      selectedDigestHashes.remove(digest);
    } else {
      selectedDigestHashes.add(digest);
    }
    notifyListeners();
  }

  void clearDigestSelection() {
    selectedDigestHashes.clear();
    notifyListeners();
  }

  void selectAllOnPage() {
    final items = lastIssues?.items ?? const [];
    for (final it in items) {
      final d = it.digestHash;
      if (d != null && d.isNotEmpty) selectedDigestHashes.add(d);
    }
    notifyListeners();
  }

  /// 每个项目本地报告库最大条数（超出时保留最新，最旧被移除）。
  static const int maxAnalysisReportsPerProject = 3;

  /// 当前项目已保存的 AI 分析报告（新在前）。
  List<AnalysisReportRecord> get analysisReportsForActiveProject {
    final id = activeProject.id;
    final raw = _analysisReportsByProject[id] ?? const <AnalysisReportRecord>[];
    final copy = List<AnalysisReportRecord>.from(raw);
    copy.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return List<AnalysisReportRecord>.unmodifiable(copy);
  }

  /// 按创建时间仅保留最新的 [maxAnalysisReportsPerProject] 条；若移除了当前挂载的报告会清除挂载。
  bool _capAnalysisReportsListInPlace(List<AnalysisReportRecord> list) {
    if (list.length <= maxAnalysisReportsPerProject) return false;
    list.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    while (list.length > maxAnalysisReportsPerProject) {
      final removed = list.removeLast();
      if (_chatAttachedReport?.id == removed.id) {
        _chatAttachedReport = null;
      }
    }
    return true;
  }

  /// 启动或导入后：各项目列表对齐条数上限。
  bool _enforceAnalysisReportsPerProjectCap() {
    var changed = false;
    for (final list in _analysisReportsByProject.values) {
      if (_capAnalysisReportsListInPlace(list)) changed = true;
    }
    return changed;
  }

  /// 返回 `true` 表示保存前已达上限，本次写入后已按时间淘汰最旧的一条（或若干条）。
  Future<bool> addAnalysisReport(AnalysisReportRecord r) async {
    final list = _analysisReportsByProject.putIfAbsent(r.projectId, () => []);
    final evicting = list.length >= maxAnalysisReportsPerProject;
    list.insert(0, r);
    _capAnalysisReportsListInPlace(list);
    await AnalysisReportStorage.save(_analysisReportsByProject);
    notifyListeners();
    return evicting;
  }

  Future<void> deleteAnalysisReport(String reportId) async {
    final pid = activeProject.id;
    final list = _analysisReportsByProject[pid];
    if (list == null) return;
    list.removeWhere((e) => e.id == reportId);
    if (_chatAttachedReport?.id == reportId) {
      _chatAttachedReport = null;
    }
    await AnalysisReportStorage.save(_analysisReportsByProject);
    notifyListeners();
  }

  void attachReportToChat(AnalysisReportRecord r) {
    _chatAttachedReport = r;
    notifyListeners();
  }

  void clearChatAttachedReport() {
    _chatAttachedReport = null;
    notifyListeners();
  }

  void requestOpenChatTab() {
    _openChatTabPending = true;
    notifyListeners();
  }

  /// 由 [MainShell] 消费：为 true 时切换到「对话」页。
  bool consumeOpenChatTabRequest() {
    if (!_openChatTabPending) return false;
    _openChatTabPending = false;
    return true;
  }

  Future<void> _bootstrap() async {
    loadingConfig = true;
    bootstrapError = null;
    notifyListeners();
    try {
      _workspace = await _configRepo.loadWorkspace();
      _workspace.ensureValidActive();
      testLocalConfigAppliedPath = null;
      testLocalConfigApplyMode = null;
      final testHit = await TestLocalConfigLoader.applyIfPresent(_workspace);
      if (testHit != null) {
        testLocalConfigAppliedPath = testHit.path;
        testLocalConfigApplyMode = testHit.mode;
        _workspace.ensureValidActive();
        debugPrint(
          '已加载本地测试配置: ${testHit.path}（模式: ${testHit.mode.name}，未写回工作区文件）',
        );
        try {
          final raw = await File(testHit.path).readAsString();
          final d = jsonDecode(raw);
          if (d is Map<String, dynamic>) {
            final n = TestLocalConfigLoader.optionalLegacyAppVersionFromImportRoot(
              Map<String, dynamic>.from(d),
            );
            if (n != null && n.isNotEmpty) listNameQuery = n;
          }
        } catch (_) {}
      }
      showProjectHub = _workspace.openProjectHubOnLaunch;
      await _syncWallpaperThemeSeed();
      try {
        _analysisReportsByProject = await AnalysisReportStorage.load();
        if (_enforceAnalysisReportsPerProjectCap()) {
          await AnalysisReportStorage.save(_analysisReportsByProject);
        }
      } catch (e, st) {
        debugPrint('加载分析报告库失败: $e\n$st');
        _analysisReportsByProject = {};
      }
    } catch (e) {
      bootstrapError = e.toString();
      _workspace = ProjectsWorkspace.empty();
      _workspace.ensureValidActive();
      showProjectHub = true;
    }
    _workspace.ensureValidActive();
    // 首次落盘失败（如 Keychain 权限）不应阻断进入项目页；保存时会再尝试或回退明文。
    if (bootstrapError == null) {
      try {
        await _persistWorkspace();
      } catch (e, st) {
        debugPrint('启动时写入本地配置失败: $e\n$st');
      }
    }
    loadingConfig = false;
    notifyListeners();
  }

  Future<void> _persistWorkspace() async {
    try {
      await _configRepo.saveWorkspace(_workspace);
    } catch (e, st) {
      debugPrint('_persistWorkspace failed: $e\n$st');
      rethrow;
    }
  }

  /// 从用户选择的 JSON 文件导入配置，规则与 [TestLocalConfigLoader] / `crash-tools-test-config.sample.json` 一致。
  /// 返回 `(null, mode)` 表示成功；返回 `(错误文案, null)` 表示失败。Web 端不支持本地文件路径。
  Future<(String?, TestConfigApplyMode?)> importConfigFromJsonPath(
    String filePath,
  ) async {
    if (kIsWeb) {
      return ('Web 端不支持从本地文件导入 JSON，请使用桌面版。', null);
    }
    try {
      String? legacyName;
      try {
        final preview = await File(filePath).readAsString();
        final dec = jsonDecode(preview);
        if (dec is Map<String, dynamic>) {
          legacyName = TestLocalConfigLoader.optionalLegacyAppVersionFromImportRoot(
            Map<String, dynamic>.from(dec),
          );
        }
      } catch (_) {}
      final r = await TestLocalConfigLoader.applyFromFile(
        File(filePath),
        _workspace,
      );
      if (r == null) {
        return (
          '无法解析该文件。请确认 JSON 为「扁平单项目」字段或含 projects 的完整工作区（与 crash-tools-test-config.sample.json 一致）。',
          null,
        );
      }
      _workspace.ensureValidActive();
      _resetWorkspaceSession();
      if (legacyName != null && legacyName.isNotEmpty) {
        listNameQuery = legacyName;
      }
      await _persistWorkspace();
      await _syncWallpaperThemeSeed();
      notifyListeners();
      return (null, r.mode);
    } catch (e) {
      return ('导入失败：$e', null);
    }
  }

  Future<void> saveConfig(ToolConfig next) async {
    activeProject.config = next;
    notifyListeners();
    await _persistWorkspace();
  }

  /// 将当前工作区写入磁盘（侧栏宽度等局部字段变更后调用），不触发 [notifyListeners]。
  Future<void> persistLayoutWidthsOnly() async {
    await _persistWorkspace();
  }

  void openProjectHub() {
    _workspace.ensureValidActive();
    _hubSelectedProjectId = _workspace.activeProjectId!;
    showProjectHub = true;
    notifyListeners();
  }

  void hubSelectProject(String id) {
    _hubSelectedProjectId = id;
    notifyListeners();
  }

  String get hubSelectedProjectId {
    _workspace.ensureValidActive();
    if (_hubSelectedProjectId.isEmpty ||
        !_workspace.projects.any((p) => p.id == _hubSelectedProjectId)) {
      return _workspace.activeProjectId!;
    }
    return _hubSelectedProjectId;
  }

  /// 以当前项目中心选中项进入工作台；必要时切换当前项目并清空列表会话状态。
  Future<void> commitHubSelectionAndEnter() async {
    await commitHubSelectionAndEnterWithId(hubSelectedProjectId);
  }

  Future<void> commitHubSelectionAndEnterWithId(String projectId) async {
    _workspace.ensureValidActive();
    if (!_workspace.projects.any((p) => p.id == projectId)) {
      return;
    }
    final changed = _workspace.activeProjectId != projectId;
    _workspace.activeProjectId = projectId;
    _hubSelectedProjectId = projectId;
    if (changed) {
      _resetWorkspaceSession();
      await _syncWallpaperThemeSeed();
    }
    showProjectHub = false;
    await _persistWorkspace();
    notifyListeners();
  }

  void _resetWorkspaceSession() {
    loadingIssues = false;
    issuesError = null;
    lastIssues = null;
    pageIndex = 1;
    selectedDigestHashes.clear();
    _workspaceBizOverride = '';
    listNameQuery = '';
    listPackageNameQuery = '';
    _listPageSizeForApi = pageSize;
    _perfStartupLaunchKind = 'all';
    overviewMetrics = null;
    overviewDashboardError = null;
    loadingOverviewMetrics = false;
    _chatAttachedReport = null;
  }

  Future<void> setOpenProjectHubOnLaunch(bool v) async {
    _workspace.openProjectHubOnLaunch = v;
    await _persistWorkspace();
    notifyListeners();
  }

  Future<void> createProject(String name) async {
    try {
      _workspace.ensureValidActive();
      final id = ProjectEntry.newId();
      final n = name.trim().isEmpty ? '新项目 ${_workspace.projects.length + 1}' : name.trim();
      _workspace.projects.add(ProjectEntry(id: id, name: n, config: ToolConfig()));
      _hubSelectedProjectId = id;
      await _persistWorkspace();
      notifyListeners();
    } catch (e, st) {
      debugPrint('createProject failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> renameProject(String id, String name) async {
    try {
      _workspace.ensureValidActive();
      final i = _workspace.projects.indexWhere((p) => p.id == id);
      if (i < 0) return;
      final t = name.trim();
      if (t.isEmpty) return;
      _workspace.projects[i].name = t;
      await _persistWorkspace();
      notifyListeners();
    } catch (e, st) {
      debugPrint('renameProject failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> deleteProject(String id) async {
    try {
      _workspace.ensureValidActive();
      if (_workspace.projects.length <= 1) {
        return;
      }
      final idx = _workspace.projects.indexWhere((p) => p.id == id);
      if (idx < 0) {
        return;
      }
      _workspace.projects.removeAt(idx);
      _analysisReportsByProject.remove(id);
      unawaited(AnalysisReportStorage.save(_analysisReportsByProject));
      if (_workspace.activeProjectId == id) {
        _workspace.activeProjectId = _workspace.projects.first.id;
        _resetWorkspaceSession();
        await _syncWallpaperThemeSeed();
      }
      if (_hubSelectedProjectId == id) {
        _hubSelectedProjectId = _workspace.activeProjectId!;
      }
      await _persistWorkspace();
      notifyListeners();
    } catch (e, st) {
      debugPrint('deleteProject failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> _syncWallpaperThemeSeed() async {
    final id = activeProject.config.wallpaperId.trim();
    if (id.isEmpty) {
      _wallpaperThemeSeed = AppTheme.defaultSeed;
      notifyListeners();
      return;
    }
    final path = WallpaperCatalog.assetPathFor(id);
    if (path == null) {
      _wallpaperThemeSeed = AppTheme.defaultSeed;
      notifyListeners();
      return;
    }
    _wallpaperThemeSeed = await WallpaperThemeSeeder.seedFromAssetPath(path);
    notifyListeners();
  }

  /// 循环切换：无壁纸 → 各内置图 → 无；写入本地配置，并同步主题色。
  Future<void> cycleWallpaper() async {
    final c = activeProject.config;
    c.wallpaperId = WallpaperCatalog.nextId(c.wallpaperId);
    notifyListeners();
    await _persistWorkspace();
    await _syncWallpaperThemeSeed();
  }

  /// [resetPageSizeToDefault] 为 true 时恢复每页 [pageSize]（常规「一键获取」、切换子模块等应传 true）。
  Future<void> refreshIssues({bool resetPageSizeToDefault = false}) async {
    if (resetPageSizeToDefault) {
      _listPageSizeForApi = pageSize;
    }
    if (_useEmasCrashMock) {
      loadingIssues = true;
      issuesError = null;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      lastIssues = EmasCrashMockData.mockGetIssues(
        pageIndex: pageIndex,
        pageSize: _listPageSizeForApi,
      );
      loadingIssues = false;
      notifyListeners();
      return;
    }

    final miss = config.validateEmas();
    if (miss.isNotEmpty) {
      issuesError = '请先完成配置：${miss.join('、')}';
      notifyListeners();
      return;
    }
    final ak = config.appKeyAsInt;
    if (ak == null) {
      issuesError = 'AppKey 必须是数字';
      notifyListeners();
      return;
    }

    loadingIssues = true;
    issuesError = null;
    notifyListeners();

    final client = EmasAppMonitorClient(
      accessKeyId: config.accessKeyId.trim(),
      accessKeySecret: config.accessKeySecret.trim(),
      regionId: config.region.trim(),
      httpClient: newOutboundHttpClient(),
    );
    try {
      lastIssues = await client.getIssues(
        appKey: ak,
        bizModule: activeBizModule,
        os: config.os.trim(),
        startTimeMs: rangeStartMs,
        endTimeMs: rangeEndMs,
        pageIndex: pageIndex,
        pageSize: _listPageSizeForApi,
        name: listNameQuery.isEmpty ? null : listNameQuery,
        packageName: effectiveEmasPackageNameForRequest,
        extraBody: _emasStartupLaunchExtra,
      );
    } catch (e) {
      issuesError = userFacingNetworkError(e);
      lastIssues = null;
    } finally {
      client.close();
      loadingIssues = false;
      notifyListeners();
    }
  }

  /// 先拉取列表第 1 页 10 条，再生成 TOP10 合并大模型总览（`ok:` / `err:`）。不依赖勾选与其它筛选。
  Future<String> pullTop10AggregateReportMarkdown() async {
    final missL = config.validateLlm();
    if (missL.isNotEmpty) return 'err:请先配置大模型：${missL.join('、')}';
    pageIndex = 1;
    _listPageSizeForApi = 10;
    await refreshIssues();
    final items = lastIssues?.items ?? const [];
    if (lastIssues == null || items.isEmpty) {
      final hint = (issuesError ?? '').trim();
      return 'err:${hint.isNotEmpty ? hint : '列表为空或拉取失败'}';
    }
    return generateTopAggregateReport(topN: 10);
  }

  /// 拉取实时概览：对齐控制台「实时大盘」常见维度，数据均为各 Biz 下 GetIssues 的 Total（聚合 issue 数）。
  Future<void> refreshOverviewDashboard() async {
    clearWorkspaceBizOverride();
    final miss = config.validateEmas();
    if (miss.isNotEmpty) {
      overviewDashboardError = '请先完成配置：${miss.join('、')}';
      overviewMetrics = null;
      notifyListeners();
      return;
    }
    final ak = config.appKeyAsInt;
    if (ak == null) {
      overviewDashboardError = 'AppKey 必须是数字';
      overviewMetrics = null;
      notifyListeners();
      return;
    }

    if (config.emasUseMockCrashData && config.bizModule.trim().toLowerCase() == 'crash') {
      loadingOverviewMetrics = true;
      overviewDashboardError = null;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      final mock = EmasCrashMockData.mockGetIssues(pageIndex: 1, pageSize: 5);
      overviewMetrics = OverviewMetricsSnapshot(
        rangeStartMs: rangeStartMs,
        rangeEndMs: rangeEndMs,
        byBizTotal: {
          'crash': mock.total,
          'anr': 0,
          'startup': 0,
          'exception': 0,
        },
        crashPreviewItems: mock.items.take(5).toList(),
        todayCrashTotal: mock.total,
      );
      loadingOverviewMetrics = false;
      notifyListeners();
      return;
    }

    loadingOverviewMetrics = true;
    overviewDashboardError = null;
    notifyListeners();

    final nameParam = listNameQuery.isEmpty ? null : listNameQuery;
    final pkgParam = effectiveEmasPackageNameForRequest;
    final client = EmasAppMonitorClient(
      accessKeyId: config.accessKeyId.trim(),
      accessKeySecret: config.accessKeySecret.trim(),
      regionId: config.region.trim(),
      httpClient: newOutboundHttpClient(),
    );
    final byBiz = <String, int>{};
    final errs = <String, String>{};
    var preview = <IssueListItem>[];
    try {
      for (final biz in _overviewBizOrder) {
        final pageSz = biz == 'crash' ? 5 : 1;
        try {
          final r = await client.getIssues(
            appKey: ak,
            bizModule: biz,
            os: config.os.trim(),
            startTimeMs: rangeStartMs,
            endTimeMs: rangeEndMs,
            pageIndex: 1,
            pageSize: pageSz,
            name: nameParam,
            packageName: pkgParam,
          );
          byBiz[biz] = r.total;
          if (biz == 'crash') {
            preview = List<IssueListItem>.of(r.items);
          }
        } catch (e) {
          errs[biz] = userFacingNetworkError(e);
        }
      }

      int? todayTotal;
      String? todayErr;
      try {
        final now = DateTime.now();
        final t0 = DateTime(now.year, now.month, now.day);
        final r = await client.getIssues(
          appKey: ak,
          bizModule: 'crash',
          os: config.os.trim(),
          startTimeMs: t0.millisecondsSinceEpoch,
          endTimeMs: now.millisecondsSinceEpoch,
          pageIndex: 1,
          pageSize: 1,
          name: nameParam,
          packageName: pkgParam,
        );
        todayTotal = r.total;
      } catch (e) {
        todayErr = userFacingNetworkError(e);
      }

      overviewMetrics = OverviewMetricsSnapshot(
        rangeStartMs: rangeStartMs,
        rangeEndMs: rangeEndMs,
        byBizTotal: byBiz,
        crashPreviewItems: preview.take(5).toList(),
        todayCrashTotal: todayTotal,
        perBizError: errs,
        todayError: todayErr,
      );
    } catch (e) {
      overviewDashboardError = userFacingNetworkError(e);
      overviewMetrics = null;
    } finally {
      client.close();
      loadingOverviewMetrics = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> fetchIssueDetail(
    String digestHash, {
    int? startTimeMs,
    int? endTimeMs,
  }) async {
    if (config.emasUseMockCrashData && EmasCrashMockData.isMockDigest(digestHash)) {
      return EmasCrashMockData.mockGetIssue(digestHash);
    }

    final miss = config.validateEmas();
    if (miss.isNotEmpty) return null;
    final ak = config.appKeyAsInt;
    if (ak == null) return null;

    final t0 = startTimeMs ?? rangeStartMs;
    final t1 = endTimeMs ?? rangeEndMs;

    final client = EmasAppMonitorClient(
      accessKeyId: config.accessKeyId.trim(),
      accessKeySecret: config.accessKeySecret.trim(),
      regionId: config.region.trim(),
      httpClient: newOutboundHttpClient(),
    );
    try {
      return await client.getIssue(
        appKey: ak,
        bizModule: activeBizModule,
        os: config.os.trim(),
        digestHash: digestHash,
        startTimeMs: t0,
        endTimeMs: t1,
        packageName: effectiveEmasPackageNameForRequest,
        extraBody: _emasStartupLaunchExtra,
      );
    } finally {
      client.close();
    }
  }

  /// 按 DigestHash 调用 GetIssue，成功则将 [lastIssues] 更新为**仅含该条**（与「一键获取」分页列表并存为两种入口）。
  /// 会依次尝试：当前时间范围 → 最近 90 个自然日（至昨天）→ 近 90 天滚动窗口（含今天），以减轻时间口径不一致导致的空结果。
  /// 成功返回 `null`，失败返回说明文案（不改变原有 [lastIssues]）。
  Future<String?> fetchIssueByDigestIntoList(String digestRaw) async {
    final digest = digestRaw.replaceAll(RegExp(r'\s+'), '');
    if (digest.isEmpty) {
      return '请输入问题 ID（DigestHash，如列表中的蓝色编号）';
    }

    if (_useEmasCrashMock && !EmasCrashMockData.isMockDigest(digest)) {
      return '已开启「崩溃列表 Mock」，请关闭后再拉控制台真实 ID，或使用 mock_digest_* 测试';
    }

    final miss = config.validateEmas();
    if (miss.isNotEmpty) return '请先完成配置：${miss.join('、')}';
    if (config.appKeyAsInt == null) return 'AppKey 须为数字';

    final previous = lastIssues;
    loadingIssues = true;
    issuesError = null;
    notifyListeners();

    IssueListItem? item;
    String? lastErr;

    Future<void> tryWindow(int t0, int t1) async {
      if (item != null) return;
      try {
        final j = await fetchIssueDetail(digest, startTimeMs: t0, endTimeMs: t1);
        final parsed = j != null ? IssueListItem.fromGetIssueResponse(j, digestHint: digest) : null;
        if (_issueListItemHasPayload(parsed)) {
          item = parsed;
          lastErr = null;
        } else if (j == null) {
          lastErr ??= '无法请求 GetIssue（请检查 AccessKey 与网络）';
        } else {
          lastErr ??= 'GetIssue 未返回有效内容（可尝试扩大上方「时间范围」后再拉）';
        }
      } catch (e) {
        lastErr = userFacingNetworkError(e);
      }
    }

    try {
      await tryWindow(rangeStartMs, rangeEndMs);
      if (item == null) {
        final w = calendarInclusiveRangeBounds(calendarDaysInclusive: 90);
        await tryWindow(w.$1, w.$2);
      }
      if (item == null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await tryWindow(now - const Duration(days: 90).inMilliseconds, now);
      }

      if (item == null) {
        lastIssues = previous;
        return lastErr ??
            '未查到该问题：请核对 ID、侧栏当前 Biz（崩溃/ANR/卡顿/异常）与控制台是否一致';
      }

      lastIssues = GetIssuesResult(
        items: <IssueListItem>[item!],
        total: 1,
        pageNum: 1,
        pageSize: 1,
        pages: 1,
      );
      pageIndex = 1;
      selectedDigestHashes.clear();
      return null;
    } finally {
      loadingIssues = false;
      notifyListeners();
    }
  }

  static bool _issueListItemHasPayload(IssueListItem? it) {
    if (it == null) return false;
    bool nn(String? s) => s != null && s.trim().isNotEmpty;
    if (!nn(it.digestHash)) return false;
    return nn(it.errorName) ||
        nn(it.stack) ||
        nn(it.errorType) ||
        it.errorCount != null ||
        it.errorDeviceCount != null;
  }

  /// 将当前列表导出为 HTML 到用户选择的绝对路径（需已有列表数据）。
  Future<String> exportHtmlReportToFile(String absolutePath) async {
    final items = lastIssues?.items ?? const [];
    if (items.isEmpty) return 'err:暂无列表数据，请先在「工作台」一键获取';
    final html = buildIssuesHtml(
      config: config,
      items: items,
      startMs: rangeStartMs,
      endMs: rangeEndMs,
      bizModuleShown: activeBizModule,
      nameFilterShown: listNameQuery.isEmpty ? null : listNameQuery,
      packageNameShown: effectiveEmasPackageNameForRequest,
    );
    await File(absolutePath).writeAsString(html, encoding: utf8);
    return 'ok';
  }

  /// 写入预览 HTML 并返回 `ok:绝对路径`，供系统默认浏览器打开。
  Future<String> writePreviewHtmlAndPath() async {
    final items = lastIssues?.items ?? const [];
    if (items.isEmpty) return 'err:暂无列表数据，请先在「工作台」一键获取';
    final html = buildIssuesHtml(
      config: config,
      items: items,
      startMs: rangeStartMs,
      endMs: rangeEndMs,
      bizModuleShown: activeBizModule,
      nameFilterShown: listNameQuery.isEmpty ? null : listNameQuery,
      packageNameShown: effectiveEmasPackageNameForRequest,
    );
    final dir = await getApplicationSupportDirectory();
    final sub = Directory(p.join(dir.path, 'reports'));
    await sub.create(recursive: true);
    final f = File(p.join(sub.path, 'preview_latest.html'));
    await f.writeAsString(html, encoding: utf8);
    return 'ok:${f.path}';
  }

  /// 简易单文件 HTML（应用支持目录）。
  Future<String> exportHtmlReport() async {
    final items = lastIssues?.items ?? const [];
    if (items.isEmpty) return 'err:当前没有可导出的列表，请先拉取问题';
    final html = buildIssuesHtml(
      config: config,
      items: items,
      startMs: rangeStartMs,
      endMs: rangeEndMs,
      bizModuleShown: activeBizModule,
      nameFilterShown: listNameQuery.isEmpty ? null : listNameQuery,
      packageNameShown: effectiveEmasPackageNameForRequest,
    );
    final dir = await getApplicationSupportDirectory();
    final sub = Directory(p.join(dir.path, 'reports'));
    await sub.create(recursive: true);
    final name = 'report_${DateTime.now().millisecondsSinceEpoch}.html';
    final f = File(p.join(sub.path, name));
    await f.writeAsString(html, encoding: utf8);
    return 'ok:${f.path}';
  }

  /// 完整报告（HTML + manifest + payloads），写入 [parentDir]。
  Future<String> exportReportBundleTo(Directory parentDir) async {
    final items = lastIssues?.items ?? const [];
    return exportReportBundle(
      config: config,
      items: items,
      startMs: rangeStartMs,
      endMs: rangeEndMs,
      parentDir: parentDir,
      bizModuleShown: activeBizModule,
      nameFilterShown: listNameQuery.isEmpty ? null : listNameQuery,
      packageNameShown: effectiveEmasPackageNameForRequest,
    );
  }

  /// 当前 [lastIssues] 列表中前 [limit] 条（含有效 digest）各自独立调用大模型，条目间**不**串联摘要。
  ///
  /// [onProgress] 每完成一条回调 `(已完成条数, 总条数)`。
  Future<List<IssueIndividualLlmResult>> analyzeTopIssuesIndividually({
    int limit = 15,
    void Function(int completed, int total)? onProgress,
  }) async {
    final missL = config.validateLlm();
    if (missL.isNotEmpty) {
      throw StateError('请先配置大模型：${missL.join('、')}');
    }

    final items = lastIssues?.items ?? const [];
    final picked = <IssueListItem>[];
    for (final it in items) {
      final d = it.digestHash?.trim();
      if (d == null || d.isEmpty) continue;
      picked.add(it);
      if (picked.length >= limit) break;
    }
    if (picked.isEmpty) {
      throw StateError('当前列表没有带 Digest 的数据，请先「一键获取」');
    }

    final client = LlmClient(
      baseUrl: config.llmBaseUrl.trim(),
      apiKey: config.llmApiKey.trim(),
      model: config.llmModel.trim(),
      chatCompletionsPath: config.effectiveLlmChatPath,
      httpClient: newOutboundHttpClient(),
    );
    final results = <IssueIndividualLlmResult>[];
    try {
      for (var i = 0; i < picked.length; i++) {
        final it = picked[i];
        final digest = it.digestHash!.trim();
        final rank = i + 1;
        try {
          final detail = await fetchIssueDetail(digest);
          if (detail == null) {
            results.add(
              IssueIndividualLlmResult(
                rank: rank,
                digestHash: digest,
                errorName: it.errorName,
                stackPreview: _shortStackPreview(it.stack),
                errorMessage: 'GetIssue 无数据（请检查时间范围与 BizModule）',
              ),
            );
            onProgress?.call(rank, picked.length);
            continue;
          }
          final stackStr = it.stack ?? '';
          final clarity = analyzeStackClarity(stackStr);
          final basePrompt = buildAnalysisUserPrompt(
            digestHash: digest,
            getIssueBody: detail,
            listTitle: it.errorName,
            listStack: stackStr,
            clarity: clarity,
          );
          final userMsg =
              '$basePrompt\n\n----------\n（本条为 Top 列表第 $rank 条，请仅针对本条独立分析，勿引用其它 digest。）';
          final reply = await client.chat([
            {'role': 'system', 'content': config.effectiveLlmSystemPrompt},
            {'role': 'user', 'content': userMsg},
          ]);
          results.add(
            IssueIndividualLlmResult(
              rank: rank,
              digestHash: digest,
              errorName: it.errorName,
              stackPreview: _shortStackPreview(it.stack),
              analysisText: reply,
            ),
          );
        } catch (e) {
          results.add(
            IssueIndividualLlmResult(
              rank: rank,
              digestHash: digest,
              errorName: it.errorName,
              stackPreview: _shortStackPreview(it.stack),
              errorMessage: userFacingNetworkError(e),
            ),
          );
        }
        onProgress?.call(rank, picked.length);
      }
      return results;
    } finally {
      client.close();
    }
  }

  String? _shortStackPreview(String? stack) {
    if (stack == null || stack.trim().isEmpty) return null;
    final t = stack.trim();
    if (t.length <= 200) return t;
    return '${t.substring(0, 200)}…';
  }

  /// 勾选条目依次调用大模型，后续条目携带同批前文摘要。
  Future<String> batchAnalyzeSelected() async {
    final missL = config.validateLlm();
    if (missL.isNotEmpty) return 'err:请先配置大模型：${missL.join('、')}';
    final ids = selectedDigestHashes.toList();
    if (ids.isEmpty) return 'err:请先勾选问题';

    final client = LlmClient(
      baseUrl: config.llmBaseUrl.trim(),
      apiKey: config.llmApiKey.trim(),
      model: config.llmModel.trim(),
      chatCompletionsPath: config.effectiveLlmChatPath,
      httpClient: newOutboundHttpClient(),
    );
    final summaries = <String>[];
    try {
      for (final digest in ids) {
        final detail = await fetchIssueDetail(digest);
        if (detail == null) {
          final miss = config.validateEmas();
          final hint = miss.isNotEmpty
              ? 'EMAS 未就绪：${miss.join('、')}'
              : (config.appKeyAsInt == null ? 'AppKey 须为数字' : 'GetIssue 无数据');
          summaries.add('### digest=$digest\n（已跳过：$hint）');
          continue;
        }
        final prior = summaries.isEmpty ? '（本批首条，尚无前文摘要）' : summaries.join('\n---\n');
        final userMsg = '''
同一批次内多个 digest 可能共享同一根因。请先参考同批已有摘要，再分析当前条目。

【同批已有摘要】
$prior

【当前 digest】
$digest

【GetIssue 响应 JSON】
${jsonEncode(detail)}
''';
        final messages = <Map<String, String>>[
          {'role': 'system', 'content': config.effectiveLlmSystemPrompt},
          {'role': 'user', 'content': userMsg},
        ];
        final reply = await client.chat(messages);
        summaries.add('### digest=$digest\n$reply');
      }
      return 'ok:${summaries.join('\n\n========\n\n')}';
    } catch (e) {
      return 'err:${userFacingNetworkError(e)}';
    } finally {
      client.close();
    }
  }

  /// 对当前 [lastIssues] 列表前 [topN] 条（有 Digest）**单次**大模型调用，生成合并总览报告（崩溃 / ANR 等随当前 [activeBizModule]）。
  ///
  /// 输入为列表接口中的堆栈摘录（不逐条拉 GetIssue，避免耗时与 token 过大）。返回 `ok:` + Markdown 或 `err:` + 说明。
  Future<String> generateTopAggregateReport({int topN = 10}) async {
    final missL = config.validateLlm();
    if (missL.isNotEmpty) return 'err:请先配置大模型：${missL.join('、')}';
    final n = topN < 1 ? 1 : (topN > 30 ? 30 : topN);
    final items = lastIssues?.items ?? const [];
    final picked = <IssueListItem>[];
    for (final it in items) {
      final d = it.digestHash?.trim();
      if (d == null || d.isEmpty) continue;
      picked.add(it);
      if (picked.length >= n) break;
    }
    if (picked.isEmpty) {
      return 'err:当前列表没有带 Digest 的数据，请先「一键获取」';
    }
    final userMsg = buildTopNAggregateUserMessage(
      issues: picked,
      bizModule: activeBizModule,
      rangeStartMs: rangeStartMs,
      rangeEndMs: rangeEndMs,
    );
    final client = LlmClient(
      baseUrl: config.llmBaseUrl.trim(),
      apiKey: config.llmApiKey.trim(),
      model: config.llmModel.trim(),
      chatCompletionsPath: config.effectiveLlmChatPath,
      httpClient: newOutboundHttpClient(),
    );
    try {
      final reply = await client.chat([
        {'role': 'system', 'content': config.effectiveLlmSystemPrompt},
        {'role': 'user', 'content': userMsg},
      ]);
      return 'ok:$reply';
    } catch (e) {
      return 'err:${userFacingNetworkError(e)}';
    } finally {
      client.close();
    }
  }

  /// `crash-tools://open?path=...` 打开 payload 并执行 Agent。
  /// 探测 EMAS 列表接口（不覆盖当前 [lastIssues]）。
  ///
  /// [draft] 非空时（如配置页未保存的表单）用其中的 AK/业务字段探测；否则用已落盘的 [config] 与工作台状态。
  Future<String> probeEmasConnection([ToolConfig? draft]) async {
    final cfg = draft ?? config;
    final bool mockCrash;
    if (draft != null) {
      mockCrash =
          cfg.emasUseMockCrashData && cfg.bizModule.trim().toLowerCase() == 'crash';
    } else {
      mockCrash = _useEmasCrashMock;
    }
    if (mockCrash) {
      return 'Mock · 崩溃模块使用本地数据预览（未请求 EMAS）';
    }

    final miss = cfg.validateEmas();
    if (miss.isNotEmpty) return '未就绪：缺少 ${miss.join('、')}';
    final ak = cfg.appKeyAsInt;
    if (ak == null) return '未就绪：AppKey 须为数字';

    final client = EmasAppMonitorClient(
      accessKeyId: cfg.accessKeyId.trim(),
      accessKeySecret: cfg.accessKeySecret.trim(),
      regionId: cfg.region.trim(),
      httpClient: newOutboundHttpClient(),
    );
    final biz = draft != null ? cfg.bizModule.trim() : activeBizModule;
    final nameQ = listNameQuery.trim().isEmpty ? null : listNameQuery.trim();
    final pkgQ = draft != null ? cfg.appPackageNameForOpenApi : effectiveEmasPackageNameForRequest;
    try {
      final r = await client.getIssues(
        appKey: ak,
        bizModule: biz,
        os: cfg.os.trim(),
        startTimeMs: rangeStartMs,
        endTimeMs: rangeEndMs,
        pageIndex: 1,
        pageSize: 1,
        name: nameQ,
        packageName: pkgQ,
        extraBody: _emasStartupLaunchExtra,
      );
      return '正常 · 时间范围内共 ${r.total} 条聚合';
    } catch (e) {
      return '异常：${userFacingNetworkError(e)}';
    } finally {
      client.close();
    }
  }

  /// 探测 GitLab 项目访问。
  Future<String> probeGitlabConnection([ToolConfig? draft]) async {
    final cfg = draft ?? config;
    final miss = cfg.validateGitlab();
    if (miss.isNotEmpty) return '未配置：${miss.join('、')}';
    final client = GitLabClient(
      baseUrl: cfg.gitlabBaseUrl.trim(),
      privateToken: cfg.gitlabToken.trim(),
      httpClient: newOutboundHttpClient(),
    );
    try {
      final bindings = cfg.gitlabBindingsResolved;
      final firstId = bindings.first.projectId.trim();
      final label = await client.fetchProjectLabel(projectId: firstId);
      if (bindings.length > 1) {
        return '正常 · $label（已配置 ${bindings.length} 个仓库）';
      }
      return '正常 · $label';
    } catch (e) {
      return '异常：${userFacingNetworkError(e)}';
    } finally {
      client.close();
    }
  }

  /// 探测大模型 Chat 接口。
  Future<String> probeLlmConnection([ToolConfig? draft]) async {
    final cfg = draft ?? config;
    final miss = cfg.validateLlm();
    if (miss.isNotEmpty) return '未配置：${miss.join('、')}';
    final client = LlmClient(
      baseUrl: cfg.llmBaseUrl.trim(),
      apiKey: cfg.llmApiKey.trim(),
      model: cfg.llmModel.trim(),
      chatCompletionsPath: cfg.effectiveLlmChatPath,
      httpClient: newOutboundHttpClient(),
    );
    try {
      await client.chat(
        [
          {'role': 'user', 'content': '只回复：OK'},
        ],
        temperature: 0,
      );
      return '正常 · 模型 ${cfg.llmModel.trim()} 可对话';
    } catch (e) {
      return '异常：${userFacingNetworkError(e)}';
    } finally {
      client.close();
    }
  }

  Future<void> handleProtocolUri(Uri? uri) async {
    if (uri == null) return;
    if (uri.scheme != 'crash-tools') return;
    try {
      if (uri.host == 'open') {
        final q = uri.queryParameters['path'];
        if (q == null || q.isEmpty) {
          debugPrint('[crash-tools] 缺少 path 参数');
          return;
        }
        final path = Uri.decodeFull(q);
        final file = File(path);
        if (!await file.exists()) {
          debugPrint('[crash-tools] 文件不存在：$path');
          return;
        }
        final text = await file.readAsString();
        final payload = AgentPayload.tryParseFile(text);
        if (payload == null) {
          debugPrint('[crash-tools] payload JSON 无效');
          return;
        }
        await AgentLauncher.runFromPayload(payload);
      } else {
        debugPrint('[crash-tools] 未识别路径：${uri.host}');
      }
    } catch (e) {
      debugPrint('[crash-tools] 协议处理失败：$e');
    }
  }
}
