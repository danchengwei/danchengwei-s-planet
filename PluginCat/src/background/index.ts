import type { AskRequest, AskResponse, BgMessage, Settings, TestRequest, TestResponse } from '../shared/types';
import { callLLM, parseAgentOutput, pingLLM } from '../shared/llm';
import { DEFAULT_PROVIDER } from '../shared/providers';

chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.sync.get(['settings', 'apiKey']).then(({ settings, apiKey }) => {
    const ok = (settings && settings.apiKey) || apiKey;
    if (!ok) chrome.runtime.openOptionsPage();
  });
});

chrome.action.onClicked.addListener(() => {
  chrome.runtime.openOptionsPage();
});

chrome.runtime.onMessage.addListener((msg: BgMessage, _sender, sendResponse) => {
  console.log('[web-pet/bg] recv', msg?.type);
  if (msg?.type === 'ASK') {
    handleAsk(msg).then((r) => {
      console.log('[web-pet/bg] ASK resp', { ok: r.ok, action: r.step?.action?.kind, error: r.error });
      sendResponse(r);
    }).catch((err) => {
      console.error('[web-pet/bg] ASK crash', err);
      sendResponse({ ok: false, error: err?.message || String(err) } as AskResponse);
    });
    return true;
  }
  if (msg?.type === 'TEST') {
    handleTest(msg).then((r) => {
      console.log('[web-pet/bg] TEST resp', r);
      sendResponse(r);
    }).catch((err) => {
      console.error('[web-pet/bg] TEST crash', err);
      sendResponse({ ok: false, error: err?.message || String(err) } as TestResponse);
    });
    return true;
  }
  return undefined;
});

async function handleAsk(msg: AskRequest): Promise<AskResponse> {
  const settings = await readSettings();
  if (!settings || !settings.apiKey) {
    return { ok: false, error: '还没配置模型服务，点扩展图标去设置页填一下吧~' };
  }
  try {
    const raw = await callLLM(settings, msg.messages);
    const step = parseAgentOutput(raw);
    return { ok: true, step };
  } catch (err: any) {
    return { ok: false, error: err?.message || String(err) };
  }
}

async function handleTest(msg: TestRequest): Promise<TestResponse> {
  console.log('[web-pet/bg] TEST start provider=', msg.settings.provider, 'model=', msg.settings.model || '(default)');
  const r = await pingLLM(msg.settings);
  return r.ok ? { ok: true, sample: r.sample } : { ok: false, error: r.error };
}

/** 兼容旧版：老版只存过 apiKey（默认视为 hunyuan） */
async function readSettings(): Promise<Settings | null> {
  const data = await chrome.storage.sync.get(['settings', 'apiKey']);
  if (data.settings && data.settings.apiKey) return data.settings as Settings;
  if (data.apiKey) return { provider: DEFAULT_PROVIDER, apiKey: data.apiKey, model: '' };
  return null;
}
