import type { PetAction } from '../shared/types';
import {
  buildObservation,
  evalInPage,
  formatApiCall,
  formatApiDetail,
  formatConsoleEntry,
  formatNetwork,
  formatObservation,
  formatQueryHit,
  formatStorageItem,
  getApiCall,
  getIndexedElement,
  isElementSensitive,
  readStorage,
  recentApiCalls,
  recentConsole,
  recentNetwork,
  redactText,
  runQuery,
  searchApiCalls
} from './observe';

/** 需要在执行前弹用户审批的 action kind */
export const SENSITIVE_ACTION_KINDS: ReadonlyArray<PetAction['kind']> = ['eval'];
export function needsApproval(a: PetAction): boolean {
  return SENSITIVE_ACTION_KINDS.includes(a.kind);
}

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
      // id 形式：返回某条请求的响应体
      if (typeof action.id === 'number') {
        const c = getApiCall(action.id);
        if (!c) return fail('network', `没有 #${action.id} 号请求`, `error: 没有 id=${action.id} 的 API 调用，请先用 {"kind":"network"} 或 {"kind":"network","query":"..."} 查列表拿 id`);
        return {
          kind: 'network',
          ok: true,
          summary: `查看 #${action.id} 响应`,
          observation: formatApiDetail(c)
        };
      }
      // 按 URL 关键字过滤
      const query = typeof action.query === 'string' ? action.query.trim() : '';
      const apis = query ? searchApiCalls(query, 20) : recentApiCalls(20);
      const lines: string[] = [];
      lines.push(`[业务 API 调用 ${apis.length} 条${query ? ` 匹配 "${query}"` : ''}（fetch/XHR）]`);
      if (apis.length === 0) {
        lines.push('(空：hook 可能挂在了页面主脚本之后，刷新页面后再问一次试试)');
      } else {
        for (const c of apis) lines.push(formatApiCall(c));
      }
      if (!query) {
        const perf = recentNetwork(20);
        lines.push('');
        lines.push(`[全部资源时序 ${perf.length} 条（含图片/脚本，只有 URL/耗时/状态）]`);
        for (const n of perf) lines.push(formatNetwork(n));
      }
      lines.push('');
      lines.push('提示：要看具体响应内容，用 {"kind":"network","id":<上面列出的 #号>}');
      return {
        kind: 'network',
        ok: true,
        summary: query ? `API 匹配 "${query}" ${apis.length} 条` : `最近 ${apis.length} 条 API`,
        observation: lines.join('\n')
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
    case 'eval': {
      const code = (action.code || '').trim();
      if (!code) return fail('eval', 'eval 代码为空', 'error: eval code is empty');
      const out = await evalInPage(code);
      if (!out.ok) return fail('eval', `eval 出错: ${out.error || '未知错误'}`, `error: ${out.error || 'eval failed'}`);
      const summary = code.length > 36 ? `执行 ${code.slice(0, 36)}…` : `执行 ${code}`;
      return {
        kind: 'eval',
        ok: true,
        summary,
        observation: `[eval 结果 type=${out.type || 'unknown'} (已截断 4KB & 脱敏)]\n${out.result ?? '(无返回值)'}`
      };
    }
    case 'console': {
      const logs = recentConsole(action.level, Math.min(Math.max(action.limit ?? 30, 1), 100));
      if (logs.length === 0) {
        return { kind: 'console', ok: true, summary: '暂无 console 日志', observation: '[console]\n(空)' };
      }
      const now = Date.now();
      const levelLabel = action.level ? ` (${action.level})` : '';
      return {
        kind: 'console',
        ok: true,
        summary: `最近 ${logs.length} 条 console${levelLabel}`,
        observation: `[console${levelLabel} ${logs.length} 条]\n` + logs.map(e => formatConsoleEntry(e, now)).join('\n')
      };
    }
    case 'storage': {
      const items = readStorage(action.area ?? 'all', action.keyMatch);
      if (items.length === 0) {
        return { kind: 'storage', ok: true, summary: '无匹配的 storage 项', observation: '[storage]\n(空)' };
      }
      return {
        kind: 'storage',
        ok: true,
        summary: `${items.length} 条 storage`,
        observation: `[storage ${items.length} 条${action.keyMatch ? ` 匹配 "${action.keyMatch}"` : ''}]\n` + items.map(formatStorageItem).join('\n')
      };
    }
    case 'query': {
      const selector = (action.selector || '').trim();
      if (!selector) return fail('query', '选择器为空', 'error: selector is empty');
      const result = runQuery(selector, action.limit ?? 10, action.attr);
      if (!result.ok) return fail('query', result.error, `error: ${result.error}`);
      if (result.hits.length === 0) {
        return { kind: 'query', ok: true, summary: `${selector} 无匹配`, observation: `[query "${selector}"]\n(无匹配节点)` };
      }
      return {
        kind: 'query',
        ok: true,
        summary: `${selector} 命中 ${result.hits.length} 个`,
        observation: `[query "${selector}" ${result.hits.length} 个]\n` + result.hits.map(h => formatQueryHit(h, action.attr)).join('\n')
      };
    }
    case 'finish':
    case 'none':
      return { kind: action.kind, ok: true, summary: '', observation: '' };
  }
}

export function actionDenied(a: PetAction): ActionResult {
  return { kind: a.kind, ok: false, summary: '用户拒绝执行', observation: 'error: 用户拒绝了这次操作，请换一个思路或 finish 说明' };
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
