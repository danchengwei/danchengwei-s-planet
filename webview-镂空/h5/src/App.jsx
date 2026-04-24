import { useEffect, useRef, useState } from 'react'
import './App.css'

/**
 * 中间取景框镂空：Web 层整体透明（除顶部栏 / 底部栏 / 按钮外），
 * 通过 viewfinder-hole-anchor 的超大 box-shadow 刷出四周米白色"取景框遮罩"。
 * 原生侧 TextureView 放在底层，WebView 位于顶层（透明），相机画面自然"透"出来。
 */
function App() {
  const holeRef = useRef(null)
  const [activeTab, setActiveTab] = useState('single')

  const callAndroid = (method, ...args) => {
    if (window.Android && typeof window.Android[method] === 'function') {
      try {
        window.Android[method](...args)
      } catch (err) {
        console.error('调用 Android 方法失败:', method, err)
      }
      return true
    }
    return false
  }

  const reportHoleRect = () => {
    const el = holeRef.current
    if (!el) return
    const r = el.getBoundingClientRect()
    callAndroid(
      'setNativeHoleRect',
      Math.round(r.left),
      Math.round(r.top),
      Math.round(r.width),
      Math.round(r.height)
    )
  }

  useEffect(() => {
    reportHoleRect()
    // 首次进入自动尝试开启相机（原生侧负责权限申请与幂等保护）
    const tAutoOpen = window.setTimeout(() => callAndroid('openCamera'), 350)
    const onResize = () => reportHoleRect()
    window.addEventListener('resize', onResize)
    let ro
    if (typeof ResizeObserver !== 'undefined') {
      ro = new ResizeObserver(reportHoleRect)
      if (holeRef.current) ro.observe(holeRef.current)
      ro.observe(document.body)
    }
    const tReport = window.setTimeout(reportHoleRect, 400)
    return () => {
      window.removeEventListener('resize', onResize)
      if (ro) ro.disconnect()
      window.clearTimeout(tAutoOpen)
      window.clearTimeout(tReport)
    }
  }, [])

  return (
    <div className="app-container">
      <div className="status-bar">
        <div className="time">9:41</div>
        <div className="status-icons">
          <span className="icon-signal" />
          <span className="icon-battery" />
        </div>
      </div>

      <div className="header">
        <button
          type="button"
          className="back-button"
          onClick={() => callAndroid('showMessage', '返回')}
          aria-label="返回"
        >
          <span className="back-chevron">&lt;</span>
        </button>
        <div className="tab-container">
          <button
            type="button"
            className={`tab ${activeTab === 'single' ? 'active' : ''}`}
            onClick={() => setActiveTab('single')}
          >
            单字测评
          </button>
          <button
            type="button"
            className={`tab ${activeTab === 'multi' ? 'active' : ''}`}
            onClick={() => setActiveTab('multi')}
          >
            多字测评
          </button>
        </div>
      </div>

      <div className="camera-section">
        <div className="camera-section-inner">
          <div
            id="h5-viewfinder-hole"
            ref={holeRef}
            className="viewfinder-hole-anchor"
            aria-hidden
          />
          <div className="viewfinder-white-ring" aria-hidden />
          <div className="left-decoration">
            <div className="monkey-icon" aria-hidden>
              🐵
            </div>
          </div>
        </div>
        <p className="instruction">
          <span className="spark">&#10022;</span>
          请将汉字居中放入方框内拍摄
          <span className="spark">&#10022;</span>
        </p>
      </div>

      <div className="bottom-controls">
        <div className="bottom-left-slot" />
        <button
          type="button"
          className="shutter-button"
          onClick={() => callAndroid('takePhoto')}
          aria-label="拍照"
        >
          <span className="shutter-inner">
            <span className="shutter-icon" />
          </span>
        </button>
        <button
          type="button"
          className="album-block"
          onClick={() => callAndroid('chooseFromAlbum')}
        >
          <span className="album-thumb" />
          <span className="album-label">相册导入</span>
        </button>
      </div>

      <div className="bottom-indicator">
        <div className="indicator-pill" />
      </div>
    </div>
  )
}

export default App
