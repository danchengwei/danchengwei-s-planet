# EMAS小助手

面向移动端研发与质量的 **桌面端辅助工具**（Flutter / macOS 为主）。在本机通过 **阿里云 EMAS AppMonitor OpenAPI**（`GetIssues` / `GetIssue`）拉取崩溃、ANR 等聚合数据，**无需自建后端**；并集成 **GitLab 堆栈检索**、**OpenAI 兼容大模型**（单条分析、Top 列表批量、勾选串联摘要）、**HTML / 完整报告导出**，以及 **`crash-tools://` 协议**唤起本机 Agent（剪贴板 / CLI）。

**多项目工作区**：每个项目独立保存 EMAS、GitLab、LLM、MCP、Agent 等配置，本地加密落盘；可选启动时进入项目选择页。适合日常对照控制台、快速筛问题、结合仓库与大模型做分析与留档。

> 说明：macOS 安装包/菜单显示名称由 `macos/Runner/Configs/AppInfo.xcconfig` 的 `PRODUCT_NAME` 决定（当前可能与「EMAS小助手」不同，可自行改成一致）。

---

## 能做什么（摘要）

| 方向 | 能力 |
|------|------|
| EMAS | 问题列表分页、单条详情、时间范围与可选 Name 筛选；工作台含实时概览、崩溃子类（崩溃/ANR/卡顿/异常）、性能入口 |
| 研发协作 | GitLab 多仓库：按堆栈关键词搜索 blobs、补充 commits 上下文写入 AI 提示词 |
| 大模型 | 配置任意 OpenAI 兼容 Chat API；详情/快析、Top N 逐条、勾选批量（同批摘要串联）、侧栏多轮对话 |
| 交付物 | 简易 HTML 报告、完整报告包（`index.html` + `manifest.json` + `payloads/*.json`） |
| 调试体验 | 配置中可开启 **崩溃列表 Mock 数据**（无需 AK，预览列表/翻页/详情 UI） |
| 本地测试 | 支持 `crash-tools-test-config.json` 覆盖配置（见 `crash-tools-test-config.sample.json`） |

更细的交互、MCP 导出、控制台 URL 模板、加密存储与安全策略等，见下文「附录」或应用内配置页说明。

---

## 环境要求

- [Flutter](https://flutter.dev/) 稳定版，`flutter doctor` 中 **macOS 桌面**可用。
- **Xcode**（macOS），建议执行过一次：`xcodebuild -runFirstLaunch`
- **CocoaPods**：`brew install cocoapods`，并保证 `pod` 在 `PATH` 中（如 `export PATH="/opt/homebrew/bin:$PATH"`）

首次克隆后：

```bash
cd crashTools
flutter pub get
cd macos && pod install && cd ..
```

---

## 构建与运行

在工程根目录（含 `pubspec.yaml` 的 `crashTools`）执行：

```bash
cd crashTools
flutter pub get
```

### 命令行（推荐日常开发）

```bash
# 调试运行（热重载）
flutter run -d macos

# 或使用脚本（等价于上一行）
./run_macos.sh

# 打开已构建的 Debug .app（无热重载；若无产物会先 build）
./run_macos.sh open
```

仅编译、不启动：

```bash
flutter build macos          # Release
flutter build macos --debug  # Debug
```

Debug 产物示例路径：`build/macos/Build/Products/Debug/<PRODUCT_NAME>.app`（名称以 `AppInfo.xcconfig` 为准）。

### VS Code / Cursor

1. 打开文件夹 `crashTools`。
2. 命令面板 **Flutter: Select Device** → 选 **macos**。
3. 运行 `lib/main.dart` 或使用 `.vscode/launch.json` 中的 **EMAS工具 (macOS Debug / Profile / Release)**。

### Xcode

1. 打开 **`macos/Runner.xcworkspace`**（不要用单独的 `.xcodeproj`）。
2. Scheme **Runner**，目标 **My Mac**，**⌘R** 运行，**⌘B** 编译。

### 其他桌面平台

```bash
flutter build windows
flutter build linux
```

---

## 使用前要配置什么

按**当前项目**在侧栏 **配置** 中填写并 **保存**（会写入加密工作区）：

- **拉取 EMAS 列表/详情**：AccessKey ID/Secret、Region、AppKey、平台 Os、BizModule（工作台子模块会临时覆盖 Biz）。
- **AI / GitLab**：按需填写；LLM 与 GitLab 地址须为 **HTTPS**。

可选：控制台总入口与单条问题 URL 模板、GitLab 多仓库、MCP 导出、本地 Agent、崩溃 Mock 开关等。

---

## 附录

### 目录结构（Dart）

| 路径 | 说明 |
|------|------|
| `lib/aliyun/` | ACS4 签名、EMAS RPC（`emas_appmonitor_client.dart`） |
| `lib/services/` | GitLab、LLM、报告、工作区加密、配置仓库、Mock 数据等 |
| `lib/models/` | `ToolConfig`、多项目 `ProjectsWorkspace` 等 |
| `lib/ui/` | 主导航、项目中心、工作台、列表/详情、配置、MCP |

### 工作区与安全（摘要）

- 多项目配置保存在应用支持目录下的 **`crash-tools-workspace.json`**（加密）；密钥文件 **`.crash-tools-workspace.key`** 同目录，请自行备份，丢失密钥将无法解密工作区。
- 保存前会校验 LLM / GitLab 为 **HTTPS**；EMAS 等请求遇限流或 5xx 时客户端会做有限次退避重试。

### 自定义协议 `crash-tools://`

HTML「去处理」等会尝试唤起本应用；macOS 已在 `Info.plist` 注册 scheme。使用 Xcode 调试原生工程时请打开 **`Runner.xcworkspace`**；若启用 macOS App Sandbox，应用内可能无法探测本机 CLI，与 `macos/Runner` 下 entitlements 配置有关。

### EMAS 控制台链接模板（提示）

控制台地址常以 `https://emas.console.aliyun.com/apm/{空间ID}/{应用ID}/{平台段}/crashAnalysis/{子模块}` 等形式出现。在 **配置 → 单条问题 URL 模板** 中可使用占位符 `{digest}`、`{osCode}`、`{bizConsole}` 等（具体以应用内说明为准），参数名需与你控制台实际查询字符串一致。

### 参考链接

- [Flutter 桌面](https://docs.flutter.dev/platform-integration/desktop)
- [在 macOS 上开发 Flutter 应用](https://docs.flutter.dev/platform-integration/macos/building)
- [阿里云 AppMonitor / emas-appmonitor OpenAPI](https://next.api.alibabacloud.com/product/emas-appmonitor)
- [GetErrors API 官方文档](https://api.aliyun.com/api/emas-appmonitor/2019-06-11/GetErrors?RegionId=cn-shanghai) - 获取错误列表
- [GitLab Search API](https://docs.gitlab.com/ee/api/search.html)

---

*包名 `crash_emas_tool` 为 Flutter 工程标识；产品对外称呼：**EMAS小助手**。*
