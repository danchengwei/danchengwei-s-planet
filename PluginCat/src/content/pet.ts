import type { AskRequest, AskResponse, ChatMessage, PetAction } from '../shared/types';
import { buildObservation, formatObservation, initNetworkObserver, recentNetwork, formatNetwork } from './observe';
import { runAction, type ActionResult } from './actions';
import type { PetRenderer } from './renderer/spine';
import { detectContext, contextToState, timeOfDayState, pickHobby } from './activity';
import { spawnEffect, type FxKind } from './fx';

const ROOT_ID = '__web_pet__';
const MOUNT_SENTINEL = '__WEB_PET_MOUNTED__';
const MAX_STEPS = 6;
const MAX_CHAT_TURNS = 4;

/* ============================================================
 * 颜文字 & 心情文案库
 * ============================================================ */
const pick = <T>(arr: readonly T[]): T => arr[Math.floor(Math.random() * arr.length)];

const BLINK_MOODS    = ['(•́ᴗ•̀)', '(=ↀωↀ=)', '(=^･^=)'] as const;
const YAWN_MOODS     = ['好困…', 'ふぁ〜', '(-_-) zzz', '(=ᆽ=)~ᴗ'] as const;
const STRETCH_MOODS  = ['伸个懒腰~', '(´-ω-)~', 'ん〜', '嗯~'] as const;
const LOOK_MOODS     = ['那是啥？', '(・・)?', '(=•́ω•̀=)'] as const;
const MEOW_MOODS     = ['喵!', '喵~', '(=^ω^=)', 'ฅ(^ω^ฅ)'] as const;
const HEART_MOODS    = ['喜欢喵~', '(=˘ᴗ˘=)♡', 'ฅ(=^ω^=)ฅ♥', '好舒服~'] as const;
const DIZZY_MOODS    = ['晕了…', '(@_@)', 'ヽ(゜Д゜)ﾉ', '头晕喵…'] as const;
const CURIOUS_MOODS  = ['？', '(・・)？', '嗯？', '(=・◞ェ◟・=)?'] as const;
const HAPPY_MOODS    = ['(=˘ᴗ˘=)♪', '开心~', '✧(•ㅂ•)', '♪♪'] as const;
const WAVE_MOODS     = ['嗨~', '(・ω・)ノ', '你好呀~', 'ฅ(･ω･ฅ)'] as const;
const SLEEP_MOODS    = ['Zzz…', '(˘ω˘) zzz', '呼~呼~'] as const;
const SHY_MOODS      = ['害羞了…', '(//ω//)', '(〃▽〃)', '不要这样嘛~'] as const;
const SCARED_MOODS   = ['吓我一跳！', '(ﾟДﾟ;)', '呜…', 'Σ(°Д°;'] as const;
const SAD_MOODS      = ['呜…', '(｡•́︿•̀｡)', '不要扔下我…', '(；ω；)'] as const;
const EXCITED_MOODS  = ['哇！起飞!', '(★^O^★)', '冲鸭!', 'ヽ(°▽°)ノ'] as const;
const THINK_MOODS    = ['让我想想…', '(・_・)', '嗯……', '(¬_¬)'] as const;
const BOW_MOODS      = ['请多指教~', '(￣▽￣)ゞ', 'Ojigi~', '你好~'] as const;
const STEALTH_MOODS  = ['悄悄地…', '(=ↀωↀ=)…', 'shhh~', '潜行中'] as const;
const SNEEZE_MOODS   = ['啊嚏！', 'くしゅん', '(>д<)!!', 'hacchi!'] as const;
const HICCUP_MOODS   = ['嗝~', '嗝！', '(o_O)嗝', '打嗝了…'] as const;
const DANCE_MOODS    = ['♪跳跳~', '(ﾉ´ヮ`)ﾉ*:・ﾟ✧', '♫♪♬', 'la la~'] as const;
const SING_MOODS     = ['🎵喵喵~', '(ᐛ)♪', '乐！', '🎶~'] as const;
const EXERCISE_MOODS = ['健身时间!', '(>_<)ง', '加油!', '肌肉！'] as const;
const EATING_MOODS   = ['吃饭饭~', '(=^・ェ・^=)', 'num num~', '好香~', '吃小鱼干!'] as const;
const WATCHING_MOODS = ['追剧中', '(ﾟoﾟ)📺', '好看!', '看得入迷'] as const;
const WORKING_MOODS  = ['认真工作…', '( ･_･)ｼﾞｰ', '敲敲键盘', '写代码ing'] as const;
const READING_MOODS  = ['看书中', '(｡･ω･｡)📖', '嗯嗯…', '知识入脑'] as const;
const SLEEPY_MOODS   = ['好困呀…', '(-.-)Zzz', '眼皮好重', '撑不住了…'] as const;
const LONELY_MOODS   = ['好无聊…', '(´-ω-`)', '陪陪我嘛~', '寂寞猫'] as const;
const GREETING_MOODS = ['早安~', 'ohayo!', '早上好!', '☀️'] as const;
const PURR_MOODS     = ['咕噜咕噜~', 'purr~', '(=˘ω˘=)', '好舒服'] as const;
const QUIET_KAOMOJI = [
  '咕噜咕噜~', '(=^‥^=)', 'ฅ(^ω^)ฅ', '(=ↀωↀ=)✧',
  '在想事情…', '(´- ω -`)', '(´・ω・｀)', '(=ＴェＴ=)',
  '有小鱼干吗~', '想你了~', '喵喵喵？', '(＾・ω・＾✿)',
  '嗯嗯~', '(=^-ω-^=)', 'ฅ(=ↀωↀ=)ฅ'
] as const;

