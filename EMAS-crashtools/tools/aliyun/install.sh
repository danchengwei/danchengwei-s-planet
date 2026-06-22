#!/bin/bash

# 阿里云 CLI 安装脚本
# 支持 macOS (Intel & Apple Silicon) 和 Linux

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== 阿里云 CLI 安装脚本 ===${NC}"
echo ""

# 检测操作系统
OS_TYPE=$(uname -s)
ARCH=$(uname -m)

echo -e "${YELLOW}检测系统信息...${NC}"
echo "OS: $OS_TYPE"
echo "Arch: $ARCH"
echo ""

# 设置安装目录
INSTALL_DIR="$HOME/aliyun"
BIN_DIR="$INSTALL_DIR/bin"

# 创建安装目录
mkdir -p "$BIN_DIR"
mkdir -p "$INSTALL_DIR/etc"

echo -e "${YELLOW}安装目录: $INSTALL_DIR${NC}"
echo ""

# 根据系统下载对应版本
DOWNLOAD_URL=""
BINARY_NAME="aliyun"

case "$OS_TYPE" in
  Darwin)
    # macOS
    if [[ "$ARCH" == "arm64" ]]; then
      # Apple Silicon (M1/M2/M3)
      DOWNLOAD_URL="https://aliyun-cli.oss-cn-hangzhou.aliyuncs.com/aliyun-cli-darwin-arm64.tgz"
      echo -e "${YELLOW}检测到: macOS Apple Silicon (arm64)${NC}"
    else
      # Intel Mac
      DOWNLOAD_URL="https://aliyun-cli.oss-cn-hangzhou.aliyuncs.com/aliyun-cli-darwin-amd64.tgz"
      echo -e "${YELLOW}检测到: macOS Intel (amd64)${NC}"
    fi
    ;;
  Linux)
    # Linux
    if [[ "$ARCH" == "x86_64" ]]; then
      DOWNLOAD_URL="https://aliyun-cli.oss-cn-hangzhou.aliyuncs.com/aliyun-cli-linux-amd64.tgz"
      echo -e "${YELLOW}检测到: Linux x86_64${NC}"
    elif [[ "$ARCH" == "aarch64" ]]; then
      DOWNLOAD_URL="https://aliyun-cli.oss-cn-hangzhou.aliyuncs.com/aliyun-cli-linux-arm64.tgz"
      echo -e "${YELLOW}检测到: Linux ARM64${NC}"
    else
      echo -e "${RED}不支持的架构: $ARCH${NC}"
      exit 1
    fi
    ;;
  *)
    echo -e "${RED}不支持的操作系统: $OS_TYPE${NC}"
    exit 1
    ;;
esac

echo ""
echo -e "${YELLOW}下载 URL: $DOWNLOAD_URL${NC}"
echo ""

# 检查是否已安装
if [[ -f "$BIN_DIR/aliyun" ]]; then
  CURRENT_VERSION=$("$BIN_DIR/aliyun" version 2>/dev/null | head -1 || echo "unknown")
  echo -e "${GREEN}✓ 阿里云CLI已安装${NC}"
  echo "  版本: $CURRENT_VERSION"
  echo ""
  read -p "是否重新安装? (y/n) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "跳过安装"
    exit 0
  fi
fi

# 下载和安装
echo -e "${YELLOW}下载阿里云CLI...${NC}"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cd "$TEMP_DIR"
if ! curl -fsSL -o aliyun.tgz "$DOWNLOAD_URL"; then
  echo -e "${RED}下载失败！${NC}"
  exit 1
fi

echo -e "${YELLOW}解压文件...${NC}"
tar -xzf aliyun.tgz

# 找到可执行文件并复制
if [[ -f "aliyun" ]]; then
  cp aliyun "$BIN_DIR/"
  chmod +x "$BIN_DIR/aliyun"
elif [[ -f "aliyun/aliyun" ]]; then
  cp aliyun/aliyun "$BIN_DIR/"
  chmod +x "$BIN_DIR/aliyun"
else
  echo -e "${RED}找不到可执行文件！${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}✓ 安装成功！${NC}"
echo ""

# 验证安装
echo -e "${YELLOW}验证安装...${NC}"
if "$BIN_DIR/aliyun" version; then
  echo -e "${GREEN}✓ 验证通过${NC}"
else
  echo -e "${RED}✗ 验证失败${NC}"
  exit 1
fi

# 设置PATH提示
echo ""
echo -e "${YELLOW}配置PATH环境变量:${NC}"
echo ""
echo "将以下内容添加到 ~/.zshrc 或 ~/.bash_profile:"
echo ""
echo "export PATH=\"$BIN_DIR:\$PATH\""
echo ""

# 自动添加到 shell 配置
SHELL_CONFIG=""
if [[ -f "$HOME/.zshrc" ]]; then
  SHELL_CONFIG="$HOME/.zshrc"
elif [[ -f "$HOME/.bash_profile" ]]; then
  SHELL_CONFIG="$HOME/.bash_profile"
elif [[ -f "$HOME/.bashrc" ]]; then
  SHELL_CONFIG="$HOME/.bashrc"
fi

if [[ -n "$SHELL_CONFIG" ]] && ! grep -q "export PATH.*aliyun" "$SHELL_CONFIG"; then
  echo "" >> "$SHELL_CONFIG"
  echo "# Aliyun CLI Path" >> "$SHELL_CONFIG"
  echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$SHELL_CONFIG"
  echo -e "${GREEN}✓ 已自动添加到 $SHELL_CONFIG${NC}"
fi

echo ""
echo -e "${GREEN}=== 安装完成 ===${NC}"
echo ""
echo "接下来请运行:"
echo "  source ~/.zshrc  (或 source ~/.bash_profile)"
echo "  aliyun configure set --profile default --access-key-id <KEY> --access-key-secret <SECRET> --region cn-shanghai"
echo ""
