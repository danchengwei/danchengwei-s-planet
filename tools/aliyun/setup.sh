#!/bin/bash

# 应用打包时的CLI环境配置脚本
# 该脚本在构建应用时被调用，确保CLI工具被正确包装

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
BUILD_DIR="${BUILD_DIR:-.}"

echo "=== 应用打包: 阿里云CLI集成 ==="
echo "Project Root: $PROJECT_ROOT"
echo "Build Dir: $BUILD_DIR"
echo ""

# 配置变量
OS_TYPE=$(uname -s)
ALIYUN_HOME="$HOME/aliyun"
ALIYUN_BIN="$ALIYUN_HOME/bin/aliyun"

# 步骤1: 检查CLI是否已安装
echo "步骤1: 检查阿里云CLI..."
if [[ ! -f "$ALIYUN_BIN" ]]; then
  echo "❌ 阿里云CLI未安装，正在安装..."
  bash "$SCRIPT_DIR/install.sh"
  if [[ ! -f "$ALIYUN_BIN" ]]; then
    echo "❌ 阿里云CLI安装失败！"
    exit 1
  fi
fi

echo "✓ 阿里云CLI已就绪: $ALIYUN_BIN"
echo ""

# 步骤2: 配置macOS应用包
if [[ "$OS_TYPE" == "Darwin" ]]; then
  echo "步骤2: 配置macOS应用资源..."

  # 找到app bundle路径
  APP_BUNDLE=$(find "$BUILD_DIR" -name "*.app" -type d 2>/dev/null | head -1)

  if [[ -n "$APP_BUNDLE" ]]; then
    RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
    TOOLS_DIR="$RESOURCES_DIR/tools"

    mkdir -p "$TOOLS_DIR"

    # 复制CLI工具和配置
    echo "  复制CLI工具到: $TOOLS_DIR"
    cp "$ALIYUN_BIN" "$TOOLS_DIR/" || true
    cp -r "$ALIYUN_HOME/etc" "$TOOLS_DIR/" 2>/dev/null || true

    # 创建包装脚本
    cat > "$TOOLS_DIR/aliyun-wrapper.sh" << 'EOF'
#!/bin/bash
# 应用内置CLI包装脚本

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ALIYUN_CLI="$SCRIPT_DIR/aliyun"
ALIYUN_HOME="$SCRIPT_DIR"

# 设置环境变量
export PATH="$SCRIPT_DIR:$PATH"
export ALIYUN_CLI_HOME="$ALIYUN_HOME"

# 执行CLI命令
exec "$ALIYUN_CLI" "$@"
EOF
    chmod +x "$TOOLS_DIR/aliyun-wrapper.sh"

    echo "✓ macOS应用资源配置完成"
  fi
fi

echo ""
echo "=== 打包集成完成 ==="
echo ""
echo "环境信息:"
echo "  CLI版本: $("$ALIYUN_BIN" version 2>/dev/null | head -1)"
echo "  安装位置: $ALIYUN_BIN"
echo ""
