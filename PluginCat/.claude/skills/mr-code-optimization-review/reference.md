# MR 审查参考细则（精简）

## 1. 变更行审查清单

**范围**：一切结论须锚定在 **两点** **`git diff <baseBranch> HEAD`**（与 `<baseBranch>..HEAD` 等价；或用户给出的等价 MR diff）内；即 **基准分支顶点** 与 **当前分支顶点** 之间的树差异中的 **`+` / `-` 行**。**三点** `base...HEAD` 仅作合入视角补充，**审查正文以两点 diff 为准**（避免 merge-base 上提交抵消导致三点为空、误以为无改动）。不得脱离该范围评价「文件里原来的逻辑」。

- **新增（`+`）**：是否正确、是否需校验、是否引入副作用或重复请求、是否破坏不变量。
- **删除（`-`）**：是否误删防护逻辑、资源释放、兼容分支或文档约定的行为。
- **连贯性**：仅评估 **本次变更** 是否自洽、是否覆盖本 MR 涉及路径；不因未改动旧代码路径「不完善」而开单。

**禁止**：把 **diff 未触及** 的存量代码单独列为问题；不把「通读全文件的优化想法」当作 MR 审查结果。

## 2. 优先级（必须输出 `priority`）

- **P0**：安全漏洞、权限绕过、敏感泄露、注入/路径遍历/不安全反序列化；崩溃、数据损坏/丢失、强一致破坏；关键 API/协议/Schema 不兼容；支付/登录/鉴权等关键路径严重缺陷。
- **P1**：明显易错边界、并发竞态、热路径性能退化、资源泄露风险、错误处理缺失、可测性不足导致线上难排障。
- **P2**：可读性、日志观测、非热路径小优化、测试补强。

**映射建议**：`critical` 倾向 P0，`major` 倾向 P1，`minor` 倾向 P2；不确定时取更高优先级。

## 3. 问题雷达（优先指出并给可执行建议）

合并相似项，避免刷屏：

- i18n：逻辑依赖中文 → 枚举 + 资源。
- 空值与 Map：缺兜底 → 默认值或显式分支。
- 魔法数/字符串 → 常量或配置。
- `console.log` 残留 → 规范日志或移除。
- 嵌套过深 → 早返回、拆函数、async/await。
- 过度 try/catch → 精准捕获或向上传递。
- 参数过多 → 对象参数或 DTO。
- N+1、重复计算 → 批处理、缓存、惰性。
- 并发共享状态 → 同步、幂等、原子操作。

## 4. 「代码优化」类建议的边界（与 MR 审查共用）

当用户要的是 **优化、重构建议** 而非单纯挑错时，优先推荐下列 **低风险** 项；高风险项除非配合升级计划，否则放入「需确认」或不写 `reviews`：

| 鼓励提出（点睛） | 默认不要当「优化」强推 |
|------------------|-------------------------|
| 判空、集合/回调边界 | 更换业务流程、改功能开关含义 |
| 泛型与类型安全、避免不安全强转 | 反射目标类/方法签名变更（未同步 AAR 时极高风险） |
| 流、Body、Cursor、订阅的关闭与取消 | 为「更优雅」整体换调用链 |
| 与已发布 API/协议/序列化字段保持一致 | 仅风格偏好的大范围重命名/拆文件 |

## 5. 不要报告的内容

以下内容**不要**写入 `reviews`：

- **未出现在本次 diff 中的旧逻辑**：包括但不限于「旁边这段老代码也该改」「整个类设计不好」等，除非该段老代码**作为 `-` 行被本 MR 删除/替换**且问题与本次删改直接相关。
- 纯风格：空行、行尾空格、引号、分号、缩进、行宽、import 顺序、尾逗号等，且可被 Prettier/ESLint 自动修复。
- 纯格式化导致的 diff、无语义变化。
- 仅注释/文案标点排版（不影响行为）。

若变更仅含上述内容：`reviews: []`，可在总结中写「存在可由格式化工具修复的差异，已忽略」。

## 6. 产出为 review 的必要条件（满足其一）

