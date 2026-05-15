# 项目级开发规范（Claude Code 自动加载）

本文件从 `.cursor/rules/*.mdc` 提取并补充；Cursor `.mdc` 规则不会被 Claude Code 自动读取，因此把关键条款同步到这里。本文件覆盖的作用域是**整个工作区**（`danchengwei-s-planet/` 下的所有子项目）。

## 通用语言与交流

- **自然语言**（回答、说明、注释、commit message、PR 描述）统一使用**简体中文**；禁止翻译腔（如"作为一个...让我们..."之类机翻句式）。
- **技术术语**（API 名、类名、关键字、函数名、文件路径、错误码）保留英文原词，不翻译成中文。
- 代码里标识符（变量 / 方法 / 类 / 资源 ID）仍按各语言惯例（多数语言是英文），不要用拼音或中文。

## Bugfix / 代码修改的固定流程

做**修改与开发**类任务时，按以下顺序执行。

### 硬性禁止（最重要）

- **不得**执行 `git add`、`git commit`、`git push`。
- 仅在本地改代码与验证，提交与推送由人工决定。
- 即便用户说"完成后帮我提交一下"，也先停下来确认这和本规则是否冲突。

### 步骤

1. **同步基线**：在**仓库 Git 根目录**（以 `git rev-parse --show-toplevel` 为准）执行 `git pull`，并写清远端与分支（例 `git pull origin main`）。
2. **进入目标模块**：`cd <模块路径>`（例如 `EMAS-crashtools`、`PluginCat`）。后续编译、静态分析、测试默认在**该模块目录**下执行。
3. **创建 bugfix 分支**：在 Git 根目录执行 `git checkout -b bugfix/<简短说明>`（示例：`bugfix/emas-overview-metrics`、`bugfix/crash-list-ui`）。**确认 `git branch --show-current` 为新分支后再改代码**。
4. **修改代码**：只改与需求相关的文件，避免无关重构与扩大范围；与现有代码风格、类型、错误处理保持一致。
5. **编译与静态检查**（在模块目录）：
   - Flutter/Dart：`dart analyze` 或 `flutter analyze`，以及 `flutter test`（或项目内脚本）。
   - 其他语言：跑该模块对应的 lint / 类型检查 / 单元测试。
   - 分析器报错与失败用例**修到通过**再结束本步。
   - **本步仍不得** `git add` / `commit` / `push`。
6. **结束交付**：用简短条目列出：
   - 变更文件路径
   - 已执行的检查命令
   - 明确标注"未执行 `git add` / `commit` / `push`"

### 适用与豁免

- 适用于绝大多数修改类任务（bugfix、feature、小重构）。
- 如果用户**显式**要求"直接提交"或"帮我 push"，在执行前必须再次向用户确认"我按规则禁止这么做，你确认要覆盖规则吗？"，得到明确肯定再动。
- 纯阅读 / 分析 / 研究类任务不触发本流程。

## Android 开发强制规则

**适用范围**：仅对 Android 子项目（Java/Kotlin + `build.gradle` + `AndroidManifest.xml`）生效；非 Android 项目（如 `PluginCat` 这种 Chrome 扩展 TS/JS 项目）不适用。遇到新子项目拿不准时，先看根目录是否有 `settings.gradle` / `build.gradle` 判断。

### 1. 语言与注释

- 所有**自然语言**输出（回答、说明、commit message、Javadoc/KDoc、行内注释）使用**简体中文**。
- 技术术语保留英文原词（`ViewModel` / `LiveData` / `CoroutineScope` 这类不要翻译）。
- **必须**为新增的类、关键方法写简要中文注释（说明**职责 / 使用场景 / 线程约束 / 为什么这么写**，而不是重复代码在做什么）。
- 输出代码时附**中文使用说明**：典型调用示例、注意事项、已知限制。

### 2. 编码规范（Google Android + 阿里 Java/Kotlin）

