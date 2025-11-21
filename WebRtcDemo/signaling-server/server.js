const WebSocket = require('ws');
const http = require('http');

const server = http.createServer();
const wss = new WebSocket.Server({ server });

// 存储房间和用户信息
const rooms = new Map(); // roomId -> Set of {ws, userId}

wss.on('connection', (ws) => {
    console.log('新客户端连接');
    
    let currentUser = null;
    
    // 发送连接成功的消息
    ws.send(JSON.stringify({
        type: 'connected',
        timestamp: Date.now()
    }));
    
    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);
            console.log('收到消息:', data);
            
            switch (data.type) {
                case 'joinRoom':
                    handleJoinRoom(ws, data);
                    break;
                case 'leaveRoom':
                    handleLeaveRoom(ws, data);
                    break;
                case 'offer':
                    handleOffer(ws, data);
                    break;
                case 'answer':
                    handleAnswer(ws, data);
                    break;
                case 'iceCandidate':
                    handleIceCandidate(ws, data);
                    break;
                default:
                    ws.send(JSON.stringify({
                        type: 'error',
                        message: '未知消息类型: ' + data.type
                    }));
            }
        } catch (e) {
            console.error('消息处理错误:', e);
            ws.send(JSON.stringify({
                type: 'error',
                message: '消息格式错误'
            }));
        }
    });
    
    ws.on('close', () => {
        console.log('客户端断开连接');
        handleDisconnect(ws);
    });
    
    ws.on('error', (error) => {
        console.error('WebSocket错误:', error);
        handleDisconnect(ws);
    });
    
    function handleJoinRoom(ws, data) {
        const { roomId, userId } = data;
        if (!roomId || !userId) {
            ws.send(JSON.stringify({
                type: 'error',
                message: '缺少roomId或userId'
            }));
            return;
        }
        
        currentUser = { roomId, userId };
        
        // 创建房间（如果不存在）
        if (!rooms.has(roomId)) {
            rooms.set(roomId, new Set());
        }
        
        // 将用户添加到房间
        const room = rooms.get(roomId);
        room.add({ ws, userId });
        
        // 发送加入成功消息
        ws.send(JSON.stringify({
            type: 'joined',
            roomId: roomId,
            userId: userId
        }));
        
        // 通知房间内的其他用户有新用户加入
        room.forEach(client => {
            if (client.ws !== ws && client.ws.readyState === WebSocket.OPEN) {
                client.ws.send(JSON.stringify({
                    type: 'roomEvent',
                    eventType: 'userJoined',
                    roomId: roomId,
                    userId: userId
                }));
            }
        });
        
        console.log(`用户 ${userId} 加入房间 ${roomId}，房间内共有 ${room.size} 人`);
    }
    
    function handleLeaveRoom(ws, data) {
        if (!currentUser) return;
        
        const { roomId, userId } = currentUser;
        
        if (rooms.has(roomId)) {
            const room = rooms.get(roomId);
            
            // 从房间中移除用户
            for (const client of room) {
                if (client.userId === userId) {
                    room.delete(client);
                    break;
                }
            }
            
            // 通知房间内的其他用户有用户离开
            room.forEach(client => {
                if (client.ws.readyState === WebSocket.OPEN) {
                    client.ws.send(JSON.stringify({
                        type: 'roomEvent',
                        eventType: 'userLeft',
                        roomId: roomId,
                        userId: userId
                    }));
                }
            });
            
            // 如果房间为空，删除房间
            if (room.size === 0) {
                rooms.delete(roomId);
            }
            
            console.log(`用户 ${userId} 离开房间 ${roomId}`);
        }
        
        currentUser = null;
    }
    
    function handleOffer(ws, data) {
        if (!currentUser) return;
        
        const { targetUserId, sdp } = data;
        const { roomId } = currentUser;
        
        if (rooms.has(roomId)) {
            const room = rooms.get(roomId);
            
            // 查找目标用户并转发offer
            for (const client of room) {
                if (client.userId === targetUserId && client.ws.readyState === WebSocket.OPEN) {
                    client.ws.send(JSON.stringify({
                        type: 'offer',
                        sdp: sdp,
                        fromUserId: currentUser.userId
                    }));
                    break;
                }
            }
        }
    }
    
    function handleAnswer(ws, data) {
        if (!currentUser) return;
        
        const { targetUserId, sdp } = data;
        const { roomId } = currentUser;
        
        if (rooms.has(roomId)) {
            const room = rooms.get(roomId);
            
            // 查找目标用户并转发answer
            for (const client of room) {
                if (client.userId === targetUserId && client.ws.readyState === WebSocket.OPEN) {
                    client.ws.send(JSON.stringify({
                        type: 'answer',
                        sdp: sdp,
                        fromUserId: currentUser.userId
                    }));
                    break;
                }
            }
        }
    }
    
    function handleIceCandidate(ws, data) {
        if (!currentUser) return;
        
        const { targetUserId, candidate, sdpMid, sdpMLineIndex } = data;
        const { roomId } = currentUser;
        
        if (rooms.has(roomId)) {
            const room = rooms.get(roomId);
            
            // 查找目标用户并转发ICE候选
            for (const client of room) {
                if (client.userId === targetUserId && client.ws.readyState === WebSocket.OPEN) {
                    client.ws.send(JSON.stringify({
                        type: 'iceCandidate',
                        candidate: candidate,
                        sdpMid: sdpMid,
                        sdpMLineIndex: sdpMLineIndex,
                        fromUserId: currentUser.userId
                    }));
                    break;
                }
            }
        }
    }
    
    function handleDisconnect(ws) {
        if (currentUser) {
            handleLeaveRoom(ws, {});
        }
    }
});

const PORT = 8080;
server.listen(PORT, '0.0.0.0', () => {
    console.log(`信令服务器运行在端口 ${PORT}`);
    console.log(`在Android模拟器中使用地址: ws://10.0.2.2:${PORT}`);
    console.log(`在真机调试中，请替换为您的本机IP地址`);
});