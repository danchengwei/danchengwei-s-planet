import type { ApiCall, ConsoleEntry, NetworkEntry, Observation, ObservedElement, StorageArea } from '../shared/types';

/* ============================================================
 * 隐私脱敏
 * ============================================================ */

const SENSITIVE_QUERY_KEY = /^(token|apikey|api[_-]?key|access[_-]?token|refresh[_-]?token|secret|password|passwd|pwd|auth|authorization|session|sid|sig|signature|key|code|otp|verification|jwt|id_token)$/i;
const SENSITIVE_NAME_RE = /(password|passwd|pwd|secret|token|apikey|api[_-]?key|auth|session|cvc|cvv|card.?number|ssn|身份证|证件号|密码|密钥)/i;

/** 识别典型的高熵 token / JWT / sk- 等敏感串 */
const TOKEN_LIKE = /\b(sk-[A-Za-z0-9_-]{16,}|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|[A-Za-z0-9_-]{32,})\b/g;

export function redactUrl(raw: string): string {
  if (!raw) return raw;
  try {
    const u = new URL(raw, location.href);
    for (const key of Array.from(u.searchParams.keys())) {
      if (SENSITIVE_QUERY_KEY.test(key)) u.searchParams.set(key, '***');
    }
    // 用户名/密码形式 http://user:pass@host
    if (u.password) u.password = '***';
    return u.toString();
  } catch {
    return raw;
  }
}

export function redactText(s: string): string {
  if (!s) return s;
  return s.replace(TOKEN_LIKE, (match) => {
    // 过短或全数字的不当作 token
    if (match.length < 20) return match;
    if (/^\d+$/.test(match)) return match;
    return '***';
  });
}

export function isElementSensitive(el: Element): boolean {
  if (el instanceof HTMLInputElement) {
    if (el.type === 'password') return true;
    const auto = (el.autocomplete || '').toLowerCase();
    if (auto.includes('password') || auto === 'current-password' || auto === 'new-password') return true;
    if (auto.startsWith('cc-') || auto === 'one-time-code') return true;
  }
  const probe = [
    el.id || '',
    el.getAttribute('name') || '',
    el.getAttribute('aria-label') || '',
    el.getAttribute('placeholder') || '',
    (el.className || '').toString()
  ].join(' ');
  return SENSITIVE_NAME_RE.test(probe);
}

/* ============================================================
 * DOM 快照（按索引供模型定位）
 * ============================================================ */

const INTERACTIVE_SELECTOR = [
  'a[href]',
  'button',
  'input:not([type="hidden"])',
  'textarea',
  'select',
  '[role="button"]',
  '[role="link"]',
  '[role="checkbox"]',
  '[role="menuitem"]',
  '[role="tab"]',
  '[onclick]',
  '[contenteditable="true"]'
].join(',');

const elementMap = new Map<number, HTMLElement>();

export function getIndexedElement(index: number): HTMLElement | undefined {
  return elementMap.get(index);
}

export function buildObservation(opts: { maxElements?: number; maxText?: number } = {}): Observation {
  const maxElements = opts.maxElements ?? 60;
  const maxText = opts.maxText ?? 4000;

  elementMap.clear();
  const all = Array.from(document.querySelectorAll<HTMLElement>(INTERACTIVE_SELECTOR))
    .filter(el => !el.closest('#__web_pet__'))
    .filter(isVisible);

  // 可视区内的元素优先
  all.sort((a, b) => score(b) - score(a));

  const elements: ObservedElement[] = [];
  for (const el of all) {
    if (elements.length >= maxElements) break;
    const ob = describe(el, elements.length);
    if (!ob) continue;
    elementMap.set(ob.index, el);
    elements.push(ob);
  }

  const selection = redactText((window.getSelection()?.toString() || '').trim()).slice(0, 600);

  return {
    url: redactUrl(location.href),
    title: document.title,
    selection,
    viewport: {
      scrollY: Math.round(window.scrollY),
      scrollMax: Math.max(0, document.documentElement.scrollHeight - window.innerHeight)
    },
    elements,
    snippet: redactText(collectVisibleText(maxText))
  };
}