- 命名：
  - 类 / 接口：`UpperCamelCase`；接口**不加** `I` 前缀。
  - 方法 / 变量 / 参数：`lowerCamelCase`。
  - 常量：`UPPER_SNAKE_CASE`；`companion object` 里的 `const val` 同此规则。
  - 包名：全小写，无下划线。
  - Kotlin 文件名与主类同名；单文件多顶层函数时，取能概括内容的名字。
- 资源：
  - 所有 XML 资源 ID、drawable / layout / menu / anim 文件名：**`snake_case`**。
  - 命名前缀约定：`btn_` / `iv_` / `tv_` / `et_` / `rv_` / `cl_` / `ll_` / `fl_` / `vg_`（按视图类型）；layout 文件 `activity_xxx.xml` / `fragment_xxx.xml` / `item_xxx.xml` / `dialog_xxx.xml`；drawable `ic_` / `bg_` / `selector_`。
- 方法长度尽量 ≤ 50 行（阿里规约）；超过就抽函数。
- **禁止 magic number / magic string**：数字抽 `const val`，字符串抽到 `strings.xml` 或常量。
- 格式化：优先使用 Android Studio 内置 Reformat；项目有 `ktlint` / `detekt` 配置则必须通过。

### 3. 技术栈

- **Kotlin 优先**；新代码一律 Kotlin（除非修改的是纯 Java 文件，保持语言一致）。
- **必须基于 Android 核心组件**：Context / Activity / Fragment / ViewModel / LiveData / Flow / StateFlow。Fragment 观察 LiveData 用 `viewLifecycleOwner`，不要用 `this`。
- **异步**：协程 + Flow；**禁止** `AsyncTask`、裸 `new Thread()`、`HandlerThread` 新代码（现有代码改到时再迁）。
- **UI 绑定**：`ViewBinding` / `DataBinding`；**禁止**新代码用 `findViewById`。
- **已废弃 API 替换对照**（新代码必须换）：
  - `AsyncTask` → 协程 / `Executor`
  - `startActivityForResult` → `ActivityResultContracts`
  - `SharedPreferences`（大量写场景）→ `DataStore`
  - `Handler()` 无参构造 → `Handler(Looper.getMainLooper())`
  - `onActivityCreated` → `onViewCreated` + `viewLifecycleOwner`
- **Jetpack 优先**：Navigation / Room / Paging / WorkManager / Hilt（按项目既有方案）。

### 4. 健壮性（必须覆盖）

- **空指针**：
  - `?.` / `?:` / `requireNotNull(x) { "原因..." }` 为主。
  - `!!` **仅用于"此处 null 是 bug，应当崩溃暴露"的场景**，且必须写注释说明为什么不可能为 null。
  - `lateinit` 只用于 DI 注入 / View 字段；其他场景用 `by lazy` 或可空属性。
  - Java 字段与 Kotlin 交互时，**显式**假定为 `Platform type`，强制判空；`@Nullable` / `@NonNull` 注解跟上。
- **生命周期**：
  - 协程启动用 `lifecycleScope` / `viewLifecycleOwner.lifecycleScope`；长任务配 `repeatOnLifecycle(Lifecycle.State.STARTED)`。
  - 监听器、EventBus 注册必须在对应 `onDestroy` / `onDestroyView` 解绑。
  - Cursor / InputStream / BufferedReader 等 Closable 用 `use { }`。
- **权限**：
  - 用 `ActivityResultContracts.RequestPermission` / `RequestMultiplePermissions`。
  - 先 `shouldShowRequestPermissionRationale` 解释再请求；处理"永不再询问"——引导到设置页。
  - 危险权限（相机 / 定位 / 录音 / 存储）在 Manifest 声明 + 运行时请求 + 用户拒绝后有 fallback 或明确提示。
