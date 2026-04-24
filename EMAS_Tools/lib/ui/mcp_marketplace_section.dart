import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/mcp_brew_gitlab_service.dart';
import '../services/mcp_local_cli_probe.dart';

/// 本地 MCP「商店」：检测 Cursor / Claude Code CLI；GitLab MCP 通过 Homebrew 安装/卸载（可选）。
class McpMarketplaceSection extends StatefulWidget {
  const McpMarketplaceSection({
    super.key,
    required this.onPipelineAfterBrewOrHostsChange,
  });

  /// 安装/卸载 gitlab-mcp 或需重算配置时：合并 mcpServers、保存项目、写入 ~/.cursor/mcp.json。
  final Future<void> Function() onPipelineAfterBrewOrHostsChange;

  @override
  State<McpMarketplaceSection> createState() => _McpMarketplaceSectionState();
}

class _McpMarketplaceSectionState extends State<McpMarketplaceSection> {
  bool? _cursorOk;
  bool? _claudeOk;
  bool? _brewOk;
  bool? _gitlabFormulaOk;
  bool _installBusy = false;
  bool _uninstallBusy = false;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    if (kIsWeb) {
      setState(() {
        _cursorOk = null;
        _claudeOk = null;
        _brewOk = false;
        _gitlabFormulaOk = false;
      });
      return;
    }
    final cursor = McpLocalCliProbe.isCursorCliOnPath();
    final claude = McpLocalCliProbe.isClaudeCliOnPath();
    final brew = McpBrewGitlabService.platformMayUseBrew ? McpBrewGitlabService.hasBrew() : Future.value(false);
    final gl = McpBrewGitlabService.platformMayUseBrew ? McpBrewGitlabService.isFormulaInstalled() : Future.value(false);
    final r = await Future.wait<Object>([cursor, claude, brew, gl]);
    if (!mounted) return;
    setState(() {
      _cursorOk = r[0] as bool;
      _claudeOk = r[1] as bool;
      _brewOk = r[2] as bool;
      _gitlabFormulaOk = r[3] as bool;
    });
  }

  Future<void> _openUrl(String url) async {
    final u = Uri.parse(url);
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _installGitlabMcp() async {
    if (_brewOk != true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未检测到 Homebrew，请先安装 brew 或使用下方 JSON 的 npx 方案')),
      );
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('安装 GitLab MCP'),
        content: const Text(
          '将在本机执行：brew install gitlab-mcp\n\n'
          '若提示找不到 formula，说明官方 Homebrew 暂无此包，请改用下方 JSON 中的 npx（@modelcontextprotocol/server-gitlab），或自行添加第三方 tap。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('开始安装')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _installBusy = true);
    final res = await McpBrewGitlabService.install();
    if (!mounted) return;
    setState(() => _installBusy = false);
    if (res.exitCode != 0) {
      final err = utf8.decode(res.stderr as List<int>);
      final out = utf8.decode(res.stdout as List<int>);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('brew install 失败'),
          content: SingleChildScrollView(
            child: SelectableText(
              err.isNotEmpty ? err : out,
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
        ),
      );
      return;
    }
    await _probe();
    if (!mounted) return;
    await widget.onPipelineAfterBrewOrHostsChange();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已安装 gitlab-mcp，并已更新项目 MCP 与 ~/.cursor/mcp.json'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _uninstallGitlabMcp() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('卸载 GitLab MCP'),
        content: const Text(
          '将执行：brew uninstall --zap gitlab-mcp\n\n'
          '--zap 会尽量清理关联数据，请确认后再继续。卸载后 GitLab 项将改回 npx 官方包写法。',
        ),
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已卸载，MCP 已切回 npx 方案并写回 Cursor 配置')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final noHost = !kIsWeb &&
        _cursorOk == false &&
        _claudeOk == false &&
        _cursorOk != null &&
        _claudeOk != null;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
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
                Icon(Icons.storefront_outlined, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '本地 MCP（模型在 Cursor / Claude Code 里调用）',
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
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
              'Cursor / Claude Code 自带 MCP 进程；GitLab 为独立 MCP 服务。'
              '装好后本工具会合并 mcp.json 并可选写入 Cursor 默认路径。',
              style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.38),
            ),
            if (noHost) ...[
              const SizedBox(height: 10),
              Material(
                color: cs.errorContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '未检测到 Cursor CLI 与 Claude CLI，请至少安装其一，否则无法在对应客户端里使用自带 MCP。',
                          style: t.bodySmall?.copyWith(color: cs.onErrorContainer, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, c) {
                final cross = c.maxWidth > 520 ? 2 : 1;
                return GridView.count(
                  crossAxisCount: cross,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: cross == 2 ? 1.15 : 1.35,
                  children: [
                    _McpProductCard(
                      title: 'Cursor',
                      subtitle: '自带 MCP · stdio',
                      techLine: 'cursor mcp start',
                      installed: _cursorOk == true,
                      busy: false,
                      primaryLabel: _cursorOk == true ? '已安装' : '去安装',
                      onPrimary: _cursorOk == true
                          ? null
                          : () => _openUrl('https://cursor.com'),
                    ),
                    _McpProductCard(
                      title: 'Claude Code',
                      subtitle: '自带 MCP · stdio',
                      techLine: 'claude mcp start',
                      installed: _claudeOk == true,
                      busy: false,
                      primaryLabel: _claudeOk == true ? '已安装' : '去安装',
                      onPrimary: _claudeOk == true
                          ? null
                          : () => _openUrl('https://code.claude.com/docs'),
                    ),
                    _McpProductCard(
                      title: 'GitLab MCP',
                      subtitle: _brewOk == true ? 'Homebrew · stdio' : 'brew / npx',
                      techLine: _brewOk == true
                          ? 'brew install gitlab-mcp'
                          : 'npx @modelcontextprotocol/server-gitlab',
                      installed: _gitlabFormulaOk == true,
                      busy: _installBusy || _uninstallBusy,
                      primaryLabel: _gitlabFormulaOk == true
                          ? '已安装'
                          : (McpBrewGitlabService.platformMayUseBrew ? '安装' : '用 npx（见 JSON）'),
                      onPrimary: _gitlabFormulaOk == true || kIsWeb
                          ? null
                          : () async {
                              if (!McpBrewGitlabService.platformMayUseBrew) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('当前系统请用下方 JSON 中的 npx 官方 GitLab MCP'),
                                  ),
                                );
                                return;
                              }
                              await _installGitlabMcp();
                            },
                      secondaryLabel: _gitlabFormulaOk == true && McpBrewGitlabService.platformMayUseBrew ? '卸载' : null,
                      onSecondary: _gitlabFormulaOk == true && !_uninstallBusy && !_installBusy ? _uninstallGitlabMcp : null,
                    ),
                  ],
                );
              },
            ),
            if (kIsWeb)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Web 版无法检测本机 CLI 或执行 brew；请使用桌面版完成安装与写入 mcp.json。',
                  style: t.labelSmall?.copyWith(color: cs.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _McpProductCard extends StatelessWidget {
  const _McpProductCard({
    required this.title,
    required this.subtitle,
    required this.techLine,
    required this.installed,
    required this.busy,
    required this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String subtitle;
  final String techLine;
  final bool installed;
  final bool busy;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(subtitle, style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                techLine,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall?.copyWith(fontFamily: 'monospace', fontSize: 11, height: 1.3),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : onPrimary,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: installed ? cs.surfaceContainerHighest : null,
                      foregroundColor: installed ? cs.onSurfaceVariant : null,
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(primaryLabel),
                  ),
                ),
                if (secondaryLabel != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: busy ? null : onSecondary,
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: Text(secondaryLabel!),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
