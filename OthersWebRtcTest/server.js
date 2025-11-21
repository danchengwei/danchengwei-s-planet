import express from 'express';
import { WebSocketServer } from 'ws';
import http from 'http';

// 创建Express应用
const app = express();
// 创建HTTP服务器
const server = http.createServer(app);
// 创建WebSocket服务器
const wss = new WebSocketServer({ noServer: true });

// 房间管理
const rooms = new Map(); // 房间ID -> 房间对象
const clients = new Map(); // client对象 -> 用户信息

// 处理WebSocket连接
wss.on('connection', (ws, request, userInfo) => {
  // 存储客户端信息
  clients.set(ws, userInfo);
  
  console.log(`新用户连接: ${userInfo.userId}`);
  
  // 处理消息
  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message);
      handleSignalingMessage(ws, data);
    } catch (error) {
      console.error('解析消息失败:', error);
    }
  });
  
  // 处理断开连接
  ws.on('close', () => {
    handleDisconnection(ws);
  });
  
  // 处理错误
  ws.on('error', (error) => {
    console.error('WebSocket错误:', error);
  });
});

// 处理HTTP升级为WebSocket
server.on('upgrade', (request, socket, head) => {
  // 检查路径是否为/webrtc
  if (request.url === '/webrtc') {
    // 提取用户ID（如果有）
    const urlParams = new URL(request.url, `http://${request.headers.host}`);
    const userId = urlParams.searchParams.get('userId') || `user_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit('connection', ws, request, { userId });
    });
  } else {
    socket.destroy();
  }
});

// 处理信令消息
function handleSignalingMessage(ws, message) {
  const userInfo = clients.get(ws);
  console.log(`收到来自 ${userInfo.userId} 的消息:`, message.type);
  
  switch (message.type) {
    case 'create_room':
      handleCreateRoom(ws, message, userInfo);
      break;
    case 'join_room':
      handleJoinRoom(ws, message, userInfo);
      break;
    case 'offer':
    case 'answer':
    case 'ice_candidate':
      // 转发P2P信令消息
      forwardSignalingMessage(ws, message);
      break;
    case 'message':
      // 转发聊天消息
      broadcastToRoom(ws, message);
      break;
    case 'user_status_update':
      // 转发用户状态更新
      broadcastToRoom(ws, message);
      break;
    default:
      console.log('未知消息类型:', message.type);
  }
}

// 处理创建房间
function handleCreateRoom(ws, message, userInfo) {
  const roomId = message.roomId;
  
  // 创建新房间
  rooms.set(roomId, {
    id: roomId,
    participants: new Map() // client -> 用户信息
  });
  
  const room = rooms.get(roomId);
  room.participants.set(ws, userInfo);
  
  // 发送房间创建成功消息
  ws.send(JSON.stringify({
    type: 'room_created',
    roomId: roomId,
    message: '房间创建成功'
  }));
  
  console.log(`创建房间成功: ${roomId}, 创建者: ${userInfo.userId}`);
}

// 处理加入房间
function handleJoinRoom(ws, message, userInfo) {
  const roomId = message.roomId;
  const room = rooms.get(roomId);
  
  if (room) {
    // 用户加入房间
    room.participants.set(ws, userInfo);
    
    // 发送房间加入成功消息给当前用户
    ws.send(JSON.stringify({
      type: 'room_joined',
      roomId: roomId,
      message: '成功加入房间'
    }));
    
    // 通知房间内其他用户有新用户加入
    const joinedMessage = {
      type: 'user_joined',
      userId: userInfo.userId,
      roomId: roomId
    };
    
    // 广播给房间内其他用户
    broadcastToRoomExcept(ws, joinedMessage, room);
    
    console.log(`用户 ${userInfo.userId} 加入房间 ${roomId}`);
  } else {
    // 房间不存在
    ws.send(JSON.stringify({
      type: 'error',
      message: '房间不存在'
    }));
    
    console.log(`用户 ${userInfo.userId} 尝试加入不存在的房间 ${roomId}`);
  }
}

// 转发P2P信令消息
function forwardSignalingMessage(ws, message) {
  const roomId = message.roomId;
  const targetUserId = message.targetUserId;
  const room = rooms.get(roomId);
  
  if (room) {
    // 查找目标用户
    let targetClient = null;
    for (const [client, info] of room.participants.entries()) {
      if (info.userId === targetUserId) {
        targetClient = client;
        break;
      }
    }
    
    if (targetClient && targetClient.readyState === WebSocketServer.OPEN) {
      targetClient.send(JSON.stringify(message));
    } else {
      console.log(`目标用户 ${targetUserId} 不在房间内或连接已关闭`);
    }
  }
}

// 广播消息到房间内所有用户
function broadcastToRoom(ws, message) {
  const userInfo = clients.get(ws);
  const roomId = message.roomId;
  const room = rooms.get(roomId);
  
  if (room) {
    const broadcastMessage = {
      ...message,
      userId: userInfo.userId,
      timestamp: Date.now()
    };
    
    for (const client of room.participants.keys()) {
      if (client.readyState === WebSocketServer.OPEN) {
        client.send(JSON.stringify(broadcastMessage));
      }
    }
  }
}

// 广播消息到房间内除了指定用户外的所有用户
function broadcastToRoomExcept(ws, message, room) {
  for (const client of room.participants.keys()) {
    if (client !== ws && client.readyState === WebSocketServer.OPEN) {
      client.send(JSON.stringify(message));
    }
  }
}

// 处理断开连接
function handleDisconnection(ws) {
  const userInfo = clients.get(ws);
  if (!userInfo) return;
  
  console.log(`用户断开连接: ${userInfo.userId}`);
  
  // 查找用户所在的房间
  for (const [roomId, room] of rooms.entries()) {
    if (room.participants.has(ws)) {
      // 从房间中移除用户
      room.participants.delete(ws);
      
      // 通知房间内其他用户
      const leftMessage = {
        type: 'user_left',
        userId: userInfo.userId,
        roomId: roomId
      };
      
      broadcastToRoomExcept(ws, leftMessage, room);
      
      // 如果房间为空，删除房间
      if (room.participants.size === 0) {
        rooms.delete(roomId);
        console.log(`房间 ${roomId} 已删除（无用户）`);
      }
      
      break;
    }
  }
  
  // 从客户端映射中移除
  clients.delete(ws);
}

// 启动服务器
const PORT = process.env.PORT || 8081;
server.listen(PORT, () => {
  console.log(`信令服务器运行在 http://localhost:${PORT}`);
  console.log(`WebSocket服务地址: ws://localhost:${PORT}/webrtc`);
});