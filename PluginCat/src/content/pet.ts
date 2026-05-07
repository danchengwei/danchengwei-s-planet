import type { AskRequest, AskResponse, ChatMessage, PetAction } from '../shared/types';
import { buildObservation, formatObservation, initNetworkObserver, recentNetwork, formatNetwork } from './observe';
import { runAction, type ActionResult } from './actions';

const ROOT_ID = '__web_pet__';
const MAX_STEPS = 6;
const MAX_CHAT_TURNS = 4;

/* ============================================================
 * 颜文字 & 心情文案库
 * 每种状态/场景都有多条随机抽，避免重复感
 * ============================================================ */
const pick = <T>(arr: readonly T[]): T => arr[Math.floor(Math.random() * arr.length)];

const BLINK_MOODS   = ['(•́ᴗ•̀)', '(=ↀωↀ=)', '(=^･^=)'] as const;
const YAWN_MOODS    = ['好困…', 'ふぁ〜', '(-_-) zzz', '(=ᆽ=)~ᴗ'] as const;
const STRETCH_MOODS = ['伸个懒腰~', '(´-ω-)~', 'ん〜', '嗯~'] as const;
const LOOK_MOODS    = ['那是啥？', '(・・)?', '(=•́ω•̀=)'] as const;
const MEOW_MOODS    = ['喵!', '喵~', '(=^ω^=)', 'ฅ(^ω^ฅ)'] as const;
const HEART_MOODS   = ['喜欢喵~', '(=˘ᴗ˘=)♡', 'ฅ(=^ω^=)ฅ♥', '好舒服~'] as const;
const DIZZY_MOODS   = ['晕了…', '(@_@)', 'ヽ(゜Д゜)ﾉ', '头晕喵…'] as const;
const CURIOUS_MOODS = ['？', '(・・)？', '嗯？', '(=・◞ェ◟・=)?'] as const;
const HAPPY_MOODS   = ['(=˘ᴗ˘=)♪', '开心~', '✧(•ㅂ•)', '♪♪'] as const;
const WAVE_MOODS    = ['嗨~', '(・ω・)ノ', '你好呀~', 'ฅ(･ω･ฅ)'] as const;
const SLEEP_MOODS   = ['Zzz…', '(˘ω˘) zzz', '呼~呼~'] as const;
const QUIET_KAOMOJI = [
  '咕噜咕噜~', '(=^‥^=)', 'ฅ(^ω^)ฅ', '(=ↀωↀ=)✧',
  '在想事情…', '(´- ω -`)', '(´・ω・｀)', '(=ＴェＴ=)',
  '有小鱼干吗~', '想你了~', '喵喵喵？', '(＾・ω・＾✿)',
  '嗯嗯~', '(=^-ω-^=)', 'ฅ(=ↀωↀ=)ฅ'
] as const;

/* ============================================================
 * SVG 小橘猫（加了心形 / 星星两组隐藏图层）
 * ============================================================ */
