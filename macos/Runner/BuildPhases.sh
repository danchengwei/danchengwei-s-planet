#!/bin/bash

# Flutter macOS 构建后置钩子
# 用于集成阿里云CLI到应用包中

set -e

# 只在Release构建时执行
if [[ "$CONFIGURATION" != "Release" ]]; then
  exit 0
fi

echo "=== Flutter macOS 构建后置处理 ==="

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
TOOLS_DIR="$PROJECT_ROOT/tools/aliyun"

if [[ -f "$TOOLS_DIR/setup.sh" ]]; then
  echo "执行应用打包集成..."
  bash "$TOOLS_DIR/setup.sh"
else
  echo "未找到 setup.sh，跳过CLI集成"
fi

echo "=== 完成 ==="
