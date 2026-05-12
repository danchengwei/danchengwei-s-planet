---
name: mr-code-optimization-review
description: 以「基准分支顶点 vs 当前分支顶点」为主：`git diff develop HEAD`（两点）；辅以可选三点对比说明；批量拉取 business / business-base / library / buildproperties 等子仓与壳工程 diff；只评变更行。输出 Markdown 与 JSON。
---

# MR 代码变更审查与优化（精简版）

## 何时使用

- **本技能为 MR 评审与「代码优化」的唯一约定入口**：凡用户提到 MR、Merge Request、代码评审、审查 diff、**代码优化**、**mr 优化**、基于变更的优化等，**一律按本技能执行**；不要在项目里另建平行 rule/skill 重复同一套要求。
- **默认先走「多模块工作流」**（见下节）：**一次性**拉齐各模块的 `git diff` 后再做审查；禁止与用户「一个模块一轮」边聊边单独跑 Git。

## 网校主工程（xueersiwangxiao）模块路径清单

以下路径均**相对主工程根目录 `ROOT`**（与 `settings.gradle` 同级，即壳 **xueersiwangxiao**）。批审 MR 时，完整路径为 `ROOT/<路径>`；每个路径是否为独立 Git 子仓以目录下是否存在 **`.git`** 为准（清单随工程演进可能新增目录，缺失项用 `find` 补全）。

### 壳（主工程根）

| 路径 | 说明 |
|------|------|
| `.` | 主 Git 仓库，含 `app`、`scripts`、`settings.gradle`、`build.gradle` 等 |

### buildproperties（配置模块子仓）

| 路径 | 说明 |
|------|------|
| `buildproperties` | 根下独立子仓，`modules.gradle` 等（勿与主仓内其他目录混淆） |

### common（单仓）

| 路径 | 说明 |
|------|------|
| `common` | **单一** Git 仓库，无 `common/*` 多级子仓列表；批处理时路径就是 `common` |

### business-base/

`business-base/<下表之一>`：

advertmanager, audio, browser, cloud, collect, contentbase, contentcommon, home, livebasics, liveframework, login, player, sharedresources, unitybridge, verticalresource, xesprivacy

### business/

`business/<下表之一>`：

addressmanager, afterclassfeedback, aipartner, aitalk, aiteacher, answer, chinesepaterner, chinesepreview, chineserecite, chineseyoungguide, contentcenter, creative, diandu, discover, download, endictation, englishbook, englishdailyreading, englishmorningread, examquestion, exercise, freecourse, fusionlogin, goldshop, happyexplore, homeworkpapertest, instantvideo, iwriter, learningchinese, legadoread, lightclass, listenread, livebusiness, liveexperience, liverecord, livevideo, newinstantvideo, personals, publiclive, quickhandwriting, reader, readpartner, studycenter, wxreactnative, xesbooks, xesmall

### library/

`library/<下表之一>`：

analytics, bytehook, cache, calendar, cameralibrary, corebrowser, cut_video, danmaku, debugtools, frameutils, framework, hybrid, imageloader, imageprocessor, imageutil, latexlibrary, legadobook, legadorhino, libpag, logger, mediapipelib, monitor, mp3encode, network, pictureselector, share, sliver, speechonlinerecognizer, speechrecognizerdelegate, stmobilejni, suyangmanager, taldownload, talrecording, texttospeech, ucrop, uicomponent, unifylog, xcrash, xesbytedancecv, xesdebug, xeslottie, xespermission, **xesrouter**, xrsbury, xslog, xutils

（注：若本地目录名与表不一致，以 `ls "$ROOT/library"` 为准。）

### 其他根目录独立子仓（按需纳入批量）

| 路径 | 说明 |
|------|------|
| `businessinterface` | 根下独立 Git 仓库，按需与特性分支一并 diff |

## 多模块与子仓：执行顺序（强制）

在**能够运行终端**时，Agent **必须**两阶段执行：**先批量拉取 diff → 再统一分析**。不得在对话里按模块分多轮只报「某一个模块」的 Git 结果。

### 阶段 0：约定参数