- 功能/逻辑缺陷或边界遗漏。
- 安全或敏感信息风险。
- 明显性能、资源、并发问题。
- 违反重要类型/API 契约，可能导致运行时错误。
- 架构导致可维护性显著下降。

## 7. Markdown 报告结构

```markdown
## MR 代码审查报告

### 变更概览
- 提交人：{userName}
- 项目：{projectName}
- MR 链接：[查看详情]({mergeUrl})
- 监听事件：{eventType}
- 目标分支：{targetBranch}
- 新增代码行数：[从 diff 统计]
- 删除代码行数：[从 diff 统计]
- 主要变更文件：[关键文件]

### 发现的问题（按优先级排序）
使用纯文本序号 **【1】【2】…**，标题格式：**【N】 [P0|P1|P2] issueHeader**（issueHeader 尽量不超过 6 个字）。
同一连续列表内不要插入小标题分组；每条下用子弹列出：问题描述、影响范围、建议方案、代码位置（文件:行号）。

### 需确认的问题（可选）
- 疑问与可能影响
- 保守建议

### 值得表扬的地方（可选，无则省略）

### 评分详情
- 变更代码质量：XX/60
- 安全风险控制：XX/25
- 代码规范遵循：XX/10
- 提交信息质量：XX/5
- **总分：XX**
```

### 7.1 多模块报告（在技能「多模块与子仓：执行顺序」触发时）

在报告 **「MR 代码审查报告」标题下、第一个模块小节之前** 增加：

```markdown
### 多模块变更总览
| 模块 | 仓库路径 | 两点 diff（develop 顶点↔HEAD）文件/行数 | 三点 …HEAD stat（可选） | 备注 |
|------|----------|------------------------------------------|-------------------------|------|
| xesmall | business/xesmall | 7 文件 +39/-13 | 同左或略异 | 独立子仓 |
| browser | business-base/browser | 有变更 | 若为空则注「净提交无文件差」 | |
| ... | library/…、buildproperties | … | … | 壳为 ROOT |

### 模块：xesmall
（以下按 §7 的「变更概览 / 问题 / 需确认 / 评分」结构写全。）

### 模块：xesrouter
...
```

- **全局「需确认」**：可放在所有模块评分之后，汇总跨模块契约、发版顺序、子仓分支不一致等问题。

## 8. JSON 结构（程序化）

**包裹标记**：`__JSON_START__` 与 `__JSON_END__` 之间为**单行或多行均可**的纯 JSON。

```typescript
interface Review {
  newPath: string;
  oldPath: string;
  type: 'old' | 'new'; // old 对应删除侧行号，new 对应新增侧行号
  startLine: number;
  endLine: number;
  issueHeader: string; // 建议不超过 6 个字
  issueContent: string;
  priority: 'P0' | 'P1' | 'P2';
  moduleId?: string; // 多模块时建议必填，与「模块：<moduleId>」一致
  // 可选扩展
  category?: 'readability' | 'reliability' | 'i18n' | 'safety' | 'performance' | 'maintainability' | 'testability' | 'config' | 'logging' | 'concurrency' | 'other';
  severity?: 'critical' | 'major' | 'minor';
  confidence?: number; // 0~1
  rationale?: string;
  fix?: string;
  tests?: string;
}

interface MRReview {
  report: string; // 可与上方 Markdown 一致
  reviews: Review[];
  summary: {
    totalScore: number;
    codeQualityScore: number; // 对应 60 分制中的「变更代码」部分
    securityScore: number;    // 25
    standardScore: number;    // 10
    commitScore: number;      // 5
  };
}

/** 多模块（技能「多模块与子仓」工作流）；与 MRReview.summary 字段含义相同 */
interface ModuleMRReview {
  moduleId: string;
  repoPath?: string;       // 相对主工程根目录，如 business/xesmall
  baseBranch: string;
  featureBranch: string;
  report: string;          // 该模块 Markdown 片段（可与总 report 中对应小节一致）
  reviews: Review[];       // 建议每条带 moduleId
  summary: MRReview['summary'];
}

interface MRReviewMulti {
  schemaVersion: '1.1';
  baseBranch: string;
  featureBranch: string;
  modules: ModuleMRReview[];
  report: string;          // 完整 Markdown：总览表 + 各模块 report 串联或摘要
  reviews: Review[];       // 可选：全量扁平化副本，便于旧工具只读 reviews；可与各 modules[].reviews 合并结果一致
  summary: MRReview['summary']; // 聚合分：默认各模块 totalScore 的算术平均（四舍五入取整）；若某模块无评分则排除后平均并在 report 中说明
}
```

