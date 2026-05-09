/**
 * 宠物交互特效粒子层
 * 负责在 .pet-fx 容器里按 FxKind 生成短暂动画元素，自动清理
 */

export type FxKind =
  | 'hearts'     // 爱心飘上去（长按/heart）
  | 'sparkles'   // 闪光爆开（happy/excited）
  | 'exclaim'    // 红色感叹号抖动（scared/sneeze）
  | 'zzz'        // Z 飘升（sleep/sleepy）
  | 'question'   // 问号弹出（curious/think）
  | 'ripple'     // 青色光环向外扩散（wave/greeting/bow）
  | 'note'       // 音符摇摆飘升（sing/dance）
  | 'glitch';    // 短暂故障色差（dizzy）

interface FxConfig {
  text: string;
  count: number;
  cls: string;
  /** 动画时长 ms，用来清理 */
  duration: number;
}

const FX_CONFIG: Record<FxKind, FxConfig> = {
  hearts:   { text: '♥', count: 3, cls: 'fx-hearts',   duration: 1400 },
  sparkles: { text: '✦', count: 6, cls: 'fx-sparkles', duration: 900  },
  exclaim:  { text: '!', count: 1, cls: 'fx-exclaim',  duration: 800  },
  zzz:      { text: 'z', count: 3, cls: 'fx-zzz',      duration: 2200 },
  question: { text: '?', count: 1, cls: 'fx-question', duration: 1100 },
  ripple:   { text: '',  count: 1, cls: 'fx-ripple',   duration: 700  },
  note:     { text: '♪', count: 3, cls: 'fx-note',     duration: 1500 },
  glitch:   { text: '',  count: 1, cls: 'fx-glitch',   duration: 500  },
};

/** 在指定容器里释放一次特效，自动清理 DOM */
export function spawnEffect(layer: HTMLElement, kind: FxKind): void {
  const cfg = FX_CONFIG[kind];
  if (!cfg) return;

  for (let i = 0; i < cfg.count; i++) {
    const el = document.createElement('span');
    el.className = `pet-fx-item ${cfg.cls}`;
    el.textContent = cfg.text;
    // 每颗粒子给随机参数，通过 CSS 变量读取
    el.style.setProperty('--i', String(i));
    el.style.setProperty('--dx', `${(Math.random() - 0.5) * 40}px`);
    el.style.setProperty('--dy', `${40 + Math.random() * 30}px`);
    el.style.setProperty('--rot', `${(Math.random() - 0.5) * 60}deg`);
    el.style.setProperty('--delay', `${i * 60}ms`);
    layer.appendChild(el);

    window.setTimeout(() => el.remove(), cfg.duration + 100);
  }
}
