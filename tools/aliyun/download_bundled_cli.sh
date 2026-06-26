#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUNDLED_DIR="$SCRIPT_DIR/bundled"

echo "=== 下载阿里云 CLI 并打包进应用 ==="
echo ""

mkdir -p "$BUNDLED_DIR/darwin-arm64"
mkdir -p "$BUNDLED_DIR/darwin-amd64"

download_cli() {
  local os_arch="$1"
  local url="$2"
  local dest_dir="$BUNDLED_DIR/$os_arch"

  echo "下载 $os_arch..."
  echo "  URL: $url"

  local tmp_dir=$(mktemp -d)
  trap "rm -rf $tmp_dir" EXIT

  curl -fsSL -o "$tmp_dir/aliyun.tgz" "$url"

  echo "  解压..."
  tar -xzf "$tmp_dir/aliyun.tgz" -C "$tmp_dir"

  if [[ -f "$tmp_dir/aliyun" ]]; then
    cp "$tmp_dir/aliyun" "$dest_dir/"
  elif [[ -f "$tmp_dir/aliyun/aliyun" ]]; then
    cp "$tmp_dir/aliyun/aliyun" "$dest_dir/"
  else
    echo "  ❌ 找不到可执行文件"
    return 1
  fi

  chmod +x "$dest_dir/aliyun"
  local version=$("$dest_dir/aliyun" version 2>/dev/null | head -1 || echo "unknown")
  echo "  ✓ 版本: $version"
}

download_cli "darwin-arm64" "https://aliyun-cli.oss-cn-hangzhou.aliyuncs.com/aliyun-cli-darwin-arm64.tgz"
download_cli "darwin-amd64" "https://aliyun-cli.oss-cn-hangzhou.aliyuncs.com/aliyun-cli-darwin-amd64.tgz"

VERSION=$("$BUNDLED_DIR/darwin-arm64/aliyun" version 2>/dev/null | head -1 | awk '{print $2}' || echo "3.0.0")
echo "$VERSION" > "$BUNDLED_DIR/VERSION"

echo ""
echo "=== 下载完成"
echo "  版本: $VERSION"
echo "  目录: $BUNDLED_DIR"
echo ""
echo "下一步: flutter build macos 时会自动打包进应用"
echo ""