function isVisible(el: HTMLElement): boolean {
  if (!el.isConnected) return false;
  const r = el.getBoundingClientRect();
  if (r.width === 0 || r.height === 0) return false;
  const style = window.getComputedStyle(el);
  if (style.display === 'none' || style.visibility === 'hidden') return false;
  if (parseFloat(style.opacity || '1') < 0.05) return false;
  return true;
}

function isInViewport(el: HTMLElement): boolean {
  const r = el.getBoundingClientRect();
  return r.top < window.innerHeight && r.bottom > 0 && r.left < window.innerWidth && r.right > 0;
}

function score(el: HTMLElement): number {
  const r = el.getBoundingClientRect();
  const inView = r.top < window.innerHeight && r.bottom > 0 && r.left < window.innerWidth && r.right > 0;
  return inView ? 1_000_000 - Math.max(0, Math.abs(r.top)) : 0;
}

function describe(el: HTMLElement, index: number): ObservedElement | null {
  const tag = el.tagName.toLowerCase();
  const role = (el.getAttribute('role') || '').toLowerCase() || undefined;
  const sensitive = isElementSensitive(el);
  const visible = isInViewport(el);

  let type: string | undefined;
  let placeholder: string | undefined;
  let name: string | undefined;
  let value: string | undefined;
  let text: string | undefined;
  let href: string | undefined;

  if (el instanceof HTMLInputElement) {
    type = el.type.toLowerCase();
    placeholder = el.placeholder || undefined;
    name = el.name || undefined;
    if (!sensitive && type !== 'password' && el.value) {
      value = truncate(redactText(el.value), 40);
    }
  } else if (el instanceof HTMLTextAreaElement) {
    placeholder = el.placeholder || undefined;
    name = el.name || undefined;
    if (!sensitive && el.value) value = truncate(redactText(el.value), 80);
  } else if (el instanceof HTMLSelectElement) {
    name = el.name || undefined;
    value = truncate(el.value || '', 40);
  } else if (el instanceof HTMLAnchorElement) {
    href = redactUrl(el.href);
    text = cleanText(el.innerText, 60);
  } else if (el instanceof HTMLButtonElement) {
    text = cleanText(el.innerText, 60);
  } else {
    text = cleanText(el.innerText || el.textContent || '', 60);
  }

  // 如果连点名字都没有的元素，不值得列出
  if (!text && !placeholder && !value && !href && !name) return null;

  return {
    index,
    tag,
    type,
    role,
    name,
    placeholder,
    value,
    text,
    href,
    visible,
    redacted: sensitive || undefined
  };
}

function collectVisibleText(maxLen: number): string {
  const root = document.body;
  if (!root) return '';
  const blocks: string[] = [];
  let total = 0;
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      const parent = node.parentElement;
      if (!parent) return NodeFilter.FILTER_REJECT;
      if (parent.closest('#__web_pet__')) return NodeFilter.FILTER_REJECT;
      const tag = parent.tagName;
      if (['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE'].includes(tag)) return NodeFilter.FILTER_REJECT;
      // 敏感输入的 autofill 提示/密码占位文案也要避开
      if (isElementSensitive(parent)) return NodeFilter.FILTER_REJECT;
      const style = window.getComputedStyle(parent);
      if (style.display === 'none' || style.visibility === 'hidden') return NodeFilter.FILTER_REJECT;
      return NodeFilter.FILTER_ACCEPT;
    }
  });
  while (walker.nextNode()) {
    const t = (walker.currentNode.textContent || '').trim();
    if (!t) continue;
    blocks.push(t);
    total += t.length + 1;
    if (total >= maxLen) break;
  }
  return blocks.join('\n').replace(/\n{3,}/g, '\n\n').slice(0, maxLen);
}

function cleanText(s: string | undefined, max: number): string | undefined {
  if (!s) return undefined;
  const t = s.replace(/\s+/g, ' ').trim();
  return t ? truncate(t, max) : undefined;
}

function truncate(s: string, n: number): string {
  return s.length > n ? s.slice(0, n) + '…' : s;
}

/* ============================================================
 * 格式化：把 Observation / Network 序列化成给模型读的纯文本
 * ============================================================ */