const CAT_SVG = `
<svg viewBox="0 0 120 140" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <g class="cat-body">
    <ellipse class="ground" cx="60" cy="134" rx="28" ry="3.5" />
    <g class="tail"><path class="fur" d="M84,108 Q112,100 104,76 Q99,68 96,78 Q100,94 82,104 Z" /></g>
    <ellipse class="fur" cx="60" cy="108" rx="32" ry="22" />
    <ellipse class="belly" cx="60" cy="114" rx="17" ry="12" />
    <g>
      <ellipse class="fur" cx="38" cy="125" rx="9" ry="6" />
      <circle class="paw-pad" cx="35" cy="125" r="1.3" />
      <circle class="paw-pad" cx="38" cy="124.5" r="1.3" />
      <circle class="paw-pad" cx="41" cy="125" r="1.3" />
    </g>
    <g class="paw-wave">
      <ellipse class="fur" cx="82" cy="125" rx="9" ry="6" />
      <circle class="paw-pad" cx="79" cy="125" r="1.3" />
      <circle class="paw-pad" cx="82" cy="124.5" r="1.3" />
      <circle class="paw-pad" cx="85" cy="125" r="1.3" />
    </g>
    <g class="head">
      <g class="ear ear-l">
        <path class="fur" d="M24,44 L32,12 L54,36 Z" />
        <path class="ear-inner" d="M30,38 L35,22 L48,37 Z" />
      </g>
      <g class="ear ear-r">
        <path class="fur" d="M96,44 L88,12 L66,36 Z" />
        <path class="ear-inner" d="M90,38 L85,22 L72,37 Z" />
      </g>
      <circle class="fur" cx="60" cy="56" r="36" />
      <line class="whisker" x1="18" y1="58" x2="38" y2="60" />
      <line class="whisker" x1="18" y1="65" x2="38" y2="65" />
      <line class="whisker" x1="18" y1="72" x2="38" y2="70" />
      <line class="whisker" x1="102" y1="58" x2="82" y2="60" />
      <line class="whisker" x1="102" y1="65" x2="82" y2="65" />
      <line class="whisker" x1="102" y1="72" x2="82" y2="70" />
      <circle class="cheek" cx="40" cy="66" r="5" />
      <circle class="cheek" cx="80" cy="66" r="5" />
      <g class="eye eye-l">
        <g class="eye-open">
          <ellipse class="eye-fill" cx="48" cy="52" rx="4" ry="6" />
          <ellipse class="eye-shine" cx="49.5" cy="49" rx="1.3" ry="2" />
        </g>
        <path class="closed-eye" d="M42,54 Q48,58 54,54" />
      </g>
      <g class="eye eye-r">
        <g class="eye-open">
          <ellipse class="eye-fill" cx="72" cy="52" rx="4" ry="6" />
          <ellipse class="eye-shine" cx="73.5" cy="49" rx="1.3" ry="2" />
        </g>
        <path class="closed-eye" d="M66,54 Q72,58 78,54" />
      </g>
      <path class="nose" d="M56,66 L64,66 L60,71 Z" />
      <path class="mouth-smile" d="M48,74 Q54,80 60,74 Q66,80 72,74" />
      <ellipse class="mouth-o" cx="60" cy="77" rx="4" ry="3" />
      <ellipse class="mouth-yawn" cx="60" cy="79" rx="8" ry="7" />
    </g>
    <g class="zzz-group">
      <text class="zzz z1" x="86" y="34" font-size="14">z</text>
      <text class="zzz z2" x="96" y="22" font-size="16">z</text>
      <text class="zzz z3" x="106" y="10" font-size="18">Z</text>
    </g>
    <g class="hearts" aria-hidden="true">
      <text class="heart h1" x="36" y="22" font-size="14">♥</text>
      <text class="heart h2" x="60" y="10" font-size="18">♥</text>
      <text class="heart h3" x="82" y="22" font-size="14">♥</text>
    </g>
    <g class="stars" aria-hidden="true">
      <text class="star s1" x="44" y="22" font-size="13">✦</text>
      <text class="star s2" x="76" y="22" font-size="13">✦</text>
      <text class="star s3" x="60" y="10" font-size="13">✦</text>
    </g>
  </g>
</svg>
`;

/* ============================================================
 * 状态机
 * ============================================================ */
type PetState =
  | 'idle' | 'blink' | 'talking' | 'sleep' | 'yawn' | 'wave' | 'happy'
  | 'stretch' | 'look' | 'meow' | 'heart' | 'dizzy' | 'curious';

class PetStateMachine {
  private current: PetState = 'idle';
  private autoTimer: number | null = null;
  private sleepTimer: number | null = null;
  private reverter: number | null = null;
  private moodTimer: number | null = null;
  private busy = false;

  constructor(private root: HTMLElement, private moodEl: HTMLElement) {
    root.classList.add('state-idle');
  }

  setState(next: PetState, durationMs?: number, mood?: string) {
    if (this.reverter) { clearTimeout(this.reverter); this.reverter = null; }
    if (this.current !== next) {
      this.root.classList.remove(`state-${this.current}`);
      this.root.classList.add(`state-${next}`);
      this.current = next;
    }
    if (mood) this.showMood(mood);
    if (durationMs) {
      this.reverter = window.setTimeout(() => {
        this.reverter = null;
        if (this.current === next && !this.busy) this.setState('idle');
      }, durationMs);
    }
  }

  get state() { return this.current; }

  setBusy(busy: boolean) {
    this.busy = busy;
    if (busy) {
      this.clearSleepTimer();
      this.stopAutoTicks();
      this.setState('talking');
    } else {
      this.setState('idle');
      this.startAutoTicks();
      this.scheduleSleep();
    }
  }

