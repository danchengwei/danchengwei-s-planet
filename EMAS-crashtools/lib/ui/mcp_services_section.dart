import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../data/mcp_builtin_registry.dart';
import '../models/mcp_config_defaults.dart';
import '../models/tool_config.dart';
import '../services/mcp_brew_gitlab_service.dart';
import '../services/mcp_local_cli_probe.dart';
import 'mcp_gitlab_edit_dialog.dart';

String _mcpDisplayTitle(String id) {
  for (final e in kBuiltinMcpCatalog) {
    if (e.id == id) {
      final s = e.displayName;
      final i = s.indexOf('（');
      return i < 0 ? s : s.substring(0, i).trim();
    }
  }
  return id;
}

String _mcpDescription(String id) {
  for (final e in kBuiltinMcpCatalog) {
    if (e.id == id) return e.description;
  }
  return '自定义 MCP 服务';
}

/// MCP 列表：内置 Cursor / Claude 紧凑检测；GitLab 展示安装卡片；支持自定义 MCP
class McpServicesSection extends StatefulWidget {
  const McpServicesSection({
    super.key,
    required this.controller,
    required this.onPipelineAfterBrewOrHostsChange,
    required this.onCommitGitlabEdit,
    required this.onSaveConfig,
    required this.onAfterServersChanged,
  });

  final AppController controller;
  final Future<void> Function() onPipelineAfterBrewOrHostsChange;
  final Future<void> Function(Map<String, dynamic> gitlabBlock) onCommitGitlabEdit;
  final Future<void> Function(ToolConfig next) onSaveConfig;
  final Future<void> Function() onAfterServersChanged;

  @override
  State<McpServicesSection> createState() => _McpServicesSectionState();
}

