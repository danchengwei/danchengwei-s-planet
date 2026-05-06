import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'

// 确保 DOM 加载完成后再初始化 React
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => {
    const root = document.getElementById('root')
    if (root) {
      createRoot(root).render(
        <StrictMode>
          <App />
        </StrictMode>,
      )
    } else {
      console.error('Failed to find root element')
    }
  })
} else {
  // DOM 已经加载完成
  const root = document.getElementById('root')
  if (root) {
    createRoot(root).render(
      <StrictMode>
        <App />
      </StrictMode>,
    )
  } else {
    console.error('Failed to find root element')
  }
}
