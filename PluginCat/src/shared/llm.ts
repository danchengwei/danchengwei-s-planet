import type { AgentStep, ChatMessage, PetAction, Settings } from './types';
import { getProvider } from './providers';

/* ============================================================
 * Agent 系统提示词
 * ============================================================ */

export const DUAL_SYSTEM_PROMPT = `你是浏览器里的电子小宠物「喵助手」。用户会和你对话。你有两种输出模式，请根据用户消息的意图选一种：

## 🅰 聊天模式（默认）
用户只是在问问题、让你总结/解释页面内容、闲聊——请**直接用中文自然语言回答**，1-3 句话，可以偶尔加"喵~"。
**不要输出 JSON，不要用 \`\`\` 代码块。**

下列情况属于聊天模式：
- "这页讲了什么？" / "总结一下" / "这个词什么意思" / "你怎么看"
- 纯闲聊、自我介绍、夸你
- 用户只是好奇，没让你"动手做事"

## 🅱 Agent 模式（需要操作浏览器时）
**只有**当用户明确要求你"做点什么"——点击/滚动/填写/查看某元素/查看网络请求/问"xx 列表/数据是哪个接口返回的"/看某接口请求体或响应/连续多步操作——才进入 Agent 模式。

排查"哪个接口是 xx 数据"时的典型流程：
1. {"kind":"network","query":"<页面内容里的关键词或接口路径片段，如 feed/list/recommend/detail>"}
2. 从返回里挑最可能的那条（看 URL 路径、method、响应耗时、是否 xhr/fetch），记下 # 号
3. {"kind":"network","id":<#号>} 看响应体前 2KB，确认字段和页面上显示的数据对得上
4. finish，告诉用户：URL、HTTP method、返回的主要字段
进入后，**整段对话**（直到 finish）都必须严格返回 JSON（不要代码块包裹）：

{
  "thought": "简短推理（≤40 字，给你自己看的思考过程）",
  "reply":   "本步进度说明（≤30 字，中文，给用户看）",
  "action":  { "kind": "...", ... }
}

### reply 字段规则（非常重要）：
- 每一步都**必须**用自然中文总结"**我接下来这一步具体在做什么**"，要**结合用户的原始需求**写；
- **禁止**写字面重复 action 类型的废话：❌"查看网络请求"、❌"观察页面"、❌"执行一次 network action"；
- 要像**跟用户解说操作**一样：
  - 用户问"文章列表接口是哪个" → reply 可以是 "正在搜索含 feed/list 的业务接口"、"查 #7 响应体确认是不是列表接口"；
  - 用户问"页面有没有报错" → reply 可以是 "拉一下最近的 error 日志"；
  - 用户让点某个按钮 → reply 可以是 "点击「提交」按钮"（具体化），不要"点击 [3]"（泛泛）；
- finish 的时候 reply 可以留空或写一句"整理完毕"之类，最终答复放在 \`action.reply\`；
- 不要带"喵~"这种语气词，进度条里要专业一点。

### 可选 action（每次只能一个）：
- {"kind":"observe"}                             刷新"可交互元素 + 可见正文"观察
- {"kind":"query","selector":".xxx","limit":10,"attr":"data-id"}  按 CSS 选择器批量取节点（不进 index）
- {"kind":"network"}                             列最近业务 API 调用（fetch/XHR）+ 全部资源时序
- {"kind":"network","query":"list"}              按 URL 关键字过滤 API 调用（例："feed"、"recommend"、"detail"）
- {"kind":"network","id":3}                      看第 3 号 API 的响应体前 2KB（先 network 拿到 # 号再查）
- {"kind":"console"}                             拿最近 console 日志；可选 level: "log"|"warn"|"error"|"info"
- {"kind":"console","level":"error","limit":20}  只看最近 error
- {"kind":"storage"}                             读 localStorage/sessionStorage/cookie 的 key+value（敏感 key 自动 REDACT）
- {"kind":"storage","area":"local","keyMatch":"user"}  只看 local 里 key 含 "user" 的
- {"kind":"eval","code":"window.__INITIAL_STATE__?.user?.name"}  在主页面 world 执行一段 JS，返回结果字符串（❗会弹用户审批）
- {"kind":"scroll","to":"top"|"bottom"|像素}
- {"kind":"click","index":n}                     点击观察列表中 [n] 号元素
- {"kind":"fill","index":n,"value":"文本"}       向 [n] 号输入框填写
- {"kind":"read","index":n}                      读取 [n] 号元素的完整文字
- {"kind":"wait","ms":<=3000}
- {"kind":"finish","reply":"最终答复"}           结束

### eval 使用守则（重要）：
- 只在 observe/query/network/console/storage 都不够用时才用 eval；能一句话表达的就别写多行。
- 永远当它是"DevTools Console 输入框"：写**表达式**（能 return 一个值），不要写 IIFE / 多语句。
- 不要 eval 读 cookie/token/密码，不要 eval 写 storage，不要 eval 提交表单或发支付。
- 用户可能会拒绝你的 eval；被拒绝时换策略或 finish，不要反复重试同一段。

### Agent 规则：
- 只使用**最近一次观察**里列出的 [index]；不确定就先 observe。
- 单轮最多 6 步；到 5 步还没完成就 finish 说明进度。
- 一旦进入 Agent 模式就保持 JSON 直到 finish，中途**不许切回纯文本**。

## 隐私安全（强约束，两种模式都适用）：
1. 元素若被标记为 ⚠️ REDACTED（密码/信用卡/验证码/API Key），**永远不会**给你原值，且 fill/read 会被拒绝。
2. URL 里 token/secret/apikey 等已被替换成 ***，不要尝试恢复或让用户提供。
3. 禁止：提交登录表单、注册账号、发起支付、读取/修改 cookie、抓取表单密码。遇到这类请求：聊天模式里直接用中文委婉拒绝；Agent 模式里用 finish 拒绝。

## 如何判断模式？
先在心里问一句："用户是让我操作浏览器吗？" 答案是否 → 聊天模式；是 → Agent 模式。含糊时默认聊天模式，不要主动给操作。`;