  interact(greet = false) {
    if (this.current === 'sleep') {
      this.setState('yawn', 900, pick(['被吵醒了…', 'ふぁ〜？', '嗯…?']));
      window.setTimeout(() => {
        if (!this.busy) this.setState(greet ? 'wave' : 'idle', greet ? 1200 : undefined, greet ? pick(WAVE_MOODS) : undefined);
      }, 900);
    } else if (greet && !this.busy) {
      this.setState('wave', 1200, pick(WAVE_MOODS));
    }
    this.scheduleSleep();
  }

  startAutoTicks() {
    this.stopAutoTicks();
    // 间隔在 2.5–4.5s 之间随机，避免节奏机械
    this.scheduleNextTick();
  }

  private scheduleNextTick() {
    const delay = 2500 + Math.random() * 2000;
    this.autoTimer = window.setTimeout(() => {
      this.tick();
      if (this.autoTimer != null) this.scheduleNextTick();
    }, delay);
  }

  stopAutoTicks() {
    if (this.autoTimer) { clearTimeout(this.autoTimer); this.autoTimer = null; }
  }

  private tick() {
    if (this.busy) return;
    if (this.current !== 'idle') return;
    const r = Math.random();
    // 20% blink、12% yawn、12% stretch、10% look、10% meow、
    // 6% wave（跟自己打招呼）、6% happy、14% 只是冒颜文字、10% 安静
    if      (r < 0.20) { this.setState('blink', 180, Math.random() < 0.3 ? pick(BLINK_MOODS) : undefined); }
    else if (r < 0.32) { this.setState('yawn', 1100, pick(YAWN_MOODS)); }
    else if (r < 0.44) { this.setState('stretch', 1200, pick(STRETCH_MOODS)); }
    else if (r < 0.54) { this.setState('look', 1400, pick(LOOK_MOODS)); }
    else if (r < 0.64) { this.setState('meow', 1500, pick(MEOW_MOODS)); }
    else if (r < 0.70) { this.setState('wave', 1200, pick(WAVE_MOODS)); }
    else if (r < 0.76) { this.setState('happy', 700, pick(HAPPY_MOODS)); }
    else if (r < 0.90) { this.showMood(pick(QUIET_KAOMOJI), 1600); } // 只冒颜文字，不改状态
    // 其余 10% 安静
  }

  scheduleSleep() {
    this.clearSleepTimer();
    this.sleepTimer = window.setTimeout(() => {
      if (!this.busy && (this.current === 'idle' || this.current === 'blink')) {
        this.setState('sleep', undefined, pick(SLEEP_MOODS));
      }
    }, 25000);
  }

  private clearSleepTimer() {
    if (this.sleepTimer) { clearTimeout(this.sleepTimer); this.sleepTimer = null; }
  }

  showMood(text: string, ms = 1400) {
    this.moodEl.textContent = text;
    this.moodEl.classList.add('show');
    if (this.moodTimer) clearTimeout(this.moodTimer);
    this.moodTimer = window.setTimeout(() => this.moodEl.classList.remove('show'), ms);
  }
}

/* ============================================================
 * Agent 执行轨迹（仅在真的进入 Agent 模式时才创建 DOM）
 * ============================================================ */
class AgentProgress {
  readonly container: HTMLElement;
  private pending: HTMLElement | null = null;
  private mounted = false;
  private msgBox: HTMLElement;

  constructor(msgBox: HTMLElement) {
    this.msgBox = msgBox;
    this.container = document.createElement('div');
    this.container.className = 'pet-exec';
  }

  private mount() {
    if (this.mounted) return;
    this.msgBox.appendChild(this.container);
    this.mounted = true;
    this.scrollIntoView();
  }

  /** 丢弃这个轨迹（聊天模式走这里，避免页面残留空轨迹容器） */
  discard() {
    this.clearPending();
    if (this.mounted) this.container.remove();
  }

  setPending(text: string) {
    this.mount();
    this.clearPending();
    const row = document.createElement('div');
    row.className = 'pet-step pending';
    row.innerHTML = `<span class="spinner-sm"></span><span class="step-text"></span>`;
    row.querySelector('.step-text')!.textContent = text;
    this.container.appendChild(row);
    this.pending = row;
    this.scrollIntoView();
  }

  clearPending() {
    if (this.pending) { this.pending.remove(); this.pending = null; }
  }

  logThought(thought: string) {
    if (!thought) return;
    this.append('💭', thought, 'thought');
  }

  logAction(action: PetAction) {
    this.append(iconFor(action), describeAction(action), 'action');
  }

