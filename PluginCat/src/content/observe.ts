import type { NetworkEntry, Observation, ObservedElement } from '../shared/types';

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