- **`baseBranch`**：默认 `develop`；以用户 / MR 目标分支为准。  
- **`featureBranch`**：默认与用户截图、需求标签或 MR 一致（如 `feature/improve/customer_service_display`）；各子仓应对齐检出该分支（或用户声明的等价名）。  
- **`modulePaths`**：**相对主工程根**、且目录下存在 **`.git`** 的路径。网校工程**具体子目录名见上节《网校主工程（xueersiwangxiao）模块路径清单》**（`business/*`、`business-base/*`、`library/*`、`common`、`buildproperties`、壳 `.`、可选 `businessinterface`）。若需求标签只写模块名（如 `xesmall`），拼成 `business/xesmall`；**`xesrouter` → `library/xesrouter`**。标签名与路径不一致时用 `find "$ROOT" -type d -name '<模块名>'` 在含 `.git` 的目录中查找；找不到则在总览表写明「无本地子仓」。

### 阶段 1：一次性批量拉取（单次终端、循环完成）

在**同一次** shell 执行中（for 循环或等价脚本），对每个 `modulePaths` 条目：

1. `git -C "<ROOT>/<path>" checkout "<featureBranch>"`（失败则记录该模块「未切换成功」并仍执行下一步看当前分支）。  
2. `git -C "<ROOT>/<path>" branch --show-current`。  
3. **主 diff（默认，必跑）**：**两点 / 顶点对比**——`git diff "<baseBranch>" HEAD --stat` 与 `git diff "<baseBranch>" HEAD`（与 `git diff <baseBranch>..HEAD` 等价）。含义：**基准分支最新提交** 与 **当前检出分支最新提交** 之间的树差异；符合「当前开发分支和 develop 比」的日常表述，**避免**子仓出现「提交在 merge-base 上抵消成空树」时误报「无变更」。  
4. **辅 diff（可选，建议打在总览表备注）**：三点 `git diff "<baseBranch>"...HEAD --stat`（merge-base→HEAD，合入 MR 常见视角）。若 **三点为空而两点非空**，须在总览表 **备注**「净提交无文件差，与 develop 顶点仍有差」，避免与平台 MR 展示不一致时产生争议。  
5. 超大 diff 仅在用户同意下对路径加过滤，且须在报告声明过滤范围。

**输出格式**：每个模块用固定分隔标头打印，便于后续解析，例如：

```text
===== MR_DIFF_MODULE path=business/xesmall branch=<当前分支> =====
--- diff stat: two-dot <baseBranch> vs HEAD ---
<git diff base HEAD --stat>
--- optional: three-dot ...HEAD stat ---
<git diff base...HEAD --stat>
--- unified diff (two-dot, 审查主材料) ---
<git diff base HEAD>
===== END MR_DIFF_MODULE business/xesmall =====
```

主工程根若属于 `modulePaths` 之一，同样用 `git -C "$ROOT"`，不要与子仓拆成多轮对话执行。

**禁止**：每讲完一个模块再让用户确认才跑下一个；**应**一轮命令拉完所有模块的 stat + diff（或写入临时文件再在下一轮读取，仍算「一批拉取」）。

### 阶段 2：统一分析

- 仅基于阶段 1 拼出的**全部** diff 文本，按「核心原则」做变更行审查；按模块写 **`### 模块：<moduleId>`** 小节。  
- 报告最前：**多模块变更总览表**（路径、当前分支、**两点 stat 摘要**、可选三点 stat、若两点与三点不一致则备注）。  
- JSON 见 [reference.md](reference.md) **§8.1**。

### 仍无 diff 时

- 所有模块 **两点** `git diff <baseBranch> HEAD --stat` 均为空：再请用户粘贴 diff、MR 链接，或核对 `featureBranch` / 路径是否错误（含是否漏扫 **`library/*`、`buildproperties`**）。

### 可选：未给定路径时的补全方式

若用户未给模块列表，可用**一次**循环扫描并批量执行阶段 1：对 `business/*`、`business-base/*`、`library/*` 下**每个子目录**若存在 `.git` 则纳入；另单独纳入 **`common`**、**`buildproperties`**、**`businessinterface`**（若存在 `.git`）、壳 **`$ROOT`**；完整枚举亦可对照上节清单与 `ls` 结果。**不要**全仓拆成多轮对话执行。

## 核心原则（必读）

