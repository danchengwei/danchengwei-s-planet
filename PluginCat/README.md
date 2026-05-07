# 🐱 网页电子宠物（Web Pet）

一款基于 **Vite + CRXJS + TypeScript + Manifest V3 + Content Script** 的 Chrome 扩展。
它在任意网页的右下角生成一只可拖动的小宠物，内部跑一个**轻量 Agent**（ReAct 循环）：

- 和它对话，它能 **观察 → 思考 → 执行 → 再观察**，通过多步动作帮你完成任务
- 读 **DOM 元素标签**（用索引精确定位）、读**可见正文**、查**最近网络请求**（PerformanceObserver）
- **隐私屏蔽**：密码 / 信用卡 / 手机验证码 / `sk-...` / JWT / URL 里的 token&key 等敏感信息永远看不到，也拒绝向敏感字段写入

### 支持的模型服务商

所有服务商都走 OpenAI 兼容协议，`baseUrl` 已经内置，用户 **只需要填 API Key**：

| 服务商 | 默认模型 | baseUrl |
| --- | --- | --- |
| 腾讯混元 Hunyuan | `hunyuan-lite` | `https://api.hunyuan.cloud.tencent.com/v1/chat/completions` |
| 智谱 GLM | `glm-4-flash` | `https://open.bigmodel.cn/api/paas/v4/chat/completions` |
| DeepSeek | `deepseek-chat` | `https://api.deepseek.com/chat/completions` |
| OpenAI (GPT) | `gpt-4o-mini` | `https://api.openai.com/v1/chat/completions` |

如果想换用该服务商的其它模型（比如 `glm-4-air`、`deepseek-reasoner`、`gpt-4o`…），在"模型名"输入框里填即可，留空就用默认。

---

## 目录结构

```
PluginTest/
├── manifest.config.ts           # CRXJS manifest (MV3)
├── vite.config.ts
├── tsconfig.json
├── package.json
└── src/
    ├── background/index.ts      # Service Worker：ASK 转发模型 / TEST 做连通性检测
    ├── content/
    │   ├── index.ts             # Content Script 入口（顺带启动 PerformanceObserver）
    │   ├── pet.ts               # 宠物 UI + Agent 执行循环（最多 6 步）
    │   ├── observe.ts           # DOM 索引化、可见正文、网络请求、全量隐私脱敏
    │   ├── actions.ts           # observe/network/scroll/click/fill/read/wait/finish
    │   └── pet.css
    ├── options/                 # 设置页（服务商下拉 + Key + 保存即测）
    │   ├── index.html
    │   ├── main.ts
    │   └── options.css
    └── shared/
        ├── providers.ts         # 4 家服务商的 baseUrl / 默认模型 / 文档链接
        ├── llm.ts               # OpenAI 兼容调用 + AGENT_SYSTEM_PROMPT + parseAgentOutput
        └── types.ts             # ChatMessage / PetAction / AgentStep / Observation…
```

## 它怎么"自动化"？— Agent 循环

每次你提问，Content Script 会跑一个最多 **6 步** 的 ReAct 循环：

```
┌─ 观察页面（DOM 索引化 + 可见正文 + 最近网络请求） ──┐
│                                                   │
│   user 说: "帮我把这条评论发出去"                   │
│                                                   │
│   轮 1  → 模型 {"action": {"kind":"observe"}}      │
│   轮 2  → 模型 {"action": {"kind":"fill","index":5,"value":"..."}}
│   轮 3  → 模型 {"action": {"kind":"click","index":8}}
│   轮 4  → 模型 {"action": {"kind":"finish","reply":"发出去啦~"}}
└────────────────────────────────────────────────────┘
```

每一轮模型都只输出**严格 JSON**：`{thought, reply, action}`。扩展解析 action → 在页面执行 → 把新观察作为下一轮 `user` 消息喂回给模型。UI 上你能看到每一步的 thought / action / result。

### 可用 Action

| Action | 说明 |
| --- | --- |
| `observe` | 重新构建"可交互元素 + 可见正文"快照 |
| `network` | 查看最近 20 条资源请求（仅 URL / 类型 / 耗时 / 状态，无 header/body） |
| `scroll` | `to: "top" \| "bottom" \| 像素数` |
| `click` | `index: n`（必须是最近一次 observe 里出现的索引） |
| `fill`  | `index: n, value: "文本"`（敏感字段会被强制拒绝） |
| `read`  | `index: n`，返回该元素的完整文字（同样拒敏） |
| `wait`  | `ms: <=3000` 让异步页面有时间反应 |
| `finish`| `reply: "..."` 结束本轮，把最终话交给用户 |

