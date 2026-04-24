import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 检测本机是否具备 **Claude Code** / **Cursor** CLI（用于 MCP 路径说明；不启动长驻服务）。
///
/// 说明：若 **App Sandbox** 为 true，macOS 会禁止应用内启动外部二进制，表现为「无权限」，
/// 与你在终端里 `claude …` 是否正常无关。
class McpLocalCliProbe {
  McpLocalCliProbe._();

  static Map<String, String> _envWithPath() {
    final base = Map<String, String>.from(Platform.environment);
    if (!Platform.isWindows) {
      final home = base['HOME'] ?? '';
      final extra = '/usr/local/bin:/opt/homebrew/bin:$home/.local/bin';
      final path = base['PATH'] ?? '';
      base['PATH'] = '$extra:$path';
    }
    return base;
  }

  static String _text(dynamic x) {
    if (x == null) return '';
    if (x is List<int>) {
      try {
        return utf8.decode(x);
      } catch (_) {
        return '';
      }
    }
    return x.toString();
  }

  static String _firstLine(String s) {
    final lines = s.split(RegExp(r'\r?\n')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (lines.isEmpty) return '';
    return lines.first;
  }

  static bool _looksLikePermissionBlock(String stderrOut, Object? error) {
    final s = '$stderrOut $error'.toLowerCase();
    return s.contains('operation not permitted') ||
        s.contains('permission denied') ||
        s.contains('not permitted') ||
        s.contains('eperm') ||
        s.contains('errno = 1') ||
        s.contains('无权限');
  }

  static String _sandboxOrPermissionHint(String productLabel) {
    return '$productLabel：应用内执行外部命令被系统拒绝（常见于 macOS「应用沙盒」开启）。'
        '终端里 claude 正常不代表本应用里也能检测。'
        '请重新编译 macOS 应用（本工程 Runner 的 entitlements 已关闭 app-sandbox），或忽略本检测；'
        'MCP 仍由 Cursor / Claude 按 mcp.json 拉起。';
  }

  static Future<ProcessResult> _run(String executable, List<String> args) async {
    return Process.run(
      executable,
      args,
      environment: _envWithPath(),
      runInShell: Platform.isWindows,
    );
  }

  /// 检测 `claude`：依次尝试新版 `claude code …` 与经典 `claude mcp …`。
  static Future<String> probeClaudeCodeCli() async {
    if (kIsWeb) return 'Web 端跳过本地 CLI 检测';
    try {
      final candidates = <List<String>>[
        const ['mcp', '--help'],
        const ['code', 'mcp', '--help'],
        const ['code', 'cli', '-v'],
        const ['--version'],
      ];
      ProcessResult? lastBad;
      for (final args in candidates) {
        final r = await _run('claude', args);
        lastBad = r;
        final out = _text(r.stdout);
        final err = _text(r.stderr);
        if (r.exitCode == 0) {
          final line = _firstLine(out.isNotEmpty ? out : err);
          if (args.length >= 2 && args[0] == 'code' && args[1] == 'mcp') {
            return 'Claude Code：已检测到 code mcp 子命令${line.isNotEmpty ? '（$line）' : ''}。'
                '若 mcp.json 中 `claude mcp start` 不可用，可改为 `claude` + args: code, mcp, start';
          }
          if (args.length >= 2 && args[0] == 'code' && args[1] == 'cli') {
            return 'Claude Code：已检测到 claude code cli（$line）。若需 MCP，请在本机执行 claude mcp --help / claude code mcp --help 核对启动参数';
          }
          if (args.first == 'mcp') {
            return line.isNotEmpty ? 'Claude Code：$line' : 'Claude Code：已检测到 claude mcp 子命令';
          }
          return 'Claude Code：已安装（$line），建议再确认 claude mcp --help 是否含 start';
        }
        if (_looksLikePermissionBlock(err + out, null)) {
          return _sandboxOrPermissionHint('Claude Code');
        }
      }
      final err = _text(lastBad?.stderr);
      final out = _text(lastBad?.stdout);
      if (_looksLikePermissionBlock(err + out, null)) {
        return _sandboxOrPermissionHint('Claude Code');
      }
      return 'Claude Code：未检测到可用 claude（exit ${lastBad?.exitCode}）${_tail(err + out)}';
    } catch (e) {
      if (_looksLikePermissionBlock('', e)) {
        return _sandboxOrPermissionHint('Claude Code');
      }
      return 'Claude Code：未检测到 claude：$e';
    }
  }

  /// 检测 `cursor` 是否可用，并尝试 `cursor mcp --help`。
  static Future<String> probeCursorCli() async {
    if (kIsWeb) return 'Web 端跳过本地 CLI 检测';
    try {
      var r = await _run('cursor', const ['mcp', '--help']);
      var out = _text(r.stdout);
      var err = _text(r.stderr);
      if (r.exitCode == 0) {
        final hint = _firstLine(out.isNotEmpty ? out : err);
        return hint.isNotEmpty ? 'Cursor：$hint' : 'Cursor：已检测到 cursor mcp 子命令';
      }
      if (_looksLikePermissionBlock(err + out, null)) {
        return _sandboxOrPermissionHint('Cursor');
      }
      r = await _run('cursor', const ['--version']);
      out = _text(r.stdout);
      err = _text(r.stderr);
      if (r.exitCode == 0) {
        return 'Cursor：已安装 cursor（${_firstLine(out + err)}），但 cursor mcp --help 失败，请核对版本';
      }
      if (_looksLikePermissionBlock(err + out, null)) {
        return _sandboxOrPermissionHint('Cursor');
      }
      return 'Cursor：未检测到可用 cursor（exit ${r.exitCode}）${_tail(err + out)}';
    } catch (e) {
      if (_looksLikePermissionBlock('', e)) {
        return _sandboxOrPermissionHint('Cursor');
      }
      return 'Cursor：未检测到 cursor：$e';
    }
  }

  static String _tail(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    final short = t.length > 120 ? '${t.substring(0, 120)}…' : t;
    return ' — $short';
  }

  /// 是否能在 PATH 中执行 `claude`（自带 MCP 宿主之一）。
  static Future<bool> isClaudeCliOnPath() async {
    if (kIsWeb) return false;
    try {
      final r = await _run('claude', const ['--version']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 是否能在 PATH 中执行 `cursor`（自带 MCP 宿主之一）。
  static Future<bool> isCursorCliOnPath() async {
    if (kIsWeb) return false;
    try {
      final r = await _run('cursor', const ['--version']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
