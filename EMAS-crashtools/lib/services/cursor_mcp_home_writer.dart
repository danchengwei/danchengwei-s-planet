import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 将 `mcpServers` 写入 Cursor 默认路径（本机用户目录下 `.cursor/mcp.json`）。
///
/// 会覆盖同名文件；写入前会创建 `.cursor` 目录。非 Web 桌面端可用。
class CursorMcpHomeWriter {
  CursorMcpHomeWriter._();

  static Future<String> writeMcpServersJson(Map<String, dynamic> mcpServers) async {
    final doc = const JsonEncoder.withIndent('  ').convert({'mcpServers': mcpServers});
    final home = _homeDir();
    if (home == null || home.isEmpty) {
      throw StateError('未找到用户主目录（HOME / USERPROFILE）');
    }
    final dir = Directory(p.join(home, '.cursor'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final f = File(p.join(dir.path, 'mcp.json'));
    await f.writeAsString(doc);
    return f.path;
  }

  static String? _homeDir() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'];
    }
    return Platform.environment['HOME'];
  }
}