/** 仅为向后兼容导出，实际使用 DUAL_SYSTEM_PROMPT */
export const AGENT_SYSTEM_PROMPT = DUAL_SYSTEM_PROMPT;

/* ============================================================
 * 对模型的调用
 * ============================================================ */

export async function callLLM(settings: Settings, messages: ChatMessage[]): Promise<string> {
  const withSystem: ChatMessage[] = [
    { role: 'system', content: DUAL_SYSTEM_PROMPT },
    ...messages
  ];
  return chatCompletion(settings, withSystem, 0.4, 1024);
}

/** 连通性/授权测试：一次最小调用，成功返回回复样本 */
export async function pingLLM(settings: Settings): Promise<{ ok: true; sample: string } | { ok: false; error: string }> {
  try {
    const sample = await chatCompletion(
      settings,
      [{ role: 'user', content: '你好，只需回复"喵"即可，用来测试连通性。' }],
      0,
      32,
      15000
    );
    return { ok: true, sample: sample.slice(0, 60) };
  } catch (err: any) {
    return { ok: false, error: err?.message || String(err) };
  }
}

async function chatCompletion(
  settings: Settings,
  messages: ChatMessage[],
  temperature: number,
  maxTokens: number,
  timeoutMs = 30000
): Promise<string> {
  const provider = getProvider(settings.provider);
  const model = (settings.model && settings.model.trim()) || provider.defaultModel;
  if (!settings.apiKey) throw new Error('API Key 未配置');

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const resp = await fetch(provider.baseUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${settings.apiKey}`
      },
      body: JSON.stringify({
        model,
        messages,
        temperature,
        max_tokens: maxTokens,
        stream: false
      }),
      signal: controller.signal
    });

    if (!resp.ok) {
      const errText = await resp.text().catch(() => '');
      throw new Error(friendlyError(provider.label, resp.status, errText));
    }
    const data = await resp.json();
    const content: string = data?.choices?.[0]?.message?.content?.toString() || '';
    if (!content) throw new Error(`${provider.label} 返回为空`);
    return content.trim();
  } catch (err: any) {
    if (err?.name === 'AbortError') throw new Error(`${provider.label} 请求超时`);
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

function friendlyError(label: string, status: number, body: string): string {
  const snippet = body.replace(/\s+/g, ' ').slice(0, 220);
  if (status === 401 || status === 403) return `${label} 鉴权失败（${status}）：API Key 无效或权限不足。`;
  if (status === 404) return `${label} 404：接口地址或模型名有误。`;
  if (status === 429) return `${label} 429：请求过于频繁或配额耗尽。`;
  if (status >= 500) return `${label} 服务异常（${status}）。`;
  return `${label} 调用失败（${status}）：${snippet}`;
}

/* ============================================================
 * 解析模型输出
 * ============================================================ */

export function parseAgentOutput(raw: string): AgentStep {
  const cleaned = stripCodeFence(raw);
  const jsonText = extractFirstJson(cleaned) ?? cleaned;
  try {
    const obj = JSON.parse(jsonText);
    return {
      thought: typeof obj.thought === 'string' ? obj.thought : '',
      reply: typeof obj.reply === 'string' ? obj.reply : '',
      action: normalizeAction(obj.action),
      raw
    };
  } catch {
    // 模型没按 JSON 回复，兜底：整段当成 finish 的 reply
    return {
      thought: '',
      reply: raw,
      action: { kind: 'finish', reply: raw },
      raw
    };
  }
}

function stripCodeFence(s: string): string {
  return s.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '').trim();
}

function extractFirstJson(s: string): string | null {
  const start = s.indexOf('{');
  const end = s.lastIndexOf('}');
  if (start === -1 || end === -1 || end <= start) return null;
  return s.slice(start, end + 1);
}

function normalizeAction(a: any): PetAction {
  if (!a || typeof a !== 'object') return { kind: 'none' };
  switch (a.kind) {
    case 'observe':  return { kind: 'observe' };
    case 'network': {
      const out: { kind: 'network'; query?: string; id?: number } = { kind: 'network' };
      if (typeof a.query === 'string' && a.query.trim()) out.query = a.query.trim();
      const idn = Number(a.id);
      if (Number.isInteger(idn) && idn > 0) out.id = idn;
      return out;
    }
    case 'scroll': {
      const to = a.to;
      if (to === 'top' || to === 'bottom') return { kind: 'scroll', to };
      const n = Number(to);
      if (Number.isFinite(n)) return { kind: 'scroll', to: n };
      return { kind: 'none' };
    }
    case 'click': {
      const i = Number(a.index);
      return Number.isInteger(i) && i >= 0 ? { kind: 'click', index: i } : { kind: 'none' };
    }
    case 'fill': {
      const i = Number(a.index);
      if (!Number.isInteger(i) || i < 0) return { kind: 'none' };
      return typeof a.value === 'string' ? { kind: 'fill', index: i, value: a.value } : { kind: 'none' };
    }
    case 'read': {
      const i = Number(a.index);
      return Number.isInteger(i) && i >= 0 ? { kind: 'read', index: i } : { kind: 'none' };
    }
    case 'wait': {
      const ms = Number(a.ms);
      return Number.isFinite(ms) && ms >= 0 ? { kind: 'wait', ms: Math.min(3000, ms) } : { kind: 'wait', ms: 500 };
    }
    case 'eval': {
      return typeof a.code === 'string' && a.code.trim() ? { kind: 'eval', code: a.code } : { kind: 'none' };
    }
    case 'console': {
      const out: { kind: 'console'; level?: 'log' | 'warn' | 'error' | 'info'; limit?: number } = { kind: 'console' };
      if (a.level === 'log' || a.level === 'warn' || a.level === 'error' || a.level === 'info') out.level = a.level;
      const lim = Number(a.limit);
      if (Number.isInteger(lim) && lim > 0) out.limit = lim;
      return out;
    }
    case 'storage': {
      const out: { kind: 'storage'; area?: 'local' | 'session' | 'cookie' | 'all'; keyMatch?: string } = { kind: 'storage' };
      if (a.area === 'local' || a.area === 'session' || a.area === 'cookie' || a.area === 'all') out.area = a.area;
      if (typeof a.keyMatch === 'string' && a.keyMatch.trim()) out.keyMatch = a.keyMatch.trim();
      return out;
    }
    case 'query': {
      if (typeof a.selector !== 'string' || !a.selector.trim()) return { kind: 'none' };
      const out: { kind: 'query'; selector: string; limit?: number; attr?: string } = { kind: 'query', selector: a.selector.trim() };
      const lim = Number(a.limit);
      if (Number.isInteger(lim) && lim > 0) out.limit = lim;
      if (typeof a.attr === 'string' && a.attr.trim()) out.attr = a.attr.trim();
      return out;
    }
    case 'finish':
      return { kind: 'finish', reply: typeof a.reply === 'string' ? a.reply : '' };
    case 'none':
    default:
      return { kind: 'none' };
  }
}