export function formatObservation(ob: Observation, includeNetwork = false): string {
  const lines: string[] = [];
  lines.push('[页面信息]');
  lines.push(`URL: ${ob.url}`);
  lines.push(`标题: ${ob.title}`);
  lines.push(`滚动: ${ob.viewport.scrollY}/${ob.viewport.scrollMax}px`);
  if (ob.selection) lines.push(`用户选中: ${truncate(ob.selection, 200)}`);

  lines.push('');
  lines.push(`[可交互元素 ${ob.elements.length} 个]`);
  if (ob.elements.length === 0) lines.push('(无)');
  for (const e of ob.elements) lines.push(formatElement(e));

  lines.push('');
  lines.push('[可见正文 (截断, 已脱敏)]');
  lines.push(ob.snippet || '(空)');

  if (includeNetwork) {
    const net = recentNetwork(20);
    lines.push('');
    lines.push(`[最近网络请求 ${net.length} 条]`);
    for (const n of net) lines.push(formatNetwork(n));
  }

  return lines.join('\n');
}

function formatElement(e: ObservedElement): string {
  const bits: string[] = [`[${e.index}]`];
  let tag = e.tag;
  if (e.type) tag += `[type=${e.type}]`;
  if (e.role) tag += `[role=${e.role}]`;
  bits.push(tag);
  if (e.redacted) {
    bits.push('⚠️ REDACTED(敏感字段，禁 fill/read)');
  } else {
    if (e.text)        bits.push(JSON.stringify(e.text));
    if (e.placeholder) bits.push(`ph=${JSON.stringify(e.placeholder)}`);
    if (e.value)       bits.push(`val=${JSON.stringify(e.value)}`);
    if (e.name)        bits.push(`name=${JSON.stringify(e.name)}`);
    if (e.href)        bits.push(`href=${e.href}`);
  }
  if (!e.visible) bits.push('(off-screen)');
  return bits.join(' ');
}

export function formatNetwork(n: NetworkEntry): string {
  const s = n.status ? ` ${n.status}` : '';
  return `[${(n.time / 1000).toFixed(1)}s]${s} ${n.type} ${n.duration}ms ${n.url}`;
}

/* ============================================================
 * 网络请求观察（仅 resource timing，不涉及 header / body）
 * ============================================================ */

const netBuf: NetworkEntry[] = [];
const NET_BUF_MAX = 200;
let observerInitialized = false;

export function initNetworkObserver() {
  if (observerInitialized) return;
  observerInitialized = true;
  try {
    const po = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        if (entry.entryType !== 'resource') continue;
        const rt = entry as PerformanceResourceTiming;
        if (netBuf.length >= NET_BUF_MAX) netBuf.shift();
        netBuf.push({
          url: redactUrl(rt.name),
          type: rt.initiatorType || 'resource',
          // responseStatus 仅在部分浏览器版本下可用
          status: (rt as any).responseStatus || undefined,
          duration: Math.round(rt.duration),
          time: Math.round(rt.startTime)
        });
      }
    });
    po.observe({ type: 'resource', buffered: true });
  } catch {
    /* 旧浏览器忽略 */
  }
}

export function recentNetwork(limit = 20): NetworkEntry[] {
  return netBuf.slice(-limit);
}

/* ============================================================
 * API 调用缓冲：接收 MAIN world injected.ts 回传的 fetch/XHR 明细
 * ============================================================ */

const apiBuf: ApiCall[] = [];
const apiById = new Map<number, ApiCall>();
const API_BUF_MAX = 200;
const consoleBuf: ConsoleEntry[] = [];
const CONSOLE_BUF_MAX = 200;
let apiObserverInitialized = false;

export function initApiObserver() {
  if (apiObserverInitialized) return;
  apiObserverInitialized = true;
  window.addEventListener('message', (ev) => {
    if (ev.source !== window) return;
    const d: any = ev.data;
    if (!d || d.__pet_api__ !== true) return;
    if (d.type === 'start') {
      const call: ApiCall = {
        id: Number(d.id),
        url: redactUrl(String(d.url || '')),
        method: String(d.method || 'GET').toUpperCase(),
        kind: d.kind === 'xhr' ? 'xhr' : 'fetch',
        reqSnippet: typeof d.reqSnippet === 'string' ? redactText(d.reqSnippet) : undefined,
        time: Number(d.time) || Date.now()
      };
      if (!Number.isFinite(call.id)) return;
      if (apiBuf.length >= API_BUF_MAX) {
        const dropped = apiBuf.shift();
        if (dropped) apiById.delete(dropped.id);
      }
      apiBuf.push(call);
      apiById.set(call.id, call);
    } else if (d.type === 'console') {
      if (consoleBuf.length >= CONSOLE_BUF_MAX) consoleBuf.shift();
      consoleBuf.push({
        level: d.level === 'warn' || d.level === 'error' || d.level === 'info' ? d.level : 'log',
        message: redactText(String(d.message || '')),
        time: Number(d.time) || Date.now()
      });
    } else if (d.type === 'end') {
      const call = apiById.get(Number(d.id));
      if (!call) return;
      if (typeof d.status === 'number') call.status = d.status;
      if (typeof d.durationMs === 'number') call.durationMs = d.durationMs;
      if (typeof d.contentType === 'string') call.contentType = d.contentType;
      if (typeof d.respSnippet === 'string') call.respSnippet = redactText(d.respSnippet);
      if (typeof d.error === 'string') call.error = d.error;
    }
  });
}

