#!/usr/bin/env bash
# 一键在本机以 Debug 启动 macOS 桌面版（含热重载）。用法：./run_macos.sh  或  bash run_macos.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  echo "未找到 flutter，请先安装 Flutter 并加入 PATH。" >&2
  exit 127
fi

case "${1:-run}" in
  run)
    exec flutter run -d macos
    ;;
  open)
    APP="$ROOT/build/macos/Build/Products/Debug/EMAS崩溃分析工具.app"
    if [[ ! -d "$APP" ]]; then
      echo "尚未构建：正在执行 flutter build macos --debug …" >&2
      flutter build macos --debug
    fi
    exec open "$APP"
    ;;
  *)
    echo "用法: $0           # flutter run -d macos（调试 + 热重载）" >&2
    echo "      $0 open     # 直接打开已构建的 Debug .app（无热重载）" >&2
    exit 1
    ;;
esac
