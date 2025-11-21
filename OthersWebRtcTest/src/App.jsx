import { useState, useRef, useEffect } from 'react'
import './App.css'
// 引入Font Awesome图标
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faVideo, faInfoCircle, faGlobe, faLaptop, faCodeBranch, faMicrophone } from '@fortawesome/free-solid-svg-icons';
import { faStop, faPlay } from '@fortawesome/free-solid-svg-icons'

function App() {
  // 状态管理
  const [isCameraActive, setIsCameraActive] = useState(false)
  const [deviceInfo, setDeviceInfo] = useState('正在检测可用的媒体设备...')
  const [videoStatus, setVideoStatus] = useState('未连接')
  const [connectionStatus, setConnectionStatus] = useState('未连接') // 新增：WebRTC连接状态
  const [videoResolution, setVideoResolution] = useState('--')
  const [videoFrameRate, setVideoFrameRate] = useState('--')
  const [toasts, setToasts] = useState([])
  const [retryCount, setRetryCount] = useState(0) // 新增：重试次数
  const [roomId, setRoomId] = useState('') // 新增：房间号
  const maxRetries = 3 // 最大重试次数
  
  // 引用
  const videoRef = useRef(null)
  const remoteVideoRef = useRef(null) // 新增：用于显示远端视频
  const mediaStreamRef = useRef(null)
  const peerConnectionRef = useRef(null) // 新增：用于WebRTC连接
  const toastRef = useRef(null)

  // 检查WebRTC支持
  const checkWebRTCSupport = () => {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      showToast('您的浏览器不支持WebRTC技术，请使用Chrome、Firefox等现代浏览器', 'error')
      return false
    } else {
      // 兼容性处理
      navigator.getUserMedia = navigator.getUserMedia || 
                               navigator.webkitGetUserMedia || 
                               navigator.mozGetUserMedia || 
                               navigator.msGetUserMedia
      return true
    }
  }
  
  // 显示提示信息
  const showToast = (message, type = 'info') => {
    const id = Date.now()
    const newToast = { id, message, type }
    
    setToasts(prevToasts => [...prevToasts, newToast])
    
    // 3秒后自动移除
    setTimeout(() => {
      setToasts(prevToasts => prevToasts.filter(toast => toast.id !== id))
    }, 3000)
  }

  // 获取设备信息
  const getDeviceInfo = async () => {
    try {
      if (!checkWebRTCSupport()) {
        setDeviceInfo('当前浏览器不支持WebRTC')
        return
      }

      const devices = await navigator.mediaDevices.enumerateDevices()
      const videoDevices = devices.filter(device => device.kind === 'videoinput')
      const audioInputDevices = devices.filter(device => device.kind === 'audioinput')
      const audioOutputDevices = devices.filter(device => device.kind === 'audiooutput')
      
      // 更新设备信息显示
      setDeviceInfo({
        videoDevices,
        audioInputDevices,
        audioOutputDevices,
        totalDevices: devices.length
      })
    } catch (error) {
      console.error('获取设备信息失败:', error)
      setDeviceInfo({
        error: error.message,
        videoDevices: [],
        audioInputDevices: [],
        audioOutputDevices: [],
        totalDevices: 0
      })
      showToast(`获取设备信息失败: ${error.message}`, 'error')
    }
  }

  // 启动摄像头
  const startCamera = async () => {
    try {
      setVideoStatus('连接中...')
      
      if (!checkWebRTCSupport()) {
        setVideoStatus('未连接')
        return
      }
      
      // 先请求所有设备权限（包括音视频），确保能获取完整设备信息
      await requestMediaPermissions()

      // 获取媒体流
      const constraints = {
        video: {
          width: { ideal: 1280 },
          height: { ideal: 720 },
          frameRate: { ideal: 30 }
        },
        audio: false
      }

      const stream = await navigator.mediaDevices.getUserMedia(constraints)
      mediaStreamRef.current = stream

      // 设置视频源
      if (videoRef.current) {
        videoRef.current.srcObject = stream
        
        // 视频加载完成后更新信息
        videoRef.current.onloadedmetadata = () => updateVideoInfo()
      }
      
      // 权限授予后重新获取设备信息，以显示完整设备名称
      setTimeout(() => {
        getDeviceInfo()
        // 设置WebRTC连接
        setupLocalConnection()
      }, 500)

      setIsCameraActive(true)
      setVideoStatus('连接中...')
      showToast(`摄像头启动成功，正在加入房间 ${roomId.trim()}...`, 'success')
    } catch (error) {
      console.error('启动摄像头失败:', error)
      handleCameraError(error)
    }
  }
  
  // 处理摄像头错误
  const handleCameraError = (error) => {
    let errorMessage = '启动摄像头失败'
    
    if (error.name) {
      switch (error.name) {
        case 'NotAllowedError':
          errorMessage = '用户拒绝了摄像头权限请求'
          break
        case 'NotFoundError':
          errorMessage = '未找到可用的摄像头设备'
          break
        case 'NotSupportedError':
          errorMessage = '浏览器不支持指定的媒体类型'
          break
        case 'TrackStartError':
          errorMessage = '摄像头设备被其他应用占用'
          break
        case 'OverconstrainedError':
          errorMessage = '摄像头不支持指定的约束条件'
          break
        default:
          errorMessage = `摄像头启动失败: ${error.message || error.name}`
      }
    }
    
    setVideoStatus('连接失败')
    showToast(errorMessage, 'error')
  }
  
  // 更新视频信息
  const updateVideoInfo = () => {
    if (!videoRef.current || !mediaStreamRef.current) return
    
    // 更新分辨率信息
    const resolution = `${videoRef.current.videoWidth} × ${videoRef.current.videoHeight}`
    setVideoResolution(resolution)
    
    // 尝试获取帧率信息
    try {
      const videoTracks = mediaStreamRef.current.getVideoTracks()
      if (videoTracks.length > 0) {
        const videoTrack = videoTracks[0]
        const settings = videoTrack.getSettings()
        const frameRate = settings.frameRate || 30
        const frameRateText = `${Math.round(frameRate)} FPS`
        
        setVideoFrameRate(frameRateText)
      }
    } catch (error) {
      console.error('获取视频信息失败:', error)
    }
  }

  // 停止摄像头和连接
  const stopCamera = () => {
    // 停止所有轨道
    if (mediaStreamRef.current) {
      mediaStreamRef.current.getTracks().forEach(track => track.stop())
      mediaStreamRef.current = null
    }
    
    // 清除视频源
    if (videoRef.current) {
      videoRef.current.srcObject = null
    }
    
    // 清除远端视频
    if (remoteVideoRef.current) {
      remoteVideoRef.current.srcObject = null
    }
    
    // 关闭WebRTC连接
    if (peerConnectionRef.current) {
      peerConnectionRef.current.close()
      peerConnectionRef.current = null
    }
    
    // 重置状态
    setIsCameraActive(false)
    setVideoStatus('未连接')
    setVideoResolution('--')
    setVideoFrameRate('--')
    
    // 显示提示
    showToast('摄像头已停止', 'info')
  }

  // WebRTC配置
  const ICE_SERVERS = [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:stun1.l.google.com:19302' }
  ]

  // 创建WebRTC连接
  const createPeerConnection = () => {
    try {
      // 创建RTCPeerConnection实例
      const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS })
      
      // 设置事件处理程序
      pc.onicecandidate = handleIceCandidate
      pc.ontrack = handleTrack
      pc.onconnectionstatechange = handleConnectionStateChange
      pc.ondatachannel = handleDataChannel
      
      peerConnectionRef.current = pc
      return pc
    } catch (error) {
      console.error('创建WebRTC连接失败:', error)
      showToast('创建连接失败，请重试', 'error')
      return null
    }
  }

  // 处理ICE候选
  const handleIceCandidate = (event) => {
    if (event.candidate) {
      // 在实际应用中，这里会将候选信息发送到信令服务器
      console.log('ICE Candidate:', event.candidate)
      // 模拟发送给对端
      simulateReceiveIceCandidate(event.candidate)
    }
  }

  // 处理收到的轨道（远端视频/音频）
  const handleTrack = (event) => {
    console.log('Received track:', event.track)
    
    if (remoteVideoRef.current) {
      try {
        // 创建新的媒体流或使用现有的流
        let stream = remoteVideoRef.current.srcObject
        if (!stream) {
          stream = new MediaStream()
          remoteVideoRef.current.srcObject = stream
          
          // 监听远端视频加载完成事件
          remoteVideoRef.current.onloadedmetadata = () => {
            console.log('远端视频已加载')
            if (remoteVideoRef.current) {
              const video = remoteVideoRef.current
              showToast(`远端视频已连接: ${video.videoWidth}x${video.videoHeight}`, 'success')
            }
          }
        }
        
        // 添加轨道到流
        stream.addTrack(event.track)
        
        // 确保视频正在播放
        if (remoteVideoRef.current.paused) {
          remoteVideoRef.current.play().catch(error => {
            console.warn('自动播放失败，用户交互后重试:', error)
          })
        }
        
      } catch (error) {
        console.error('处理远端轨道失败:', error)
        showToast('处理远端视频流失败', 'error')
      }
    }
  }

  // 处理连接状态变化
  const handleConnectionStateChange = () => {
    if (peerConnectionRef.current) {
      const state = peerConnectionRef.current.connectionState
      console.log('Connection state:', state)
      setConnectionStatus(state)
      
      switch (state) {
        case 'connected':
          setVideoStatus('已连接')
          setRetryCount(0) // 重置重试计数
          showToast('WebRTC连接已建立', 'success')
          break
        case 'disconnected':
          setVideoStatus('已断开')
          showToast('连接已断开', 'warning')
          // 尝试重新连接
          handleReconnect()
          break
        case 'failed':
          setVideoStatus('连接失败')
          showToast('连接失败，请重试', 'error')
          // 尝试重新连接
          handleReconnect()
          break
        case 'closed':
          setVideoStatus('已关闭')
          showToast('连接已关闭', 'info')
          break
      }
    }
  }
  
  // 处理重新连接
  const handleReconnect = () => {
    if (retryCount < maxRetries) {
      setTimeout(() => {
        showToast(`正在尝试重新连接... (${retryCount + 1}/${maxRetries})`, 'info')
        setRetryCount(prev => prev + 1)
        
        // 关闭当前连接
        if (peerConnectionRef.current) {
          peerConnectionRef.current.close()
        }
        
        // 重新建立连接
        setupLocalConnection()
      }, 2000)
    } else {
      showToast('达到最大重试次数，请手动重启摄像头', 'error')
      setRetryCount(0)
    }
  }

  // 处理数据通道
  const handleDataChannel = (event) => {
    const dataChannel = event.channel
    dataChannel.onmessage = (e) => console.log('收到消息:', e.data)
    dataChannel.onopen = () => console.log('数据通道已打开')
    dataChannel.onclose = () => console.log('数据通道已关闭')
  }

  // 模拟接收ICE候选（本地测试用）
  const simulateReceiveIceCandidate = (candidate) => {
    if (peerConnectionRef.current) {
      peerConnectionRef.current.addIceCandidate(candidate)
        .then(() => console.log('添加ICE候选成功'))
        .catch(error => console.error('添加ICE候选失败:', error))
    }
  }

  // 模拟创建和接受Offer（本地测试用）
  const setupLocalConnection = async () => {
    try {
      // 创建新的PeerConnection
      const pc = createPeerConnection()
      if (!pc) return
      
      // 设置房间信息标识
      pc.roomId = roomId.trim()
      console.log(`创建WebRTC连接，房间号: ${roomId.trim()}`)

      // 添加本地轨道到连接
      if (mediaStreamRef.current) {
        mediaStreamRef.current.getTracks().forEach(track => {
          try {
            pc.addTrack(track, mediaStreamRef.current)
            console.log('添加轨道到连接:', track.kind)
          } catch (error) {
            console.error('添加轨道失败:', error)
          }
        })
      } else {
        console.error('没有可用的媒体流')
        showToast('没有可用的媒体流，请重启摄像头', 'error')
        return
      }

      // 创建Offer
      const offer = await pc.createOffer({
        offerToReceiveVideo: true,
        offerToReceiveAudio: false
      })
      await pc.setLocalDescription(offer)
      console.log('已创建Offer并设置本地描述')
      
      // 模拟发送Offer给对端并接收Answer
      setTimeout(() => {
        if (pc.localDescription) {
          // 模拟对端创建Answer
          const answer = new RTCSessionDescription({
            type: 'answer',
            sdp: pc.localDescription.sdp
          })
          // 设置远程描述
          pc.setRemoteDescription(answer)
            .then(() => {
              console.log('远程描述设置成功，房间号:', pc.roomId)
              showToast(`房间 ${pc.roomId} 连接模拟已建立`, 'success')
              setConnectionStatus(`已连接到房间 ${pc.roomId}`)
            })
            .catch(error => {
              console.error('设置远程描述失败:', error)
              showToast('设置远程描述失败', 'error')
              // 触发重连
              handleReconnect()
            })
        }
      }, 1000)

    } catch (error) {
      console.error('设置本地连接失败:', error)
      showToast(`设置连接失败: ${error.message}`, 'error')
      // 触发重连
      handleReconnect()
    }
  }

  // 请求媒体权限以获取完整设备信息
  const requestMediaPermissions = async () => {
    try {
      if (!checkWebRTCSupport()) {
        return
      }

      // 显示正在请求权限的提示
      showToast('正在请求摄像头和麦克风权限...', 'info')

      // 请求音视频权限，但不实际使用媒体流
      const tempStream = await navigator.mediaDevices.getUserMedia({
        video: true,
        audio: true
      })

      // 立即停止临时流，但保留权限
      tempStream.getTracks().forEach(track => track.stop())
      
      // 权限获取成功后，重新获取设备信息以显示完整名称
      getDeviceInfo()
      showToast('权限获取成功，可以查看完整设备信息', 'success')
    } catch (error) {
      console.log('用户拒绝了媒体权限或没有可用设备:', error)
      // 提供更友好的错误提示
      if (error.name === 'NotAllowedError') {
        showToast('请在浏览器设置中允许访问摄像头和麦克风权限', 'warning')
      }
      // 即使权限被拒绝，也继续获取基本设备信息
      getDeviceInfo()
    }
  }

  // 初始化
  useEffect(() => {
    // 只获取基本设备信息，权限请求将在用户点击打开摄像头时触发
    getDeviceInfo()
  }, [])

  // 清理函数
  useEffect(() => {
    return () => {
      stopCamera()
    }
  }, [])

  return (
    <div className="app">
      <header className="header">
        <h1>
          <FontAwesomeIcon icon={faVideo} /> WebRTC 摄像头调用演示
        </h1>
        <p>使用Vite代理的React WebRTC应用</p>
      </header>

      <main className="main">
        <section className="demo-section">
          <div className="controls">
            <div className="room-input-container">
              <input
                type="text"
                placeholder="请输入房间号"
                value={roomId}
                onChange={(e) => setRoomId(e.target.value)}
                disabled={isCameraActive}
                className="room-input"
              />
            </div>
            <button 
              onClick={startCamera} 
              disabled={isCameraActive || !roomId.trim()}
              className="btn btn-primary"
            >
              <FontAwesomeIcon icon={faPlay} /> 开始摄像头
            </button>
            <button 
              onClick={stopCamera} 
              disabled={!isCameraActive}
              className="btn btn-error"
            >
              <FontAwesomeIcon icon={faStop} /> 停止摄像头
            </button>

          </div>

          <div className="video-container">
            <div className="video-wrapper">
              {!isCameraActive && (
                <div className="video-placeholder">
                  <FontAwesomeIcon icon={faVideo} />
                  <p>点击"开始摄像头"按钮启动视频流</p>
                </div>
              )}
              <video 
                ref={videoRef} 
                autoPlay 
                muted 
                playsInline 
                className={isCameraActive ? 'active' : 'hidden'}
              />
              <div className={`status-badge pulse ${isCameraActive ? 'toast-success' : 'toast-error'}`}>
              <span className="status-dot"></span>
              {videoStatus}
            </div>
            </div>

            <div className="video-wrapper">
              <h3>远端画面</h3>
              {!isCameraActive ? (
                <div className="video-placeholder">
                  <FontAwesomeIcon icon={faGlobe} />
                  <p>等待接收远端视频流</p>
                </div>
              ) : (
                <>
                  <video 
                    ref={remoteVideoRef} 
                    autoPlay 
                    playsInline 
                    className="remote-video"
                  />
                  <div className={`status-badge ${connectionStatus === 'connected' ? 'toast-success' : 'toast-error'}`}>
                    <span className="status-dot"></span>
                    {connectionStatus === 'connected' ? '已连接' : 
                     connectionStatus === 'disconnected' ? '已断开' :
                     connectionStatus === 'failed' ? '连接失败' : '未连接'}
                  </div>
                </>
              )}
            </div>
          </div>

          <div className="stats">
            <div className="stat-item">
              <span className="stat-label">分辨率:</span>
              <span className="stat-value">{videoResolution}</span>
            </div>
            <div className="stat-item">
              <span className="stat-label">帧率:</span>
              <span className="stat-value">{videoFrameRate}</span>
            </div>
            <div className="stat-item">
              <span className="stat-label">连接状态:</span>
              <span className="stat-value" style={{
                color: connectionStatus === 'connected' ? '#48bb78' : 
                       connectionStatus === 'disconnected' || connectionStatus === 'failed' ? '#f56565' : '#718096'
              }}>
                {connectionStatus === 'connected' ? '已连接' : 
                 connectionStatus === 'disconnected' ? '已断开' :
                 connectionStatus === 'failed' ? '连接失败' : 
                 connectionStatus === 'connecting' ? '连接中...' : '未连接'}
              </span>
            </div>
          </div>

          <div className="device-info">
            <h3>
              <FontAwesomeIcon icon={faInfoCircle} /> 设备信息
            </h3>
            {typeof deviceInfo === 'object' && !deviceInfo.error ? (
              <div className="device-grid">
                <div className="device-card">
                  <h4>摄像头 ({deviceInfo.videoDevices.length})</h4>
                  {deviceInfo.videoDevices.length > 0 ? (
                    <ul>
                      {deviceInfo.videoDevices.map((device, index) => (
                        <li key={index}>{device.label || '未知摄像头'}</li>
                      ))}
                    </ul>
                  ) : (
                    <p className="no-device">未检测到摄像头设备</p>
                  )}
                </div>
                <div className="device-card">
                  <h4>麦克风 ({deviceInfo.audioInputDevices.length})</h4>
                  {deviceInfo.audioInputDevices.length > 0 ? (
                    <ul>
                      {deviceInfo.audioInputDevices.map((device, index) => (
                        <li key={index}>{device.label || '未知麦克风'}</li>
                      ))}
                    </ul>
                  ) : (
                    <p className="no-device">未检测到麦克风设备</p>
                  )}
                </div>
                <div className="device-card">
                  <h4>扬声器 ({deviceInfo.audioOutputDevices.length})</h4>
                  {deviceInfo.audioOutputDevices.length > 0 ? (
                    <ul>
                      {deviceInfo.audioOutputDevices.map((device, index) => (
                        <li key={index}>{device.label || '未知扬声器'}</li>
                      ))}
                    </ul>
                  ) : (
                    <p className="no-device">未检测到扬声器设备</p>
                  )}
                </div>
              </div>
            ) : deviceInfo.error ? (
              <div className="error-message">{deviceInfo.error}</div>
            ) : (
              <div className="loading-message">{deviceInfo}</div>
            )}
          </div>

          <div className="proxy-info">
            <h3>代理配置</h3>
            <p>当前项目已配置Vite代理:</p>
            <ul>
              <li><code>/api</code> → <code>http://localhost:3000</code></li>
              <li><code>/webrtc</code> → <code>http://localhost:8080</code></li>
            </ul>
          </div>
        </section>
      </main>

      {/* WebRTC 功能特性部分 */}
      <section className="demo-section features-section">
        <h2 style={{ textAlign: 'center', fontSize: '2rem', marginBottom: '2rem' }}>WebRTC 功能特性</h2>
        <div className="features-grid">
          <div className="feature-card">
            <FontAwesomeIcon icon={faVideo} />
            <h3>视频采集</h3>
            <p>支持多种视频格式和分辨率，实时采集摄像头数据</p>
          </div>
          <div className="feature-card">
            <FontAwesomeIcon icon={faMicrophone} />
            <h3>音频处理</h3>
            <p>回声消除、降噪处理、自动增益控制</p>
          </div>
          <div className="feature-card">
            <FontAwesomeIcon icon={faCodeBranch} />
            <h3>编解码</h3>
            <p>VP8/VP9视频编码，Opus音频编码</p>
          </div>
          <div className="feature-card">
            <FontAwesomeIcon icon={faInfoCircle} />
            <h3>网络传输</h3>
            <p>RTP/RTCP协议，P2P直连通信</p>
          </div>
        </div>
      </section>

      <footer className="footer">
        <div className="social-icons">
          <FontAwesomeIcon icon={faCodeBranch} />
          <FontAwesomeIcon icon={faLaptop} />
          <FontAwesomeIcon icon={faGlobe} />
        </div>
        <p>&copy; {new Date().getFullYear()} WebRTC 演示 | 使用Vite构建</p>
        <p>基于webrtc的完整功能演示--但成伟</p>
      </footer>
      
      {/* Toast 提示系统 */}
      <div className="toast-container" ref={toastRef}>
        {toasts.map(toast => (
          <div 
            key={toast.id} 
            className={`toast toast-${toast.type} animate-slide-in`}
          >
            <span className={`toast-icon ${toast.type}`}></span>
            <span className="toast-message">{toast.message}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

export default App