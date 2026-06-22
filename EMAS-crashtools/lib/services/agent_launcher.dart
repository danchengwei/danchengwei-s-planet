import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/agent_payload.dart';
import '../models/tool_config.dart';

/// 根据配置复制剪贴板或启动本机 CLI（默认 Claude Code：`claude`）。
class AgentLauncher {
  /// 由 EMAS 详情 JSON 与列表项摘要拼出提示词（中文）。
  static String buildPromptFromIssue({
    required String digestHash,
    required Map<String, dynamic>? getIssueBody,
    String? listTitle,
    String? listStack,
  }) {
    final buf = StringBuffer();
    buf.writeln('请分析以下移动端聚合问题（Digest: $digestHash），给出可能根因、修复建议与验证步骤。');
    if (listTitle != null && listTitle.isNotEmpty) {
      buf.writeln('\n【列表摘要标题】\n$listTitle');
    }
    if (listStack != null && listStack.isNotEmpty) {
      buf.writeln('\n【列表堆栈摘要】\n$listStack');
    }
    if (getIssueBody != null) {
      buf.writeln('\n【GetIssue 原始 JSON】\n${const JsonEncoder.withIndent('  ').convert(getIssueBody)}');
    }
    return buf.toString();
  }

  static Future<void> runFromPayload(AgentPayload p) async {
    final wd = p.workingDirectory.trim().isEmpty ? null : p.workingDirectory.trim();
    switch (p.mode) {
      case 'clipboard':
        await Clipboard.setData(ClipboardData(text: p.prompt));
        return;
      case 'stdin':
        final proc = await Process.start(
          p.executable,
          p.fixedArgs,
          workingDirectory: wd,
          runInShell: Platform.isWindows,
        );
        proc.stdin.write(p.prompt);
        await proc.stdin.close();
        await proc.exitCode;
        return;
      case 'args':
      default:
        final args = [...p.fixedArgs, p.prompt];
        await Process.run(
          p.executable,
          args,
          workingDirectory: wd,
          runInShell: Platform.isWindows,
        );
    }
  }

  static AgentPayload payloadFromConfig({
    required ToolConfig config,
    required String digestHash,
    required String prompt,
  }) {
    return AgentPayload(
      version: AgentPayload.currentVersion,
      digestHash: digestHash,
      prompt: prompt,
      workingDirectory: config.agentWorkDir.trim(),
      executable: config.agentExecutable.trim().isEmpty ? 'claude' : config.agentExecutable.trim(),
      mode: config.agentMode.trim().isEmpty ? 'clipboard' : config.agentMode.trim(),
      fixedArgs: config.agentFixedArgsList,
    );
  }
}
