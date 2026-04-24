import '../models/mcp_catalog_entry.dart';

/// 应用内置 MCP 注册表（简化版：仅保留 Cursor、Claude Code、GitLab）
///
/// 说明：龙虾 / Claude / Cursor 等客户端会从**各自配置文件**读列表；本工具将同类结构存在项目里并支持导出。
/// 「安装」在客户端侧通常还包含：本机执行 `npx …`、写入 `~/.cursor/mcp.json` 等——本应用仅负责**合并模板 + 导出**，不代执行子进程。
const List<McpCatalogEntry> kBuiltinMcpCatalog = [
  McpCatalogEntry(
    id: 'claude-code',
    displayName: 'Claude Code（自带 MCP）',
    description:
        '使用本机已安装的 Claude Code CLI，合并为 `claude mcp start`（以本机 `claude mcp --help` 为准）。'
        '一般用户请用 MCP 页顶部「一键应用推荐」即可，无需点本项。'
        '进阶：可在安装对话框折叠区填写包装脚本绝对路径（如仓库 scripts/start_claude_code_mcp.sh）。',
    command: 'claude',
    args: ['mcp', 'start'],
    envTemplate: {},
    wrapperScriptPathFieldHint: '可选：start_claude_code_mcp.sh 的绝对路径（仓库 scripts/ 下）',
    installCheckType: McpInstallCheckType.cli,
    installCheckTarget: 'claude',
  ),
  McpCatalogEntry(
    id: 'cursor',
    displayName: 'Cursor（自带 MCP）',
    description:
        '使用本机 Cursor CLI，合并为 `cursor mcp start`。一般用户用顶部「一键应用推荐」即可。'
        '进阶：安装对话框折叠区可填 scripts/start_cursor_mcp.sh 绝对路径。',
    command: 'cursor',
    args: ['mcp', 'start'],
    envTemplate: {},
    wrapperScriptPathFieldHint: '可选：start_cursor_mcp.sh 的绝对路径（仓库 scripts/ 下）',
    installCheckType: McpInstallCheckType.cli,
    installCheckTarget: 'cursor',
  ),
  McpCatalogEntry(
    id: 'gitlab',
    displayName: 'GitLab',
    description: '访问 GitLab 仓库、文件、Issue、合并请求等（npm：@modelcontextprotocol/server-gitlab）。',
    command: 'npx',
    args: ['-y', '@modelcontextprotocol/server-gitlab'],
    envTemplate: {
      'GITLAB_PERSONAL_ACCESS_TOKEN': '在 GitLab 页填好后可用「一键应用推荐」自动写入',
      'GITLAB_API_URL': '默认 https://gitlab.com/api/v4；自建填 https://域名/api/v4',
    },
    installCheckType: McpInstallCheckType.npmPackage,
    installCheckTarget: '@modelcontextprotocol/server-gitlab',
  ),
];

/// 获取所有可安装的 MCP 条目（排除内置 CLI 工具）
List<McpCatalogEntry> getInstallableMcpCatalog() {
  return kBuiltinMcpCatalog
      .where((e) => e.installCheckType != McpInstallCheckType.cli)
      .toList();
}

/// 根据 ID 查找 MCP 条目
McpCatalogEntry? findMcpCatalogEntryById(String id) {
  for (final entry in kBuiltinMcpCatalog) {
    if (entry.id == id) return entry;
  }
  return null;
}
