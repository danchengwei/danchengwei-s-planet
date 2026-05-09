/**
 * PIXI v8 + Spine 宠物渲染器
 * 通过 chrome.runtime.getURL 加载 public/pet/spineboy 下的资源
 * 对外只暴露 play / destroy / ready
 */

export interface PetRenderer {
  canvas: HTMLCanvasElement;
  play(animation: string, opts?: { loop?: boolean; timeScale?: number }): void;
  destroy(): void;
}

const ASSET_BASE = 'pet/spineboy/';
const SKELETON_FILE = 'spineboy-pro.json';
const ATLAS_FILE = 'spineboy-pma.atlas';

export async function createSpineRenderer(
  size: number = 84,
): Promise<PetRenderer> {
  // Chrome 扩展 content script 禁用 unsafe-eval，必须在使用 Pixi 前先引入这个子模块
  // 用普通函数替代 Pixi v8 内部的 new Function() 管线
  await import('pixi.js/unsafe-eval');
  const { Application, Assets } = await import('pixi.js');
  const { Spine } = await import('@esotericsoftware/spine-pixi-v8');

  const app = new Application();
  await app.init({
    width: size,
    height: size,
    backgroundAlpha: 0,
    antialias: true,
    preference: 'webgl',
    failIfMajorPerformanceCaveat: false,
    powerPreference: 'low-power',
    resolution: Math.min(window.devicePixelRatio || 1, 2),
    autoDensity: true,
  });

  const skeletonAlias = 'petSkeleton';
  const atlasAlias = 'petAtlas';

  await Assets.load([
    { alias: skeletonAlias, src: chrome.runtime.getURL(ASSET_BASE + SKELETON_FILE) },
    { alias: atlasAlias, src: chrome.runtime.getURL(ASSET_BASE + ATLAS_FILE) },
  ]);

  const spine = Spine.from({ skeleton: skeletonAlias, atlas: atlasAlias });

  // spineboy 的骨骼原点在脚底、大概高 700 单位，缩放到 84×84 容器里站立
  const bounds = spine.getBounds();
  const scale = (size * 0.95) / Math.max(bounds.width, bounds.height);
  spine.scale.set(scale);
  // 水平居中，垂直让脚贴近底部
  spine.x = size / 2;
  spine.y = size - 4;

  app.stage.addChild(spine);

  // canvas 不吃交互事件（拖拽/点击交给外层 .pet-avatar div）
  app.canvas.style.pointerEvents = 'none';
  app.canvas.style.display = 'block';
  app.canvas.style.width = '100%';
  app.canvas.style.height = '100%';

  return {
    canvas: app.canvas,
    play(animation, opts = {}) {
      const loop = opts.loop ?? true;
      try {
        const track = spine.state.setAnimation(0, animation, loop);
        if (opts.timeScale != null) track.timeScale = opts.timeScale;
      } catch (err) {
        console.warn('[web-pet] spine play failed:', animation, err);
      }
    },
    destroy() {
      try {
        app.destroy(true, { children: true, texture: true, textureSource: true });
      } catch {
        /* noop */
      }
    },
  };
}
