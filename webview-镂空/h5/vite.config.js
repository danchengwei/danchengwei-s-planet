import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

/** 去掉 type="module"，否则 Android WebView 在 file:// 下常不执行脚本 */
function stripScriptModuleType() {
  return {
    name: 'strip-script-module-type',
    apply: 'build', // 仅在构建时生效，dev 模式必须保留 type="module"
    transformIndexHtml: {
      order: 'post',
      handler(html) {
        // 去掉 type="module" 和 crossorigin：Android WebView 在 file:// 下
        // 1) 不执行 type=module 脚本；2) 会按 CORS 拒绝带 crossorigin 的脚本/样式
        return html
          .replace(/\s*type="module"/gi, '')
          .replace(/\s*crossorigin(?:="[^"]*")?/gi, '')
      },
    },
  }
}

// https://vite.dev/config/
export default defineConfig({
  base: './',
  plugins: [react(), stripScriptModuleType()],
  // Vite 8 用 oxc 代替 esbuild 处理用户源码；降级到 es2019 让旧 WebView 也能跑（??= 等 ES2020+ 会报 Unexpected token '='）
  oxc: {
    target: 'es2019',
  },
  // 预打包 node_modules 时也要降级（react-dom 里有 ??=）。Vite 8 用 rolldown，target 放在 transform 下
  optimizeDeps: {
    rolldownOptions: {
      transform: {
        target: 'es2019',
      },
    },
  },
  // 打成 IIFE 单包，index 用普通 script 标签，便于 Android WebView 通过 file:///android_asset/ 加载（避免 type=module 在 file 协议下不执行）
  build: {
    target: 'es2015',
    cssCodeSplit: false,
    rollupOptions: {
      output: {
        format: 'iife',
        inlineDynamicImports: true,
        name: 'MyDemoH5',
      },
    },
  },
  server: {
    host: '0.0.0.0', // 允许外部访问（Android设备访问）
    port: 5173,
    // HMR 必须让 WebView 知道连电脑的 IP，而不是 localhost
    hmr: {
      host: '10.8.227.21',
      port: 5173,
    },
  }
})
