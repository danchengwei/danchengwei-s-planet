import type { ProviderId } from './providers';

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface Settings {
  provider: ProviderId;
  apiKey: string;
  /** 为空时使用 provider 的 defaultModel */
  model: string;
}

/* ---------- Observation（给模型看的页面状态） ---------- */

export interface ObservedElement {
  index: number;
  tag: string;
  type?: string;
  role?: string;
  name?: string;
  placeholder?: string;
  value?: string;
  href?: string;
  text?: string;
  visible: boolean;
  /** 敏感字段：密码 / 信用卡等，不会泄露原值，也不允许 fill/read */
  redacted?: boolean;
}

export interface NetworkEntry {
  url: string;
  type: string;
  status?: number;
  duration: number;
  /** ms since navigation start */
  time: number;
}

/** 被 MAIN world 的 fetch/XHR hook 捕获的一条业务 API 调用（带响应体摘要） */
export interface ApiCall {
  id: number;
  url: string;
  method: string;
  kind: 'fetch' | 'xhr';
  status?: number;
  durationMs?: number;
  contentType?: string;
  /** 请求体前 512 字（已脱敏） */
  reqSnippet?: string;
  /** 响应体前 2KB（已脱敏，仅 text/json 等文本类 content-type） */
  respSnippet?: string;
  error?: string;
  /** Date.now() when started */
  time: number;
}

export interface Observation {
  url: string;
  title: string;
  selection: string;
  viewport: { scrollY: number; scrollMax: number };
  elements: ObservedElement[];
  /** 可见正文（截断 & 脱敏） */
  snippet: string;
}

/* ---------- Agent Action ---------- */

export interface ConsoleEntry {
  level: 'log' | 'warn' | 'error' | 'info';
  message: string;
  time: number;
}

export type StorageArea = 'local' | 'session' | 'cookie' | 'all';

export type PetAction =
  | { kind: 'observe' }
  | { kind: 'network'; query?: string; id?: number }
  | { kind: 'scroll'; to: 'top' | 'bottom' | number }
  | { kind: 'click'; index: number }
  | { kind: 'fill'; index: number; value: string }
  | { kind: 'read'; index: number }
  | { kind: 'wait'; ms: number }
  /** 在页面 MAIN world 执行一段 JS，拿返回值（会弹审批） */
  | { kind: 'eval'; code: string }
  /** 拿最近的 console 日志 */
  | { kind: 'console'; level?: ConsoleEntry['level']; limit?: number }
  /** 读 localStorage / sessionStorage / cookie */
  | { kind: 'storage'; area?: StorageArea; keyMatch?: string }
  /** 用 CSS 选择器批量查 DOM 节点（不进可交互元素索引） */
  | { kind: 'query'; selector: string; limit?: number; attr?: string }
  | { kind: 'finish'; reply: string }
  | { kind: 'none' };

export interface AgentStep {
  thought: string;
  reply: string;
  action: PetAction;
  /** 模型原始输出，用于写回 messages 历史 */
  raw: string;
}

/* ---------- 消息协议 ---------- */

export interface AskRequest {
  type: 'ASK';
  messages: ChatMessage[];
}

export interface AskResponse {
  ok: boolean;
  step?: AgentStep;
  error?: string;
}

export interface TestRequest {
  type: 'TEST';
  settings: Settings;
}

export interface TestResponse {
  ok: boolean;
  error?: string;
  sample?: string;
}

export type BgMessage = AskRequest | TestRequest;