/* ============================================================
 * SVG 小橘猫 —— Spine 资源加载失败时的回退
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
  </g>
</svg>
`;

/* ============================================================
 * 状态机
 * ============================================================ */
export type PetState =
  | 'idle' | 'blink' | 'talking' | 'sleep' | 'yawn' | 'wave' | 'happy'
  | 'stretch' | 'look' | 'meow' | 'heart' | 'dizzy' | 'curious'
  // 新增：情绪反应
  | 'shy' | 'scared' | 'sad' | 'excited' | 'think' | 'bow' | 'stealth' | 'purr'
  // 新增：生理反应
  | 'sneeze' | 'hiccup'
  // 新增：业余爱好
  | 'dance' | 'sing' | 'exercise'
  // 新增：日常活动
  | 'eating' | 'watching' | 'working' | 'reading'
  // 新增：时辰与长期状态
  | 'sleepy' | 'lonely' | 'greeting';

interface PetAnimTarget { name: string; loop: boolean; timeScale?: number }

/**
 * FSM 状态 → Spine 动画映射
 * spineboy 占位资源可用动作：idle / walk / run / jump / death / hoverboard / aim / shoot / portal
 * 想换成自家美术时，改这张表即可
 */
const STATE_ANIMATION: Record<PetState, PetAnimTarget> = {
  idle:     { name: 'idle',       loop: true },
  blink:    { name: 'idle',       loop: true },
  look:     { name: 'idle',       loop: true },
  meow:     { name: 'idle',       loop: true },
  stretch:  { name: 'idle',       loop: true },
  curious:  { name: 'idle',       loop: true },
  heart:    { name: 'idle',       loop: true },
  yawn:     { name: 'idle',       loop: true, timeScale: 0.4 },
  talking:  { name: 'walk',       loop: true, timeScale: 0.9 },
  wave:     { name: 'jump',       loop: false },
  happy:    { name: 'jump',       loop: false },
  sleep:    { name: 'death',      loop: false },
  dizzy:    { name: 'hoverboard', loop: true, timeScale: 1.4 },
  // 新增映射（把表情差异化让给气泡；动作上复用 spineboy 的 9 个动画）
  shy:      { name: 'idle',       loop: true, timeScale: 0.8 },
  scared:   { name: 'hoverboard', loop: true, timeScale: 1.6 },
  sad:      { name: 'idle',       loop: true, timeScale: 0.6 },
  excited:  { name: 'jump',       loop: false, timeScale: 1.3 },
  think:    { name: 'aim',        loop: true, timeScale: 0.6 },
  bow:      { name: 'jump',       loop: false, timeScale: 0.7 },
  stealth:  { name: 'walk',       loop: true, timeScale: 0.5 },
  purr:     { name: 'idle',       loop: true },
  sneeze:   { name: 'jump',       loop: false, timeScale: 1.6 },
  hiccup:   { name: 'idle',       loop: true },
  dance:    { name: 'run',        loop: true, timeScale: 1.1 },
  sing:     { name: 'idle',       loop: true, timeScale: 1.1 },
  exercise: { name: 'run',        loop: true, timeScale: 1.3 },
  eating:   { name: 'idle',       loop: true, timeScale: 0.9 },
  watching: { name: 'idle',       loop: true, timeScale: 0.75 },
  working:  { name: 'walk',       loop: true, timeScale: 0.8 },
  reading:  { name: 'idle',       loop: true, timeScale: 0.7 },
  sleepy:   { name: 'idle',       loop: true, timeScale: 0.5 },
  lonely:   { name: 'idle',       loop: true, timeScale: 0.7 },
  greeting: { name: 'jump',       loop: false, timeScale: 0.9 },
};

