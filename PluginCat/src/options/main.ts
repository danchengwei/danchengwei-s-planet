import { DEFAULT_PROVIDER, getProvider, PROVIDERS, PROVIDER_IDS, type ProviderId } from '../shared/providers';
import type { Settings, TestRequest, TestResponse } from '../shared/types';

const providerSel = document.getElementById('provider') as HTMLSelectElement;
const modelInput  = document.getElementById('model') as HTMLInputElement;
const modelHint   = document.getElementById('modelHint') as HTMLElement;
const keyInput    = document.getElementById('apiKey') as HTMLInputElement;
const docLink     = document.getElementById('docLink') as HTMLAnchorElement;
const saveBtn     = document.getElementById('save') as HTMLButtonElement;
const busy        = document.getElementById('busy') as HTMLElement;

// Modal elements
const modal          = document.getElementById('modal') as HTMLElement;
const modalCard      = modal.querySelector('.modal-card') as HTMLElement;
const modalIcon      = document.getElementById('modalIcon') as HTMLElement;
const modalTitle     = document.getElementById('modalTitle') as HTMLElement;
const modalBody      = document.getElementById('modalBody') as HTMLElement;
const modalSample    = document.getElementById('modalSample') as HTMLElement;
const modalPrimary   = document.getElementById('modalPrimary') as HTMLButtonElement;
const modalSecondary = document.getElementById('modalSecondary') as HTMLButtonElement;

/* ---- 初始化下拉 ---- */
for (const id of PROVIDER_IDS) {
  const opt = document.createElement('option');
  opt.value = id;
  opt.textContent = PROVIDERS[id].label;
  providerSel.appendChild(opt);
}

providerSel.addEventListener('change', () => applyProvider(providerSel.value as ProviderId));

saveBtn.addEventListener('click', saveAndTest);
for (const el of [modelInput, keyInput]) {
  el.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') saveAndTest();
  });
}

modal.addEventListener('click', (e) => {
  if ((e.target as HTMLElement).dataset.modalClose !== undefined) closeModal();
});
modalPrimary.addEventListener('click', closeModal);

load();

/* ---- 逻辑 ---- */
async function load() {
  const data = await chrome.storage.sync.get(['settings', 'apiKey']);
  let s: Partial<Settings> = {};
  if (data.settings) s = data.settings;
  else if (data.apiKey) s = { provider: DEFAULT_PROVIDER, apiKey: data.apiKey, model: '' };

  const pid: ProviderId = PROVIDERS[s.provider as ProviderId] ? (s.provider as ProviderId) : DEFAULT_PROVIDER;
  providerSel.value = pid;
  applyProvider(pid);
  if (s.model) modelInput.value = s.model;
  if (s.apiKey) keyInput.value = s.apiKey;
}

function applyProvider(id: ProviderId) {
  const p = getProvider(id); // 未知 id 自动回落到默认 provider
  modelInput.placeholder = `默认：${p.defaultModel}`;
  modelHint.textContent = `留空则使用默认模型 ${p.defaultModel}`;
  keyInput.placeholder = p.keyHint;
  docLink.href = p.docUrl;
  docLink.textContent = `→ 去 ${p.label} 获取 API Key`;
}

const FRONT_TIMEOUT_MS = 45_000;
let busyTickTimer: number | null = null;
const busyLabel = busy.querySelector('span:last-child') as HTMLElement;

function startBusyTicker() {
  const t0 = Date.now();
  busyLabel.textContent = '正在测试模型连通性…（0s）';
  busyTickTimer = window.setInterval(() => {
    const s = Math.floor((Date.now() - t0) / 1000);
    busyLabel.textContent = `正在测试模型连通性…（${s}s）`;
  }, 500);
}
function stopBusyTicker() {
  if (busyTickTimer != null) { clearInterval(busyTickTimer); busyTickTimer = null; }
  busyLabel.textContent = '正在测试模型连通性…';
}

async function saveAndTest() {
  const provider = providerSel.value as ProviderId;
  const model = modelInput.value.trim();
  const apiKey = keyInput.value.trim();

  if (!apiKey) {
    showModal('error', '还没填 API Key', '请先填入 API Key 再点完成。');
    return;
  }

  const settings: Settings = { provider, apiKey, model };
  await chrome.storage.sync.set({ settings });
  await chrome.storage.sync.remove('apiKey').catch(() => {});

  saveBtn.disabled = true;
  busy.hidden = false;
  startBusyTicker();

  console.log('[web-pet/options] test start', { provider, model: model || '(default)' });

  try {
    const req: TestRequest = { type: 'TEST', settings };
    // 前端超时兜底：即使 background 没回 sendResponse 也能让 UI 跳出去
    const res = await Promise.race([
      chrome.runtime.sendMessage(req) as Promise<TestResponse>,
      new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error(
          `前端等待超时（${FRONT_TIMEOUT_MS / 1000}s）。可能是 background 无响应；请到 chrome://extensions → 本扩展 → "Service Worker" 查看报错。`
        )), FRONT_TIMEOUT_MS)
      )
    ]);

    console.log('[web-pet/options] test result', res);

    if (!res) {
      showModal('error', '测试失败', 'background 没返回任何数据；可能 Service Worker 崩了，请查看扩展的 Service Worker 控制台。');
    } else if (res.ok) {
      showSuccess(res.sample || '');
    } else {
      showModal('error', '测试失败', res.error || '未知错误，请检查 API Key 是否正确');
    }
  } catch (err: any) {
    console.error('[web-pet/options] test error', err);
    showModal('error', '测试失败', err?.message || String(err));
  } finally {
    stopBusyTicker();
    saveBtn.disabled = false;
    busy.hidden = true;
  }
}

function showSuccess(sample: string) {
  modalCard.classList.remove('error'); modalCard.classList.add('success');
  modalIcon.textContent = '✓';
  modalTitle.textContent = '配置成功！🎉';
  modalBody.innerHTML = `
    模型已经准备好了。<br/>
    打开任意普通网页，右下角就能看到小橘猫 —— 点它就能对话，也可以直接拖着它换位置。<br/>
    <strong style="color:#d04a3b">已经打开过的网页需要刷新一下才会出现哦~</strong>
  `;
  if (sample) {
    modalSample.hidden = false;
    modalSample.textContent = `模型回复样例：${sample}`;
  } else {
    modalSample.hidden = true;
  }
  modalSecondary.hidden = false;
  modalSecondary.textContent = '去一个网页试试';
  modalSecondary.onclick = () => {
    chrome.tabs.create({ url: 'https://zh.wikipedia.org/wiki/Wikipedia:%E9%A6%96%E9%A1%B5' });
    closeModal();
  };
  modalPrimary.textContent = '好的';
  openModal();
}

function showModal(kind: 'success' | 'error', title: string, body: string) {
  modalCard.classList.remove('success', 'error');
  modalCard.classList.add(kind);
  modalIcon.textContent = kind === 'success' ? '✓' : '!';
  modalTitle.textContent = title;
  modalBody.textContent = body;
  modalSample.hidden = true;
  modalSecondary.hidden = true;
  modalSecondary.onclick = null;
  modalPrimary.textContent = '知道了';
  openModal();
}

function openModal() {
  modal.hidden = false;
  setTimeout(() => modalPrimary.focus(), 50);
}
function closeModal() {
  modal.hidden = true;
}
