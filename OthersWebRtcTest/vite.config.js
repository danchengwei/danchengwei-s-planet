import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0', // 允许局域网访问
    proxy: {
      // 配置代理
      '/api': {
        target: 'http://localhost:3000',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, '')
      },
      // 可以添加更多代理配置
      '/webrtc': {
        target: 'http://localhost:8080',
        changeOrigin: true
      }
    }
  }
})