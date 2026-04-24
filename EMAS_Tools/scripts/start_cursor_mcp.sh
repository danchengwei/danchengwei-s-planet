#!/usr/bin/env bash
# =============================================================================
# Cursor 自带 MCP 的本地启动包装（stdio 入口）
#
# 用途：在 Cursor 的 mcp.json 里配置为：
#   "command": "bash",
#   "args": ["/本机绝对路径/crashTools/scripts/start_cursor_mcp.sh"]
#
# 注意：大模型不能替你执行终端；须由 Cursor 按上述方式拉起本进程。
# 子命令以本机 Cursor CLI 为准。若 `mcp start` 不可用，请执行：
#   cursor mcp --help
# =============================================================================
set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"

if ! command -v cursor >/dev/null 2>&1; then
  echo "crashTools: 未找到 cursor 命令。请安装 Cursor 并确保 CLI 在 PATH 中（Cursor 设置中可安装 shell command）。" >&2
  exit 127
fi

exec cursor mcp start "$@"
