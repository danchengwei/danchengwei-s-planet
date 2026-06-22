import 'dart:convert';

/// 导出到磁盘供 `crash-tools://` 打开的 Agent 任务描述（与 HTML 同目录 payloads/*.json）。
class AgentPayload {
  AgentPayload({
    required this.version,
    required this.digestHash,
    required this.prompt,
    required this.workingDirectory,
    required this.executable,
    required this.mode,
    this.fixedArgs = const [],
  });

  static const currentVersion = 1;

  final int version;
  final String digestHash;
  final String prompt;
  final String workingDirectory;
  final String executable;
  /// stdin | clipboard | args
  final String mode;
  final List<String> fixedArgs;

  Map<String, dynamic> toJson() => {
        'version': version,
        'digestHash': digestHash,
        'prompt': prompt,
        'workingDirectory': workingDirectory,
        'executable': executable,
        'mode': mode,
        'fixedArgs': fixedArgs,
      };

  static AgentPayload? tryParseFile(String jsonText) {
    try {
      final m = jsonDecode(jsonText);
      if (m is! Map<String, dynamic>) return null;
      final v = m['version'];
      if (v is! int || v < 1) return null;
      final prompt = m['prompt']?.toString();
      final exe = m['executable']?.toString();
      final mode = m['mode']?.toString();
      if (prompt == null || exe == null || mode == null) return null;
      return AgentPayload(
        version: v,
        digestHash: m['digestHash']?.toString() ?? '',
        prompt: prompt,
        workingDirectory: m['workingDirectory']?.toString() ?? '',
        executable: exe,
        mode: mode,
        fixedArgs: (m['fixedArgs'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      );
    } catch (_) {
      return null;
    }
  }
}