/**
 * 不同 state 的 "mood 气泡词库"；交给 PetStateMachine.setStateWithMood 选词
 * 默认 idle/talking 不带词库（不自动冒气泡）
 */
const STATE_MOODS: Partial<Record<PetState, readonly string[]>> = {
  blink:    BLINK_MOODS,
  yawn:     YAWN_MOODS,
  stretch:  STRETCH_MOODS,
  look:     LOOK_MOODS,
  meow:     MEOW_MOODS,
  heart:    HEART_MOODS,
  dizzy:    DIZZY_MOODS,
  curious:  CURIOUS_MOODS,
  happy:    HAPPY_MOODS,
  wave:     WAVE_MOODS,
  sleep:    SLEEP_MOODS,
  shy:      SHY_MOODS,
  scared:   SCARED_MOODS,
  sad:      SAD_MOODS,
  excited:  EXCITED_MOODS,
  think:    THINK_MOODS,
  bow:      BOW_MOODS,
  stealth:  STEALTH_MOODS,
  purr:     PURR_MOODS,
  sneeze:   SNEEZE_MOODS,
  hiccup:   HICCUP_MOODS,
  dance:    DANCE_MOODS,
  sing:     SING_MOODS,
  exercise: EXERCISE_MOODS,
  eating:   EATING_MOODS,
  watching: WATCHING_MOODS,
  working:  WORKING_MOODS,
  reading:  READING_MOODS,
  sleepy:   SLEEPY_MOODS,
  lonely:   LONELY_MOODS,
  greeting: GREETING_MOODS,
};

/**
 * 状态 → 特效映射：spineboy 动画只有 9 种，大量状态共用 idle/jump。
 * 通过 CSS 粒子特效让不同状态在视觉上真正有区分。
 */
const STATE_FX: Partial<Record<PetState, FxKind>> = {
  // 正向/喜欢
  heart:    'hearts',
  happy:    'sparkles',
  excited:  'sparkles',
  wave:     'ripple',
  greeting: 'ripple',
  bow:      'ripple',
  // 负向/紧张
  scared:   'exclaim',
  sneeze:   'exclaim',
  dizzy:    'glitch',
  // 睡眠/困倦
  sleep:    'zzz',
  sleepy:   'zzz',
  yawn:     'zzz',
  // 好奇/思考
  curious:  'question',
  think:    'question',
  // 艺能
  sing:     'note',
  dance:    'note',
};

