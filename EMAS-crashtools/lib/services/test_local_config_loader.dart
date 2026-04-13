import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/projects_workspace.dart';
import '../models/tool_config.dart';

/// 本地测试配置：启动时若存在指定 JSON 则读入并覆盖内存中的工作区/当前项目配置，
/// **不写回**加密工作区文件，便于每次新包/重装后仍用同一份文件调试。
///
/// 查找顺序（找到第一个即使用）：
/// 1. 环境变量 `CRASH_TOOLS_TEST_CONFIG` 指向的绝对路径
/// 2. 应用支持目录下的 `crash-tools-test-config.json`（与正式工作区同目录）
/// 3. 进程当前工作目录下的 `crash-tools-test-config.json`（`flutter run` 时常为工程根目录）
///
/// JSON 两种形态：
/// - **完整工作区**：含 `projects` 数组（可选 `schemaVersion`、`activeProjectId` 等），与 [ProjectsWorkspace.toJson] 一致
/// - **单项目扁平**：与 [ToolConfig.toJson] 字段一致，仅覆盖**当前活动项目**的 [ToolConfig]
class TestLocalConfigLoader {
  TestLocalConfigLoader._();

  static const fileName = 'crash-tools-test-config.json';

  /// 环境变量名：可指向任意路径的测试配置文件。
  static const envPathKey = 'CRASH_TOOLS_TEST_CONFIG';

  /// 供单元测试或脚本：从已有文件应用到 [workspace]，返回是否成功。
  static Future<TestConfigApplyResult?> applyFromFile(
    File file,
    ProjectsWorkspace workspace,
  ) async {
    if (kIsWeb) return null;
    if (!await file.exists()) return null;
    try {
      final text = await file.readAsString();
      final dynamic root = jsonDecode(text);
      if (root is! Map) return null;
      final m = Map<String, dynamic>.from(root);
      m.remove('__comment');
      return _applyDecodedMap(m, workspace, file.path);
    } catch (e, st) {
      debugPrint('TestLocalConfigLoader.applyFromFile: $e\n$st');
      return null;
    }
  }

  /// 启动时调用：按规则解析路径并应用。
  static Future<TestConfigApplyResult?> applyIfPresent(ProjectsWorkspace workspace) async {
    if (kIsWeb) return null;
    final path = await resolveExistingPath();
    if (path == null) return null;
    return applyFromFile(File(path), workspace);
  }

  /// 返回第一个存在的测试配置文件绝对路径；不存在则 null。
  static Future<String?> resolveExistingPath() async {
    if (kIsWeb) return null;
    final env = Platform.environment[envPathKey]?.trim();
    if (env != null && env.isNotEmpty) {
      final f = File(env);
      if (await f.exists()) return f.path;
    }
    try {
      final dir = await getApplicationSupportDirectory();
      final f1 = File(p.join(dir.path, fileName));
      if (await f1.exists()) return f1.path;
    } catch (e, st) {
      debugPrint('TestLocalConfigLoader support dir: $e\n$st');
    }
    try {
      final f2 = File(p.join(Directory.current.path, fileName));
      if (await f2.exists()) return f2.path;
    } catch (_) {}
    return null;
  }

  /// 单元测试用：根据 Map 直接应用（不落盘）。
  static TestConfigApplyResult? applyDecodedMapForTest(
    Map<String, dynamic> map,
    ProjectsWorkspace workspace,
  ) {
    if (kIsWeb) return null;
    final m = Map<String, dynamic>.from(map);
    m.remove('__comment');
    return _applyDecodedMap(m, workspace, '(memory)');
  }

  static TestConfigApplyResult? _applyDecodedMap(
    Map<String, dynamic> m,
    ProjectsWorkspace workspace,
    String sourceLabel,
  ) {
    final projectsRaw = m['projects'];
    if (projectsRaw is List) {
      _applyFullWorkspace(workspace, m);
      return TestConfigApplyResult(path: sourceLabel, mode: TestConfigApplyMode.workspace);
    }
    _applyFlatToolConfig(workspace, m);
    return TestConfigApplyResult(path: sourceLabel, mode: TestConfigApplyMode.toolConfig);
  }

  static void _applyFullWorkspace(ProjectsWorkspace into, Map<String, dynamic> j) {
    final w = ProjectsWorkspace.fromJson(j);
    w.ensureValidActive();
    into.openProjectHubOnLaunch = w.openProjectHubOnLaunch;
    into.activeProjectId = w.activeProjectId;
    into.projects.clear();
    for (final p in w.projects) {
      into.projects.add(
        ProjectEntry(
          id: p.id,
          name: p.name,
          config: ToolConfig.fromJson(p.config.toJson()),
        ),
      );
    }
    into.ensureValidActive();
  }

  static void _applyFlatToolConfig(ProjectsWorkspace workspace, Map<String, dynamic> j) {
    workspace.ensureValidActive();
    final activeId = workspace.activeProjectId!;
    final idx = workspace.projects.indexWhere((p) => p.id == activeId);
    final proj = idx >= 0 ? workspace.projects[idx] : workspace.projects.first;
    proj.config = ToolConfig.fromJson(j);
  }
}

enum TestConfigApplyMode { workspace, toolConfig }

class TestConfigApplyResult {
  TestConfigApplyResult({required this.path, required this.mode});

  final String path;
  final TestConfigApplyMode mode;
}
