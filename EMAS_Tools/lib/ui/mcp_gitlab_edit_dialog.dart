import 'package:flutter/material.dart';

import '../models/mcp_config_defaults.dart';

class _EnvRowControllers {
  _EnvRowControllers({String key = '', String value = ''})
      : keyCtrl = TextEditingController(text: key),
        valueCtrl = TextEditingController(text: value);

  final TextEditingController keyCtrl;
  final TextEditingController valueCtrl;

  void dispose() {
    keyCtrl.dispose();
    valueCtrl.dispose();
  }
}

/// 编辑单条 MCP（命令、参数、环境变量）；结果通过 [Navigator.pop] 返回。
class McpGitlabEditDialog extends StatefulWidget {
  const McpGitlabEditDialog({
    super.key,
    required this.initialBlock,
    this.readonlyServiceName = 'GitLab',
    this.descriptionText = '连接 GitLab API（Token 与 API 地址可在环境变量与「GitLab」页同步）',
  });

  final Map<String, dynamic> initialBlock;
  /// 只读展示的「服务名称」。
  final String readonlyServiceName;
  final String descriptionText;

  @override
  State<McpGitlabEditDialog> createState() => _McpGitlabEditDialogState();
}

Widget _readonlyBox(ColorScheme cs, {required Widget child}) {
  return DecoratedBox(
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: child,
    ),
  );
}

class _McpGitlabEditDialogState extends State<McpGitlabEditDialog> {
  late final TextEditingController _commandCtrl;
  late final TextEditingController _argsCtrl;
  final List<_EnvRowControllers> _envRows = [];

  @override
  void initState() {
    super.initState();
    final b = widget.initialBlock;
    _commandCtrl = TextEditingController(text: b['command']?.toString() ?? 'npx');
    final args = b['args'];
    final argLines = args is List ? args.map((e) => e.toString()).join('\n') : '';
    _argsCtrl = TextEditingController(text: argLines);
    final envRaw = b['env'];
    if (envRaw is Map && envRaw.isNotEmpty) {
      envRaw.forEach((k, v) {
        _envRows.add(_EnvRowControllers(key: k.toString(), value: v?.toString() ?? ''));
      });
    } else {
      final d = McpConfigDefaults.defaultGitlabServerBlock()['env'];
      if (d is Map) {
        d.forEach((k, v) {
          _envRows.add(_EnvRowControllers(key: k.toString(), value: v?.toString() ?? ''));
        });
      }
    }
  }

  @override
  void dispose() {
    _commandCtrl.dispose();
    _argsCtrl.dispose();
    for (final r in _envRows) {
      r.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _buildResult() {
    final lines = _argsCtrl.text
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final env = <String, String>{};
    for (final r in _envRows) {
      final k = r.keyCtrl.text.trim();
      if (k.isEmpty) continue;
      env[k] = r.valueCtrl.text;
    }
    final cmd = _commandCtrl.text.trim();
    return {
      'command': cmd.isEmpty ? 'npx' : cmd,
      'args': lines,
      'env': env,
    };
  }

  void _addEnvRow() {
    setState(() => _envRows.add(_EnvRowControllers()));
  }

  void _removeEnvRow(int index) {
    setState(() {
      _envRows[index].dispose();
      _envRows.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('编辑 MCP 服务'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('服务名称', style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              _readonlyBox(
                cs,
                child: Text(widget.readonlyServiceName, style: t.bodyLarge),
              ),
              const SizedBox(height: 12),
              Text('描述', style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              _readonlyBox(
                cs,
                child: Text(
                  widget.descriptionText,
                  style: t.bodySmall?.copyWith(height: 1.35),
                ),
              ),
              const SizedBox(height: 12),
              Text('传输类型', style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              _readonlyBox(
                cs,
                child: Text('标准输入输出 (stdio)', style: t.bodyLarge),
              ),
              const SizedBox(height: 12),
              Text('命令', style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              TextField(
                controller: _commandCtrl,
                decoration: InputDecoration(
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              Text('参数（每行一项）', style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              TextField(
                controller: _argsCtrl,
                minLines: 3,
                maxLines: 8,
                style: t.bodyMedium?.copyWith(fontFamily: 'monospace', fontSize: 12),
                decoration: InputDecoration(
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  hintText: '-y\n@modelcontextprotocol/server-gitlab',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('环境变量', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addEnvRow,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('添加'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (var i = 0; i < _envRows.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _envRows[i].keyCtrl,
                        decoration: InputDecoration(
                          labelText: '键',
                          filled: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _envRows[i].valueCtrl,
                        decoration: InputDecoration(
                          labelText: '值',
                          filled: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '删除',
                      onPressed: () => _removeEnvRow(i),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _buildResult()),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
