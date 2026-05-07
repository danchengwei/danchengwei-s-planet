import type { PetAction } from '../shared/types';
import {
  buildObservation,
  formatNetwork,
  formatObservation,
  getIndexedElement,
  isElementSensitive,
  recentNetwork,
  redactText
} from './observe';

export interface ActionResult {
  kind: PetAction['kind'];
  ok: boolean;
  /** 给用户看的一句话总结 */
  summary: string;
  /** 给模型看的反馈，会被写成下一轮 user message */
  observation: string;
}

export async function runAction(action: PetAction): Promise<ActionResult> {
  switch (action.kind) {
    case 'observe': {
      await wait(120);
      const ob = buildObservation();
      return {
        kind: 'observe',
        ok: true,
        summary: `刷新观察（${ob.elements.length} 个元素）`,
        observation: formatObservation(ob)
      };
    }
    case 'network': {
      const net = recentNetwork(20);
      if (net.length === 0) {
        return { kind: 'network', ok: true, summary: '暂无网络请求', observation: '[最近网络请求]\n(空)' };
      }
      return {
        kind: 'network',
        ok: true,
        summary: `最近 ${net.length} 条网络请求`,
        observation: '[最近网络请求]\n' + net.map(formatNetwork).join('\n')
      };
    }
    case 'scroll': {
      performScroll(action.to);
      await wait(450);
      const ob = buildObservation();
      return {
        kind: 'scroll',
        ok: true,
        summary: `滚动到 ${describeScroll(action.to)}`,
        observation: `scrolled to ${action.to}\n` + formatObservation(ob)
      };
    }
    case 'click': {
      const el = getIndexedElement(action.index);
      if (!el) return fail('click', `元素 [${action.index}] 不存在`, `error: 没有 index=${action.index} 的元素，请先 observe`);
      if (!el.isConnected) return fail('click', `元素 [${action.index}] 已从 DOM 移除`, `error: element [${action.index}] is no longer in the DOM, please re-observe`);
      if (isElementSensitive(el)) return fail('click', `元素 [${action.index}] 为敏感字段，已拒绝`, 'error: element is redacted (sensitive field)');
      el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      await wait(250);
      try {
        el.click();
      } catch (e: any) {
        return fail('click', `点击 [${action.index}] 失败`, `error: ${e?.message || e}`);
      }
      await wait(500);
      const ob = buildObservation();
      return {
        kind: 'click',
        ok: true,
        summary: `点击了 [${action.index}]${brief(el)}`,
        observation: `clicked [${action.index}]\n` + formatObservation(ob)
      };
    }
    case 'fill': {
      const el = getIndexedElement(action.index);
      if (!el) return fail('fill', `元素 [${action.index}] 不存在`, `error: 没有 index=${action.index}`);
      if (!el.isConnected) return fail('fill', `元素 [${action.index}] 已从 DOM 移除`, `error: element [${action.index}] is no longer in the DOM, please re-observe`);
      if (isElementSensitive(el)) return fail('fill', `[${action.index}] 是敏感字段 (密码等)，拒绝填写`, 'error: refused to fill sensitive field (password/card/etc.)');
      if (!(el instanceof HTMLInputElement) && !(el instanceof HTMLTextAreaElement) && !(el as HTMLElement).isContentEditable) {
        return fail('fill', `[${action.index}] 不是可填写元素`, 'error: element is not fillable');
      }
      el.focus();
      if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
        const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
        setter?.call(el, action.value);
      } else {
        (el as HTMLElement).textContent = action.value;
      }
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      const preview = truncate(redactText(action.value), 24);
      return {
        kind: 'fill',
        ok: true,
        summary: `填入 [${action.index}] = ${JSON.stringify(preview)}`,
        observation: `filled [${action.index}] with ${JSON.stringify(preview)}`
      };
    }
    case 'read': {
      const el = getIndexedElement(action.index);
      if (!el) return fail('read', `元素 [${action.index}] 不存在`, `error: 没有 index=${action.index}`);
      if (!el.isConnected) return fail('read', `元素 [${action.index}] 已从 DOM 移除`, `error: element [${action.index}] is no longer in the DOM, please re-observe`);
      if (isElementSensitive(el)) return fail('read', `[${action.index}] 为敏感字段，拒绝读取`, 'error: refused to read sensitive field');
      const full = (el.innerText || el.textContent || '').trim();
      const safe = redactText(full).slice(0, 1500);
      return {
        kind: 'read',
        ok: true,
        summary: `读取 [${action.index}]`,
        observation: `[${action.index}] 内容:\n${safe || '(空)'}`
      };
    }
    case 'wait': {
      const ms = Math.min(3000, Math.max(0, Math.round(action.ms)));
      await wait(ms);
      return { kind: 'wait', ok: true, summary: `等了 ${ms}ms`, observation: `waited ${ms}ms` };
    }
    case 'finish':
    case 'none':
      return { kind: action.kind, ok: true, summary: '', observation: '' };
  }
}

function fail(kind: PetAction['kind'], summary: string, observation: string): ActionResult {
  return { kind, ok: false, summary, observation };
}

function performScroll(to: 'top' | 'bottom' | number) {
  if (to === 'top') window.scrollTo({ top: 0, behavior: 'smooth' });
  else if (to === 'bottom') window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'smooth' });
  else window.scrollTo({ top: Math.max(0, Number(to) || 0), behavior: 'smooth' });
}

function describeScroll(to: 'top' | 'bottom' | number): string {
  if (to === 'top') return '顶部';
  if (to === 'bottom') return '底部';
  return `${to}px`;
}

function brief(el: HTMLElement): string {
  const t = (el.innerText || (el as HTMLInputElement).placeholder || '').replace(/\s+/g, ' ').trim();
  return t ? ` (${truncate(t, 18)})` : '';
}

function wait(ms: number): Promise<void> {
  return new Promise(r => setTimeout(r, ms));
}

function truncate(s: string, n: number): string {
  return s.length > n ? s.slice(0, n) + '…' : s;
}
