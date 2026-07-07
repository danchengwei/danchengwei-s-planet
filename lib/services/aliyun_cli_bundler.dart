import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AliyunCliBundler {
  static const _assetBase = 'tools/aliyun/bundled';
  static const _cliDirName = 'aliyun-cli';
  static const _versionFileName = '.bundled_version';

  static String? _cachedCliPath;
  static bool _checked = false;

  static Future<String?> ensureCliAvailable() async {
    if (_checked) return _cachedCliPath;
    _checked = true;

    try {
      final dir = await _getCliDir();
      final cliPath = p.join(dir.path, 'aliyun');
      final versionFile = p.join(dir.path, _versionFileName);

      final assetVersion = await _getBundledVersion();
      final installedVersion = await _readInstalledVersion(versionFile);

      if (assetVersion != null &&
          (installedVersion != assetVersion || !File(cliPath).existsSync())) {
        debugPrint('[AliyunCliBundler] 部署内置 CLI (版本: $assetVersion)');
        await _deployBundledCli(dir, cliPath, versionFile, assetVersion);
      } else if (File(cliPath).existsSync()) {
        debugPrint('[AliyunCliBundler] 使用已部署的 CLI');
      } else {
        debugPrint('[AliyunCliBundler] 无内置 CLI，将使用系统 aliyun 命令');
        return null;
      }

      if (Platform.isMacOS || Platform.isLinux) {
        await Process.run('chmod', ['+x', cliPath]);
      }

      _cachedCliPath = cliPath;
      return cliPath;
    } catch (e, st) {
      debugPrint('[AliyunCliBundler] 部署失败: $e\n$st');
      return null;
    }
  }

  static Future<Directory> _getCliDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, _cliDirName));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String?> _getBundledVersion() async {
    try {
      final v = await rootBundle.loadString('$_assetBase/VERSION');
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _readInstalledVersion(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) {
        return (await f.readAsString()).trim();
      }
    } catch (_) {}
    return null;
  }

  /// 获取 .app 包内 flutter_assets 目录的文件系统路径
  static String? _getAppBundlePath() {
    final exePath = Platform.resolvedExecutable;
    // macOS: .../EMAS崩溃分析工具.app/Contents/MacOS/EMAS崩溃分析工具
    // flutter_assets 在: .../Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/
    if (Platform.isMacOS) {
      final contentsDir = p.dirname(p.dirname(exePath));
      final flutterAssetsDir = p.join(
        contentsDir,
        'Frameworks',
        'App.framework',
        'Versions',
        'A',
        'Resources',
        'flutter_assets',
      );
      if (Directory(flutterAssetsDir).existsSync()) {
        return flutterAssetsDir;
      }
      // 兼容不带 Versions/A 的结构
      final altDir = p.join(
        contentsDir,
        'Frameworks',
        'App.framework',
        'Resources',
        'flutter_assets',
      );
      if (Directory(altDir).existsSync()) {
        return altDir;
      }
    }
    return null;
  }

  static Future<void> _deployBundledCli(
    Directory dir,
    String cliPath,
    String versionFilePath,
    String version,
  ) async {
    final arch = Platform.isMacOS
        ? (await _isArm64Mac() ? 'darwin-arm64' : 'darwin-amd64')
        : Platform.isLinux
            ? (await _isArm64Linux() ? 'linux-arm64' : 'linux-amd64')
            : null;

    if (arch == null) {
      throw UnsupportedError('不支持的平台');
    }

    // 优先从 .app 包内文件系统直接拷贝，避免 rootBundle.load 加载大文件 OOM
    final appBundlePath = _getAppBundlePath();
    if (appBundlePath != null) {
      final sourcePath = p.join(appBundlePath, '$_assetBase/$arch/aliyun');
      final sourceFile = File(sourcePath);
      if (sourceFile.existsSync()) {
        debugPrint('[AliyunCliBundler] 从 .app 包拷贝 CLI: $sourcePath');
        await sourceFile.copy(cliPath);
        await File(versionFilePath).writeAsString(version);
        return;
      }
      debugPrint('[AliyunCliBundler] .app 包内未找到 CLI: $sourcePath');
    }

    // 回退: rootBundle.load (小文件或开发模式)
    debugPrint('[AliyunCliBundler] 回退到 rootBundle.load 加载 CLI');
    final assetPath = '$_assetBase/$arch/aliyun';
    final bytes = await rootBundle.load(assetPath);
    final file = File(cliPath);
    await file.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );

    await File(versionFilePath).writeAsString(version);
  }

  static Future<bool> _isArm64Mac() async {
    try {
      final result = await Process.run('uname', ['-m']);
      final arch = (result.stdout as String).trim();
      return arch == 'arm64';
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _isArm64Linux() async {
    try {
      final result = await Process.run('uname', ['-m']);
      final arch = (result.stdout as String).trim();
      return arch == 'aarch64' || arch == 'arm64';
    } catch (_) {
      return false;
    }
  }

  static void resetCache() {
    _checked = false;
    _cachedCliPath = null;
  }
}
