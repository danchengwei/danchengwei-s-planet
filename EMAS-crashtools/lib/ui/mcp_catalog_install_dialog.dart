import 'package:flutter/material.dart';

import '../models/mcp_catalog_entry.dart';

/// 从注册表「安装」：填写 env（及可选包装脚本路径）后合并到 `mcpServers`。
class McpCatalogInstallDialog extends StatefulWidget {
  const McpCatalogInstallDialog({
    super.key,
    required this.entry,
    this.initialEnv,
    this.initialWrapperScriptPath,
    required this.onApply,
  });

  final McpCatalogEntry entry;
  final Map<String, String>? initialEnv;
  final String? initialWrapperScriptPath;

  final void Function(
    Map<String, String> env, {
    String? wrapperScriptAbsolutePath,
  }) onApply;

  @override
  State<McpCatalogInstallDialog> createState() => _McpCatalogInstallDialogState();
}

class _McpCatalogInstallDialogState extends State<McpCatalogInstallDialog> {
  late final Map<String, TextEditingController> _controllers;
  TextEditingController? _scriptPathCtrl;

  @override
  void initState() {
    super.initState();
    final init = widget.initialEnv ?? {};
    _controllers = {
      for (final k in widget.entry.envTemplate.keys)
        k: TextEditingController(text: init[k] ?? ''),
    };
    final hint = widget.entry.wrapperScriptPathFieldHint;
    if (hint != null) {
      _scriptPathCtrl = TextEditingController(text: widget.initialWrapperScriptPath ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _scriptPathCtrl?.dispose();
    super.dispose();
  }

  String _launchSubtitle(McpCatalogEntry e) {
    final line1 = '启动：${e.command} ${e.args.join(' ')}';
    if (e.command == 'npx') {
      return '$line1\n版本：${e.version}（npm 由 -y 拉取）';
    }
    return line1;
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final scriptHint = e.wrapperScriptPathFieldHint;
    return AlertDialog(
      title: Text('合并到配置：${e.displayName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(e.description, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35)),
            const SizedBox(height: 8),
            Text(
              _launchSubtitle(e),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (scriptHint != null) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: false,
                title: Text(
                  '进阶：启动包装脚本（多数用户请留空）',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                children: [
                  TextField(
                    controller: _scriptPathCtrl,
                    decoration: InputDecoration(
                      labelText: '脚本绝对路径（可选）',
                      hintText: scriptHint,
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '留空则直接用上方 command；填写后改为 bash 执行该脚本。客户端拉起 MCP，非聊天里执行。',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (e.envTemplate.isEmpty && scriptHint == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '此项无预设环境变量；合并后可在下方 JSON 的 env 中按需手写。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              )
            else
              for (final k in e.envTemplate.keys) ...[
                TextField(
                  controller: _controllers[k],
                  decoration: InputDecoration(
                    labelText: k,
                    hintText: e.envTemplate[k],
                    alignLabelWithHint: true,
                  ),
                  obscureText: k.toUpperCase().contains('TOKEN') || k.toUpperCase().contains('SECRET'),
                ),
                const SizedBox(height: 10),
              ],
            Text(
              '将写入 mcpServers「${e.id}」。若已存在同名项会被覆盖。',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final env = {for (final x in _controllers.entries) x.key: x.value.text};
            final trimmed = (_scriptPathCtrl?.text ?? '').trim();
            Navigator.pop(context);
            widget.onApply(
              env,
              wrapperScriptAbsolutePath: trimmed.isEmpty ? null : trimmed,
            );
          },
          child: const Text('合并到 JSON'),
        ),
      ],
    );
  }
}
