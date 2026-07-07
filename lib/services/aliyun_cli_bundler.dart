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

      // 检测平台架构
      final arch = Platform.isMacOS
          ? (await _isArm64() ? 'darwin-arm64' : 'darwin-amd64')
          : Platform.isLinux
              ? (await _isArm64() ? 'linux-arm64' : 'linux-amd64')
              : null;

      if (arch == null) {
        debugPrint('[AliyunCliBundler] 不支持的平台');
        return null;
      }

      debugPrint('[AliyunCliBundler] 平台: $arch, exe: ${Platform.resolvedExecutable}');

      // 定位 .app 包内 CLI 源文件
      final sourceCliPath = _findBundledCliPath(arch);
      debugPrint('[AliyunCliBundler] 包内 CLI 路径: ${sourceCliPath ?? "未找到"}');

      // 读取版本号（优先从文件系统，回退到 rootBundle）
      final assetVersion = await _readAssetVersion(sourceCliPath);
      final installedVersion = await _readInstalledVersion(versionFile);

      final needDeploy = sourceCliPath != null &&
          (installedVersion != assetVersion || !File(cliPath).existsSync());

      if (needDeploy) {
        debugPrint('[AliyunCliBundler] 部署内置 CLI (版本: $assetVersion)');
        await _deployFromAppBundle(sourceCliPath, cliPath, versionFile, assetVersion);
      } else if (File(cliPath).existsSync()) {
        debugPrint('[AliyunCliBundler] 使用已部署的 CLI');
      } else {
        debugPrint('[AliyunCliBundler] 无内置 CLI，将使用系统 aliyun 命令');
        return null;
      }

      if (Platform.isMacOS || Platform.isLinux) {
        await Process.run('chmod', ['+x', cliPath]);
      }

      // 确保必要插件已安装
      await _ensurePlugins(cliPath);

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

  /// 从 .app 包内定位 flutter_assets 目录，返回 CLI 二进制的完整路径
  static String? _findBundledCliPath(String arch) {
    final exePath = Platform.resolvedExecutable;
    if (exePath.isEmpty) return null;

    // macOS: .app/Contents/MacOS/ExecutableName
    // flutter_assets: .app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets
    if (Platform.isMacOS) {
      final contentsDir = p.dirname(p.dirname(exePath));

      final candidates = [
        p.join(contentsDir, 'Frameworks', 'App.framework', 'Versions', 'A',
            'Resources', 'flutter_assets'),
        p.join(contentsDir, 'Frameworks', 'App.framework', 'Resources',
            'flutter_assets'),
      ];

      for (final flutterAssetsDir in candidates) {
        final cliPath = p.join(flutterAssetsDir, _assetBase, arch, 'aliyun');
        if (File(cliPath).existsSync()) {
          return cliPath;
        }
      }

      // 遍历 Frameworks 目录兜底查找
      final frameworksDir = Directory(p.join(contentsDir, 'Frameworks'));
      if (frameworksDir.existsSync()) {
        for (final framework in frameworksDir.listSync().whereType<Directory>()) {
          final searchDir = p.join(framework.path, 'Resources', 'flutter_assets');
          final cliPath = p.join(searchDir, _assetBase, arch, 'aliyun');
          if (File(cliPath).existsSync()) {
            return cliPath;
          }
        }
      }
    }

    if (Platform.isLinux) {
      // Linux: 可执行文件同目录下的 data/flutter_assets/
      final exeDir = p.dirname(exePath);
      final candidates = [
        p.join(exeDir, 'data', 'flutter_assets'),
        p.join(exeDir, 'flutter_assets'),
      ];
      for (final flutterAssetsDir in candidates) {
        final cliPath = p.join(flutterAssetsDir, _assetBase, arch, 'aliyun');
        if (File(cliPath).existsSync()) {
          return cliPath;
        }
      }
    }

    return null;
  }

  /// 读取内置 CLI 版本号（优先从文件系统，回退到 rootBundle）
  static Future<String?> _readAssetVersion(String? sourceCliPath) async {
    // 优先从 .app 包内文件系统读取 VERSION
    if (sourceCliPath != null) {
      final versionPath = p.join(p.dirname(p.dirname(sourceCliPath)), 'VERSION');
      final versionFile = File(versionPath);
      if (versionFile.existsSync()) {
        try {
          return (await versionFile.readAsString()).trim();
        } catch (_) {}
      }
    }

    // 回退到 rootBundle
    try {
      final v = await rootBundle.loadString('$_assetBase/VERSION');
      return v.trim();
    } catch (_) {}

    return null;
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

  /// 从 .app 包内文件系统拷贝 CLI 二进制
  static Future<void> _deployFromAppBundle(
    String sourcePath,
    String destPath,
    String versionFilePath,
    String? version,
  ) async {
    debugPrint('[AliyunCliBundler] 拷贝: $sourcePath -> $destPath');

    final sourceFile = File(sourcePath);
    // 使用流式拷贝，避免内存问题
    final stream = sourceFile.openRead();
    final sink = File(destPath).openWrite();
    await stream.pipe(sink);
    await sink.flush();
    await sink.close();

    if (version != null) {
      await File(versionFilePath).writeAsString(version);
    }

    debugPrint('[AliyunCliBundler] 拷贝完成，文件大小: ${await File(destPath).length()} bytes');
  }

  static const _requiredPlugins = ['aliyun-cli-emas-appmonitor'];

  /// 确保必要插件已安装
  static Future<void> _ensurePlugins(String cliPath) async {
    try {
      final result = await Process.run(cliPath, ['plugin', 'list']);
      if (result.exitCode != 0) {
        debugPrint('[AliyunCliBundler] 无法获取插件列表: ${result.stderr}');
        return;
      }

      final installed = (result.stdout as String).split('\n')
          .map((l) => l.trim().split(RegExp(r'\s+')).first)
          .where((n) => n.isNotEmpty && n != 'Name')
          .toSet();

      for (final plugin in _requiredPlugins) {
        if (!installed.contains(plugin)) {
          debugPrint('[AliyunCliBundler] 安装插件: $plugin');
          final installResult = await Process.run(
            cliPath, ['plugin', 'install', '--names', plugin],
          );
          if (installResult.exitCode == 0) {
            debugPrint('[AliyunCliBundler] 插件 $plugin 安装成功');
          } else {
            debugPrint('[AliyunCliBundler] 插件 $plugin 安装失败: ${installResult.stderr}');
          }
        }
      }
    } catch (e) {
      debugPrint('[AliyunCliBundler] 插件检查异常: $e');
    }
  }

  static Future<bool> _isArm64() async {
    try {
      final result = await Process.run('uname', ['-m']);
      final arch = (result.stdout as String).trim();
      return arch == 'arm64' || arch == 'aarch64';
    } catch (_) {
      return false;
    }
  }

  static void resetCache() {
    _checked = false;
    _cachedCliPath = null;
  }
}