### 隐私屏蔽规则

| 做了什么 | 怎么做的 |
| --- | --- |
| 密码 / 信用卡 / CVV / 验证码 | `input[type=password]` / `autocomplete=cc-*` / `one-time-code` 等一律标 `⚠️ REDACTED`，模型看不到值，`fill` / `read` 也被拒绝 |
| id/name/class/aria-label 含 `password\|token\|secret\|apikey\|密码\|密钥\|身份证` 等关键词 | 同上，整块字段直接 REDACTED |
| 可见正文里出现形如 `sk-xxx…` / JWT / 32+ 位高熵串 | 正则替换为 `***` |
| URL 查询参数名匹配 `token\|apikey\|access_token\|secret\|password\|auth\|session\|code\|signature` | 值替换成 `***`，URL 里 `user:pass@host` 的 pass 部分也抹掉 |

模型拿到的"页面观察"长这样（已脱敏）：

```
[可交互元素 14 个]
[0] button "登录"
[1] button "注册"
[2] input[type=email] ph="邮箱" val="me@example.com"
[3] input[type=password] ⚠️ REDACTED(敏感字段，禁 fill/read)
[4] a "忘记密码？" href=https://example.com/forgot?token=***
...
```

## 在 Chrome 中安装

### 1. 构建产物

```bash
cd PluginTest
npm install          # 首次执行
npm run build        # 产物输出到 dist/
```

构建完成后 `dist/` 目录下会有 `manifest.json`、`service-worker-loader.js`、`src/`、`assets/` 等文件。

### 2. 打开 Chrome 扩展管理页

在 Chrome 地址栏输入：

```
chrome://extensions
```

### 3. 开启「开发者模式」

扩展管理页的 **右上角** 有一个 `开发者模式 / Developer mode` 开关，打开它。

### 4. 加载已解压的扩展

点左上角的 **加载已解压的扩展程序 / Load unpacked**，在弹出的文件选择器中选择本项目的 **`dist/` 目录**（不是项目根目录）。

> ⚠️ 选错目录会报 `Manifest file is missing or unreadable`，一定要选 `dist/`。

### 5. 配置模型与 API Key

首次加载扩展后浏览器会自动打开设置页。如果没弹出，也可以通过以下任一方式打开：

- 工具栏上的 🧩 拼图按钮 → 找到「网页电子宠物」→ 点击图标（可先固定到工具栏）；
- 或在 `chrome://extensions` 中找到本扩展 → **详细信息 → 扩展程序选项**。

在设置页：

1. **服务商**：下拉选择 Hunyuan / GLM / DeepSeek / OpenAI；
2. **模型名**：留空即用默认（每家都选了较便宜的模型），也可填写同家的其它模型名；
3. **API Key**：粘贴对应服务商的 Key（点"→ 去 XX 获取 API Key"直接跳到官方控制台）；
4. 点 **完成**。

扩展会自动做一次最小模型调用来测试连通性：

- ✓ 成功：弹出"配置成功"窗口，可以点「去一个网页试试」打开一个示例页看小猫；
- ✗ 失败：弹出错误弹窗，通常是 Key 错误/过期、没开通服务、或者网络问题，按提示改完再点完成即可。

> Key 只保存在 `chrome.storage.sync`，不会上传到任何第三方。

### 6. 开始使用

打开任意普通网页（例如 `https://www.zhihu.com`），右下角即可看到小橘猫 🐱。点它唤出对话框即可提问或下指令；按住小猫可以把它拖到任意位置。

> ⚠️ 如果你在**配置之前**就已经打开了网页，content script 不会追溯注入。需要**刷新那些网页**才能看到小猫。

## 开发模式（边改边看）

```bash
npm run dev
```

这会启动 Vite 的 watch + CRXJS 热更新，同样通过 **加载已解压的扩展程序 → 选 `dist/`** 安装。代码改动会自动刷新 content script；service worker 有时需要在 `chrome://extensions` 手动点一下 🔄。

调试日志：

- Content script：被注入页面上 F12 → Console。
- Background service worker：`chrome://extensions` → 本扩展卡片 → 点 **Service Worker** 链接打开专用 DevTools。

## 打包发布

```bash
npm run pack          # 产出 web-pet.zip，可直接上传 Chrome Web Store
```

## 使用示例

点右下角的小猫，弹出对话框：

