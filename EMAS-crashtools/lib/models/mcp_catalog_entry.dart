/// MCP 安装检测类型
enum McpInstallCheckType {
  /// 检测 CLI 命令是否存在（如 claude、cursor）
  cli,
  /// 检测 npm 包是否已全局安装
  npmPackage,
  /// 检测 Homebrew formula 是否已安装
  brewFormula,
  /// 无需检测，总是视为可用
  none,
}

/// 内置 MCP「商店 / 注册表」单条（与常见 mcpServers 子项字段对应）。
class McpCatalogEntry {
  const McpCatalogEntry({
    required this.id,
    required this.displayName,
    required this.description,
    required this.command,
    required this.args,
    required this.envTemplate,
    this.version = 'latest',
    this.wrapperScriptPathFieldHint,
    this.installCheckType = McpInstallCheckType.none,
    this.installCheckTarget,
  });

  /// 写入 `mcpServers` 时的键名，如 `gitlab`、`github`。
  final String id;

  final String displayName;
  final String description;
  final String command;
  final List<String> args;

  /// 环境变量名 → 占位说明（值仅作 UI 提示，合并时用用户输入覆盖）。
  final Map<String, String> envTemplate;

  /// 展示用；实际由 `npx -y` 等拉取 npm 上最新。
  final String version;

  /// 非空时，安装对话框显示「包装脚本绝对路径」。
  /// 若用户填写非空路径，则生成 `command: bash`、`args: [路径]`（例如 `scripts/start_claude_code_mcp.sh` 的绝对路径）；
  /// 若留空，则使用 [command] / [args]（如 `claude mcp start`）。
  final String? wrapperScriptPathFieldHint;

  /// 安装检测类型
  final McpInstallCheckType installCheckType;

  /// 安装检测目标（如 cli 命令名、npm 包名、brew formula 名）
  final String? installCheckTarget;

  /// 生成可并入 `mcpServers[id]` 的对象。
  Map<String, dynamic> buildServerBlock(
    Map<String, String> envValues, {
    String? wrapperScriptAbsolutePath,
  }) {
    final env = <String, String>{};
    for (final k in envTemplate.keys) {
      env[k] = envValues[k]?.trim() ?? '';
    }
    final script = wrapperScriptAbsolutePath?.trim() ?? '';
    if (wrapperScriptPathFieldHint != null && script.isNotEmpty) {
      return <String, dynamic>{
        'command': 'bash',
        'args': <String>[script],
        'env': env,
      };
    }
    return <String, dynamic>{
      'command': command,
      'args': List<String>.from(args),
      'env': env,
    };
  }
}
