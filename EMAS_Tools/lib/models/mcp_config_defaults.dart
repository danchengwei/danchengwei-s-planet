import 'dart:convert';

/// 与 Cursor / Claude Desktop 等兼容的 `mcpServers` 默认值与合并规则。
///
/// **工作区持久化**：默认只保存 **GitLab** 一条（及进阶 JSON 里用户追加的其它服务）。
/// **Cursor 写入 / 完整导出**：自动合并内置 **claude-code**、**cursor**（自带 MCP，不可在本工具内改）。
class McpConfigDefaults {
  McpConfigDefaults._();

  /// SaaS 默认 API 根路径（与官方 MCP 环境变量一致）；自建实例在 GitLab 页填域名后会覆盖。
  static const String defaultGitlabApiV4Url = 'https://gitlab.com/api/v4';

  /// Claude Code 内置 MCP（仅用于导出到 `mcp.json`，不写入工作区配置）。
  static Map<String, dynamic> builtinClaudeCodeMcpEntry() => {
        'command': 'claude',
        'args': <String>['mcp', 'start'],
        'env': <String, String>{},
      };

  /// Cursor 内置 MCP（仅用于导出，不写入工作区）。
  static Map<String, dynamic> builtinCursorMcpEntry() => {
        'command': 'cursor',
        'args': <String>['mcp', 'start'],
        'env': <String, String>{},
      };

  /// 单条 GitLab MCP（npx 官方包）模板。
  static Map<String, dynamic> defaultGitlabServerBlock() => {
        'command': 'npx',
        'args': <String>['-y', '@modelcontextprotocol/server-gitlab'],
        'env': <String, String>{
          'GITLAB_PERSONAL_ACCESS_TOKEN': '',
          'GITLAB_API_URL': defaultGitlabApiV4Url,
        },
      };

  /// 工作区默认 `mcpServers`：**仅含 GitLab**。
  static Map<String, dynamic> defaultStoredMcpServers() => {
        'gitlab': deepCopyMap(Map<dynamic, dynamic>.from(defaultGitlabServerBlock())),
      };

  /// 与 [defaultStoredMcpServers] 相同；保留名称以兼容旧调用。
  static Map<String, dynamic> mcpServersMap() => defaultStoredMcpServers();

  /// 去掉不应持久化的内置宿主键；**不**自动补 `gitlab`（允许用户删除后保持空项，GitLab 页保存会再补全）。
  static Map<String, dynamic> normalizeStoredMcpServers(Map<String, dynamic> raw) {
    final inner = deepCopyMap(Map<dynamic, dynamic>.from(raw));
    inner.remove('claude-code');
    inner.remove('cursor');
    return inner;
  }

  /// 供写入 `~/.cursor/mcp.json` 或「复制完整 JSON」。
  /// [include] 为 `false` 时跳过该项；为 `null` 时包含全部（兼容旧调用）。
  static Map<String, dynamic> fullMcpServersForClientExport(
    Map<String, dynamic> stored, {
    bool Function(String id)? include,
  }) {
    bool inc(String id) => include == null || include(id);
    final norm = normalizeStoredMcpServers(stored);
    final out = <String, dynamic>{};
    if (inc('claude-code')) {
      out['claude-code'] = deepCopyMap(Map<dynamic, dynamic>.from(builtinClaudeCodeMcpEntry()));
    }
    if (inc('cursor')) {
      out['cursor'] = deepCopyMap(Map<dynamic, dynamic>.from(builtinCursorMcpEntry()));
    }
    for (final e in norm.entries) {
      if (e.key == 'claude-code' || e.key == 'cursor') continue;
      if (!inc(e.key)) continue;
      final v = e.value;
      if (v is Map) {
        out[e.key] = deepCopyMap(Map<dynamic, dynamic>.from(v));
      }
    }
    return out;
  }

