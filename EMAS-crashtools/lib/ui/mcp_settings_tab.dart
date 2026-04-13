import 'dart:convert';
import 'dart:io' show File;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../data/mcp_builtin_registry.dart';
import '../models/mcp_catalog_entry.dart';
import '../models/mcp_config_defaults.dart';
import '../models/tool_config.dart';
import '../services/cursor_mcp_home_writer.dart';
import '../services/mcp_brew_gitlab_service.dart';
import 'mcp_catalog_install_dialog.dart';
import 'mcp_services_section.dart';

/// MCP（`mcpServers`）配置：工作区默认仅 GitLab；写入 Cursor 时合并内置 Claude Code / Cursor。
class McpSettingsTab extends StatefulWidget {
  const McpSettingsTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<McpSettingsTab> createState() => _McpSettingsTabState();
}

class _McpSettingsTabState extends State<McpSettingsTab> {
  late TextEditingController _jsonCtrl;
  late String _boundProjectId;

  static String _prettyDocument(Map<String, dynamic> mcpServers) {
    return const JsonEncoder.withIndent('  ').convert({'mcpServers': mcpServers});
  }

  @override
  void initState() {
    super.initState();
    _jsonCtrl = TextEditingController();
    _boundProjectId = widget.controller.activeProject.id;
    _reloadFromConfig();
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    final id = widget.controller.activeProject.id;
    if (!mounted || id == _boundProjectId) return;
    setState(() {
      _boundProjectId = id;
      _reloadFromConfig();
    });
  }