export function recentApiCalls(limit = 20): ApiCall[] {
  return apiBuf.slice(-limit);
}

export function searchApiCalls(query: string, limit = 20): ApiCall[] {
  const q = query.trim().toLowerCase();
  if (!q) return recentApiCalls(limit);
  return apiBuf.filter(c => c.url.toLowerCase().includes(q)).slice(-limit);
}

export function getApiCall(id: number): ApiCall | undefined {
  return apiById.get(id);
}

export function formatApiCall(c: ApiCall): string {
  const status = c.status != null ? String(c.status) : (c.error ? 'ERR' : '…');
  const dur = c.durationMs != null ? `${c.durationMs}ms` : '?';
  return `#${c.id} ${c.kind} ${c.method} ${status} ${dur} ${c.url}`;
}

export function formatApiDetail(c: ApiCall): string {
  const lines: string[] = [];
  lines.push(`#${c.id} ${c.method} ${c.url}`);
  const status = c.status != null ? String(c.status) : (c.error || '?');
  const dur = c.durationMs != null ? `${c.durationMs}ms` : '?';
  lines.push(`状态: ${status}  耗时: ${dur}  类型: ${c.kind}${c.contentType ? `  content-type: ${c.contentType}` : ''}`);
  if (c.reqSnippet) {
    lines.push('[请求体 (截断到 512 字, 已脱敏)]');
    lines.push(c.reqSnippet);
  }
  if (c.respSnippet) {
    lines.push('[响应体 (截断到 2KB, 已脱敏)]');
    lines.push(c.respSnippet);
  } else if (!c.error) {
    lines.push('(响应体未捕获：非文本/JSON 或请求仍在进行)');
  }
  return lines.join('\n');
}

/* ============================================================
 * Console 缓冲
 * ============================================================ */

export function recentConsole(level?: ConsoleEntry['level'], limit = 50): ConsoleEntry[] {
  const base = level ? consoleBuf.filter(c => c.level === level) : consoleBuf;
  return base.slice(-limit);
}

export function formatConsoleEntry(e: ConsoleEntry, base = Date.now()): string {
  const ago = Math.max(0, Math.round((base - e.time) / 1000));
  return `[-${ago}s] [${e.level.toUpperCase()}] ${e.message}`;
}

/* ============================================================
 * evalInPage：跨 world 执行 JS（主世界求值，拿返回值）
 * ============================================================ */

