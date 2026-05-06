# H5 静态页面部署指南

## 概述

本项目已将 H5 页面改为静态文件方式加载，WebView 直接从本地 assets 目录读取 HTML 文件，无需启动本地代理服务器。

## 目录结构

```
app/src/main/assets/h5/
├── index.html              # 主 HTML 文件
├── favicon.svg             # 网站图标
├── icons.svg               # SVG 图标集
└── assets/                 # 构建后的资源文件
    ├── index-*.js          # JavaScript  bundle
    └── style-*.css         # CSS bundle
```

## 开发流程

### 1. 修改 H5 代码

在 `h5/` 目录下进行 React 开发：

```bash
cd h5
npm run dev
```

### 2. 构建并部署到 Android

有两种方式：

#### 方式一：使用自动化脚本（推荐）

```bash
./deploy-h5.sh
```

该脚本会自动：
- 构建 H5 项目
- 清理旧的 assets 文件
- 复制新的构建文件到 Android assets 目录

#### 方式二：手动部署

```bash
# 1. 进入 H5 目录
cd h5

# 2. 构建项目
npm run build

# 3. 复制文件到 Android assets
cp dist/index.html ../app/src/main/assets/h5/
cp dist/assets/* ../app/src/main/assets/h5/assets/
cp dist/favicon.svg ../app/src/main/assets/h5/
cp dist/icons.svg ../app/src/main/assets/h5/
```

### 3. 运行 Android 应用

在 Android Studio 中运行应用，WebView 将自动加载本地静态页面。

## 技术细节

### WebView 配置

MainActivity 中的关键配置：

```java
private void loadH5Page() {
    // 加载本地静态 HTML 文件（无需代理服务器）
    webView.loadUrl("file:///android_asset/h5/index.html");
}
```

### Vite 构建配置

`h5/vite.config.js` 已针对 Android WebView 优化：

- **去掉 type="module"**：Android WebView 在 file:// 协议下不执行 module 类型脚本
- **去掉 crossorigin**：避免 CORS 问题
- **降级到 ES2019**：兼容旧版 WebView
- **IIFE 格式**：打包为立即执行函数，便于 file:// 协议加载

### 权限和访问

本地文件访问已配置：

```java
webSettings.setAllowFileAccess(true);
webSettings.setAllowFileAccessFromFileURLs(true);
webSettings.setAllowUniversalAccessFromFileURLs(true);
```

## 优势

✅ **无需启动本地服务器**：直接加载本地文件  
✅ **离线可用**：不依赖网络连接  
✅ **加载速度快**：无网络延迟  
✅ **简化调试**：减少网络相关错误  
✅ **生产环境友好**：可直接打包到 APK  

## 注意事项

⚠️ **每次修改 H5 代码后必须重新构建**  
⚠️ **确保 vite.config.js 配置正确**（特别是 stripScriptModuleType 插件）  
⚠️ **CSS 和 JS 文件名带 hash，每次构建会变化**  

## 故障排查

### H5 页面空白

1. 检查是否已执行 `npm run build`
2. 确认文件已复制到 `app/src/main/assets/h5/`
3. 查看 Logcat 中的 "H5Console" 和 "MainActivity" 日志

### JavaScript 不执行

1. 确认 vite.config.js 中有 `stripScriptModuleType()` 插件
2. 检查生成的 HTML 中 script 标签没有 `type="module"`
3. 确认 target 设置为 es2019 或更低

### 样式不生效

1. 确认 link 标签没有 `crossorigin` 属性
2. 检查 CSS 文件是否正确复制到 assets 目录
3. 验证 CSS 文件路径在 HTML 中正确引用

## 快速命令

```bash
# 一键构建和部署
./deploy-h5.sh

# 仅构建 H5（不部署）
cd h5 && npm run build

# 查看当前 assets 文件
ls -lh app/src/main/assets/h5/
```