  void _reloadFromConfig() {
    _jsonCtrl.text = _prettyDocument(widget.controller.config.mcpServers);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _jsonCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _parseEditorDocument() {
    try {
      final root = jsonDecode(_jsonCtrl.text.trim());
      if (root is! Map<String, dynamic>) return null;
      final inner = root['mcpServers'];
      if (inner is! Map) return null;
      return McpConfigDefaults.deepCopyMap(inner);
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final innerRaw = _parseEditorDocument();
    if (innerRaw == null) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('无法保存'),
          content: const Text('JSON 无效，或缺少顶层的 mcpServers 对象。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定')),
          ],
        ),
      );
      return;
    }
    final inner = McpConfigDefaults.normalizeStoredMcpServers(innerRaw);
    final base = widget.controller.config.toJson();
    base['mcpServers'] = inner;
    final next = ToolConfig.fromJson(base);
    try {
      await widget.controller.saveConfig(next);
    } catch (e, st) {
      debugPrint('saveConfig (MCP) failed: $e\n$st');
      if (!mounted) return;
      final cs = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败：$e', style: TextStyle(color: cs.onErrorContainer)),
          backgroundColor: cs.errorContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('保存成功。MCP 配置已写入本机。'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _resetDefault() {
    setState(() {
      _jsonCtrl.text = _prettyDocument(McpConfigDefaults.defaultStoredMcpServers());
    });
  }

  Future<Map<String, dynamic>> _mergedStoredForCursorExport() async {
    final parsed = _parseEditorDocument();
    final base = parsed ?? widget.controller.config.mcpServers;
    final norm = McpConfigDefaults.normalizeStoredMcpServers(base);
    final brewExe = await _gitlabBrewExecutableIfInstalled();
    return McpConfigDefaults.autoMergedMcpServersForSave(
      currentMcpServers: norm,
      gitlabToken: widget.controller.config.gitlabToken,
      gitlabBaseUrl: widget.controller.config.gitlabBaseUrl,
      gitlabBrewExecutable: brewExe,
      ensureGitlabBlock: false,
    );
  }

  Future<void> _commitGitlabDialog(Map<String, dynamic> gitlabBlock) async {
    final c = widget.controller.config;
    final inner = McpConfigDefaults.deepCopyMap(Map<dynamic, dynamic>.from(c.mcpServers));
    inner['gitlab'] = gitlabBlock;
    final brewExe = await _gitlabBrewExecutableIfInstalled();
    final merged = McpConfigDefaults.autoMergedMcpServersForSave(
      currentMcpServers: inner,
      gitlabToken: c.gitlabToken,
      gitlabBaseUrl: c.gitlabBaseUrl,
      gitlabBrewExecutable: brewExe,
    );
    final j = c.toJson();
    j['mcpServers'] = merged;
    final next = ToolConfig.fromJson(j);
    try {
      await widget.controller.saveConfig(next);
    } catch (e, st) {
      debugPrint('saveConfig (GitLab MCP dialog) failed: $e\n$st');
      if (!mounted) return;
      final cs = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败：$e', style: TextStyle(color: cs.onErrorContainer)),
          backgroundColor: cs.errorContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _reloadFromConfig());
    await _writeCursorHomeMcpSilent(merged);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('GitLab MCP 已保存；已尝试写入本机 Cursor mcp.json'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<String?> _gitlabBrewExecutableIfInstalled() async {
    if (kIsWeb || !McpBrewGitlabService.platformMayUseBrew) return null;
    if (!await McpBrewGitlabService.hasBrew()) return null;
    if (!await McpBrewGitlabService.isFormulaInstalled()) return null;
    return McpBrewGitlabService.resolveExecutablePath();
  }

  Future<void> _pipelineAfterBrewOrHostsChange() async {
    final c = widget.controller.config;
    final brewExe = await _gitlabBrewExecutableIfInstalled();
    final parsed = _parseEditorDocument();
    final base = parsed ?? c.mcpServers;
    final merged = McpConfigDefaults.autoMergedMcpServersForSave(
      currentMcpServers: base,
      gitlabToken: c.gitlabToken,
      gitlabBaseUrl: c.gitlabBaseUrl,
      gitlabBrewExecutable: brewExe,
    );
    final j = c.toJson();
    j['mcpServers'] = merged;
    j['mcpGitlabInstallAck'] = true;
    await widget.controller.saveConfig(ToolConfig.fromJson(j));
    if (mounted) setState(() => _jsonCtrl.text = _prettyDocument(merged));
    await _writeCursorHomeMcpSilent(merged);
  }

  Future<void> _writeCursorHomeMcpSilent(Map<String, dynamic> storedMerged) async {
    if (kIsWeb) return;
    try {
      final full = McpConfigDefaults.fullMcpServersForClientExport(
        storedMerged,
        include: widget.controller.config.isMcpIdIncludedInExport,
      );
      await CursorMcpHomeWriter.writeMcpServersJson(full);
    } catch (e, st) {
      debugPrint('writeCursorHomeMcpSilent: $e\n$st');
    }
  }

  Future<void> _loadRecommendedToEditorOnly() async {
    final c = widget.controller.config;
    final brewExe = await _gitlabBrewExecutableIfInstalled();
    final inner = McpConfigDefaults.recommendedMcpServers(
      gitlabToken: c.gitlabToken,
      gitlabBaseUrl: c.gitlabBaseUrl,
      gitlabBrewExecutable: brewExe,
    );
    setState(() => _jsonCtrl.text = _prettyDocument(inner));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已载入推荐配置到下方 JSON，请点击右上角「保存」写入工作区'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _applyRecommendedAndSave() async {
    final c = widget.controller.config;
    final brewExe = await _gitlabBrewExecutableIfInstalled();
    final inner = McpConfigDefaults.recommendedMcpServers(
      gitlabToken: c.gitlabToken,
      gitlabBaseUrl: c.gitlabBaseUrl,
      gitlabBrewExecutable: brewExe,
    );
    final base = c.toJson();
    base['mcpServers'] = inner;
    base['mcpGitlabInstallAck'] = true;
    final next = ToolConfig.fromJson(base);
    try {
      await widget.controller.saveConfig(next);
    } catch (e, st) {
      debugPrint('applyRecommended MCP: $e\n$st');
      if (!mounted) return;
      final cs = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败：$e', style: TextStyle(color: cs.onErrorContainer)),
          backgroundColor: cs.errorContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!mounted) return;
    _jsonCtrl.text = _prettyDocument(inner);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已应用推荐 MCP 并保存。可复制 JSON 到 Cursor 的 mcp.json'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _syncGitlabIntoGitlabMcp() async {
    final inner = _parseEditorDocument();
    if (inner == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先修正 JSON（需含 mcpServers）')),
      );
      return;
    }
    if (inner['gitlab'] is! Map) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前配置中没有名为 gitlab 的 MCP 项')),
      );
      return;
    }
    final c = widget.controller.config;
    final brewExe = await _gitlabBrewExecutableIfInstalled();
    final next = McpConfigDefaults.autoMergedMcpServersForSave(
      currentMcpServers: inner,
      gitlabToken: c.gitlabToken,
      gitlabBaseUrl: c.gitlabBaseUrl,
      gitlabBrewExecutable: brewExe,
    );
    setState(() => _jsonCtrl.text = _prettyDocument(next));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已合并 GitLab 页凭据（含 brew / npx 方案），记得保存')),
    );
  }

  Future<void> _importFromFile() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Web 端不支持本地文件导入，请使用桌面版。')),
      );
      return;
    }
    try {
      final xf = await openFile(
        acceptedTypeGroups: const [XTypeGroup(label: 'JSON', extensions: ['json'])],
      );
      if (xf == null) return;
      final text = await xf.readAsString();
      final parsed = McpConfigDefaults.parseImportedMcpDocument(text);
      if (parsed == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件格式无法识别：需要 mcpServers 或各服务名 → 配置')),
        );
        return;
      }
      setState(() => _jsonCtrl.text = _prettyDocument(parsed));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已载入文件内容，记得点保存写入工作区')),
      );
    } catch (e, st) {
      debugPrint('MCP import: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  Future<void> _exportToFile() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Web 端请直接全选复制 JSON；导出文件请使用桌面版。')),
      );
      return;
    }
    try {
      final loc = await getSaveLocation(
        suggestedName: 'mcp.json',
        acceptedTypeGroups: const [XTypeGroup(label: 'JSON', extensions: ['json'])],
      );
      if (loc == null) return;
      await File(loc.path).writeAsString(_jsonCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已写入 ${loc.path}')),
      );
    } catch (e, st) {
      debugPrint('MCP export: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _jsonCtrl.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制工作区 JSON 到剪贴板')),
    );
  }

  Future<void> _copyFullForCursor() async {
    try {
      final merged = await _mergedStoredForCursorExport();
      final full = McpConfigDefaults.fullMcpServersForClientExport(
        merged,
        include: widget.controller.config.isMcpIdIncludedInExport,
      );
      await Clipboard.setData(ClipboardData(text: _prettyDocument(full)));
    } catch (e, st) {
      debugPrint('_copyFullForCursor: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('复制失败：$e')));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制完整 mcpServers（含 Cursor / Claude Code / GitLab）'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 合并 GitLab 页凭据后写入本机 `~/.cursor/mcp.json`（或 Windows 用户目录下 `.cursor`）。
  Future<void> _writeCursorHomeMcpJson() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Web 端不支持写入本机 .cursor 目录')),
      );
      return;
    }
    final merged = await _mergedStoredForCursorExport();
    final full = McpConfigDefaults.fullMcpServersForClientExport(
      merged,
      include: widget.controller.config.isMcpIdIncludedInExport,
    );
    try {
      final path = await CursorMcpHomeWriter.writeMcpServersJson(full);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已写入 Cursor 默认配置：$path（请在 Cursor 内重载 MCP）'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e, st) {
      debugPrint('writeCursorHomeMcp: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('写入失败：$e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Map<String, String>? _initialEnvForCatalogEntry(McpCatalogEntry entry) {
    final inner = _parseEditorDocument();
    if (inner == null) return null;
    final block = inner[entry.id];
    if (block is! Map) return null;
    final envRaw = block['env'];
    if (envRaw is! Map) return null;
    return Map<String, String>.from(
      envRaw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
    );
  }

  String? _initialWrapperScriptForEntry(McpCatalogEntry entry) {
    if (entry.wrapperScriptPathFieldHint == null) return null;
    final inner = _parseEditorDocument();
    if (inner == null) return null;
    final block = inner[entry.id];
    if (block is! Map) return null;
    if (block['command']?.toString().trim() != 'bash') return null;
    final args = block['args'];
    if (args is! List || args.isEmpty) return null;
    return args.first.toString();
  }

  void _mergeCatalogEntry(
    McpCatalogEntry entry,
    Map<String, String> env, {
    String? wrapperScriptAbsolutePath,
  }) {
    final inner = _parseEditorDocument();
    if (inner == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先修正 JSON（需含合法 mcpServers）')),
      );
      return;
    }
    final next = McpConfigDefaults.deepCopyMap(inner);
    next[entry.id] = entry.buildServerBlock(
      env,
      wrapperScriptAbsolutePath: wrapperScriptAbsolutePath,
    );
    setState(() => _jsonCtrl.text = _prettyDocument(next));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已合并「${entry.displayName}」到 mcpServers.${entry.id}，请点击保存')),
    );
  }

  void _openCatalogInstallDialog(McpCatalogEntry entry) {
    showDialog<void>(
      context: context,
      builder: (ctx) => McpCatalogInstallDialog(
        entry: entry,
        initialEnv: _initialEnvForCatalogEntry(entry),
        initialWrapperScriptPath: _initialWrapperScriptForEntry(entry),
        onApply: (env, {wrapperScriptAbsolutePath}) => _mergeCatalogEntry(
          entry,
          env,
          wrapperScriptAbsolutePath: wrapperScriptAbsolutePath,
        ),
      ),
    );
  }

  /// 从 MCP 商店添加服务器到配置
  Future<void> _addServerFromStore(McpCatalogEntry entry) async {
    final c = widget.controller.config;
    final inner = McpConfigDefaults.deepCopyMap(Map<dynamic, dynamic>.from(c.mcpServers));
    
    // 使用默认环境变量值（空字符串）
    final envValues = <String, String>{};
    for (final key in entry.envTemplate.keys) {
      envValues[key] = '';
    }
    
    inner[entry.id] = entry.buildServerBlock(envValues);
    final j = c.toJson();
    j['mcpServers'] = inner;
    
    final next = ToolConfig.fromJson(j);
    try {
      await widget.controller.saveConfig(next);
      if (mounted) {
        setState(() => _reloadFromConfig());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${entry.displayName} 已添加到 MCP 配置')),
        );
      }
      // 同步到 Cursor
      final merged = await _mergedStoredForCursorExport();
      await _writeCursorHomeMcpSilent(merged);
    } catch (e, st) {
      debugPrint('addServerFromStore: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final hasWallpaper = widget.controller.config.wallpaperId.trim().isNotEmpty;
        final bodyFill = hasWallpaper ? cs.surface.withValues(alpha: 0.92) : cs.surface;
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('MCP'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_rounded, size: 20),
                  label: const Text('保存'),
                ),
              ),
            ],
          ),
          body: ColoredBox(
            color: bodyFill,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Text(
                  '当前项目：${widget.controller.activeProjectName}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 10),
                McpServicesSection(
                  controller: widget.controller,
                  onPipelineAfterBrewOrHostsChange: _pipelineAfterBrewOrHostsChange,
                  onCommitGitlabEdit: _commitGitlabDialog,
                  onSaveConfig: widget.controller.saveConfig,
                  onAfterServersChanged: () async {
                    final merged = await _mergedStoredForCursorExport();
                    await _writeCursorHomeMcpSilent(merged);
                    if (mounted) setState(() => _reloadFromConfig());
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  '「GitLab」页保存时会自动把 Token 写入本项目 `mcpServers.gitlab.env`。'
                  '上方编辑或 brew 变更后会尝试合并并写入 ~/.cursor/mcp.json（含内置 Cursor / Claude）。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: cs.primaryContainer.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: cs.primary.withValues(alpha: 0.28)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_awesome_rounded, color: cs.primary, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              '推荐配置（开箱）',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '1）在「GitLab」页保存 Token（已会自动同步到 MCP）。\n'
                          '2）在此点「写入 Cursor 默认路径」或「一键应用推荐并保存」。\n'
                          '3）在 Cursor 里重载 MCP；「复制完整 Cursor 用 JSON」含内置宿主 + GitLab。',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.42),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: _applyRecommendedAndSave,
                              icon: const Icon(Icons.bolt_rounded, size: 20),
                              label: const Text('一键应用推荐并保存'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _writeCursorHomeMcpJson,
                              icon: const Icon(Icons.folder_special_outlined),
                              label: const Text('写入 ~/.cursor/mcp.json'),
                            ),
                            OutlinedButton(
                              onPressed: _loadRecommendedToEditorOnly,
                              child: const Text('仅载入推荐到下方（不保存）'),
                            ),
                            TextButton(
                              onPressed: _resetDefault,
                              child: const Text('恢复空模板'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: false,
                      tilePadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      title: Text(
                        '进阶：注册表「安装」单条',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '工作区 JSON 默认只有 GitLab；写入 Cursor 时会自动带上 Claude Code / Cursor。'
                        '若要追加 GitHub 等其它服务，可在此合并单条。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.35,
                            ),
                      ),
                      children: [
                        Text(
                          '点「安装」只合并对应一条进下方 JSON，不会替代整份推荐配置。',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.35,
                              ),
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < kBuiltinMcpCatalog.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.35)),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(kBuiltinMcpCatalog[i].displayName),
                            subtitle: Text(
                              kBuiltinMcpCatalog[i].description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: FilledButton.tonal(
                              onPressed: () => _openCatalogInstallDialog(kBuiltinMcpCatalog[i]),
                              child: const Text('安装'),
                            ),
                            onTap: () => _openCatalogInstallDialog(kBuiltinMcpCatalog[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  title: Text(
                    '各客户端配置文件路径（保存后需客户端重载 MCP）',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  children: [
                    SelectableText(
                      'Cursor（常见）：用户目录下 .cursor/mcp.json；自带 MCP 可用 cursor mcp start（见仓库 scripts/start_cursor_mcp.sh）。\n'
                      'Claude Code：~/.claude 或项目 .claude/settings.json；自带 MCP 可用 claude mcp start（见 scripts/start_claude_code_mcp.sh）。\n'
                      '其它客户端以各自文档为准。\n\n'
                      'MCP 进程由客户端按 command/args 在本机拉起；大模型不会替你执行 shell。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _importFromFile,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('从文件导入'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _exportToFile,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('导出为文件'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _copyAll,
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('复制工作区 JSON'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _copyFullForCursor,
                      icon: const Icon(Icons.copy_all_rounded),
                      label: const Text('复制完整 Cursor 用 JSON'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _writeCursorHomeMcpJson,
                      icon: const Icon(Icons.save_alt_outlined),
                      label: const Text('写入 ~/.cursor/mcp.json'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _syncGitlabIntoGitlabMcp,
                      icon: const Icon(Icons.sync_alt_rounded),
                      label: const Text('仅同步 GitLab 页到当前 JSON'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _jsonCtrl,
                  maxLines: null,
                  minLines: 22,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.35,
                    color: cs.onSurface,
                  ),
                  decoration: InputDecoration(
                    alignLabelWithHint: true,
                    labelText: '工作区 mcpServers（JSON）',
                    hintText: '{"mcpServers": { "gitlab": { ... } }}',
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
