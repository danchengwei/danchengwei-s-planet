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
  // WebSocket相关状态
  const [wsConnection, setWsConnection] = useState(null)
  const [wsConnected, setWsConnected] = useState(false)
  const [usersInRoom, setUsersInRoom] = useState([])
  const [userId] = useState(`user_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`) // 生成唯一用户ID
  // WebRTC相关状态
  const [peerConnections, setPeerConnections] = useState({}) // 多用户P2P连接管理
  const [localStream, setLocalStream] = useState(null) // 本地媒体流
  // 消息和状态同步相关
  const [messages, setMessages] = useState([])
  const [newMessage, setNewMessage] = useState('')
  const [userStatuses, setUserStatuses] = useState({}) // 存储用户状态，如麦克风、摄像头开关状态
  
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
  
  // 建立WebSocket连接
  const connectToSignalingServer = () => {
    try {
      // 注意：实际使用时需要替换为真实的WebSocket服务器地址
      // 这里使用模拟地址，实际部署时需要配置真实的信令服务器
      const wsUrl = process.env.REACT_APP_SIGNALING_SERVER || 'ws://localhost:8080/webrtc'
      
      // 创建WebSocket连接
      const ws = new WebSocket(wsUrl)
      
      // 设置WebSocket事件处理
      ws.onopen = () => {
        console.log('WebSocket连接已建立')
        setWsConnected(true)
        setConnectionStatus('信令服务器已连接')
        showToast('信令服务器连接成功', 'success')
      }
      
      ws.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data)
          handleSignalingMessage(message)
        } catch (error) {
          console.error('解析WebSocket消息失败:', error)
        }
      }
      
      ws.onclose = () => {
        console.log('WebSocket连接已关闭')
        setWsConnected(false)
        setConnectionStatus('信令服务器连接已断开')
        showToast('信令服务器连接已断开', 'error')
      }
      
      ws.onerror = (error) => {
        console.error('WebSocket错误:', error)
        setWsConnected(false)
        showToast('信令服务器连接错误', 'error')
      }
      
      setWsConnection(ws)
    } catch (error) {
      console.error('建立WebSocket连接失败:', error)
      showToast('无法连接到信令服务器', 'error')
    }
  }
  
  // 处理信令消息
  const handleSignalingMessage = (message) => {
    console.log('收到信令消息:', message)
    
    switch (message.type) {
      case 'room_created':
        handleRoomCreated(message)
        break
      case 'room_joined':
        handleRoomJoined(message)
        break
      case 'user_joined':
        handleUserJoined(message)
        break
      case 'user_left':
        handleUserLeft(message)
        break
      case 'offer':
        handleOffer(message)
        break
      case 'answer':
        handleAnswer(message)
        break
      case 'ice_candidate':
        handleIceCandidateMessage(message)
        break
      case 'message':
        handleChatMessage(message)
        break
      case 'user_status_update':
        handleUserStatusUpdate(message)
        break
      case 'status_broadcast':
        handleStatusBroadcast(message)
        break
      case 'error':
        showToast(`错误: ${message.message}`, 'error')
        break
      default:
        console.log('未知的信令消息类型:', message.type)
    }
  }
  
  // 发送信令消息
  const sendSignalingMessage = (data) => {
    if (wsConnection && wsConnected) {
      wsConnection.send(JSON.stringify({
        ...data,
        userId: userId,
        timestamp: Date.now()
      }))
    } else {
      console.error('WebSocket未连接，无法发送信令消息')
    }
  }
  
  // 房间创建逻辑
  const createRoom = () => {
    if (!wsConnection || !wsConnected) {
      showToast('请先连接信令服务器', 'error')
      return
    }
    
    const newRoomId = `room_${Date.now()}_${Math.random().toString(36).substr(2, 5)}`
    
    // 发送创建房间请求
    sendSignalingMessage({
      type: 'create_room',
      roomId: newRoomId
    })
    
    showToast(`正在创建房间: ${newRoomId}`, 'info')
    setConnectionStatus('正在创建房间...')
  }
  
  // 房间加入逻辑
  const joinRoom = (roomToJoin) => {
    if (!wsConnection || !wsConnected) {
      showToast('请先连接信令服务器', 'error')
      return
    }
    
    if (!roomToJoin.trim()) {
      showToast('请输入房间ID', 'error')
      return
    }
    
    // 发送加入房间请求
    sendSignalingMessage({
      type: 'join_room',
      roomId: roomToJoin.trim()
    })
    
    showToast(`正在加入房间: ${roomToJoin}`, 'info')
    setConnectionStatus('正在加入房间...')
  }
  
  // 离开房间逻辑
  const leaveRoom = () => {
    if (!roomId) {
      showToast('您还未加入任何房间', 'info')
      return
    }
    
    // 发送离开房间请求
    sendSignalingMessage({
      type: 'leave_room',
      roomId: roomId
    })
    
    // 清理所有P2P连接
    Object.keys(peerConnections).forEach(remoteUserId => {
      handleDisconnect(remoteUserId)
    })
    
    // 重置房间相关状态
    setRoomId('')
    setUsersInRoom([])
    setConnectionStatus('未连接')
    setMessages([])
    
    showToast('已离开房间', 'success')
  }
  
  // 处理房间创建成功
  const handleRoomCreated = (message) => {
    console.log('房间创建成功:', message)
    setRoomId(message.roomId)
    setConnectionStatus('已创建房间')
    setUsersInRoom([{
      id: userId,
      name: `用户_${userId.slice(-6)}`,
      isSelf: true,
      connected: true
    }])
    showToast(`房间创建成功: ${message.roomId}`, 'success')
  }
  
  // 处理房间加入成功
  const handleRoomJoined = (message) => {
    console.log('加入房间成功:', message)
    setRoomId(message.roomId)
    setConnectionStatus('已加入房间')
    
    // 更新房间内用户列表
    const users = [
      { id: userId, name: `用户_${userId.slice(-6)}`, isSelf: true, connected: true },
      ...message.existingUsers.map(user => ({
        id: user.userId,
        name: `用户_${user.userId.slice(-6)}`,
        isSelf: false,
        connected: false
      }))
    ]
    setUsersInRoom(users)
    showToast(`成功加入房间: ${message.roomId}`, 'success')
    
    // 如果有本地流，向房间内其他用户发起连接
    if (localStream && message.existingUsers.length > 0) {
      message.existingUsers.forEach(user => {
        setupLocalConnection(user.userId)
      })
    }
  }
  
  // 处理新用户加入
  const handleUserJoined = (message) => {
    console.log('新用户加入:', message)
    
    // 添加新用户到列表
    setUsersInRoom(prev => [...prev, {
      id: message.userId,
      name: `用户_${message.userId.slice(-6)}`,
      isSelf: false,
      connected: false
    }])
    
    // 通知用户有新用户加入
    showToast(`用户 ${message.userId.slice(-6)} 加入房间`, 'info')
    
    // 如果有本地流，向新用户发起连接
    if (localStream) {
      setupLocalConnection(message.userId)
    }
  }
  
  // 处理用户离开
  const handleUserLeft = (message) => {
    console.log('用户离开:', message)
    
    // 移除离开的用户
    setUsersInRoom(prev => prev.filter(user => user.id !== message.userId))
    
    // 通知用户有用户离开
    showToast(`用户 ${message.userId.slice(-6)} 离开房间`, 'info')
    
    // 清理与离开用户的连接
    handleDisconnect(message.userId)
  }
  
  // 多用户连接管理 - 创建本地连接
  const setupLocalConnection = async (remoteUserId) => {
    try {
      // 检查是否已存在连接
      if (peerConnections[remoteUserId]) {
        console.log(`与用户 ${remoteUserId} 的连接已存在`)
        return
      }
      
      // 创建新的RTCPeerConnection
      const pc = new RTCPeerConnection({
        iceServers: [
          { urls: 'stun:stun.l.google.com:19302' },
          { urls: 'stun:stun1.l.google.com:19302' }
        ]
      })
      
      // 添加本地流到连接
      if (localStream) {
        localStream.getTracks().forEach(track => {
          pc.addTrack(track, localStream)
        })
      }
      
      // 设置ICE候选处理
      pc.onicecandidate = (event) => {
        if (event.candidate) {
          sendSignalingMessage({
            type: 'ice_candidate',
            to: remoteUserId,
            roomId: roomId,
            candidate: event.candidate
          })
        }
      }
      
      // 设置轨道处理
      pc.ontrack = (event) => {
        console.log('收到远程流:', remoteUserId)
        
        // 处理远程流
        const stream = event.streams[0]
        setRemoteStreams(prev => ({
          ...prev,
          [remoteUserId]: stream
        }))
        
        // 通知用户连接成功
        const remoteUser = usersInRoom.find(user => user.id === remoteUserId)
        if (remoteUser) {
          showToast(`与 ${remoteUser.name} 建立了视频连接`, 'success')
        }
      }
      
      // 设置连接状态变化处理
      pc.onconnectionstatechange = () => {
        const state = pc.connectionState
        console.log(`与用户 ${remoteUserId} 的连接状态: ${state}`)
        
        if (state === 'connected') {
          // 更新连接状态
          setConnectionStatus('已连接')
        } else if (state === 'disconnected' || state === 'failed' || state === 'closed') {
          // 清理连接
          handleDisconnect(remoteUserId)
        }
      }
      
      // 设置ICE连接状态
      pc.oniceconnectionstatechange = () => {
        console.log('ICE连接状态:', pc.iceConnectionState)
        
        if (pc.iceConnectionState === 'disconnected' || pc.iceConnectionState === 'failed') {
          console.log('与用户', remoteUserId, '的连接断开')
          handleDisconnect(remoteUserId)
        }
      }
      
      // 存储新的连接
      setPeerConnections(prev => ({
        ...prev,
        [remoteUserId]: pc
      }))
      
      // 创建offer并发送给远程用户
      try {
        const offer = await pc.createOffer({
          offerToReceiveVideo: true,
          offerToReceiveAudio: true
        })
        
        await pc.setLocalDescription(offer)
        
        // 发送offer给远程用户
        sendSignalingMessage({
          type: 'offer',
          to: remoteUserId,
          roomId: roomId,
          offer: offer
        })
        
      } catch (offerError) {
        console.error('创建offer失败:', offerError)
        handleDisconnect(remoteUserId)
      }
      
    } catch (error) {
      console.error(`设置与用户 ${remoteUserId} 的连接失败:`, error)
    }
  }
  
  // 处理收到的offer
  const handleOffer = async (message) => {
    try {
      const { from: remoteUserId, offer } = message
      
      console.log('收到来自', remoteUserId, '的offer')
      
      // 获取或创建与该用户的连接
      let pc = peerConnections[remoteUserId]
      if (!pc) {
        // 创建新的RTCPeerConnection
        pc = new RTCPeerConnection({
          iceServers: [
            { urls: 'stun:stun.l.google.com:19302' },
            { urls: 'stun:stun1.l.google.com:19302' }
          ]
        })
        
        // 添加本地流到连接
        if (localStream) {
          localStream.getTracks().forEach(track => {
            pc.addTrack(track, localStream)
          })
        }
        
        // 设置ICE候选处理
        pc.onicecandidate = (event) => {
          if (event.candidate) {
            sendSignalingMessage({
              type: 'ice_candidate',
              to: remoteUserId,
              roomId: roomId,
              candidate: event.candidate
            })
          }
        }
        
        // 设置轨道处理
        pc.ontrack = (event) => {
          console.log('收到远程流:', remoteUserId)
          
          // 处理远程流
          const stream = event.streams[0]
          setRemoteStreams(prev => ({
            ...prev,
            [remoteUserId]: stream
          }))
          
          // 通知用户连接成功
          const remoteUser = usersInRoom.find(user => user.id === remoteUserId)
          if (remoteUser) {
            showToast(`与 ${remoteUser.name} 建立了视频连接`, 'success')
          }
        }
        
        // 设置连接状态变化处理
        pc.onconnectionstatechange = () => {
          const state = pc.connectionState
          console.log(`与用户 ${remoteUserId} 的连接状态: ${state}`)
          
          if (state === 'connected') {
            setConnectionStatus('已连接')
          } else if (state === 'disconnected' || state === 'failed' || state === 'closed') {
            handleDisconnect(remoteUserId)
          }
        }
        
        // 设置ICE连接状态
        pc.oniceconnectionstatechange = () => {
          console.log('ICE连接状态:', pc.iceConnectionState)
          
          if (pc.iceConnectionState === 'disconnected' || pc.iceConnectionState === 'failed') {
            handleDisconnect(remoteUserId)
          }
        }
        
        // 存储连接
        setPeerConnections(prev => ({
          ...prev,
          [remoteUserId]: pc
        }))
      }
      
      // 设置远程描述
      await pc.setRemoteDescription(new RTCSessionDescription(offer))
      
      // 创建answer
      const answer = await pc.createAnswer({
        offerToReceiveVideo: true,
        offerToReceiveAudio: true
      })
      
      // 设置本地描述
      await pc.setLocalDescription(answer)
      
      // 发送answer给远程用户
      sendSignalingMessage({
        type: 'answer',
        to: remoteUserId,
        roomId: roomId,
        answer: answer
      })
      
    } catch (error) {
      console.error('处理offer失败:', error)
    }
  }
  
  // 处理收到的answer
  const handleAnswer = async (message) => {
    try {
      const { from: remoteUserId, answer } = message
      
      console.log('收到来自', remoteUserId, '的answer')
      
      // 获取与该用户的连接
      const pc = peerConnections[remoteUserId]
      if (pc) {
        // 设置远程描述
        await pc.setRemoteDescription(new RTCSessionDescription(answer))
      } else {
        console.error(`未找到与用户 ${remoteUserId} 的连接`)
      }
    } catch (error) {
      console.error('处理answer失败:', error)
    }
  }
  
  // 处理收到的ICE候选
  const handleIceCandidateMessage = async (message) => {
    try {
      const { from: remoteUserId, candidate } = message
      
      console.log('收到来自', remoteUserId, '的ICE候选')
      
      // 获取与该用户的连接
      const pc = peerConnections[remoteUserId]
      if (pc && pc.remoteDescription) {
        // 添加ICE候选
        await pc.addIceCandidate(new RTCIceCandidate(candidate))
      } else {
        console.error(`未找到与用户 ${remoteUserId} 的连接或远程描述未设置`)
      }
    } catch (error) {
      console.error('处理ICE候选失败:', error)
    }
  }
  
  // 处理用户断开连接
  const handleDisconnect = (remoteUserId) => {
    // 关闭并移除连接
    const pc = peerConnections[remoteUserId]
    if (pc) {
      pc.close()
    }
    
    // 更新连接状态
    setPeerConnections(prev => {
      const newConnections = { ...prev }
      delete newConnections[remoteUserId]
      return newConnections
    })
    
    // 更新远程流
    setRemoteStreams(prev => {
      const newStreams = { ...prev }
      delete newStreams[remoteUserId]
      return newStreams
    })
    
    // 更新连接状态显示
    if (Object.keys(peerConnections).length === 0 && roomId) {
      setConnectionStatus('已加入房间')
    }
  }
  
  // 发送聊天消息
  const sendChatMessage = (content) => {
    if (!content.trim() || !roomId.trim()) return
    
    const message = {
      content: content.trim(),
      timestamp: new Date().toLocaleString()
    }
    
    // 添加到本地消息列表
    setMessages(prevMessages => [...prevMessages, {
      ...message,
      from: userId,
      isSelf: true,
      userInfo: {
        id: userId,
        name: `用户_${userId.slice(-6)}`
      }
    }])
    
    // 发送到服务器进行转发
    sendSignalingMessage({
      type: 'message',
      roomId: roomId,
      content: message
    })
    
    // 清空输入框
    setNewMessage('')
  }
  
  // 处理收到的聊天消息
  const handleChatMessage = (message) => {
    if (message.from === userId) return // 忽略自己发送的消息
    
    // 添加到消息列表
    setMessages(prevMessages => [...prevMessages, {
      ...message.content,
      from: message.from,
      isSelf: false,
      userInfo: message.userInfo
    }])
  }
  
  // 处理用户状态更新
  const handleUserStatusUpdate = (message) => {
    const { userId: targetUserId, status } = message
    setUserStatuses(prev => ({
      ...prev,
      [targetUserId]: { ...prev[targetUserId], ...status }
    }))
  }
  
  // 处理状态广播
  const handleStatusBroadcast = (message) => {
    const { statuses } = message
    setUserStatuses(prev => ({ ...prev, ...statuses }))
  }
  
  // 更新并广播本地用户状态
  const updateAndBroadcastStatus = (statusUpdates) => {
    // 更新本地状态
    setUserStatuses(prev => ({
      ...prev,
      [userId]: {
        ...prev[userId],
        ...statusUpdates,
        updatedAt: Date.now()
      }
    }))
    
    // 广播给房间内其他用户
    sendSignalingMessage({
      type: 'user_status_update',
      roomId: roomId,
      status: statusUpdates
    })
  }
  
  // 处理收到的用户状态更新
  const handleUserStatusUpdate = (message) => {
    if (message.from === userId) return // 忽略自己的状态更新
    
    // 更新其他用户的状态
    setUserStatuses(prev => ({
      ...prev,
      [message.from]: {
        ...prev[message.from],
        ...message.status,
        updatedAt: Date.now()
      }
    }))
  }
  
  // 处理状态广播（服务器广播给房间内所有用户）
  const handleStatusBroadcast = (message) => {
    // 更新所有用户的状态
    setUserStatuses(message.userStatuses)
  }
  
  // 发送信令消息
  const sendSignalingMessage = (message) => {
    if (wsConnection && wsConnection.readyState === WebSocket.OPEN) {
      wsConnection.send(JSON.stringify({
        ...message,
        from: userId,
        timestamp: Date.now()
      }))
    } else {
      console.error('WebSocket未连接，无法发送消息')
      showToast('信令服务器未连接，请稍后重试', 'error')
    }
  }
  
  // 创建房间
  const createRoom = () => {
    if (!wsConnected) {
      showToast('请先连接到信令服务器', 'error')
      return
    }
    
    const roomName = roomId.trim() || `room_${Date.now()}_${Math.random().toString(36).substr(2, 5)}`
    setRoomId(roomName)
    
    sendSignalingMessage({
      type: 'create_room',
      roomId: roomName,
      userInfo: {
        id: userId,
        name: `用户_${userId.slice(-6)}`
      }
    })
    
    setConnectionStatus(`正在创建房间: ${roomName}`)
  }
  
  // 加入房间
  const joinRoom = () => {
    if (!wsConnected) {
      showToast('请先连接到信令服务器', 'error')
      return
    }
    
    const targetRoomId = roomId.trim()
    if (!targetRoomId) {
      showToast('请输入房间号', 'error')
      return
    }
    
    sendSignalingMessage({
      type: 'join_room',
      roomId: targetRoomId,
      userInfo: {
        id: userId,
        name: `用户_${userId.slice(-6)}`
      }
    })
    
    setConnectionStatus(`正在加入房间: ${targetRoomId}`)
  }
  
  // 离开房间
  const leaveRoom = () => {
    if (!roomId.trim()) {
      showToast('您还未加入任何房间', 'info')
      return
    }
    
    // 发送离开房间请求
    sendSignalingMessage({
      type: 'leave_room',
      roomId: roomId.trim(),
    })
    
    // 清理所有P2P连接
    Object.keys(peerConnections).forEach(userId => {
      handleDisconnect(userId)
    })
    
    // 重置房间相关状态
    setUsersInRoom([])
    setConnectionStatus('未连接')
    setRoomId('')
    setMessages([])
    
    showToast('已离开房间', 'success')
  }
  
  // 远程流状态管理
  const [remoteStreams, setRemoteStreams] = useState({})
  
  // 处理Offer消息
  const handleOffer = async (message) => {
    console.log('收到Offer:', message)
    
    try {
      // 创建或获取与发送者的PeerConnection
      let pc = peerConnections[message.from]
      if (!pc) {
        pc = setupPeerConnection(message.from)
      }
      
      // 设置远程描述
      await pc.setRemoteDescription(new RTCSessionDescription(message.offer))
      
      // 创建Answer
      const answer = await pc.createAnswer()
      await pc.setLocalDescription(answer)
      
      // 发送Answer给发送者
      sendSignalingMessage({
        type: 'answer',
        to: message.from,
        roomId: roomId,
        answer: answer
      })
      
      console.log('已发送Answer给用户:', message.from)
    } catch (error) {
      console.error('处理Offer失败:', error)
      showToast('处理连接请求失败', 'error')
    }
  }
  
  // 处理Answer消息
  const handleAnswer = async (message) => {
    console.log('收到Answer:', message)
    
    try {
      const pc = peerConnections[message.from]
      if (!pc) {
        console.error('找不到对应的PeerConnection:', message.from)
        return
      }
      
      // 设置远程描述
      await pc.setRemoteDescription(new RTCSessionDescription(message.answer))
      console.log('已设置远程描述，连接建立中...')
    } catch (error) {
      console.error('处理Answer失败:', error)
      showToast('处理连接应答失败', 'error')
    }
  }
  
  // 处理ICE候选消息
  const handleIceCandidateMessage = async (message) => {
    console.log('收到ICE候选:', message)
    
    try {
      const pc = peerConnections[message.from]
      if (!pc) {
        console.error('找不到对应的PeerConnection:', message.from)
        return
      }
      
      // 添加ICE候选
      await pc.addIceCandidate(new RTCIceCandidate(message.candidate))
    } catch (error) {
      console.error('添加ICE候选失败:', error)
    }
  }
  
  // 设置PeerConnection
  const setupPeerConnection = (remoteUserId) => {
    console.log('为用户', remoteUserId, '创建PeerConnection')
    
    // 创建PeerConnection配置
    const pcConfig = {
      iceServers: [
        { urls: 'stun:stun.l.google.com:19302' },
        { urls: 'stun:stun1.l.google.com:19302' }
        // 可以在这里添加TURN服务器配置
      ]
    }
    
    // 创建PeerConnection
    const pc = new RTCPeerConnection(pcConfig)
    
    // 添加本地流
    if (localStream) {
      localStream.getTracks().forEach(track => {
        pc.addTrack(track, localStream)
      })
    }
    
    // 监听ICE候选
    pc.onicecandidate = (event) => {
      if (event.candidate) {
        sendSignalingMessage({
          type: 'ice_candidate',
          to: remoteUserId,
          roomId: roomId,
          candidate: event.candidate
        })
      }
    }
    
    // 监听ICE连接状态
    pc.oniceconnectionstatechange = () => {
      console.log('ICE连接状态:', pc.iceConnectionState)
      
      if (pc.iceConnectionState === 'disconnected' || pc.iceConnectionState === 'failed') {
        console.log('与用户', remoteUserId, '的连接断开')
        // 清理资源
        if (remoteStreams[remoteUserId]) {
          remoteStreams[remoteUserId].getTracks().forEach(track => track.stop())
          setRemoteStreams(prev => {
            const newStreams = { ...prev }
            delete newStreams[remoteUserId]
            return newStreams
          })
        }
      }
    }
    
    // 监听远程流
    pc.ontrack = (event) => {
      console.log('收到远程流:', remoteUserId)
      
      // 处理远程流
      const stream = event.streams[0]
      setRemoteStreams(prev => ({
        ...prev,
        [remoteUserId]: stream
      }))
      
      // 通知用户连接成功
      const remoteUser = usersInRoom.find(user => user.id === remoteUserId)
      if (remoteUser) {
        showToast(`与 ${remoteUser.name} 建立了视频连接`, 'success')
      }
    }
    
    // 存储PeerConnection
    setPeerConnections(prev => ({
      ...prev,
      [remoteUserId]: pc
    }))
    
    return pc
  }
  
  // 多用户连接设置 - 为每个远程用户创建P2P连接
  const setupLocalConnection = async (remoteUserId) => {
    try {
      // 检查是否已存在连接
      if (peerConnections[remoteUserId]) {
        console.log(`与用户 ${remoteUserId} 的连接已存在`)
        return
      }
      
      // 创建新的RTCPeerConnection
      const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS })
      
      // 添加本地流到连接
      if (localStream) {
        localStream.getTracks().forEach(track => {
          pc.addTrack(track, localStream)
        })
      }
      
      // 设置ICE候选处理
      pc.onicecandidate = (event) => {
        if (event.candidate) {
          sendSignalingMessage({
            type: 'ice_candidate',
            to: remoteUserId,
            roomId: roomId,
            candidate: event.candidate
          })
        }
      }
      
      // 设置轨道处理
      pc.ontrack = (event) => {
        console.log('收到远程流:', remoteUserId)
        
        // 处理远程流
        const stream = event.streams[0]
        setRemoteStreams(prev => ({
          ...prev,
          [remoteUserId]: stream
        }))
        
        // 通知用户连接成功
        const remoteUser = usersInRoom.find(user => user.id === remoteUserId)
        if (remoteUser) {
          showToast(`与 ${remoteUser.name} 建立了视频连接`, 'success')
        }
      }
      
      // 设置连接状态变化处理
      pc.onconnectionstatechange = () => {
        const state = pc.connectionState
        console.log(`与用户 ${remoteUserId} 的连接状态: ${state}`)
        
        if (state === 'connected') {
          // 更新连接状态
          setConnectionStatus('已连接')
        } else if (state === 'disconnected' || state === 'failed' || state === 'closed') {
          // 清理连接
          handleDisconnect(remoteUserId)
        }
      }
      
      // 设置ICE连接状态
      pc.oniceconnectionstatechange = () => {
        console.log('ICE连接状态:', pc.iceConnectionState)
        
        if (pc.iceConnectionState === 'disconnected' || pc.iceConnectionState === 'failed') {
          console.log('与用户', remoteUserId, '的连接断开')
          handleDisconnect(remoteUserId)
        }
      }
      
      // 存储新的连接
      setPeerConnections(prev => ({
        ...prev,
        [remoteUserId]: pc
      }))
      
      // 创建offer并发送给远程用户
      try {
        const offer = await pc.createOffer({
          offerToReceiveVideo: true,
          offerToReceiveAudio: true
        })
        
        await pc.setLocalDescription(offer)
        
        // 发送offer给远程用户
        sendSignalingMessage({
          type: 'offer',
          to: remoteUserId,
          roomId: roomId,
          offer: offer
        })
        
      } catch (offerError) {
        console.error('创建offer失败:', offerError)
        handleDisconnect(remoteUserId)
      }
      
    } catch (error) {
      console.error(`设置与用户 ${remoteUserId} 的连接失败:`, error)
    }
  }
  
  // 处理用户断开连接
  const handleDisconnect = (remoteUserId) => {
    // 关闭并移除连接
    const pc = peerConnections[remoteUserId]
    if (pc) {
      pc.close()
    }
    
    // 更新连接状态
    setPeerConnections(prev => {
      const newConnections = { ...prev }
      delete newConnections[remoteUserId]
      return newConnections
    })
    
    // 更新远程流
    setRemoteStreams(prev => {
      const newStreams = { ...prev }
      delete newStreams[remoteUserId]
      return newStreams
    })
    
    // 更新连接状态显示
    if (Object.keys(peerConnections).length === 0) {
      setConnectionStatus('未连接')
    }
  }
  
  // 房间事件处理函数
  // 这些函数已在文件前面部分定义，删除重复定义
  
  // 组件挂载时连接WebSocket
  useEffect(() => {
    connectToSignalingServer()
    
    // 组件卸载时关闭WebSocket连接
    return () => {
      if (wsConnection) {
        wsConnection.close()
      }
    }
  }, [])

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
      setLocalStream(stream) // 设置localStream状态用于多用户连接

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
    
    // 广播摄像头关闭状态
    updateAndBroadcastStatus({ cameraEnabled: false })
    
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
  
  // 切换麦克风
  const toggleMicrophone = () => {
    if (!mediaStreamRef.current) return
    
    const audioTracks = mediaStreamRef.current.getAudioTracks()
    if (audioTracks.length === 0) return
    
    const isEnabled = !audioTracks[0].enabled
    audioTracks[0].enabled = isEnabled
    
    // 广播麦克风状态
    updateAndBroadcastStatus({ audioEnabled: isEnabled })
    
    showToast(isEnabled ? '麦克风已开启' : '麦克风已静音', 'info')
  }
  
  // 切换摄像头
  const toggleCamera = () => {
    if (!mediaStreamRef.current) return
    
    const videoTracks = mediaStreamRef.current.getVideoTracks()
    if (videoTracks.length === 0) return
    
    const isEnabled = !videoTracks[0].enabled
    videoTracks[0].enabled = isEnabled
    
    // 广播摄像头状态
    updateAndBroadcastStatus({ cameraEnabled: isEnabled })
    
    showToast(isEnabled ? '摄像头已开启' : '摄像头已关闭', 'info')
  }

  // WebRTC配置
  const ICE_SERVERS = [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:stun1.l.google.com:19302' }
  ]

  // 创建WebRTC连接（单用户版本，保留但不再使用）
  const createPeerConnection = () => {
    try {
      // 创建RTCPeerConnection实例
      const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS })
      
      // 设置事件处理程序
      pc.onicecandidate = (event) => {
        if (event.candidate) {
          console.log('ICE Candidate:', event.candidate)
        }
      }
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

  // WebRTC连接处理函数在多用户部分已重新实现

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

  // 单用户版本的setupLocalConnection已移除，保留多用户版本

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

      <main className="main-content">
        <section className="demo-section">
          <h2>WebRTC 视频会议系统</h2>
          
          {/* 房间管理控件 */}
          <div className="room-controls">
            <div className="room-form">
              <input
                type="text"
                placeholder="输入房间号或留空自动生成"
                value={roomId}
                onChange={(e) => setRoomId(e.target.value)}
                className="room-input"
              />
              <div className="room-buttons">
                {!roomId ? (
                  <>
                    <button 
                      onClick={createRoom} 
                      disabled={!wsConnected}
                      className="btn btn-primary"
                    >
                      创建房间
                    </button>
                    <button 
                      onClick={joinRoom} 
                      disabled={!wsConnected || !roomId.trim()}
                      className="btn btn-secondary"
                    >
                      加入房间
                    </button>
                  </>
                ) : (
                  <button 
                    onClick={leaveRoom} 
                    className="btn btn-danger"
                  >
                    离开房间
                  </button>
                )}
              </div>
            </div>
            
            {/* 摄像头控制 */}
            <div className="camera-controls">
              {!isCameraActive ? (
                <button 
                  onClick={startCamera} 
                  className="btn btn-primary"
                >
                  <FontAwesomeIcon icon={faVideo} /> 开始摄像头
                </button>
              ) : (
                <>
                  <button 
                    onClick={toggleMicrophone} 
                    className="btn btn-secondary"
                  >
                    <FontAwesomeIcon icon={faMicrophone} /> 麦克风
                  </button>
                  <button 
                    onClick={toggleCamera} 
                    className="btn btn-secondary"
                  >
                    <FontAwesomeIcon icon={faVideo} /> 摄像头
                  </button>
                  <button 
                    onClick={stopCamera} 
                    className="btn btn-danger"
                  >
                    <FontAwesomeIcon icon={faStop} /> 停止
                  </button>
                </>
              )}
            </div>
          </div>
          
          <div className="connection-status">
            <span>信令服务器: </span>
            <span className={`status-indicator ${wsConnected ? 'connected' : 'disconnected'}`}>
              {wsConnected ? '已连接' : '未连接'}
            </span>
            {roomId && (
              <span className="room-info">当前房间: {roomId}</span>
            )}
          </div>

          {/* 视频会议区域 */}
          <div className="meeting-container">
            {/* 视频网格 */}
            <div className="video-grid">
              {/* 本地视频 */}
              <div className="video-wrapper local-video">
                <span className="video-label">我 ({usersInRoom.find(u => u.isSelf)?.name || '本地'})</span>
                {!isCameraActive ? (
                  <div className="video-placeholder">
                    <FontAwesomeIcon icon={faVideo} />
                    <p>点击"开始摄像头"按钮启动视频</p>
                  </div>
                ) : (
                  <video 
                    ref={videoRef} 
                    autoPlay 
                    muted 
                    playsInline 
                    className="active"
                  />
                )}
                <div className={`status-badge ${isCameraActive ? 'toast-success' : 'toast-error'}`}>
                  <span className="status-dot"></span>
                  {videoStatus}
                </div>
              </div>
              
              {/* 远程视频列表 */}
              {Object.entries(remoteStreams).map(([userId, stream]) => {
                const user = usersInRoom.find(u => u.id === userId);
                return (
                  <div key={userId} className="video-wrapper remote-video">
                    <span className="video-label">{user?.name || `用户_${userId.slice(-6)}`}</span>
                    <video 
                      autoPlay 
                      playsInline 
                      className="remote-video"
                      key={userId}
                      ref={(video) => {
                        if (video && stream && video.srcObject !== stream) {
                          video.srcObject = stream;
                        }
                      }}
                    />
                    <div className="status-badge toast-success">
                      <span className="status-dot"></span>
                      已连接
                    </div>
                  </div>
                );
              })}
              
              {/* 未连接的用户占位 */}
              {usersInRoom.filter(u => !u.isSelf && !remoteStreams[u.id]).map(user => (
                <div key={user.id} className="video-wrapper remote-video">
                  <span className="video-label">{user.name}</span>
                  <div className="video-placeholder">
                    <FontAwesomeIcon icon={faGlobe} />
                    <p>等待视频连接...</p>
                  </div>
                  <div className="status-badge toast-warning">
                    <span className="status-dot"></span>
                    连接中
                  </div>
                </div>
              ))}
            </div>
            
            {/* 用户列表和聊天区域 */}
            <div className="meeting-sidebar">
              {/* 用户列表 */}
              <div className="users-list">
                <h3>会议成员 ({usersInRoom.length})</h3>
                <ul>
                  {usersInRoom.map(user => (
                    <li key={user.id} className={user.isSelf ? 'self' : ''}>
                      <span className="user-name">{user.name}</span>
                      {user.isSelf && <span className="self-tag">(自己)</span>}
                      <div className="user-status">
                        {userStatuses[user.id]?.audioEnabled ? '🎤' : '🔇'}
                        {userStatuses[user.id]?.cameraEnabled ? '📹' : '📷'}
                      </div>
                    </li>
                  ))}
                </ul>
              </div>
              
              {/* 聊天区域 */}
              <div className="chat-container">
                <h3>聊天</h3>
                <div className="chat-messages">
                  {messages.length === 0 ? (
                    <div className="no-messages">暂无消息</div>
                  ) : (
                    messages.map((msg, index) => (
                      <div key={index} className={`message ${msg.isSelf ? 'self' : 'other'}`}>
                        <div className="message-header">
                          <span className="message-sender">{msg.userInfo?.name || '用户'}</span>
                          <span className="message-time">{msg.timestamp}</span>
                        </div>
                        <div className="message-content">{msg.content}</div>
                      </div>
                    ))
                  )}
                </div>
                <div className="chat-input-container">
                  <input
                    type="text"
                    placeholder="输入消息..."
                    value={newMessage}
                    onChange={(e) => setNewMessage(e.target.value)}
                    onKeyPress={(e) => {
                      if (e.key === 'Enter') {
                        sendChatMessage(newMessage);
                      }
                    }}
                    disabled={!roomId}
                    className="chat-input"
                  />
                  <button 
                    onClick={() => sendChatMessage(newMessage)}
                    disabled={!roomId || !newMessage.trim()}
                    className="btn btn-primary send-button"
                  >
                    发送
                  </button>
                </div>
              </div>
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