type AnimPlayer = (target: PetAnimTarget) => void;

class PetStateMachine {
  private current: PetState = 'idle';
  private autoTimer: number | null = null;
  private sleepTimer: number | null = null;
  private reverter: number | null = null;
  private moodTimer: number | null = null;
  private lonelyTimer: number | null = null;
  private macroTimer: number | null = null;
  private clockTimer: number | null = null;
  private lastTimeState: PetState | null = null;
  private busy = false;
  private player: AnimPlayer | null = null;

  constructor(
    private root: HTMLElement,
    private moodEl: HTMLElement,
    private fxLayer: HTMLElement,
  ) {
    root.classList.add('state-idle');
  }

  /** 随机挑一个 mood；若状态没绑词库返回 undefined */
  private moodFor(state: PetState): string | undefined {
    const bank = STATE_MOODS[state];
    return bank ? pick(bank) : undefined;
  }

  /** 接上渲染器后补一次当前动画，避免初始化竞态 */
  attachPlayer(player: AnimPlayer) {
    this.player = player;
    player(STATE_ANIMATION[this.current]);
  }

  setState(next: PetState, durationMs?: number, mood?: string) {
    if (this.reverter) { clearTimeout(this.reverter); this.reverter = null; }
    if (this.current !== next) {
      this.root.classList.remove(`state-${this.current}`);
      this.root.classList.add(`state-${next}`);
      this.current = next;
      this.player?.(STATE_ANIMATION[next]);
      const fx = STATE_FX[next];
      if (fx) spawnEffect(this.fxLayer, fx);
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
      this.scheduleLonely();
    }
  }

