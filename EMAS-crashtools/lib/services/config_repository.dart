import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/projects_workspace.dart';
import 'workspace_cipher.dart';

/// 多项目工作区：`crash-tools-workspace.json`。
/// 非 Web 平台写入 **AES-256-CBC 加密**（密钥文件 `.crash-tools-workspace.key` 在同目录）；仍可读取旧版明文以自动迁移。
/// 若仅有旧版 `crash-tools-config.json`，首次启动会迁移并备份为 `.migrated.bak`。
class ConfigRepository {
  static const _workspaceFileName = 'crash-tools-workspace.json';
  static const _legacyFileName = 'crash-tools-config.json';

  Future<Directory> _supportDir() async => getApplicationSupportDirectory();

  Future<File> _workspaceFile() async {
    final dir = await _supportDir();
    return File(p.join(dir.path, _workspaceFileName));
  }

  Future<File> _legacyFile() async {
    final dir = await _supportDir();
    return File(p.join(dir.path, _legacyFileName));
  }

  Future<Map<String, dynamic>?> _decodeWorkspaceFileText(String text) async {
    try {
      if (WorkspaceCipher.looksEncrypted(text)) {
        final jsonText = await WorkspaceCipher.openUtf8(text);
        final decoded = jsonDecode(jsonText);
        return decoded is Map<String, dynamic> ? decoded : null;
      }
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e, st) {
      debugPrint('decode workspace: $e\n$st');
      return null;
    }
  }

  Future<ProjectsWorkspace> loadWorkspace() async {
    try {
      final wf = await _workspaceFile();
      if (await wf.exists()) {
        final text = await wf.readAsString();
        final encrypted = WorkspaceCipher.looksEncrypted(text);
        final decoded = await _decodeWorkspaceFileText(text);
        if (decoded != null) {
          final ws = ProjectsWorkspace.fromJson(decoded);
          ws.ensureValidActive();
          return ws;
        }
        if (encrypted) {
          throw StateError('工作区已加密，解密失败（密钥丢失、文件损坏或本机安全存储不可用）。');
        }
      }

      final lf = await _legacyFile();
      if (await lf.exists()) {
        final text = await lf.readAsString();
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          if (decoded['projects'] is List) {
            final ws = ProjectsWorkspace.fromJson(decoded);
            ws.ensureValidActive();
            await saveWorkspace(ws);
            try {
              await lf.rename('${lf.path}.migrated.bak');
            } catch (_) {}
            return ws;
          }
          final ws = ProjectsWorkspace.fromLegacyFlatConfig(decoded);
          ws.ensureValidActive();
          await saveWorkspace(ws);
          try {
            await lf.rename('${lf.path}.migrated.bak');
          } catch (_) {}
          return ws;
        }
      }
    } catch (e, st) {
      debugPrint('loadWorkspace: $e\n$st');
    }
    final empty = ProjectsWorkspace.empty();
    empty.ensureValidActive();
    return empty;
  }

  Future<void> saveWorkspace(ProjectsWorkspace w) async {
    final f = await _workspaceFile();
    await f.parent.create(recursive: true);
    const enc = JsonEncoder.withIndent('  ');
    final json = enc.convert(w.toJson());
    late final String payload;
    if (kIsWeb) {
      payload = json;
    } else {
      try {
        payload = await WorkspaceCipher.sealUtf8(json);
      } catch (e, st) {
        debugPrint('工作区加密失败，回退明文写入（请检查 macOS Keychain 权限）: $e\n$st');
        payload = json;
      }
    }
    await f.writeAsString(payload);
    await _restrictFileToOwnerOnly(f);
  }

  /// 降低本机其他用户读取密钥配置的风险（Windows 依赖目录 ACL，跳过 chmod）。
  static Future<void> _restrictFileToOwnerOnly(File f) async {
    if (kIsWeb || Platform.isWindows) return;
    try {
      final r = await Process.run('chmod', ['600', f.path]);
      if (r.exitCode != 0) {
        debugPrint('chmod 600 failed: ${r.stderr}');
      }
    } catch (e, st) {
      debugPrint('restrict config file mode: $e\n$st');
    }
  }
}