  logResult(result: ActionResult) {
    if (!result.summary) return;
    this.append(result.ok ? '·' : '⚠️', result.summary, result.ok ? 'result' : 'error');
  }

  logError(message: string) {
    this.append('⚠️', message, 'error');
  }

  private append(icon: string, text: string, variant: string) {
    this.mount();
    this.clearPending();
    const row = document.createElement('div');
    row.className = `pet-step ${variant}`;
    row.innerHTML = `<span class="step-icon"></span><span class="step-text"></span>`;
    row.querySelector('.step-icon')!.textContent = icon;
    row.querySelector('.step-text')!.textContent = text;
    this.container.appendChild(row);
    this.scrollIntoView();
  }

  private scrollIntoView() {
    this.msgBox.scrollTop = this.msgBox.scrollHeight;
  }
}

function iconFor(a: PetAction): string {
  switch (a.kind) {
    case 'observe': return '🔍';
    case 'network': return '🌐';
    case 'scroll':  return '📜';
    case 'click':   return '👆';
    case 'fill':    return '✍️';
    case 'read':    return '👁️';
    case 'wait':    return '⏳';
    case 'finish':  return '✅';
    case 'none':    return '·';
  }
}

function describeAction(a: PetAction): string {
  switch (a.kind) {
    case 'observe': return '观察页面';
    case 'network': return '查看网络请求';
    case 'scroll':  return `滚动到 ${a.to === 'top' ? '顶部' : a.to === 'bottom' ? '底部' : a.to + 'px'}`;
    case 'click':   return `点击 [${a.index}]`;
    case 'fill':    return `填入 [${a.index}]`;
    case 'read':    return `读取 [${a.index}]`;
    case 'wait':    return `等待 ${a.ms}ms`;
    case 'finish':  return '完成';
    case 'none':    return '无动作';
  }
}

/** 判断模型输出是否意图进入 Agent 模式 */
function looksLikeAgentJson(raw: string): boolean {
  const t = raw.trim();
  if (!t) return false;
  if (t.startsWith('```')) return /"action"/.test(t);
  if (t.startsWith('{'))   return /"action"/.test(t);
  return false;
}

/* ============================================================
 * 组件挂载
 * ============================================================ */
