// 从 assets/icon.svg 光栅化出 16/32/48/128 四个尺寸的 PNG 到 public/icons/
// 在 `npm run build` / `npm run dev` 之前自动跑。
import sharp from 'sharp';
import fs from 'fs/promises';
import path from 'path';
import url from 'url';

const root = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
const srcSvg = path.join(root, 'assets', 'icon.svg');
const outDir = path.join(root, 'public', 'icons');

const sizes = [16, 32, 48, 128];

const svgBuffer = await fs.readFile(srcSvg);
await fs.mkdir(outDir, { recursive: true });

await Promise.all(
  sizes.map(async (size) => {
    const out = path.join(outDir, `icon-${size}.png`);
    await sharp(svgBuffer, { density: Math.max(72, size * 4) })
      .resize(size, size)
      .png({ compressionLevel: 9 })
      .toFile(out);
    console.log(`✓ ${path.relative(root, out)}  (${size}x${size})`);
  })
);