- **配置变更**：
  - 旋转、字体缩放、深色模式、分屏都要考虑；数据用 `ViewModel` 保存，UI 瞬时状态用 `rememberSaveable` / `onSaveInstanceState`。
  - 不要无脑 `android:configChanges` 吃掉所有变更。
- **资源释放**：Bitmap / MediaPlayer / Camera / 定位监听 / 传感器 等必须显式 release / unregister。

### 5. 类型安全与空边界（在 §4 基础上补充）

- 强转前**永远**先 `is` 判断，或用 `as?` + 空兜底分支；不要让 `ClassCastException` 在线上首见。
- 集合访问：`list.getOrNull(i)` / `list.firstOrNull()`；Map：`map[key] ?: default`。
- 避免 `Any` 滥用；能写泛型就写泛型。
- 与后端契约：
  - 所有后端字段假定**可空**除非接口文档写明 non-null；Gson / Moshi / kotlinx.serialization 的默认值配好。
  - 字段名对齐接口，不要靠注解改名掩盖前端拼错。
- 数字运算：int 除法、long / int 混算、浮点比较都要想边界；金额用 `BigDecimal`，**禁止** `double`。

### 6. 业务上下文与 bug 预防

- 写代码前**读上下文**：被改函数的调用方、相邻模块的使用姿势、相关业务文档（若有）。
- 输出代码前**主动列出潜在边界**并在注释或说明里写明至少以下几类（按相关性选 2-3 项）：
  - 空 / 空集合 / 超长字符串；
  - 并发竞态 / 多次进入 / 快速点击；
  - 网络失败 / 超时 / 弱网重复返回；
  - 慢速设备 / 低内存 / 后台被杀；
  - Activity 重建 / Fragment `detached` / View 已销毁。
- 业务分支语义不确定时**先问用户**，不要自作主张改逻辑。

### 7. 资源引用（**不要硬编码**）

- **用户可见文案** → `strings.xml`；多语言需要则同步 `values-en/strings.xml` 等。
- **颜色** → `colors.xml`；优先走主题属性 `?attr/colorPrimary` / `?attr/colorOnSurface` 以便换肤 / 深色模式。
- **尺寸** → `dimens.xml`（padding / margin / textSize）；字体 `sp`，其他 `dp`。
- **样式 / 主题** → `styles.xml` / `themes.xml`。
- **形状 / 选择器** → 独立 `drawable/` XML，不要在布局里内联一次性 drawable。
- **例外**（允许硬编码）：
  - 仅开发者可见的 `Log` tag / 调试字符串；
  - `Intent` action / extras key（可抽常量但不必进 `strings.xml`）；
  - 单元测试里的断言字符串。

### 8. 字符编码

- 所有源文件 **UTF-8 (无 BOM)**；换行 `LF`（`.bat` / Windows 脚本除外）。
- 禁止文件内出现 `U+FFFD`（替代字符）、smart quotes（`"" ''`）、中文全角冒号 `：` 混在**代码标识符**或**资源 key**里（文案里用是可以的）。
- 新建文件前如果项目根没有 `.editorconfig`，保持和该模块既有文件的编码 / 换行一致。

### 9. 输出格式与交付

- 输出代码时按以下顺序给出：
  1. **中文说明**（这段代码解决什么问题、关键设计决策）；
  2. **代码**（带中文 KDoc / 行注释，注释写 why 不写 what）；
  3. **使用示例**（调用方视角的 2-5 行片段）；
  4. **边界 / 注意事项**（从 §6 列出的那几点里挑相关的说）。
- 涉及新依赖、新权限、新 Manifest 声明时**显式**列出，不要埋在 diff 里。

---

## 非 Android 子项目

目前工作区里的非 Android 项目（以 `PluginCat` 的 Chrome 扩展为代表）**不套用** §Android 规则；但 §通用语言与交流、§Bugfix 流程 这两节仍然生效。Chrome 扩展遵循扩展自己的规范（Manifest V3 / 隔离世界 / `chrome.*` API 等）。