export function mountPet() {
  if (document.getElementById(ROOT_ID)) return;

  initNetworkObserver();

  const root = document.createElement('div');
  root.id = ROOT_ID;
  root.innerHTML = `
    <div class="pet-panel" data-panel>
      <div class="pet-header">
        <span>🐱 网页小助手</span>
        <span class="pet-close" data-close>×</span>
      </div>
      <div class="pet-messages" data-messages>
        <div class="pet-msg sys">嗨，我是喵助手，可以问我页面的问题，也可以让我帮你操作浏览器～</div>
      </div>
      <div class="pet-input-row">
        <input class="pet-input" data-input placeholder="问我点什么…（Enter 发送）" />
        <button class="pet-send" data-send>发送</button>
      </div>
    </div>
    <div class="pet-mood" data-mood></div>
    <div class="pet-avatar" data-avatar>${CAT_SVG}</div>
  `;
  document.documentElement.appendChild(root);

  injectStyle();

  const avatar = root.querySelector<HTMLElement>('[data-avatar]')!;
  const panel = root.querySelector<HTMLElement>('[data-panel]')!;
  const closeBtn = root.querySelector<HTMLElement>('[data-close]')!;
  const input = root.querySelector<HTMLInputElement>('[data-input]')!;
  const sendBtn = root.querySelector<HTMLButtonElement>('[data-send]')!;
  const msgBox = root.querySelector<HTMLElement>('[data-messages]')!;
  const moodEl = root.querySelector<HTMLElement>('[data-mood]')!;

  enableDrag(root, avatar);

  const fsm = new PetStateMachine(root, moodEl);
  fsm.startAutoTicks();
  fsm.scheduleSleep();
  window.setTimeout(() => fsm.setState('wave', 1200, '你好呀~'), 700);

  // 调试入口：在 DevTools Console 里运行 __petDemo('heart') / 'dizzy' / 'meow' / 'stretch' / 'look' / 'curious' / 'wave' / 'yawn'
  (window as any).__petDemo = (s: PetState, ms = 2000, mood?: string) => {
    fsm.setState(s, ms, mood);
    return `triggered state-${s} for ${ms}ms`;
  };
  console.log('[web-pet] 调试：在 Console 里试试 __petDemo("heart") / __petDemo("dizzy") / __petDemo("meow") 等');

  /* ---- 鼠标交互（纯鼠标，无快捷键） ----
     - 单击: 开/关面板
     - 连点 2s 内 ≥3 次: 晕
     - 长按 ≥500ms: 摸摸（heart）
     - 悬停 ≥1.5s: 好奇歪头
     - 双击: 开心弹跳（happy）  */
  const clickTimes: number[] = [];
  let hoverTimer: number | null = null;
  let longPressTimer: number | null = null;
  let longPressed = false;
  let dblClickFirstAt = 0;

  avatar.addEventListener('mousedown', () => {
    longPressed = false;
    if (longPressTimer) clearTimeout(longPressTimer);
    longPressTimer = window.setTimeout(() => {
      longPressTimer = null;
      longPressed = true;
      fsm.setState('heart', 1500, pick(HEART_MOODS));
    }, 500);
  });
  const cancelLongPress = () => {
    if (longPressTimer) { clearTimeout(longPressTimer); longPressTimer = null; }
  };
  window.addEventListener('mousemove', cancelLongPress);
  window.addEventListener('mouseup', () => {
    // 松开时取消正在计数的长按，但不清 longPressed（click 阶段要读）
    cancelLongPress();
  });

  avatar.addEventListener('click', () => {
    // 长按已触发过 heart，不再切面板
    if (longPressed) { longPressed = false; return; }

    // 连点统计（2 秒内 ≥3 次 = 晕）
    const now = Date.now();
    clickTimes.push(now);
    while (clickTimes.length && clickTimes[0] < now - 2000) clickTimes.shift();
    if (clickTimes.length >= 3) {
      clickTimes.length = 0;
      fsm.setState('dizzy', 2500, pick(DIZZY_MOODS));
      return;
    }

    // 双击检测（400ms）
    if (now - dblClickFirstAt < 400) {
      dblClickFirstAt = 0;
      fsm.setState('happy', 800, pick(HAPPY_MOODS));
      return;
    }
    dblClickFirstAt = now;

    // 普通点击 = 切换面板
    const willOpen = !panel.classList.contains('open');
    panel.classList.toggle('open');
    if (willOpen) {
      input.focus();
      fsm.interact(true);
    }
  });

  avatar.addEventListener('mouseenter', () => {
    fsm.interact();
    if (hoverTimer) clearTimeout(hoverTimer);
    hoverTimer = window.setTimeout(() => {
      if (fsm.state === 'idle') fsm.setState('curious', 2200, pick(CURIOUS_MOODS));
    }, 1500);
  });
  avatar.addEventListener('mouseleave', () => {
    if (hoverTimer) { clearTimeout(hoverTimer); hoverTimer = null; }
  });

  panel.addEventListener('mouseenter', () => fsm.interact());
  input.addEventListener('focus', () => fsm.interact());

  closeBtn.addEventListener('click', () => {
    panel.classList.remove('open');
    fsm.setState('happy', 700, '拜拜~');
  });

  /* ---- 会话 ---- */
  const chatHistory: ChatMessage[] = [];
  let busy = false;

  const onSend = async () => {
    if (busy) return;
    const q = input.value.trim();
    if (!q) return;
    input.value = '';
    appendMessage('user', q);
    busy = true;
    sendBtn.disabled = true;
    fsm.setBusy(true);

    const progress = new AgentProgress(msgBox);
    let finalReply = '';
    let reachedFinish = false;
    let errored = false;
    let inAgent = false;

    const ob = buildObservation();
    const net = recentNetwork();
    const firstTurn = `用户请求：${q}\n\n${formatObservation(ob)}${net.length ? '\n\n[最近网络请求]\n' + net.map(formatNetwork).join('\n') : ''}`;

    const messages: ChatMessage[] = [
      ...chatHistory.slice(-MAX_CHAT_TURNS * 2),
      { role: 'user', content: firstTurn }
    ];

    const thinkingBubble = appendMessage('bot', '思考中…');
    thinkingBubble.classList.add('thinking');

    try {
      for (let step = 1; step <= MAX_STEPS; step++) {
        if (inAgent && step > 1) progress.setPending(`第 ${step}/${MAX_STEPS} 步：思考中…`);

        const res = (await chrome.runtime.sendMessage({ type: 'ASK', messages } as AskRequest)) as AskResponse;

        if (!res?.ok || !res.step) {
          errored = true;
          const errMsg = `出错了：${res?.error || '未知错误'}`;
          if (inAgent) progress.logError(errMsg);
          else thinkingBubble.textContent = errMsg;
          break;
        }

        const { thought, reply, action, raw } = res.step;
        messages.push({ role: 'assistant', content: raw });

        /* ======== 第 1 轮：分流到聊天 or Agent ======== */
        if (step === 1) {
          if (!looksLikeAgentJson(raw)) {
            // ===== 聊天模式：直接把 raw 当回答显示 =====
            finalReply = raw.trim() || reply || '…';
            thinkingBubble.textContent = finalReply;
            thinkingBubble.classList.remove('thinking');
            reachedFinish = true;
            break;
          }
          // 进入 Agent 模式：把 thinking bubble 替换成执行轨迹
          inAgent = true;
          thinkingBubble.remove();
          progress.logThought(thought);
          progress.logAction(action);
        } else {
          progress.logThought(thought);
          progress.logAction(action);
        }

        /* ======== Agent 模式分支处理 ======== */
        if (action.kind === 'finish') {
          finalReply = action.reply || reply || '搞定啦~';
          reachedFinish = true;
          break;
        }
        if (action.kind === 'none') {
          finalReply = reply || '（模型没给出下一步动作）';
          reachedFinish = true;
          break;
        }

        const result = await runAction(action);
        progress.logResult(result);
        messages.push({ role: 'user', content: `[action result]\n${result.observation || (result.ok ? 'ok' : 'failed')}` });
      }
    } catch (err: any) {
      errored = true;
      const msg = `出错了：${err?.message || err}`;
      if (inAgent) progress.logError(msg);
      else thinkingBubble.textContent = msg;
    } finally {
      progress.clearPending();
      if (!inAgent) {
        // 聊天模式下 progress 从未 mount，DOM 里没东西——保险起见再 discard 一次
        progress.discard();
      }

      if (!errored) {
        if (inAgent) {
          if (!reachedFinish) finalReply = '这次有点难喵… 超过最大步数了，要不换个说法？';
          appendMessage('bot', finalReply);
        }
        // 聊天模式的 finalReply 已经写在 thinkingBubble 里，不用再 append

        if (reachedFinish && finalReply) {
          chatHistory.push({ role: 'user', content: q });
          chatHistory.push({ role: 'assistant', content: finalReply });
        }
      }

      busy = false;
      sendBtn.disabled = false;
      fsm.setBusy(false);
    }
  };

  sendBtn.addEventListener('click', onSend);
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      onSend();
    }
  });

  function appendMessage(role: 'user' | 'bot' | 'sys', text: string) {
    const el = document.createElement('div');
    el.className = `pet-msg ${role}`;
    el.textContent = text;
    msgBox.appendChild(el);
    msgBox.scrollTop = msgBox.scrollHeight;
    return el;
  }
}