  interact(greet = false) {
    this.notePoke();
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

  /** 记录一次用户互动，用来重置 "lonely" 计时器 */
  notePoke() {
    this.scheduleLonely();
  }

  startAutoTicks() {
    this.stopAutoTicks();
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
    // 18% blink / 11% yawn / 11% stretch / 9% look / 9% meow / 5% wave / 5% happy
    // 3% sneeze / 3% hiccup / 3% dance / 3% sing / 3% exercise / 14% 安静冒颜文字
    if      (r < 0.18) { this.setState('blink', 180, Math.random() < 0.3 ? pick(BLINK_MOODS) : undefined); }
    else if (r < 0.29) { this.setState('yawn', 1100, pick(YAWN_MOODS)); }
    else if (r < 0.40) { this.setState('stretch', 1200, pick(STRETCH_MOODS)); }
    else if (r < 0.49) { this.setState('look', 1400, pick(LOOK_MOODS)); }
    else if (r < 0.58) { this.setState('meow', 1500, pick(MEOW_MOODS)); }
    else if (r < 0.63) { this.setState('wave', 1200, pick(WAVE_MOODS)); }
    else if (r < 0.68) { this.setState('happy', 700, pick(HAPPY_MOODS)); }
    else if (r < 0.71) { this.setState('sneeze', 900, pick(SNEEZE_MOODS)); }
    else if (r < 0.74) { this.setState('hiccup', 1400, pick(HICCUP_MOODS)); }
    else if (r < 0.77) { this.setState('dance', 2000, pick(DANCE_MOODS)); }
    else if (r < 0.80) { this.setState('sing', 2000, pick(SING_MOODS)); }
    else if (r < 0.83) { this.setState('exercise', 2200, pick(EXERCISE_MOODS)); }
    else if (r < 0.97) { this.showMood(pick(QUIET_KAOMOJI), 1600); }
  }

  /** 每 3~5 分钟挑一个 "业余爱好" 持续几秒，模拟日常活动 */
  startMacroRoutine() {
    this.stopMacroRoutine();
    const schedule = () => {
      const delay = 180_000 + Math.random() * 120_000;
      this.macroTimer = window.setTimeout(() => {
        if (!this.busy && this.current === 'idle') {
          const hobby = pickHobby();
          this.setState(hobby, 4500, this.moodFor(hobby));
        }
        schedule();
      }, delay);
    };
    schedule();
  }

  stopMacroRoutine() {
    if (this.macroTimer) { clearTimeout(this.macroTimer); this.macroTimer = null; }
  }

  /** 每分钟检查时辰；早/午/晚/夜若变化则触发对应状态（一个时辰只触发一次） */
  startClockWatcher() {
    this.stopClockWatcher();
    const check = () => {
      const next = timeOfDayState();
      if (next && next !== this.lastTimeState && !this.busy && this.current === 'idle') {
        this.lastTimeState = next;
        this.setState(next, 3500, this.moodFor(next));
      } else if (!next) {
        this.lastTimeState = null;
      }
    };
    check();
    this.clockTimer = window.setInterval(check, 60_000);
  }

  stopClockWatcher() {
    if (this.clockTimer) { clearInterval(this.clockTimer); this.clockTimer = null; }
  }

  /** 依据当前页面上下文做一次 "入场活动"，比如在 bilibili 默认切看剧 */
  applyContextOnce(href: string) {
    const ctx = detectContext(href);
    const state = contextToState(ctx);
    if (state) {
      // 稍等 greet 结束再切
      window.setTimeout(() => {
        if (!this.busy && this.current === 'idle') {
          this.setState(state, 4000, this.moodFor(state));
        }
      }, 2200);
    }
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

  /** 15s 没被 poke 且仍在 idle → 孤单一下（不会打断 sleep 流程） */
  scheduleLonely() {
    if (this.lonelyTimer) clearTimeout(this.lonelyTimer);
    this.lonelyTimer = window.setTimeout(() => {
      if (!this.busy && this.current === 'idle') {
        this.setState('lonely', 1800, pick(LONELY_MOODS));
      }
    }, 15000);
  }

  destroy() {
    this.stopAutoTicks();
    this.stopMacroRoutine();
    this.stopClockWatcher();
    this.clearSleepTimer();
    if (this.lonelyTimer) { clearTimeout(this.lonelyTimer); this.lonelyTimer = null; }
    if (this.reverter)    { clearTimeout(this.reverter);    this.reverter = null; }
    if (this.moodTimer)   { clearTimeout(this.moodTimer);   this.moodTimer = null; }
  }

  showMood(text: string, ms = 1400) {
    this.moodEl.textContent = text;
    this.moodEl.classList.add('show');
    if (this.moodTimer) clearTimeout(this.moodTimer);
    this.moodTimer = window.setTimeout(() => this.moodEl.classList.remove('show'), ms);
  }
}

/* ============================================================
 * Agent 执行轨迹
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

function looksLikeAgentJson(raw: string): boolean {
  const t = raw.trim();
  if (!t) return false;
  // 允许模型在 JSON 前后带自然语言前缀/后缀；只要任意位置出现包含 "kind" 或 "action" 的 JSON 片段即视为 Agent 输出。
  // 小模型（hunyuan-lite / glm-flash）普遍会在 JSON 前加一句 "好的我来帮你~"，严格的 startsWith 会误伤。
  return /\{[\s\S]*?"(kind|action)"[\s\S]*?\}/.test(t);
}

/* ============================================================
 * 异步加载 Spine 渲染器；失败时注入 SVG 回退
 * ============================================================ */
async function initRenderer(
  avatar: HTMLElement,
  fsm: PetStateMachine,
): Promise<PetRenderer | null> {
  try {
    const mod = await import('./renderer/spine');
    const renderer = await mod.createSpineRenderer(84);
    // canvas 装到 .pet-avatar
    avatar.innerHTML = '';
    avatar.appendChild(renderer.canvas);
    fsm.attachPlayer((target) => renderer.play(target.name, target));
    avatar.classList.add('has-spine');
    return renderer;
  } catch (err) {
    console.warn('[web-pet] Spine 渲染器加载失败，回退到 SVG：', err);
    if (!avatar.innerHTML.trim()) avatar.innerHTML = CAT_SVG;
    avatar.classList.add('has-svg-fallback');
    return null;
  }
}

/* ============================================================
 * 组件挂载
 * ============================================================ */
export function mountPet() {
  if ((window as any)[MOUNT_SENTINEL]) return;
  if (document.getElementById(ROOT_ID)) return;
  (window as any)[MOUNT_SENTINEL] = true;

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
    <div class="pet-fx" data-fx></div>
    <div class="pet-avatar" data-avatar></div>
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
  const fxLayer = root.querySelector<HTMLElement>('[data-fx]')!;

  const fsm = new PetStateMachine(root, moodEl, fxLayer);
  fsm.startAutoTicks();
  fsm.scheduleSleep();
  fsm.scheduleLonely();
  fsm.startMacroRoutine();
  fsm.startClockWatcher();
  window.setTimeout(() => fsm.setState('wave', 1200, '你好呀~'), 700);
  // 入场活动（bilibili → watching / github → working / 美食站 → eating …）
  fsm.applyContextOnce(location.href);

  // 拖拽：拖到顶部→excited、拖到底部→sad、速度很快→scared（每次拖只触发一次）
  let dragZoneFired: 'top' | 'bottom' | 'fast' | null = null;
  enableDrag(root, avatar, (info) => {
    fsm.notePoke();
    if (dragZoneFired) return;
    if (info.topY < 40) {
      dragZoneFired = 'top';
      fsm.setState('excited', 2000, pick(EXCITED_MOODS));
    } else if (info.bottomY > window.innerHeight - 4) {
      dragZoneFired = 'bottom';
      fsm.setState('sad', 2200, pick(SAD_MOODS));
    } else if (info.speedPxPerMs > 2.5) {
      dragZoneFired = 'fast';
      fsm.setState('scared', 1500, pick(SCARED_MOODS));
    }
  }, () => { dragZoneFired = null; });

  // 异步装 Spine 渲染器；失败自动回退 SVG
  const deferRendererInit = (cb: () => void) => {
    const ric = (window as any).requestIdleCallback as
      | ((cb: () => void, opts?: { timeout: number }) => number)
      | undefined;
    if (ric) ric(cb, { timeout: 1500 });
    else window.setTimeout(cb, 16);
  };
  deferRendererInit(() => { void initRenderer(avatar, fsm); });

  // 调试入口
  (window as any).__petDemo = (s: PetState, ms = 2000, mood?: string) => {
    fsm.setState(s, ms, mood);
    return `triggered state-${s} for ${ms}ms`;
  };
  console.log('[web-pet] 调试：__petDemo("heart") / __petDemo("dizzy") / __petDemo("sleep") 等');

  /* ---- 鼠标手势（共 18 种）---- */
  const clickTimes: number[] = [];
  let hoverTimer: number | null = null;
  let longPressTimer: number | null = null;
  let superLongPressTimer: number | null = null;
  let longPressed = false;
  let dblClickFirstAt = 0;
  let hoverEnterAt = 0;
  let lastShyAt = 0;
  let lastShakeAt = 0;

  avatar.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    longPressed = false;
    if (longPressTimer) clearTimeout(longPressTimer);
    if (superLongPressTimer) clearTimeout(superLongPressTimer);
    longPressTimer = window.setTimeout(() => {
      longPressTimer = null;
      longPressed = true;
      fsm.setState('heart', 1500, pick(HEART_MOODS));
    }, 500);
    // 2.5s 超长按 → 睡在手上
    superLongPressTimer = window.setTimeout(() => {
      superLongPressTimer = null;
      longPressed = true;
      fsm.setState('sleep', 4000, pick(SLEEP_MOODS));
    }, 2500);
  });

