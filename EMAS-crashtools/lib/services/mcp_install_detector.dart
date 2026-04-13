import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/mcp_builtin_registry.dart';
import '../models/mcp_catalog_entry.dart';

/// MCP 安装检测服务
/// 用于检测各种 MCP 服务是否已在本地安装
class McpInstallDetector {
  McpInstallDetector._();

  static Map<String, String> _envWithPath() {
    final base = Map<String, String>.from(Platform.environment);
    if (!Platform.isWindows) {
      final home = base['HOME'] ?? '';
      final extra = '/usr/local/bin:/opt/homebrew/bin:$home/.local/bin:$home/.npm-global/bin';
      final path = base['PATH'] ?? '';
      base['PATH'] = '$extra:$path';
    }
    return base;
  }

  /// 检测 CLI 命令是否存在
  static Future<bool> isCliInstalled(String command) async {
    if (kIsWeb) return false;
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        [command],
        environment: _envWithPath(),
        runInShell: Platform.isWindows,
      );
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('isCliInstalled error: $e');
      return false;
    }
  }

  /// 检测 npm 包是否已全局安装
  static Future<bool> isNpmPackageInstalled(String packageName) async {
    if (kIsWeb) return false;
    try {
      // 首先检查 npx 是否可用
      final npxCheck = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        ['npx'],
        environment: _envWithPath(),
        runInShell: Platform.isWindows,
      );
      if (npxCheck.exitCode != 0) return false;

      // 尝试用 npx 检查包是否存在
      // 使用 --dry-run 或 --package 来检查而不实际执行
      final result = await Process.run(
        'npm',
        ['list', '-g', packageName, '--json'],
        environment: _envWithPath(),
        runInShell: Platform.isWindows,
      );

      if (result.exitCode == 0) {
        final output = utf8.decode(result.stdout as List<int>);
        final json = jsonDecode(output) as Map<String, dynamic>;
        final dependencies = json['dependencies'] as Map<String, dynamic>?;
        if (dependencies != null && dependencies.containsKey(packageName.split('/').last)) {
          return true;
        }
      }

      // 备选方案：检查 npx 是否能解析到该包
      final npxResult = await Process.run(
        'npx',
        ['--dry-run', packageName],
        environment: _envWithPath(),
        runInShell: Platform.isWindows,
      );
      
      // npx --dry-run 会返回解析到的路径
      return npxResult.exitCode == 0;
    } catch (e) {
      debugPrint('isNpmPackageInstalled error: $e');
      return false;
    }
  }

  /// 检测 Homebrew formula 是否已安装
  static Future<bool> isBrewFormulaInstalled(String formula) async {
    if (kIsWeb || Platform.isWindows) return false;
    try {
      final result = await Process.run(
        'brew',
        ['list', '--formula', formula],
        environment: _envWithPath(),
      );
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('isBrewFormulaInstalled error: $e');
      return false;
    }
  }

  /// 检测 Homebrew 是否可用
  static Future<bool> hasBrew() async {
    if (kIsWeb || Platform.isWindows) return false;
    try {
      final result = await Process.run(
        'which',
        ['brew'],
        environment: _envWithPath(),
      );
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// 根据条目类型检测安装状态
  static Future<bool> checkInstallStatus(McpCatalogEntry entry) async {
    switch (entry.installCheckType) {
      case McpInstallCheckType.cli:
        if (entry.installCheckTarget == null) return false;
        return isCliInstalled(entry.installCheckTarget!);
      case McpInstallCheckType.npmPackage:
        if (entry.installCheckTarget == null) return false;
        return isNpmPackageInstalled(entry.installCheckTarget!);
      case McpInstallCheckType.brewFormula:
        if (entry.installCheckTarget == null) return false;
        return isBrewFormulaInstalled(entry.installCheckTarget!);
      case McpInstallCheckType.none:
        return true;
    }
  }

  /// 批量检测所有可安装 MCP 的状态
  /// 返回 Map<entryId, isInstalled>
  static Future<Map<String, bool>> checkAllInstallableStatus() async {
    final catalog = getInstallableMcpCatalog();
    final results = <String, bool>{};
    
    for (final entry in catalog) {
      results[entry.id] = await checkInstallStatus(entry);
    }
    
    return results;
  }

  /// 安装 npm 包
  static Future<ProcessResult> installNpmPackage(String packageName) async {
    return Process.run(
      'npm',
      ['install', '-g', packageName],
      environment: _envWithPath(),
      runInShell: Platform.isWindows,
    );
  }

  /// 使用 npx 直接运行（无需全局安装）
  static Future<ProcessResult> runWithNpx(
    String packageName,
    List<String> args,
  ) async {
    final allArgs = ['-y', packageName, ...args];
    return Process.run(
      'npx',
      allArgs,
      environment: _envWithPath(),
      runInShell: Platform.isWindows,
    );
  }
}
