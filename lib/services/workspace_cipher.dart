import 'dart:convert';
import 'dart:io';

import 'package:encrypt/encrypt.dart';
import 'package:flutter/foundation.dart' hide Key;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 工作区 JSON 的本地加密：AES-256-CBC + PKCS7。
///
/// 数据密钥保存在应用支持目录下的 **`.crash-tools-workspace.key`**（非 Keychain，避免 iOS/macOS
/// 未配置 Keychain Sharing / 沙盒 entitlement 时出现 **-34018** 导致无法启动）。
/// Unix 系尽量 `chmod 600` 缩小同机其他用户可读范围。
///
/// 磁盘格式：首行魔数 + Base64(IV(16) || 密文)。
abstract final class WorkspaceCipher {
  static const String magicPrefix = 'CRASHTOOLS_WS_V1\n';

  /// 单元测试环境使用固定密钥；勿用于正式构建。
  static const String _testOnlyKeyUtf8 = '01234567890123456789012345678901';

  static const String _fileKeyName = '.crash-tools-workspace.key';

  static bool get _isFlutterTest =>
      !kIsWeb && (Platform.environment['FLUTTER_TEST'] == 'true');

  static Future<Key> _loadOrCreateAesKey() async {
    if (kIsWeb) {
      throw UnsupportedError('工作区加密在当前 Web 构建中不可用');
    }
    if (_isFlutterTest) {
      return Key.fromUtf8(_testOnlyKeyUtf8);
    }

    final dir = await getApplicationSupportDirectory();
    final keyFile = File(p.join(dir.path, _fileKeyName));
    if (await keyFile.exists()) {
      final fb64 = (await keyFile.readAsString()).trim();
      if (fb64.isNotEmpty) {
        return Key.fromBase64(fb64);
      }
    }

    final key = Key.fromSecureRandom(32);
    await keyFile.parent.create(recursive: true);
    await keyFile.writeAsString(key.base64);
    if (!kIsWeb && !Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', keyFile.path]);
      } catch (_) {}
    }
    return key;
  }

  static bool looksEncrypted(String fileContent) {
    return fileContent.trimLeft().startsWith('CRASHTOOLS_WS_V1');
  }

  /// 将 UTF-8 JSON 明文封装为可写入磁盘的文本。
  static Future<String> sealUtf8(String plainUtf8) async {
    final key = await _loadOrCreateAesKey();
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final encrypted = encrypter.encrypt(plainUtf8, iv: iv);
    final combined = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combined.setAll(0, iv.bytes);
    combined.setAll(iv.bytes.length, encrypted.bytes);
    return '$magicPrefix${base64Encode(combined)}';
  }

  /// 解密 [sealed] 全文（须含魔数前缀）。
  static Future<String> openUtf8(String sealed) async {
    if (!sealed.startsWith(magicPrefix)) {
      throw FormatException('非加密工作区格式');
    }
    final b64 = sealed.substring(magicPrefix.length).trim();
    final raw = base64Decode(b64);
    if (raw.length <= 16) {
      throw FormatException('加密数据损坏或过短');
    }
    final iv = IV(Uint8List.sublistView(raw, 0, 16));
    final cipher = Encrypted(Uint8List.sublistView(raw, 16));
    final key = await _loadOrCreateAesKey();
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    return encrypter.decrypt(cipher, iv: iv);
  }
}