  /// 将 Token、GitLab 站点根 URL 合并进 [inner] 的 `gitlab.env`（用于 MCP）。
  /// [gitlabBaseUrl] 为空时按 gitlab.com SaaS 处理。
  static void mergeGitlabEnvFromFields(
    Map<String, dynamic> inner, {
    required String gitlabToken,
    required String gitlabBaseUrl,
  }) {
    final gl = inner['gitlab'];
    if (gl is! Map) return;
    final glMap = Map<String, dynamic>.from(gl);
    final envRaw = glMap['env'];
    final env = envRaw is Map
        ? Map<String, String>.from(
            envRaw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
          )
        : <String, String>{};
    env['GITLAB_PERSONAL_ACCESS_TOKEN'] = gitlabToken.trim();
    var base = gitlabBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      base = 'https://gitlab.com';
    }
    env['GITLAB_API_URL'] = base.endsWith('/api/v4') ? base : '$base/api/v4';
    glMap['env'] = env;
    inner['gitlab'] = glMap;
  }

  static Map<String, String> _gitlabEnvMap(String gitlabToken, String gitlabBaseUrl) {
    var base = gitlabBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) base = 'https://gitlab.com';
    final api = base.endsWith('/api/v4') ? base : '$base/api/v4';
    return {
      'GITLAB_PERSONAL_ACCESS_TOKEN': gitlabToken.trim(),
      'GITLAB_API_URL': api,
    };
  }

  /// 推荐 `mcpServers`（**工作区形态**，仅 GitLab + 合并后的 env）。
  /// [gitlabBrewExecutable] 非空时用 brew 安装的 `gitlab-mcp` 可执行文件，否则用 npx 官方包。
  static Map<String, dynamic> recommendedMcpServers({
    required String gitlabToken,
    required String gitlabBaseUrl,
    String? gitlabBrewExecutable,
  }) {
    final inner = deepCopyMap(Map<dynamic, dynamic>.from(defaultStoredMcpServers()));
    final brew = gitlabBrewExecutable?.trim() ?? '';
    if (brew.isNotEmpty) {
      inner['gitlab'] = {
        'command': brew,
        'args': <String>[],
        'env': _gitlabEnvMap(gitlabToken, gitlabBaseUrl),
      };
    } else {
      mergeGitlabEnvFromFields(
        inner,
        gitlabToken: gitlabToken,
        gitlabBaseUrl: gitlabBaseUrl,
      );
    }
    return inner;
  }

  /// 保存项目配置时调用：规范化工作区 `mcpServers`，并把 GitLab 页的 Token/API 写入 `gitlab.env`。
  /// [gitlabBrewExecutable] 非空时 `gitlab` 项改为 brew 二进制 + env。
  static Map<String, dynamic> autoMergedMcpServersForSave({
    required Map<String, dynamic> currentMcpServers,
    required String gitlabToken,
    required String gitlabBaseUrl,
    String? gitlabBrewExecutable,
    /// 为 `true` 时在缺少 `gitlab` 键时插入默认模板（「GitLab」页保存、推荐配置等）；MCP 页用户删除后写 Cursor 时应为 `false`。
    bool ensureGitlabBlock = true,
  }) {
    final inner = normalizeStoredMcpServers(currentMcpServers);
    if (ensureGitlabBlock && (!inner.containsKey('gitlab') || inner['gitlab'] is! Map)) {
      inner['gitlab'] = deepCopyMap(Map<dynamic, dynamic>.from(defaultGitlabServerBlock()));
    }
    final brew = gitlabBrewExecutable?.trim() ?? '';
    if (brew.isNotEmpty) {
      inner['gitlab'] = {
        'command': brew,
        'args': <String>[],
        'env': _gitlabEnvMap(gitlabToken, gitlabBaseUrl),
      };
    } else {
      mergeGitlabEnvFromFields(
        inner,
        gitlabToken: gitlabToken,
        gitlabBaseUrl: gitlabBaseUrl,
      );
    }
    return inner;
  }

  /// 深拷贝，避免 JSON 往返时修改同一引用。
  static Map<String, dynamic> deepCopyMap(Map<dynamic, dynamic> source) {
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(source)) as Map);
  }

  /// 解析用户上传的 JSON：支持根级 `mcpServers`，或根级即为各 server 名 → 配置。
  static Map<String, dynamic>? parseImportedMcpDocument(String text) {
    final dynamic root = jsonDecode(text.trim());
    if (root is! Map) return null;
    final map = Map<String, dynamic>.from(root);
    final inner = map['mcpServers'];
    if (inner is Map) {
      return normalizeStoredMcpServers(deepCopyMap(Map<dynamic, dynamic>.from(inner)));
    }
    if (map.isNotEmpty && _looksLikeServerMap(map)) {
      return normalizeStoredMcpServers(deepCopyMap(Map<dynamic, dynamic>.from(map)));
    }
    return null;
  }

  static bool _looksLikeServerMap(Map<String, dynamic> m) {
    for (final e in m.values) {
      if (e is Map && (e.containsKey('command') || e.containsKey('url') || e.containsKey('type'))) {
        return true;
      }
    }
    return false;
  }
}