| 你说 | 宠物一般会 |
| --- | --- |
| "这个页面讲了什么？" | 1 步 finish，基于初始观察总结 |
| "帮我滚到底部看看有啥" | `scroll→bottom` → `observe` → finish |
| "帮我把登录按钮点一下" | `observe` → `click index=X` → finish |
| "在搜索框里填 TypeScript 然后按回车" | `fill index=X value="TypeScript"` → `click`/按钮 → finish |
| "这页最近发了什么请求？有没有失败的接口？" | `network` → finish，列最近资源请求（已脱敏） |
| "帮我登录" / "帮我输密码" | 直接 finish 拒绝（隐私约束） |

你在对话框里能看到每一步的 thought / action / result，这是 debug 和信任的关键。

## 权限说明

| 权限 | 用途 |
| --- | --- |
| `storage` | 保存 settings（provider / apiKey / model） |
| `activeTab` | 当前标签页操作 |
| `scripting` | 保留，便于后续扩展能力 |
| `host_permissions: 4 家模型 API` | 走 background 调 LLM（绕开 CORS） |
| `<all_urls>` (content script) | 在任意网页注入宠物 |

### 数据只发给谁

| 数据 | 去向 |
| --- | --- |
| DOM 元素列表 / 可见正文 / 最近网络请求摘要（脱敏后） | 你选的模型服务商 |
| 密码 / 信用卡 / 验证码 / Authorization / Cookie | **任何地方都不发**，扩展主动屏蔽 |
| API Key | 只保存在本机 `chrome.storage.sync`，调 LLM 时放 HTTP header |

## 小宠物的"情绪状态"

SVG 小橘猫有 7 种状态，由 CSS keyframes 驱动：

| 状态 | 触发时机 | 表现 |
| --- | --- | --- |
| `idle` | 默认 | 身体上下轻浮，尾巴持续摇摆 |
| `blink` | 空闲时自动随机（约 65% 概率） | 快速眨一下眼 |
| `yawn` | 空闲时自动随机（约 20% 概率）/ 从睡眠中被唤醒 | 张大嘴打哈欠 + 小伸展 |
| `sleep` | 闲置 25 秒自动入睡 | 闭眼缓慢呼吸 + 飘三个 Zzz |
| `wave` | 挂载 700ms 后 / 打开对话面板 / 从睡眠被唤醒 | 右前爪抬起挥手 + 耳朵抖动 |
| `talking` | 发送消息等待回复期间 | 身体左右摆动 + 嘴巴张合 |
| `happy` | 关闭对话面板 | 快速弹跳两下 |

交互细节：悬停头像 / 进入面板 / 聚焦输入框都会"唤醒"小猫（睡眠中会先打哈欠再醒），并重置 25s 的睡眠倒计时；状态切换时头像左侧会浮出一个心情小气泡（"嗨~"、"好困…"、"Zzz…"…）。

## 常见问题

| 问题 | 原因 / 解决 |
| --- | --- |
| 加载扩展时报 "Manifest file is missing or unreadable" | 选错了目录，必须选 `dist/`，不是项目根目录 |
| 配置完 Key 但页面上看不到小猫 | **最常见！** 已经打开过的网页需要 **刷新** 才会注入 content script。F12 控制台搜索 `[web-pet]` 能看到挂载日志 |
| 某些页面仍然看不到 | `chrome://` / `chrome-extension://` / Chrome 应用商店 / `about:blank` 等受限页面浏览器禁止注入 content script |
| 点完成弹出 "鉴权失败 (401)" | API Key 无效、复制时带了多余空格、或服务没开通；按弹窗提示改完再点完成 |
| 点完成弹出 "请求超时" | 网络或对应服务商接口有问题，稍后重试；OpenAI 在国内需自备代理 |
| 改了代码但 Chrome 里行为没变 | `chrome://extensions` 中点本扩展卡片的 🔄 刷新；必要时关掉再重新 `加载已解压的扩展程序` |
| 控制台看不到 background 日志 | 在 `chrome://extensions` 本扩展卡片上点 **Service Worker** 链接打开专用 DevTools |

## 已知限制

- 只注入顶层页面（`all_frames: false`），忽略 iframe。
- 为了不超模型上下文长度，页面正文会截断到 ~6000 字符。
- `click` / `fill` 基于可见文字 / CSS 选择器模糊匹配；复杂 SPA 的富交互组件可能匹配不到。
- `hunyuan-lite` 不支持流式展示（本实现 `stream: false`），回答会整段返回。
