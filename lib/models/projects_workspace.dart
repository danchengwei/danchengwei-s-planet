import 'dart:math';

import 'tool_config.dart';

/// 单个业务项目：展示名 + 独立 [ToolConfig]。
class ProjectEntry {
  ProjectEntry({
    required this.id,
    required this.name,
    required this.config,
  });

  final String id;
  String name;
  ToolConfig config;

  static String newId() {
    final r = Random();
    return '${DateTime.now().microsecondsSinceEpoch}_${r.nextInt(0x7fffffff)}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'config': config.toJson(),
      };

  factory ProjectEntry.fromJson(Map<String, dynamic> j) {
    final cfgMap = j['config'];
    final cfg = cfgMap is Map<String, dynamic>
        ? ToolConfig.fromJson(cfgMap)
        : ToolConfig();
    final nameRaw = j['name']?.toString().trim() ?? '';
    return ProjectEntry(
      id: j['id']?.toString() ?? newId(),
      name: nameRaw.isNotEmpty ? nameRaw : '未命名项目',
      config: cfg,
    );
  }
}

/// 本地多项目工作区（单文件持久化）。
class ProjectsWorkspace {
  ProjectsWorkspace({
    required this.openProjectHubOnLaunch,
    required this.activeProjectId,
    required this.projects,
  });

  /// 为 true 时冷启动先进入项目选择页（类似 IDE 欢迎页）。
  bool openProjectHubOnLaunch;

  String? activeProjectId;

  final List<ProjectEntry> projects;

  factory ProjectsWorkspace.empty() {
    final id = ProjectEntry.newId();
    return ProjectsWorkspace(
      openProjectHubOnLaunch: true,
      activeProjectId: id,
      projects: [ProjectEntry(id: id, name: '项目 1', config: ToolConfig())],
    );
  }

  /// 由旧版单文件 `crash-tools-config.json` 扁平结构迁移。
  factory ProjectsWorkspace.fromLegacyFlatConfig(Map<String, dynamic> j) {
    final cfg = ToolConfig.fromJson(j);
    final id = ProjectEntry.newId();
    return ProjectsWorkspace(
      openProjectHubOnLaunch: true,
      activeProjectId: id,
      projects: [
        ProjectEntry(id: id, name: '默认项目', config: cfg),
      ],
    );
  }

  factory ProjectsWorkspace.fromJson(Map<String, dynamic> j) {
    final raw = j['projects'];
    final list = <ProjectEntry>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(ProjectEntry.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return ProjectsWorkspace(
      openProjectHubOnLaunch: j['openProjectHubOnLaunch'] as bool? ?? true,
      activeProjectId: j['activeProjectId']?.toString(),
      projects: list,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 2,
        'openProjectHubOnLaunch': openProjectHubOnLaunch,
        'activeProjectId': activeProjectId,
        'projects': projects.map((e) => e.toJson()).toList(),
      };

  /// 保证至少一个项目且 [activeProjectId] 有效。
  void ensureValidActive() {
    if (projects.isEmpty) {
      final id = ProjectEntry.newId();
      projects.add(ProjectEntry(id: id, name: '项目 1', config: ToolConfig()));
      activeProjectId = id;
      return;
    }
    final cur = activeProjectId;
    if (cur == null || !projects.any((p) => p.id == cur)) {
      activeProjectId = projects.first.id;
    }
  }
}
