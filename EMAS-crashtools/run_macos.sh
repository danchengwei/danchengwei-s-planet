#!/usr/bin/env bash
# 一键在本机以 Debug 启动 macOS 桌面版（含热重载）。
# 用法：./run_macos.sh | ./run_macos.sh open | ./run_macos.sh build | ./run_macos.sh clean
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# 常见本机 Flutter / Homebrew 路径，避免「已安装但当前 shell 找不到」
export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/.local/bin:${PATH}"

usage() {
  echo "用法: $0              # flutter run -d macos（调试 + 热重载）" >&2
  echo "      $0 open         # 打开已构建的 Debug .app（无热重载；无产物则先 build）" >&2
  echo "      $0 build        # 仅编译 Debug，不启动" >&2
  echo "      $0 clean        # flutter clean（缓解 Xcode stale / 路径错乱类警告）" >&2
  echo "      $0 -h|--help    # 显示本说明" >&2
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f "$ROOT/pubspec.yaml" ]]; then
  echo "未在脚本所在目录找到 pubspec.yaml，请从 Flutter 工程根目录执行。" >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "未找到 flutter，请先安装 Flutter 并加入 PATH（或确认 Homebrew 路径已 export）。" >&2
  exit 127
fi

# 与 macos/Runner/Configs/AppInfo.xcconfig 中 PRODUCT_NAME 保持一致，避免改名后 open 失效
read_product_name() {
  local f="$ROOT/macos/Runner/Configs/AppInfo.xcconfig"
  local name=""
  if [[ -f "$f" ]]; then
    name="$(sed -n 's/^PRODUCT_NAME[[:space:]]*=[[:space:]]*//p' "$f" | head -1 | tr -d '\r')"
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
  fi
  printf '%s' "${name:-EMAS崩溃分析工具}"
}

resolve_debug_app() {
  local product="$1"
  local debug_dir="$ROOT/build/macos/Build/Products/Debug"
  local preferred="$debug_dir/${product}.app"

  if [[ -d "$preferred" ]]; then
    printf '%s' "$preferred"
    return 0
  fi

  shopt -s nullglob
  local candidates=( "$debug_dir"/*.app )
  shopt -u nullglob
  if [[ ${#candidates[@]} -eq 1 ]]; then
    printf '%s' "${candidates[0]}"
    return 0
  fi
  if [[ ${#candidates[@]} -gt 1 ]]; then
    local a
    for a in "${candidates[@]}"; do
      if [[ "$(basename "$a")" == "${product}.app" ]]; then
        printf '%s' "$a"
        return 0
      fi
    done
    printf '%s' "${candidates[0]}"
    return 0
  fi
  return 1
}

case "${1:-run}" in
  run)
    exec flutter run -d macos
    ;;
  open)
    PRODUCT_NAME="$(read_product_name)"
    if ! APP="$(resolve_debug_app "$PRODUCT_NAME")"; then
      echo "尚未构建：正在执行 flutter build macos --debug …" >&2
      flutter build macos --debug
      APP="$(resolve_debug_app "$PRODUCT_NAME")" || {
        echo "构建完成但未在 Debug 目录找到 .app，请检查 macos 工程与 AppInfo.xcconfig。" >&2
        exit 1
      }
    fi
    exec open "$APP"
    ;;
  build)
    exec flutter build macos --debug
    ;;
  clean)
    exec flutter clean
    ;;
  *)
    usage
    exit 1
    ;;
esac