function injectStyle() {
  if (document.getElementById('__web_pet_style__')) return;
  const link = document.createElement('link');
  link.id = '__web_pet_style__';
  link.rel = 'stylesheet';
  link.href = chrome.runtime.getURL('src/content/pet.css');
  document.documentElement.appendChild(link);
}

function enableDrag(root: HTMLElement, handle: HTMLElement) {
  let startX = 0, startY = 0, origRight = 24, origBottom = 24;
  let dragging = false;
  let moved = false;

  handle.addEventListener('mousedown', (e) => {
    dragging = true;
    moved = false;
    startX = e.clientX;
    startY = e.clientY;
    const rect = root.getBoundingClientRect();
    origRight = window.innerWidth - rect.right;
    origBottom = window.innerHeight - rect.bottom;
    e.preventDefault();
  });

  window.addEventListener('mousemove', (e) => {
    if (!dragging) return;
    const dx = e.clientX - startX;
    const dy = e.clientY - startY;
    if (Math.abs(dx) + Math.abs(dy) > 3) moved = true;
    root.style.right = `${Math.max(0, origRight - dx)}px`;
    root.style.bottom = `${Math.max(0, origBottom - dy)}px`;
  });

  window.addEventListener('mouseup', () => {
    if (!dragging) return;
    dragging = false;
    if (moved) handle.addEventListener('click', suppressOnce, { capture: true, once: true });
  });

  function suppressOnce(ev: Event) {
    ev.stopImmediatePropagation();
    ev.preventDefault();
  }
}