**对比范围与禁区（必读）**：审查对象**仅限于**阶段 1 拉取的 **两点** `git diff <baseBranch> HEAD`（或用户粘贴的等价 MR diff）中的 **`+` / `-` 行** 及读懂这些变更所需的**最少上下文**。**禁止**对 **diff 未触及** 的存量代码做逻辑分析、重构建议或「原实现不合理」类评价；此类内容 **一律不写入 `reviews`**。仅当旧代码作为 **`-` 侧**被本 MR 删除或替换，且问题与**本次删改**直接相关时，才可写入。打开完整源文件只辅助对照行号与语义，**禁止**整文件通读式「代码赏析」替代 MR 边界。

1. **只把变更行当审查主战场**：优先分析以 `+`、`-` 标记的行；上下文仅用于读懂「相对基准改了什么」，不对未改片段做扩展点评。
2. **无重要问题则少写**：若仅存在可交给格式化工具处理的问题，或没有功能/安全/性能/契约类风险，`reviews` 必须为 `[]`，报告中说明「未发现重要问题」或「仅有格式化类问题已忽略」。
3. **禁止空洞表扬**：无显著价值不写「值得表扬」；有则简短列举。
4. **合并去重**：同类问题合并为一条，列出受影响位置。
5. **节流**：默认最多输出前 10 条问题（可用占位 `{max_reviews}`，默认 10）；排序：P0 先于 P1 先于 P2；同优先级按 severity `critical` > `major` > `minor`。
6. **业务不明先问**：在报告中增加「需确认的问题」小节，列疑问与保守建议，避免武断。
7. **优化建议默认「画龙点睛」**：在**已有跑通业务**上提优化时，优先鼓励 **判空、边界、类型安全、资源释放/生命周期、日志可观测性** 等低风险加固；**不要**把「换实现路径、改反射/IPC 目标类、合并模块、改业务分支语义」当作常规优化项提出，除非属于下方「业务可改」情形。
8. **业务与契约**：主工程若依赖 **已发布 AAR/远端包**，不得默认本地源码与线上一致；评审中若建议改反射签名、跨模块入口，必须标注 **需同步发版/依赖升级**，否则标为「需确认」而非强推。
9. **业务逻辑何时可评 P0/P1 为「应改」**：仅当存在 **明显且低级** 的重大错误（如条件反了、必现 NPE、契约与文档严重不符且确认为 bug）。其余业务语义问题一律放入「需确认的问题」，不写进 `reviews` 或仅给 P2 信息类提醒。

## 审查侧重点（简表）

| 维度 | 关注什么 |
|------|----------|
| 变更逻辑 | 增删是否合理、边界与错误路径、与前后逻辑是否一致 |
| 安全 | 注入、权限、敏感数据、校验与反序列化等 |
| 质量 | 命名、结构、重复、可测性；复杂处是否需注释「为何」 |
| 提交 | 提交信息是否说明意图；变更粒度是否合适 |

优先级与「问题雷达」、忽略项、详细输出格式（含 JSON）见 [reference.md](reference.md)。

## 输出要求

1. 先给出 **Markdown 报告**（结构见 reference **§7 / §7.1**；多模块时含总览表与各 `### 模块：` 小节）。
2. 再给出 **单一 JSON 对象**，用标记包裹：

```text
__JSON_START__
{ ... }
__JSON_END__
```

3. JSON：**单模块**时顶层为 `MRReview`（`report`、`reviews`、`summary`）。**多模块**时顶层为 `MRReviewMulti`（含 `modules[]` 与聚合 `summary`），见 reference **§8.1**；每条 `Review` 建议带 `moduleId` 便于过滤。
4. 行号必须对应 **该模块 diff 中** 所评代码在新文件或旧文件中的行号；`type` 为 `new` 表示评的是 `+` 侧，`old` 表示 `-` 侧。

## 语言与风格

- 对用户说明与报告正文：**简体中文**；技术术语可保留英文。
- 语气专业、客观、可执行；问题描述写清「原因 + 影响 + 修复要点或测试建议」。

## 附加字段（可选）

当需要程序化消费时，每条 review 可按 reference 补充 `category`、`severity`、`confidence`、`rationale`、`fix`、`tests` 等字段；若与主流程冲突，以 reference 中的接口为准。