### 8.1 多模块 JSON 约定（与技能「多模块与子仓」对应）

- **仅一个模块有变更**：允许只输出 `MRReview`（不传 `schemaVersion` / `modules`），与历史行为一致。  
- **两个及以上模块有变更**：输出 `MRReviewMulti`；`modules[].reviews` 每条建议填写 `moduleId`。  
- **聚合 `summary`**：`totalScore` 等为各模块同名字段的算术平均；`codeQualityScore` 等同理。若模块间权重不同，须在 `report` 中声明加权规则再写入 JSON。

**顶层示例**：

```json
{
  "report": "## MR 代码审查报告\n...",
  "reviews": [],
  "summary": {
    "totalScore": 0,
    "codeQualityScore": 0,
    "securityScore": 0,
    "standardScore": 0,
    "commitScore": 0
  }
}
```

## 9. 输入占位（若用户模板中有）

- `{diffs_text}`：diff 正文。
- `{commits_text}`：提交历史。
- `{max_reviews}`：最大条数，默认 10。
- `{baseBranch}`、`{featureBranch}`：基准与特性分支名。
- `{moduleList}`：用户或标签给出的模块列表（与 Git 扫描结果交集）。

## 10. Git：一次性批量拉取各模块 diff（推荐模板）

**原则**：一条脚本 / 一次终端会话内跑完所有模块，再进入分析；不要按模块与用户分多轮执行。

**默认对比方式**：**两点** `git diff <baseBranch> HEAD`（顶点对比）。**辅**：三点 `git diff <baseBranch>...HEAD` 仅打 stat 便于总览表备注。

**网校主工程路径**：完整 **`business/`、`business-base/`、`library/` 子目录名**及 **`common`、`buildproperties`、壳 `.`** 见同目录 **`mr-code-optimization-review/SKILL.md`** 中章节《网校主工程（xueersiwangxiao）模块路径清单》。批跑时把需审模块拼成 `ROOT/前缀/名称`。

```bash
ROOT="/path/to/xueersiwangxiao"   # 主工程 xueersiwangxiao 根
BASE="develop"
FEAT="feature/improve/customer_service_display"
# 示例：按需从 SKILL 清单中挑选或循环 business/* library/* 等
MODULES=(
  "business/xesmall"
  "business-base/browser"
  "library/xesrouter"
  "buildproperties"
  "common"
  "."    # 壳
  # "businessinterface"
)

for rel in "${MODULES[@]}"; do
  repo="$ROOT/$rel"
  [ -d "$repo/.git" ] || { echo "===== SKIP (no .git): $rel ====="; continue; }
  echo "===== MR_DIFF_MODULE path=$rel ====="
  git -C "$repo" checkout "$FEAT" 2>/dev/null || true
  echo "branch=$(git -C "$repo" branch --show-current)"
  echo "--- two-dot: git diff $BASE HEAD --stat ---"
  git -C "$repo" diff "$BASE" HEAD --stat
  echo "--- three-dot (optional): git diff $BASE...HEAD --stat ---"
  git -C "$repo" diff "$BASE"...HEAD --stat
  echo "--- unified diff (two-dot, 审查主材料) ---"
  git -C "$repo" diff "$BASE" HEAD
  echo "===== END MR_DIFF_MODULE $rel ====="
done
```

**备忘**：`git branch --show-current`；子仓是否存在：`[ -d path/.git ]`。**审查主命令**：`git -C <repoPath> diff <baseBranch> HEAD`。**合入净差**：`git -C <repoPath> diff <baseBranch>...HEAD`。
