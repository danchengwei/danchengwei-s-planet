import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'aliyun/emas_appmonitor_client.dart';
import 'models/agent_payload.dart';
import 'models/issue_individual_llm_result.dart';
import 'models/projects_workspace.dart';
import 'models/tool_config.dart';
import 'models/wallpaper_catalog.dart';
import 'services/agent_launcher.dart';
import 'services/analysis_prompt_builder.dart';
import 'services/stack_clarity.dart';
import 'services/config_repository.dart';
import 'services/emas_crash_mock_data.dart';
import 'services/test_local_config_loader.dart';
import 'services/gitlab_client.dart';
import 'services/llm_client.dart';
import 'services/report_bundle.dart';
import 'services/report_html.dart';
import 'services/security_redaction.dart';
import 'services/wallpaper_theme_seeder.dart';

/// 全局状态：多项目工作区、当前项目配置、列表、多选、协议回调。
class AppController extends ChangeNotifier {
  AppController() {
    _bootstrap();
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

  int rangeStartMs = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
  int rangeEndMs = DateTime.now().millisecondsSinceEpoch;

  /// 工作台子模块临时覆盖的 BizModule（如 anr、performance）；空则使用 [config.bizModule]。
  String _workspaceBizOverride = '';

  /// GetIssues 可选的 Name 条件（如版本号、错误名关键字，依控制台/OpenAPI 而定）。
  String listNameQuery = '';

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

  void setTimeRangeBack(Duration back) {
    final now = DateTime.now();
    rangeEndMs = now.millisecondsSinceEpoch;
    rangeStartMs = now.subtract(back).millisecondsSinceEpoch;
    pageIndex = 1;
    notifyListeners();
  }

  bool loadingIssues = false;
  String? issuesError;
  GetIssuesResult? lastIssues;
  int pageIndex = 1;
  final int pageSize = 20;

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
      }
      showProjectHub = _workspace.openProjectHubOnLaunch;
      await _syncWallpaperThemeSeed();
    } catch (e) {
      bootstrapError = e.toString();
      _workspace = ProjectsWorkspace.empty();
      _workspace.ensureValidActive();
      showProjectHub = true;
    }
    _workspace.ensureValidActive();
    listNameQuery = config.emasListNameQuery.trim();
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
    await _configRepo.saveWorkspace(_workspace);
  }

  Future<void> saveConfig(ToolConfig next) async {
    activeProject.config = next;
    listNameQuery = next.emasListNameQuery.trim();
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
    listNameQuery = activeProject.config.emasListNameQuery.trim();
    _perfStartupLaunchKind = 'all';
  }

  Future<void> setOpenProjectHubOnLaunch(bool v) async {
    _workspace.openProjectHubOnLaunch = v;
    await _persistWorkspace();
    notifyListeners();
  }

  Future<void> createProject(String name) async {
    _workspace.ensureValidActive();
    final id = ProjectEntry.newId();
    final n = name.trim().isEmpty ? '新项目 ${_workspace.projects.length + 1}' : name.trim();
    _workspace.projects.add(ProjectEntry(id: id, name: n, config: ToolConfig()));
    _hubSelectedProjectId = id;
    await _persistWorkspace();
    notifyListeners();
  }

  Future<void> renameProject(String id, String name) async {
    _workspace.ensureValidActive();
    final i = _workspace.projects.indexWhere((p) => p.id == id);
    if (i < 0) return;
    final t = name.trim();
    if (t.isEmpty) return;
    _workspace.projects[i].name = t;
    await _persistWorkspace();
    notifyListeners();
  }

  Future<void> deleteProject(String id) async {
    _workspace.ensureValidActive();
    if (_workspace.projects.length <= 1) {
      return;
    }
    final idx = _workspace.projects.indexWhere((p) => p.id == id);
    if (idx < 0) {
      return;
    }
    _workspace.projects.removeAt(idx);
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

  Future<void> refreshIssues() async {
    if (_useEmasCrashMock) {
      loadingIssues = true;
      issuesError = null;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      lastIssues = EmasCrashMockData.mockGetIssues(
        pageIndex: pageIndex,
        pageSize: pageSize,
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
    );
    try {
      lastIssues = await client.getIssues(
        appKey: ak,
        bizModule: activeBizModule,
        os: config.os.trim(),
        startTimeMs: rangeStartMs,
        endTimeMs: rangeEndMs,
        pageIndex: pageIndex,
        pageSize: pageSize,
        name: listNameQuery.isEmpty ? null : listNameQuery,
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

  Future<Map<String, dynamic>?> fetchIssueDetail(String digestHash) async {
    if (config.emasUseMockCrashData && EmasCrashMockData.isMockDigest(digestHash)) {
      return EmasCrashMockData.mockGetIssue(digestHash);
    }

    final miss = config.validateEmas();
    if (miss.isNotEmpty) return null;
    final ak = config.appKeyAsInt;
    if (ak == null) return null;

    final client = EmasAppMonitorClient(
      accessKeyId: config.accessKeyId.trim(),
      accessKeySecret: config.accessKeySecret.trim(),
      regionId: config.region.trim(),
    );
    try {
      return await client.getIssue(
        appKey: ak,
        bizModule: activeBizModule,
        os: config.os.trim(),
        digestHash: digestHash,
        startTimeMs: rangeStartMs,
        endTimeMs: rangeEndMs,
        extraBody: _emasStartupLaunchExtra,
      );
    } finally {
      client.close();
    }
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
    );
    final biz = draft != null ? cfg.bizModule.trim() : activeBizModule;
    final nameQ = draft != null
        ? (cfg.emasListNameQuery.trim().isEmpty ? null : cfg.emasListNameQuery.trim())
        : (listNameQuery.isEmpty ? null : listNameQuery);
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