export function evalInPage(code: string, timeoutMs = 6000): Promise<{ ok: boolean; result?: string; type?: string; error?: string }> {
  return new Promise(resolve => {
    const reqId = `eval-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    let done = false;
    const handler = (ev: MessageEvent) => {
      if (ev.source !== window) return;
      const d: any = ev.data;
      if (!d || d.__pet_res__ !== true || d.reqId !== reqId) return;
      if (done) return;
      done = true;
      window.removeEventListener('message', handler);
      clearTimeout(timer);
      resolve({ ok: !!d.ok, result: d.result, type: d.type, error: d.error });
    };
    const timer = window.setTimeout(() => {
      if (done) return;
      done = true;
      window.removeEventListener('message', handler);
      resolve({ ok: false, error: `eval 超时 (>${timeoutMs}ms)` });
    }, timeoutMs);
    window.addEventListener('message', handler);
    window.postMessage({ __pet_req__: true, type: 'eval', reqId, code }, '*');
  });
}

/* ============================================================
 * Storage 读取（localStorage / sessionStorage / cookie）
 * ============================================================ */

const SENSITIVE_STORAGE_KEY = /(password|passwd|pwd|secret|token|apikey|api[_-]?key|auth|session|sid|jwt|access[_-]?token|refresh[_-]?token|otp|verification)/i;

export interface StorageItem {
  area: 'local' | 'session' | 'cookie';
  key: string;
  value?: string;
  redacted?: boolean;
  size?: number;
}

export function readStorage(area: StorageArea = 'all', keyMatch?: string): StorageItem[] {
  const out: StorageItem[] = [];
  const areas: Array<'local' | 'session' | 'cookie'> =
    area === 'all' ? ['local', 'session', 'cookie'] : [area];
  for (const a of areas) {
    if (a === 'local' || a === 'session') {
      const store = a === 'local' ? window.localStorage : window.sessionStorage;
      try {
        for (let i = 0; i < store.length; i++) {
          const key = store.key(i);
          if (!key) continue;
          if (keyMatch && !key.toLowerCase().includes(keyMatch.toLowerCase())) continue;
          const raw = store.getItem(key) ?? '';
          out.push(buildItem(a, key, raw));
        }
      } catch { /* ignore: some pages disable storage */ }
    } else if (a === 'cookie') {
      try {
        const raw = document.cookie || '';
        if (!raw) continue;
        const pairs = raw.split(/;\s*/).filter(Boolean);
        for (const p of pairs) {
          const eq = p.indexOf('=');
          const key = eq === -1 ? p : p.slice(0, eq);
          const value = eq === -1 ? '' : p.slice(eq + 1);
          if (keyMatch && !key.toLowerCase().includes(keyMatch.toLowerCase())) continue;
          out.push(buildItem('cookie', key, decodeCookieValue(value)));
        }
      } catch { /* ignore */ }
    }
  }
  return out;
}

function decodeCookieValue(v: string): string {
  try { return decodeURIComponent(v); } catch { return v; }
}

function buildItem(area: 'local' | 'session' | 'cookie', key: string, raw: string): StorageItem {
  const size = raw.length;
  if (SENSITIVE_STORAGE_KEY.test(key)) {
    return { area, key, redacted: true, size };
  }
  return { area, key, value: truncateStr(redactText(raw), 2048), size };
}

function truncateStr(s: string, n: number): string {
  return s.length > n ? s.slice(0, n) + '…' : s;
}

export function formatStorageItem(it: StorageItem): string {
  const tag = `[${it.area}]`;
  if (it.redacted) return `${tag} ${it.key} = ⚠️ REDACTED (${it.size} 字符)`;
  return `${tag} ${it.key} = ${JSON.stringify(it.value || '')} (${it.size} 字符)`;
}

/* ============================================================
 * DOM query：按 CSS 选择器批量取节点
 * ============================================================ */

export interface QueryHit {
  index: number;
  tag: string;
  text?: string;
  attr?: string;
}

export function runQuery(selector: string, limit = 10, attr?: string): { ok: true; hits: QueryHit[] } | { ok: false; error: string } {
  let nodes: NodeListOf<Element>;
  try {
    nodes = document.querySelectorAll(selector);
  } catch (err: any) {
    return { ok: false, error: `无效选择器: ${err?.message || err}` };
  }
  const hits: QueryHit[] = [];
  const cap = Math.min(limit, 30);
  for (let i = 0; i < nodes.length && hits.length < cap; i++) {
    const el = nodes[i] as HTMLElement;
    if (el.closest('#__web_pet__')) continue;
    const text = redactText((el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim()).slice(0, 200);
    const hit: QueryHit = { index: i, tag: el.tagName.toLowerCase() };
    if (text) hit.text = text;
    if (attr) {
      const av = el.getAttribute(attr);
      if (av) hit.attr = redactText(av).slice(0, 200);
    }
    hits.push(hit);
  }
  return { ok: true, hits };
}

export function formatQueryHit(h: QueryHit, attr?: string): string {
  const parts = [`[${h.index}]`, `<${h.tag}>`];
  if (h.text) parts.push(JSON.stringify(h.text));
  if (attr && h.attr) parts.push(`${attr}=${JSON.stringify(h.attr)}`);
  return parts.join(' ');
}