  const cancelPressTimers = () => {
    if (longPressTimer) { clearTimeout(longPressTimer); longPressTimer = null; }
    if (superLongPressTimer) { clearTimeout(superLongPressTimer); superLongPressTimer = null; }
  };
  window.addEventListener('mousemove', cancelPressTimers);
  window.addEventListener('mouseup', cancelPressTimers);

  avatar.addEventListener('click', (e) => {
    if (longPressed) { longPressed = false; return; }
    fsm.notePoke();

    // 修饰键分流
    if (e.shiftKey) {
      fsm.setState('bow', 1600, pick(BOW_MOODS));
      return;
    }
    if (e.ctrlKey || e.metaKey) {
      fsm.setState('stealth', 2200, pick(STEALTH_MOODS));
      return;
    }
    if (e.altKey) {
      fsm.setState('meow', 1600, 'MEOW!!');
      return;
    }

    const now = Date.now();
    clickTimes.push(now);
    while (clickTimes.length && clickTimes[0] < now - 2000) clickTimes.shift();
    if (clickTimes.length >= 3) {
      clickTimes.length = 0;
      fsm.setState('dizzy', 2500, pick(DIZZY_MOODS));
      return;
    }

    if (now - dblClickFirstAt < 400) {
      dblClickFirstAt = 0;
      fsm.setState('happy', 800, pick(HAPPY_MOODS));
      return;
    }
    dblClickFirstAt = now;

    const willOpen = !panel.classList.contains('open');
    panel.classList.toggle('open');
    if (willOpen) {
      input.focus();
      fsm.interact(true);
    }
  });

