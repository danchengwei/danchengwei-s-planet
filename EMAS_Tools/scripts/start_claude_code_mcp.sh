#!/usr/bin/env bash
# =============================================================================
# Claude Code 自带 MCP 的本地启动包装（stdio 入口）
#
# 用途：在 Cursor / Claude Desktop 等的 mcp.json 里配置为：
#   "command": "bash",
#   "args": ["/本机绝对路径/crashTools/scripts/start_claude_code_mcp.sh"]
#
# 注意：大模型不能替你执行终端命令；须由 MCP 客户端按上述方式拉起本进程，
#       或由你在本机终端手动运行以排查问题。
#
# 子命令以本机 Claude Code 版本为准。若 `mcp start` 不可用，请执行：
#   claude mcp --help
# 并按输出将下方 exec 行改为当前版本支持的启动方式。
# =============================================================================
set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"

if ! command -v claude >/dev/null 2>&1; then
  echo "crashTools: 未找到 claude 命令。请先安装 Claude Code CLI 并确保在 PATH 中。" >&2
  exit 127
fi

# 不同版本 CLI 入口可能为 `claude mcp start` 或 `claude code mcp start`，依次尝试。
set +e
claude mcp --help >/dev/null 2>&1
mcp_help=$?
claude code mcp --help >/dev/null 2>&1
code_mcp_help=$?
set -e

if [ "$mcp_help" -eq 0 ]; then
  exec claude mcp start "$@"
fi
if [ "$code_mcp_help" -eq 0 ]; then
  exec claude code mcp start "$@"
fi

echo "crashTools: 无法判断 MCP 启动方式。请在本机执行: claude mcp --help 与 claude code mcp --help" >&2
exec claude mcp start "$@"
