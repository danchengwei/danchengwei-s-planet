const WebSocket = require('ws');
const http = require('http');

const server = http.createServer();
const wss = new WebSocket.Server({ server });

// 存储房间和用户信息
const rooms = new Map(); // roomId -> Set of {ws, userId}

wss.on('connection', (ws) => {
    console.log('新客户端连接');
    
    let currentUser = null;
    let joinedRooms = new Set(); // 跟踪用户加入的房间
    
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
                case 'createRoom':
                    handleCreateRoom(ws, data);
                    break;
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
                case 'getRoomInfo':
                    handleGetRoomInfo(ws, data);
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
    
    function handleCreateRoom(ws, data) {
        const { roomId } = data;
        if (!roomId) {
            ws.send(JSON.stringify({
                type: 'error',
                message: '缺少roomId'
            }));
            return;
        }
        
        // 创建房间（如果不存在）
        if (!rooms.has(roomId)) {
            rooms.set(roomId, new Set());
            console.log(`创建新房间: ${roomId}`);
            ws.send(JSON.stringify({
                type: 'roomCreated',
                roomId: roomId,
                message: `房间 ${roomId} 创建成功`
            }));
        } else {
            ws.send(JSON.stringify({
                type: 'error',
                message: '房间已存在'
            }));
        }
    }

    function handleJoinRoom(ws, data) {
        const { roomId, userId } = data;
        if (!roomId || !userId) {
            ws.send(JSON.stringify({
                type: 'error',
                message: '缺少roomId或userId'
            }));
            return;
        }
        
        // 记录尝试加入房间的日志
        console.log(`用户 ${userId} 尝试加入房间 ${roomId}`);
        
        // 检查房间是否存在
        if (!rooms.has(roomId)) {
            console.log(`用户 ${userId} 尝试加入不存在的房间 ${roomId}`);
            ws.send(JSON.stringify({
                type: 'error',
                message: `房间 ${roomId} 不存在，请先创建房间`
            }));
            return;
        }
        
        currentUser = { roomId, userId };
        joinedRooms.add(roomId);
        
        // 检查用户是否已在房间中
        const room = rooms.get(roomId);
        for (const client of room) {
            if (client.userId === userId) {
                console.log(`警告: 用户 ${userId} 已在房间 ${roomId} 中`);
                ws.send(JSON.stringify({
                    type: 'error',
                    message: '用户已在房间中'
                }));
                return;
            }
        }
        
        console.log(`房间 ${roomId} 已存在，当前人数: ${room.size}`);
        
        // 将用户添加到房间
        const roomSet = rooms.get(roomId);
        roomSet.add({ ws, userId });
        
        // 发送加入成功消息
        ws.send(JSON.stringify({
            type: 'joined',
            roomId: roomId,
            userId: userId
        }));
        
        // 通知房间内的其他用户有新用户加入
        roomSet.forEach(client => {
            if (client.ws !== ws && client.ws.readyState === WebSocket.OPEN) {
                client.ws.send(JSON.stringify({
                    type: 'userJoined',
                    roomId: roomId,
                    userId: userId
                }));
            }
        });
        
        // 向新加入的用户发送房间内现有用户的信息
        const existingUsers = [];
        roomSet.forEach(client => {
            if (client.ws !== ws && client.ws.readyState === WebSocket.OPEN) {
                existingUsers.push(client.userId);
            }
        });
        
        if (existingUsers.length > 0) {
            ws.send(JSON.stringify({
                type: 'existingUsers',
                roomId: roomId,
                users: existingUsers
            }));
        }
        
        console.log(`用户 ${userId} 成功加入房间 ${roomId}，房间内共有 ${roomSet.size} 人`);
        logCurrentRoomInfo();
    }
    
    function handleLeaveRoom(ws, data) {
        if (!currentUser) {
            console.log('用户未加入任何房间，无法执行离开操作');
            return;
        }
        
        const { roomId, userId } = currentUser;
        
        if (rooms.has(roomId)) {
            const room = rooms.get(roomId);
            
            // 从房间中移除用户
            let userFound = false;
            for (const client of room) {
                if (client.userId === userId) {
                    room.delete(client);
                    userFound = true;
                    break;
                }
            }
            
            if (!userFound) {
                console.log(`用户 ${userId} 不在房间 ${roomId} 中`);
                return;
            }
            
            // 通知房间内的其他用户有用户离开
            room.forEach(client => {
                if (client.ws.readyState === WebSocket.OPEN) {
                    client.ws.send(JSON.stringify({
                        type: 'userLeft',
                        roomId: roomId,
                        userId: userId
                    }));
                }
            });
            
            // 如果房间为空，删除房间
            if (room.size === 0) {
                rooms.delete(roomId);
                console.log(`房间 ${roomId} 已清空，删除房间`);
            } else {
                console.log(`用户 ${userId} 离开房间 ${roomId}，房间剩余人数: ${room.size}`);
            }
            
            logCurrentRoomInfo();
        } else {
            console.log(`尝试离开不存在的房间: ${roomId}`);
        }
        
        currentUser = null;
    }
    
    function handleOffer(ws, data) {
        if (!currentUser) {
            console.log('用户未加入任何房间，无法发送offer');
            return;
        }
        
        const { targetUserId, sdp } = data;
        const { roomId, userId } = currentUser;
        
        if (rooms.has(roomId)) {
            const room = rooms.get(roomId);
            
            // 查找目标用户并转发offer
            let targetUserFound = false;
            for (const client of room) {
                if (client.userId === targetUserId && client.ws.readyState === WebSocket.OPEN) {
                    client.ws.send(JSON.stringify({
                        type: 'offer',
                        sdp: sdp,
                        from: currentUser.userId
                    }));
                    targetUserFound = true;
                    console.log(`转发offer: ${userId} -> ${targetUserId} (房间: ${roomId})`);
                    break;
                }
            }
            
            if (!targetUserFound) {
                console.log(`在房间 ${roomId} 中未找到目标用户: ${targetUserId}`);
            }
        } else {
            console.log(`尝试在不存在的房间中发送offer: ${roomId}`);
        }
    }
    
    function handleAnswer(ws, data) {
        if (!currentUser) {
            console.log('用户未加入任何房间，无法发送answer');
            return;
        }
        
        const { targetUserId, sdp } = data;
        const { roomId, userId } = currentUser;
        
        if (rooms.has(roomId)) {
            const room = rooms.get(roomId);
            
            // 查找目标用户并转发answer
            let targetUserFound = false;
            for (const client of room) {
                if (client.userId === targetUserId && client.ws.readyState === WebSocket.OPEN) {
                    client.ws.send(JSON.stringify({
                        type: 'answer',
                        sdp: sdp,
                        from: currentUser.userId
                    }));
                    targetUserFound = true;
                    console.log(`转发answer: ${userId} -> ${targetUserId} (房间: ${roomId})`);
                    break;
                }
            }
            
            if (!targetUserFound) {
                console.log(`在房间 ${roomId} 中未找到目标用户: ${targetUserId}`);
            }
        } else {
            console.log(`尝试在不存在的房间中发送answer: ${roomId}`);
        }
    }
    
    function handleIceCandidate(ws, data) {
        if (!currentUser) {
            console.log('用户未加入任何房间，无法发送ICE候选');
            return;
        }
        
        const { targetUserId, candidate, sdpMid, sdpMLineIndex } = data;
        const { roomId, userId } = currentUser;
        
        if (rooms.has(roomId)) {
            const room = rooms.get(roomId);
            
            // 查找目标用户并转发ICE候选
            let targetUserFound = false;
            for (const client of room) {
                if (client.userId === targetUserId && client.ws.readyState === WebSocket.OPEN) {
                    client.ws.send(JSON.stringify({
                        type: 'iceCandidate',
                        candidate: candidate,
                        sdpMid: sdpMid,
                        sdpMLineIndex: sdpMLineIndex,
                        from: currentUser.userId
                    }));
                    targetUserFound = true;
                    console.log(`转发ICE候选: ${userId} -> ${targetUserId} (房间: ${roomId})`);
                    break;
                }
            }
            
            if (!targetUserFound) {
                console.log(`在房间 ${roomId} 中未找到目标用户: ${targetUserId}`);
            }
        } else {
            console.log(`尝试在不存在的房间中发送ICE候选: ${roomId}`);
        }
    }
    
    function handleGetRoomInfo(ws, data) {
        const roomList = [];
        rooms.forEach((room, roomId) => {
            const userIds = Array.from(room).map(client => client.userId);
            roomList.push({
                roomId: roomId,
                userCount: room.size,
                users: userIds
            });
        });
        
        ws.send(JSON.stringify({
            type: 'roomInfo',
            rooms: roomList,
            totalRooms: rooms.size
        }));
    }
    
    function handleDisconnect(ws) {
        console.log('处理客户端断开连接');
        if (currentUser) {
            console.log(`用户 ${currentUser.userId} 断开连接，自动离开房间 ${currentUser.roomId}`);
            handleLeaveRoom(ws, {});
        }
    }
    
    // 记录当前房间信息
    function logCurrentRoomInfo() {
        console.log('=== 当前房间信息 ===');
        if (rooms.size === 0) {
            console.log('暂无活跃房间');
        } else {
            console.log(`共有 ${rooms.size} 个活跃房间:`);
            rooms.forEach((room, roomId) => {
                const userIds = Array.from(room).map(client => client.userId);
                console.log(`  房间 ${roomId}: ${room.size} 人 [${userIds.join(', ')}]`);
            });
        }
        console.log('==================');
    }
});

const PORT = 8080;
server.listen(PORT, '0.0.0.0', () => {
    console.log(`信令服务器运行在端口 ${PORT}`);
    console.log(`在Android模拟器中使用地址: ws://10.0.2.2:${PORT}`);
    console.log(`在真机调试中，请替换为您的本机IP地址`);
});