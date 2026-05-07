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

export type PetAction =
  | { kind: 'observe' }
  | { kind: 'network' }
  | { kind: 'scroll'; to: 'top' | 'bottom' | number }
  | { kind: 'click'; index: number }
  | { kind: 'fill'; index: number; value: string }
  | { kind: 'read'; index: number }
  | { kind: 'wait'; ms: number }
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
