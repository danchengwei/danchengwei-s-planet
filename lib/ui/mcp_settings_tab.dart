import 'package:flutter/material.dart';

import '../app_controller.dart';

/// MCP 设置标签页
class McpSettingsTab extends StatelessWidget {
  const McpSettingsTab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hub_outlined, size: 64, color: cs.primary),
            const SizedBox(height: 16),
            const Text(
              'MCP 配置',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '暂无 MCP 配置\n敬请期待',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
