#!/bin/bash

# H5 静态资源构建和部署脚本
# 将 H5 项目构建并复制到 Android assets 目录

set -e

echo "========================================"
echo "H5 静态资源构建和部署工具"
echo "========================================"

# 获取脚本所在目录的父目录（项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
H5_DIR="$PROJECT_ROOT/h5"
ANDROID_ASSETS_H5="$PROJECT_ROOT/app/src/main/assets/h5"

echo ""
echo "[1/4] 检查 H5 项目目录..."
if [ ! -d "$H5_DIR" ]; then
    echo "错误: H5 项目目录不存在: $H5_DIR"
    exit 1
fi

echo "[2/4] 构建 H5 项目..."
cd "$H5_DIR"
npm run build

echo ""
echo "[3/4] 清理旧的 assets 文件..."
rm -rf "$ANDROID_ASSETS_H5/assets"
rm -f "$ANDROID_ASSETS_H5/index.html"
rm -f "$ANDROID_ASSETS_H5/favicon.svg"
rm -f "$ANDROID_ASSETS_H5/icons.svg"

echo "[4/4] 复制新的构建文件..."
mkdir -p "$ANDROID_ASSETS_H5/assets"
cp "$H5_DIR/dist/index.html" "$ANDROID_ASSETS_H5/"
cp "$H5_DIR/dist/assets/"* "$ANDROID_ASSETS_H5/assets/"
cp "$H5_DIR/dist/favicon.svg" "$ANDROID_ASSETS_H5/" 2>/dev/null || true
cp "$H5_DIR/dist/icons.svg" "$ANDROID_ASSETS_H5/" 2>/dev/null || true

echo ""
echo "========================================"
echo "✅ 部署完成！"
echo "========================================"
echo ""
echo "目标目录: $ANDROID_ASSETS_H5"
echo ""
echo "文件列表:"
ls -lh "$ANDROID_ASSETS_H5"
echo ""
ls -lh "$ANDROID_ASSETS_H5/assets/"