  // 右键 → think
  avatar.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    fsm.setState('think', 2200, pick(THINK_MOODS));
    fsm.notePoke();
  });

  // 中键 → sneeze
  avatar.addEventListener('auxclick', (e) => {
    if (e.button === 1) {
      e.preventDefault();
      fsm.setState('sneeze', 900, pick(SNEEZE_MOODS));
      fsm.notePoke();
    }
  });

  // 滚轮 over pet → dizzy（吞滚动避免影响宿主页）
  avatar.addEventListener('wheel', (e) => {
    e.preventDefault();
    fsm.setState('dizzy', 1500, pick(DIZZY_MOODS));
    fsm.notePoke();
  }, { passive: false });

  // 悬停 1.5s 不动 → curious；并记录进入时间用于 "shy"
  avatar.addEventListener('mouseenter', () => {
    hoverEnterAt = Date.now();
    fsm.interact();
    if (hoverTimer) clearTimeout(hoverTimer);
    hoverTimer = window.setTimeout(() => {
      if (fsm.state === 'idle') fsm.setState('curious', 2200, pick(CURIOUS_MOODS));
    }, 1500);
  });
  avatar.addEventListener('mouseleave', () => {
    if (hoverTimer) { clearTimeout(hoverTimer); hoverTimer = null; }
    // 光顾一下就跑 → 害羞（10s 冷却，避免扫过鼠标误触）
    const dur = Date.now() - hoverEnterAt;
    if (hoverEnterAt && dur > 40 && dur < 200 && Date.now() - lastShyAt > 10_000 && fsm.state === 'idle') {
      lastShyAt = Date.now();
      fsm.setState('shy', 1800, pick(SHY_MOODS));
    }
  });

  // 鼠标在 pet 上快速来回 → scared（0.8s 内 ≥3 次方向反转，2.5s 冷却）
  let moveSamples: { t: number; x: number }[] = [];
  let lastDirSign: 1 | -1 | 0 = 0;
  let dirChanges = 0;
  avatar.addEventListener('mousemove', (e) => {
    const now = Date.now();
    moveSamples.push({ t: now, x: e.clientX });
    moveSamples = moveSamples.filter((m) => now - m.t < 800);
    if (moveSamples.length < 2) return;
    const prev = moveSamples[moveSamples.length - 2];
    const dx = e.clientX - prev.x;
    if (Math.abs(dx) < 4) return;
    const sign: 1 | -1 = dx > 0 ? 1 : -1;
    if (lastDirSign !== 0 && sign !== lastDirSign) {
      dirChanges++;
      if (dirChanges >= 3 && now - lastShakeAt > 2500) {
        lastShakeAt = now;
        dirChanges = 0;
        fsm.setState('scared', 1800, pick(SCARED_MOODS));
        fsm.notePoke();
      }
    }
    lastDirSign = sign;
  });

  panel.addEventListener('mouseenter', () => fsm.interact());
  input.addEventListener('focus', () => fsm.interact());

  // 面板头部长按 → purr（"撸猫"；300ms 即可触发，比 heart 更快）
  const headerEl = panel.querySelector('.pet-header') as HTMLElement | null;
  if (headerEl) {
    let headerTimer: number | null = null;
    headerEl.addEventListener('mousedown', () => {
      if (headerTimer) clearTimeout(headerTimer);
      headerTimer = window.setTimeout(() => {
        headerTimer = null;
        fsm.setState('purr', 2000, pick(PURR_MOODS));
      }, 300);
    });
    const cancelHeader = () => { if (headerTimer) { clearTimeout(headerTimer); headerTimer = null; } };
    headerEl.addEventListener('mouseup', cancelHeader);
    headerEl.addEventListener('mouseleave', cancelHeader);
  }

  closeBtn.addEventListener('click', (e) => {
    e.stopPropagation();
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

        if (step === 1) {
          if (!looksLikeAgentJson(raw)) {
            finalReply = raw.trim() || reply || '…';
            thinkingBubble.textContent = finalReply;
            thinkingBubble.classList.remove('thinking');
            reachedFinish = true;
            break;
          }
          inAgent = true;
          thinkingBubble.remove();
          progress.logThought(thought);
          progress.logAction(action);
        } else {
          progress.logThought(thought);
          progress.logAction(action);
        }

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
      if (!inAgent) progress.discard();

      if (!errored) {
        if (inAgent) {
          if (!reachedFinish) finalReply = '这次有点难喵… 超过最大步数了，要不换个说法？';
          appendMessage('bot', finalReply);
        }
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

interface DragInfo {
  topY: number;        // pet 上边缘当前 viewport y
  bottomY: number;     // pet 下边缘当前 viewport y
  speedPxPerMs: number;// 上一帧鼠标速度
}

function enableDrag(
  root: HTMLElement,
  handle: HTMLElement,
  onDragMove?: (info: DragInfo) => void,
  onDragEnd?: () => void,
) {
  let startX = 0, startY = 0, origRight = 24, origBottom = 24;
  let dragging = false;
  let moved = false;
  let lastX = 0, lastY = 0, lastT = 0;

  handle.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return; // 只响应左键开始拖
    dragging = true;
    moved = false;
    startX = e.clientX;
    startY = e.clientY;
    lastX = e.clientX; lastY = e.clientY; lastT = Date.now();
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

    if (onDragMove) {
      const now = Date.now();
      const dt = Math.max(now - lastT, 1);
      const speed = Math.hypot(e.clientX - lastX, e.clientY - lastY) / dt;
      lastX = e.clientX; lastY = e.clientY; lastT = now;
      const rect = root.getBoundingClientRect();
      onDragMove({ topY: rect.top, bottomY: rect.bottom, speedPxPerMs: speed });
    }
  });

  window.addEventListener('mouseup', () => {
    if (!dragging) return;
    dragging = false;
    if (moved) {
      handle.addEventListener('click', suppressOnce, { capture: true, once: true });
      onDragEnd?.();
    }
  });

  function suppressOnce(ev: Event) {
    ev.stopImmediatePropagation();
    ev.preventDefault();
  }
}
