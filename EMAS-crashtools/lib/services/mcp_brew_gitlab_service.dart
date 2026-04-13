import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 通过 Homebrew 安装/卸载 **gitlab-mcp**（若你本机无此 formula，`brew install` 会失败，可改用内置 npx 方案）。
///
/// 命令与你在终端中一致：`brew install gitlab-mcp`、`brew uninstall --zap gitlab-mcp`。
class McpBrewGitlabService {
  McpBrewGitlabService._();

  static Map<String, String> _env() {
    final base = Map<String, String>.from(Platform.environment);
    if (!Platform.isWindows) {
      final home = base['HOME'] ?? '';
      final extra = '/opt/homebrew/bin:/usr/local/bin:$home/.local/bin';
      final path = base['PATH'] ?? '';
      base['PATH'] = '$extra:$path';
    }
    return base;
  }

  /// 非 Web、非 Windows 时可能使用 brew（Linux 需本机已装 Homebrew）。
  static bool get platformMayUseBrew => !kIsWeb && !Platform.isWindows;

  static Future<bool> hasBrew() async {
    if (!platformMayUseBrew) return false;
    try {
      final r = await Process.run('which', ['brew'], environment: _env());
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isFormulaInstalled() async {
    if (!platformMayUseBrew) return false;
    try {
      final r = await Process.run(
        'brew',
        ['list', '--formula', 'gitlab-mcp'],
        environment: _env(),
      );
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 供 `mcpServers.gitlab.command` 使用；找不到则回退为 `gitlab-mcp`（依赖 PATH）。
  static Future<String?> resolveExecutablePath() async {
    if (!await isFormulaInstalled()) return null;
    try {
      final pr = await Process.run('brew', ['--prefix', 'gitlab-mcp'], environment: _env());
      if (pr.exitCode != 0) return 'gitlab-mcp';
      final prefix = utf8.decode(pr.stdout as List<int>).trim();
      for (final name in ['gitlab-mcp', 'gitlab-mcp-server', 'server-gitlab']) {
        final f = File('$prefix/bin/$name');
        if (await f.exists()) return f.path;
      }
      return 'gitlab-mcp';
    } catch (_) {
      return 'gitlab-mcp';
    }
  }

  static Future<ProcessResult> install() async {
    return Process.run('brew', ['install', 'gitlab-mcp'], environment: _env());
  }

  static Future<ProcessResult> uninstallZap() async {
    return Process.run('brew', ['uninstall', '--zap', 'gitlab-mcp'], environment: _env());
  }

  /// 本机 `npx` 是否在 PATH 中（用于官方 npm 包方案）。
  static Future<bool> hasNpx() async {
    if (kIsWeb) return false;
    try {
      if (Platform.isWindows) {
        final r = await Process.run('where', ['npx'], environment: _env(), runInShell: true);
        return r.exitCode == 0;
      }
      final r = await Process.run('which', ['npx'], environment: _env());
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 已装 brew formula，或本机有 npx，均可认为 GitLab MCP **运行环境已就绪**。
  static Future<bool> isGitlabMcpRuntimeReady() async {
    if (kIsWeb) return false;
    if (await isFormulaInstalled()) return true;
    return hasNpx();
  }

  /// 统一安装：优先 `brew install gitlab-mcp`；失败或未装 brew 时若有 npx 则视为可用 npx 方案（可选尝试 npm 全局装包）。
  /// 不弹窗，由调用方展示结果文案。
  static Future<({bool ok, String message})> installGitlabMcpUnified() async {
    if (kIsWeb) return (ok: false, message: 'Web 端无法在本机执行安装');

    if (await isFormulaInstalled()) {
      return (ok: true, message: '本机已通过 Homebrew 安装 GitLab MCP');
    }

    if (platformMayUseBrew && await hasBrew()) {
      final res = await install();
      if (res.exitCode == 0) {
        return (ok: true, message: '安装完成');
      }
    }

    if (await hasNpx()) {
      try {
        await Process.run(
          'npm',
          ['install', '-g', '@modelcontextprotocol/server-gitlab'],
          environment: _env(),
          runInShell: Platform.isWindows,
        ).timeout(const Duration(seconds: 120));
      } catch (_) {
        // 全局装失败仍允许走 npx -y 按需拉取
      }
      return (ok: true, message: '已就绪（将使用 npx 运行 GitLab MCP）');
    }

    return (ok: false, message: '未检测到 Homebrew 与 npx，请先安装 Homebrew 或 Node.js');
  }
}