class _McpServicesSectionState extends State<McpServicesSection> {
  bool? _cursorOk;
  bool? _claudeOk;
  bool? _gitlabFormulaOk;
  /// brew 已装 formula 或本机有 npx。
  bool? _gitlabRuntimeReady;
  bool _installBusy = false;
  bool _uninstallBusy = false;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    if (kIsWeb) {
      if (!mounted) return;
      setState(() {
        _cursorOk = null;
        _claudeOk = null;
        _gitlabFormulaOk = false;
        _gitlabRuntimeReady = false;
      });
      return;
    }
    final cursor = McpLocalCliProbe.isCursorCliOnPath();
    final claude = McpLocalCliProbe.isClaudeCliOnPath();
    final gl = McpBrewGitlabService.platformMayUseBrew ? McpBrewGitlabService.isFormulaInstalled() : Future.value(false);
    final npx = McpBrewGitlabService.hasNpx();
    final r = await Future.wait<Object>([cursor, claude, gl, npx]);
    if (!mounted) return;
    final formulaOk = r[2] as bool;
    final npxOk = r[3] as bool;
    setState(() {
      _cursorOk = r[0] as bool;
      _claudeOk = r[1] as bool;
      _gitlabFormulaOk = formulaOk;
      _gitlabRuntimeReady = formulaOk || npxOk;
    });
  }

  Future<void> _openUrl(String url) async {
    final u = Uri.parse(url);
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _setExportInclude(String id, bool value) async {
    final c = widget.controller.config;
    final inc = Map<String, bool>.from(c.mcpExportIncludeById);
    if (value) {
      inc.remove(id);
    } else {
      inc[id] = false;
    }
    final j = c.toJson();
    j['mcpExportIncludeById'] = inc;
    await widget.onSaveConfig(ToolConfig.fromJson(j));
    await widget.onAfterServersChanged();
  }

  Future<void> _deleteServer(String id) async {
    final c = widget.controller.config;
    final inner = McpConfigDefaults.deepCopyMap(Map<dynamic, dynamic>.from(c.mcpServers));
    inner.remove(id);
    final inc = Map<String, bool>.from(c.mcpExportIncludeById);
    inc.remove(id);
    final j = c.toJson();
    j['mcpServers'] = inner;
    j['mcpExportIncludeById'] = inc;
    if (id == 'gitlab') j['mcpGitlabInstallAck'] = false;
    await widget.onSaveConfig(ToolConfig.fromJson(j));
    await widget.onAfterServersChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已删除「$id」')));
  }

  /// 环境已就绪时仅写入模板并合并 Token / 写 Cursor。
  Future<void> _addGitlabTemplateAckAndPipeline() async {
    final c = widget.controller.config;
    final inner = McpConfigDefaults.deepCopyMap(Map<dynamic, dynamic>.from(c.mcpServers));
    inner['gitlab'] = McpConfigDefaults.deepCopyMap(
      Map<dynamic, dynamic>.from(McpConfigDefaults.defaultGitlabServerBlock()),
    );
    final j = c.toJson();
    j['mcpServers'] = inner;
    j['mcpGitlabInstallAck'] = true;
    await widget.onSaveConfig(ToolConfig.fromJson(j));
    await widget.onPipelineAfterBrewOrHostsChange();
    await _probe();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已添加到项目并同步配置')),
    );
  }

  /// 未配置 GitLab 时的入口：环境已就绪则只加模板；否则自动执行安装（brew / npm / npx）。
  Future<void> _onGitLabMarketCardTap() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Web 端无法在本机执行安装')),
      );
      return;
    }
    if (_gitlabRuntimeReady == true) {
      await _addGitlabTemplateAckAndPipeline();
      return;
    }
    await _runGitlabUnifiedInstall();
  }

  /// 自动尝试安装并写入项目（无 brew/npx 分步提示）。
  Future<void> _runGitlabUnifiedInstall() async {
    if (kIsWeb || !mounted) return;
    setState(() => _installBusy = true);
    try {
      final o = await McpBrewGitlabService.installGitlabMcpUnified();
      if (!mounted) return;
      if (!o.ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(o.message)));
        return;
      }
      final c = widget.controller.config;
      final inner = McpConfigDefaults.deepCopyMap(Map<dynamic, dynamic>.from(c.mcpServers));
      if (!inner.containsKey('gitlab') || inner['gitlab'] is! Map) {
        inner['gitlab'] = McpConfigDefaults.deepCopyMap(
          Map<dynamic, dynamic>.from(McpConfigDefaults.defaultGitlabServerBlock()),
        );
      }
      final j = c.toJson();
      j['mcpServers'] = inner;
      j['mcpGitlabInstallAck'] = true;
      await widget.onSaveConfig(ToolConfig.fromJson(j));
      await widget.onPipelineAfterBrewOrHostsChange();
      await _probe();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(o.message)));
    } finally {
      if (mounted) setState(() => _installBusy = false);
    }
  }

  Future<void> _confirmDelete(String id, String title) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除 MCP 服务'),
        content: Text('确定从工作区移除「$title」吗？可稍后再添加模板。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (go == true && mounted) await _deleteServer(id);
  }

  Future<void> _openEditServer(String id, Map<String, dynamic> block) async {
    final title = _mcpDisplayTitle(id);
    final desc = _mcpDescription(id);
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => McpGitlabEditDialog(
        initialBlock: McpConfigDefaults.deepCopyMap(Map<dynamic, dynamic>.from(block)),
        readonlyServiceName: title,
        descriptionText: desc,
      ),
    );
    if (result == null || !mounted) return;
    if (id == 'gitlab') {
      await widget.onCommitGitlabEdit(result);
      return;
    }
    final c = widget.controller.config;
    final inner = McpConfigDefaults.deepCopyMap(Map<dynamic, dynamic>.from(c.mcpServers));
    inner[id] = result;
    final j = c.toJson();
    j['mcpServers'] = inner;
    await widget.onSaveConfig(ToolConfig.fromJson(j));
    await widget.onAfterServersChanged();
  }

  Future<void> _uninstallGitlabMcp() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('卸载 GitLab MCP'),
        content: const Text('将执行：brew uninstall --zap gitlab-mcp'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _uninstallBusy = true);
    final res = await McpBrewGitlabService.uninstallZap();
    if (!mounted) return;
    setState(() => _uninstallBusy = false);
    if (res.exitCode != 0) {
      final err = utf8.decode(res.stderr as List<int>);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('卸载失败：$err')));
      return;
    }
    await _probe();
    if (!mounted) return;
    await widget.onPipelineAfterBrewOrHostsChange();
  }

  /// 打开自定义 MCP 对话框
  Future<void> _openAddCustomMcp() async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => const _AddCustomMcpDialog(),
    );
    if (result == null || !mounted) return;

    final c = widget.controller.config;
    final inner = McpConfigDefaults.deepCopyMap(Map<dynamic, dynamic>.from(c.mcpServers));
    final id = result['id'] as String;
    inner[id] = result['block'];
    final j = c.toJson();
    j['mcpServers'] = inner;
    await widget.onSaveConfig(ToolConfig.fromJson(j));
    await widget.onAfterServersChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已添加自定义 MCP「$id」')),
    );
  }

  bool _gitlabEditable(ToolConfig c) =>
      c.mcpGitlabInstallAck || _gitlabRuntimeReady == true || _gitlabFormulaOk == true;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final c = widget.controller.config;
        final cs = Theme.of(context).colorScheme;
        final t = Theme.of(context).textTheme;
        final ids = c.mcpServers.keys.map((e) => e.toString()).toList()..sort();

        // 检查 GitLab 是否已配置
        final hasGitlabConfigured = ids.contains('gitlab');

        return Card(
          elevation: 0,
          color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.hub_outlined, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('MCP 服务', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                      tooltip: '重新检测',
                      onPressed: _installBusy || _uninstallBusy ? null : _probe,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '内置项仅做本机 CLI 检测，占位较小；开关表示是否写入导出的 mcp.json。'
                  '其它服务需先在本机安装，确认后才可编辑参数并同步 JSON；实际 MCP 进程由 Cursor / Claude 在会话中拉起。',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.38),
                ),
                const SizedBox(height: 14),
                Text(
                  '内置 MCP',
                  style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, cons) {
                    final wide = cons.maxWidth > 520;
                    final cursorTile = _BuiltinCompactTile(
                      title: 'Cursor',
                      commandHint: 'cursor mcp start',
                      cliOk: _cursorOk,
                      exportOn: c.isMcpIdIncludedInExport('cursor'),
                      onExportChanged: (v) => _setExportInclude('cursor', v),
                      onInstallTap: () => _openUrl('https://cursor.com'),
                    );
                    final claudeTile = _BuiltinCompactTile(
                      title: 'Claude Code',
                      commandHint: 'claude mcp start',
                      cliOk: _claudeOk,
                      exportOn: c.isMcpIdIncludedInExport('claude-code'),
                      onExportChanged: (v) => _setExportInclude('claude-code', v),
                      onInstallTap: () => _openUrl('https://code.claude.com/docs'),
                    );
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: cursorTile),
                          const SizedBox(width: 10),
                          Expanded(child: claudeTile),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        cursorTile,
                        const SizedBox(height: 8),
                        claudeTile,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      '可安装服务',
                      style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // GitLab 安装卡片（类似图二样式）
                if (!hasGitlabConfigured)
                  _GitLabInstallCard(
                    onPrimary: _onGitLabMarketCardTap,
                    busy: _installBusy,
                    runtimeReady: _gitlabRuntimeReady == true,
                  )
                else
                  _TavilyStyleMcpCard(
                    serverId: 'gitlab',
                    title: _mcpDisplayTitle('gitlab'),
                    description: _mcpDescription('gitlab'),
                    block: c.mcpServers['gitlab'] is Map
                        ? Map<String, dynamic>.from(c.mcpServers['gitlab'] as Map)
                        : <String, dynamic>{},
                    locked: !_gitlabEditable(c),
                    envReadyBadge: _gitlabRuntimeReady == true,
                    exportOn: c.isMcpIdIncludedInExport('gitlab'),
                    onExportChanged: (v) => _setExportInclude('gitlab', v),
                    onEdit: c.mcpServers['gitlab'] is Map
                        ? () => _openEditServer(
                              'gitlab',
                              Map<String, dynamic>.from(c.mcpServers['gitlab'] as Map),
                            )
                        : null,
                    onDelete: () => _confirmDelete('gitlab', _mcpDisplayTitle('gitlab')),
                    onInstallWhenLocked: !kIsWeb ? _runGitlabUnifiedInstall : null,
                    installBusy: _installBusy,
                    onBrewUninstall: _gitlabFormulaOk == true && !kIsWeb ? _uninstallGitlabMcp : null,
                    brewUninstallBusy: _uninstallBusy,
                  ),
                // 已配置的其他 MCP 服务
                for (var i = 0; i < ids.length; i++) ...[
                  if (ids[i] != 'gitlab') ...[
                    const SizedBox(height: 10),
                    _TavilyStyleMcpCard(
                      serverId: ids[i],
                      title: _mcpDisplayTitle(ids[i]),
                      description: _mcpDescription(ids[i]),
                      block: c.mcpServers[ids[i]] is Map
                          ? Map<String, dynamic>.from(c.mcpServers[ids[i]] as Map)
                          : <String, dynamic>{},
                      locked: false,
                      exportOn: c.isMcpIdIncludedInExport(ids[i]),
                      onExportChanged: (v) => _setExportInclude(ids[i], v),
                      onEdit: c.mcpServers[ids[i]] is Map
                          ? () => _openEditServer(
                                ids[i],
                                Map<String, dynamic>.from(c.mcpServers[ids[i]] as Map),
                              )
                          : null,
                      onDelete: () => _confirmDelete(ids[i], _mcpDisplayTitle(ids[i])),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                // 自定义 MCP 按钮
                OutlinedButton.icon(
                  onPressed: _openAddCustomMcp,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('添加自定义 MCP'),
                ),
                if (kIsWeb)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Web 版无法检测 CLI 或执行 brew。',
                      style: t.labelSmall?.copyWith(color: cs.outline),
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

/// GitLab 未加入项目时的卡片：一键安装或（环境已就绪时）添加到项目。
class _GitLabInstallCard extends StatelessWidget {
  const _GitLabInstallCard({
    required this.onPrimary,
    required this.busy,
    required this.runtimeReady,
  });

  final VoidCallback onPrimary;
  final bool busy;
  final bool runtimeReady;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.code_rounded,
                    size: 20,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'GitLab',
                            style: t.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          if (runtimeReady) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2E7D32).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '已就绪',
                                style: t.labelSmall?.copyWith(
                                  color: const Color(0xFF2E7D32),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        runtimeReady
                            ? '本机运行环境已就绪，可将 GitLab MCP 加入当前项目。'
                            : '点击后将自动尝试安装（无需选择安装方式）；完成后可编辑并同步配置。',
                        style: t.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                          fontSize: 12,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: busy ? null : onPrimary,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(runtimeReady ? '添加' : '安装'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'stdio',
                    style: t.labelSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'npx -y @modelcontextprotocol/server-gitlab',
                    style: t.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '2 个键',
                  style: t.labelSmall?.copyWith(
                    color: cs.tertiary,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 内置 MCP 紧凑卡片（Cursor / Claude）
class _BuiltinCompactTile extends StatelessWidget {
  const _BuiltinCompactTile({
    required this.title,
    required this.commandHint,
    required this.cliOk,
    required this.exportOn,
    required this.onExportChanged,
    required this.onInstallTap,
  });

  final String title;
  final String commandHint;
  final bool? cliOk;
  final bool exportOn;
  final ValueChanged<bool> onExportChanged;
  final VoidCallback onInstallTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final detected = kIsWeb ? null : cliOk;
    final statusColor = detected == null
        ? cs.outline
        : (detected ? const Color(0xFF43A047) : cs.error);
    final statusText = kIsWeb
        ? 'Web 不检测'
        : (detected == null ? '检测中…' : (detected ? '已检测到 CLI' : '未检测到'));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.power_rounded, size: 16, color: cs.primary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    'stdio · $commandHint',
                    style: t.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 5, top: 4),
                        decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                      ),
                      Expanded(
                        child: Text(
                          statusText,
                          style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 0.82,
                  child: Switch.adaptive(
                    value: exportOn,
                    onChanged: (v) => onExportChanged(v),
                  ),
                ),
                if (!kIsWeb && cliOk != true)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: onInstallTap,
                    child: Text('安装', style: t.labelSmall),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// MCP 服务卡片（已安装状态）
class _TavilyStyleMcpCard extends StatelessWidget {
  const _TavilyStyleMcpCard({
    required this.serverId,
    required this.title,
    required this.description,
    required this.block,
    required this.locked,
    this.envReadyBadge = false,
    required this.exportOn,
    required this.onExportChanged,
    required this.onEdit,
    required this.onDelete,
    this.onInstallWhenLocked,
    this.installBusy = false,
    this.onBrewUninstall,
    this.brewUninstallBusy = false,
  });

  final String serverId;
  final String title;
  final String description;
  final Map<String, dynamic> block;
  final bool locked;
  final bool envReadyBadge;
  final bool exportOn;
  final ValueChanged<bool> onExportChanged;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onInstallWhenLocked;
  final bool installBusy;
  final VoidCallback? onBrewUninstall;
  final bool brewUninstallBusy;

  static String _commandOneLiner(Map<String, dynamic> b) {
    final cmd = b['command']?.toString() ?? '';
    final args = b['args'];
    final a = args is List ? args.map((e) => e.toString()).join(' ') : '';
    if (cmd.isEmpty) return '未配置命令';
    return a.isEmpty ? cmd : '$cmd $a';
  }

  static int _envCount(Map<String, dynamic> b) {
    final env = b['env'];
    if (env is! Map) return 0;
    return env.keys.length;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final cmdLine = _commandOneLiner(block);
    final nKeys = _envCount(block);
    final accentKeys = cs.tertiary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    serverId == 'gitlab' ? Icons.code_rounded : Icons.extension_rounded,
                    size: 22,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: '编辑',
                  onPressed: locked || onEdit == null ? null : onEdit,
                  icon: Icon(Icons.edit_outlined, size: 20, color: locked ? cs.outline : cs.onSurface),
                ),
                IconButton(
                  tooltip: '删除',
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: cs.error.withValues(alpha: 0.9)),
                ),
                Switch.adaptive(
                  value: exportOn,
                  onChanged: onExportChanged,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (envReadyBadge && serverId == 'gitlab' && !locked) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: const Color(0xFF43A047)),
                  const SizedBox(width: 6),
                  Text(
                    '本机运行环境已就绪',
                    style: t.labelSmall?.copyWith(
                      color: const Color(0xFF43A047),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            if (locked) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '请先完成本机安装后再编辑参数（将自动尝试可用方式，无需选择 brew / npx）。',
                      style: t.labelSmall?.copyWith(color: cs.onPrimaryContainer, height: 1.35),
                    ),
                    const SizedBox(height: 10),
                    if (onInstallWhenLocked != null)
                      FilledButton.icon(
                        onPressed: installBusy ? null : onInstallWhenLocked,
                        icon: installBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download_rounded, size: 20),
                        label: const Text('安装'),
                      ),
                    if (onBrewUninstall != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: brewUninstallBusy ? null : onBrewUninstall,
                          child: brewUninstallBusy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('卸载 Homebrew 版'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'stdio',
                    style: t.labelSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(' · ', style: t.bodySmall?.copyWith(color: cs.outline)),
                Expanded(
                  child: Text(
                    cmdLine,
                    style: t.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$nKeys 个键',
                  style: t.labelSmall?.copyWith(
                    color: accentKeys,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 添加自定义 MCP 对话框
class _AddCustomMcpDialog extends StatefulWidget {
  const _AddCustomMcpDialog();

  @override
  State<_AddCustomMcpDialog> createState() => _AddCustomMcpDialogState();
}

class _AddCustomMcpDialogState extends State<_AddCustomMcpDialog> {
  final _idCtrl = TextEditingController();
  final _commandCtrl = TextEditingController();
  final _argsCtrl = TextEditingController();
  final _envCtrl = TextEditingController();

  @override
  void dispose() {
    _idCtrl.dispose();
    _commandCtrl.dispose();
    _argsCtrl.dispose();
    _envCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _buildResult() {
    final id = _idCtrl.text.trim();
    final command = _commandCtrl.text.trim();
    if (id.isEmpty || command.isEmpty) return null;

    final args = _argsCtrl.text
        .split(' ')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final env = <String, String>{};
    final envLines = _envCtrl.text.split('\n');
    for (final line in envLines) {
      final parts = line.split('=');
      if (parts.length >= 2) {
        env[parts[0].trim()] = parts.sublist(1).join('=').trim();
      }
    }

    return {
      'id': id,
      'block': <String, dynamic>{
        'command': command,
        'args': args,
        'env': env,
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加自定义 MCP'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _idCtrl,
              decoration: const InputDecoration(
                labelText: '服务 ID',
                hintText: '如：my-custom-mcp',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commandCtrl,
              decoration: const InputDecoration(
                labelText: '命令',
                hintText: '如：npx、node、python',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _argsCtrl,
              decoration: const InputDecoration(
                labelText: '参数（空格分隔）',
                hintText: '如：-y @modelcontextprotocol/server-xxx',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _envCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '环境变量（可选）',
                hintText: '每行一个，格式：KEY=value\n如：API_KEY=your_key',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final result = _buildResult();
            if (result != null) {
              Navigator.pop(context, result);
            }
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}
