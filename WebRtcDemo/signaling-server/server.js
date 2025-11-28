const WebSocket = require('ws');
const http = require('http');
const url = require('url');

const server = http.createServer();
const wss = new WebSocket.Server({ 
    server,
    verifyClient: (info) => {
        console.log(`[${new Date().toISOString()}] 验证客户端连接:`, {
            origin: info.origin,
            secure: info.secure,
            req: info.req.headers
        });
        return true; // 允许所有连接
    }
});

// 存储房间和用户信息
const rooms = new Map(); // roomId -> Set of {ws, userId}
// 全局存储所有连接
const allConnections = new Map(); // 用于跟踪所有活跃连接

// 生成唯一ID
function generateUniqueId() {
    return Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15);
}

// 安全发送消息的函数
function safeSend(ws, message) {
    try {
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify(message));
            return true;
        }
    } catch (e) {
        console.error('发送消息失败:', e);
    }
    return false;
}

wss.on('connection', (ws, req) => {
    // 生成连接ID
    const connectionId = generateUniqueId();
    allConnections.set(connectionId, ws);
    
    console.log(`[${new Date().toISOString()}] 新客户端连接, ID: ${connectionId}, 当前连接数: ${allConnections.size}`);
    
    // 使用WebSocket对象的属性来存储用户信息
    ws.currentUser = null;
    ws.joinedRooms = new Set(); // 跟踪用户加入的房间
    ws.connectionId = connectionId; // 存储连接ID
    
    // 发送连接成功的消息
    safeSend(ws, {
        type: 'connected',
        timestamp: Date.now(),
        connectionId: connectionId
    });
    
    ws.on('message', (message) => {
        try {
            // 健壮性检查
            if (!message || (typeof message !== 'string' && !Buffer.isBuffer(message))) {
                console.warn('收到无效消息类型');
                safeSend(ws, {
                    type: 'error',
                    message: '无效的消息格式'
                });
                return;
            }
            
            // 尝试解析JSON
            let data;
            try {
                data = JSON.parse(message.toString());
            } catch (parseError) {
                console.error('解析消息失败:', parseError);
                safeSend(ws, {
                    type: 'error',
                    message: '消息解析失败，请检查JSON格式'
                });
                return;
            }
            
            // 验证消息结构
            if (!data.type) {
                console.warn('消息缺少type字段');
                safeSend(ws, {
                    type: 'error',
                    message: '消息缺少必要的type字段'
                });
                return;
            }
            
            console.log(`收到消息 [${connectionId}]:`, data.type);
            
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
                    safeSend(ws, {
                        type: 'error',
                        message: '未知消息类型: ' + data.type
                    });
            }
        } catch (e) {
            console.error('消息处理错误:', e);
            safeSend(ws, {
                type: 'error',
                message: '消息处理时发生错误'
            });
        }
    });
    
    ws.on('close', (code, reason) => {
        console.log(`[${new Date().toISOString()}] 客户端断开连接, ID: ${connectionId}, 代码: ${code}, 原因: ${reason}`);
        handleDisconnect(ws);
    });
    
    ws.on('error', (error) => {
        console.error(`WebSocket错误 [${connectionId}]:`, error.message);
        // 注意：这里不立即调用handleDisconnect，因为close事件会被触发
    });
    
    function handleCreateRoom(ws, data) {
        try {
            const { roomId } = data;
            if (!roomId || typeof roomId !== 'string' || roomId.trim() === '') {
                safeSend(ws, {
                    type: 'error',
                    message: '房间ID无效'
                });
                return;
            }
            
            // 创建房间（如果不存在）
            if (!rooms.has(roomId)) {
                rooms.set(roomId, new Set());
                console.log(`[${new Date().toISOString()}] 创建新房间: ${roomId}`);
                safeSend(ws, {
                    type: 'roomCreated',
                    roomId: roomId,
                    message: `房间 ${roomId} 创建成功`
                });
            } else {
                // 房间已存在，允许用户加入
                safeSend(ws, {
                    type: 'roomExists',
                    roomId: roomId,
                    message: `房间 ${roomId} 已存在，可以直接加入`
                });
            }
        } catch (e) {
            console.error('创建房间错误:', e);
            safeSend(ws, {
                type: 'error',
                message: '创建房间失败'
            });
        }
    }
    
    function handleJoinRoom(ws, data) {
        try {
            const { roomId, userId } = data;
            if (!roomId || !userId || typeof roomId !== 'string' || typeof userId !== 'string') {
                safeSend(ws, {
                    type: 'error',
                    message: '房间ID或用户ID无效'
                });
                return;
            }
            
            // 记录尝试加入房间的日志
            console.log(`[${new Date().toISOString()}] 用户 ${userId} 尝试加入房间 ${roomId}`);
            
            // 检查房间是否存在
            if (!rooms.has(roomId)) {
                console.log(`用户 ${userId} 尝试加入不存在的房间 ${roomId}`);
                safeSend(ws, {
                    type: 'error',
                    message: `房间 ${roomId} 不存在，请先创建房间`
                });
                return;
            }
            
            // 如果用户已在其他房间，先离开
            if (ws.currentUser && ws.currentUser.roomId && ws.currentUser.roomId !== roomId) {
                console.log(`用户 ${userId} 已在房间 ${ws.currentUser.roomId} 中，先离开再加入新房间`);
                handleLeaveRoomInternal(ws, ws.currentUser.roomId);
            }
            
            ws.currentUser = { roomId, userId };
            ws.joinedRooms.add(roomId);
            
            // 检查用户是否已在房间中
            const room = rooms.get(roomId);
            let userInRoom = false;
            for (const client of room) {
                if (client.userId === userId) {
                    console.log(`警告: 用户 ${userId} 已在房间 ${roomId} 中`);
                    safeSend(ws, {
                        type: 'error',
                        message: '用户已在房间中'
                    });
                    return;
                }
            }
            
            console.log(`房间 ${roomId} 已存在，当前人数: ${room.size}`);
            
            // 将用户添加到房间
            const roomSet = rooms.get(roomId);
            roomSet.add({ ws, userId });
            
            // 发送加入成功消息
            safeSend(ws, {
                type: 'joined',
                roomId: roomId,
                userId: userId
            });
            
            // 通知房间内的其他用户有新用户加入
            const disconnectedClients = [];
            roomSet.forEach(client => {
                if (client.ws !== ws) {
                    if (!safeSend(client.ws, {
                        type: 'userJoined',
                        roomId: roomId,
                        userId: userId
                    })) {
                        // 记录断开连接的客户端
                        disconnectedClients.push(client);
                    }
                }
            });
            
            // 清理断开连接的客户端
            if (disconnectedClients.length > 0) {
                console.log(`发现 ${disconnectedClients.length} 个断开连接的客户端，进行清理`);
                disconnectedClients.forEach(client => {
                    roomSet.delete(client);
                });
            }
            
            // 向新加入的用户发送房间内现有用户的信息
            const existingUsers = [];
            roomSet.forEach(client => {
                if (client.ws !== ws && client.ws.readyState === WebSocket.OPEN) {
                    existingUsers.push(client.userId);
                }
            });
            
            if (existingUsers.length > 0) {
                safeSend(ws, {
                    type: 'existingUsers',
                    roomId: roomId,
                    users: existingUsers
                });
            }
            
            console.log(`用户 ${userId} 成功加入房间 ${roomId}，房间内共有 ${roomSet.size} 人`);
            logCurrentRoomInfo();
        } catch (e) {
            console.error('加入房间错误:', e);
            safeSend(ws, {
                type: 'error',
                message: '加入房间失败'
            });
        }
    }
    
    // 内部离开房间方法（不发送消息）
    function handleLeaveRoomInternal(ws, roomId) {
        try {
            if (!roomId || !rooms.has(roomId)) return;
            
            const room = rooms.get(roomId);
            const userId = ws.currentUser?.userId;
            
            if (!userId) return;
            
            // 从房间中移除用户
            let userFound = false;
            for (const client of room) {
                if (client.userId === userId) {
                    room.delete(client);
                    userFound = true;
                    break;
                }
            }
            
            if (!userFound) return;
            
            // 通知房间内的其他用户有用户离开
            const disconnectedClients = [];
            room.forEach(client => {
                if (!safeSend(client.ws, {
                    type: 'userLeft',
                    roomId: roomId,
                    userId: userId
                })) {
                    disconnectedClients.push(client);
                }
            });
            
            // 清理断开连接的客户端
            if (disconnectedClients.length > 0) {
                disconnectedClients.forEach(client => {
                    room.delete(client);
                });
            }
            
            // 如果房间为空，删除房间
            if (room.size === 0) {
                rooms.delete(roomId);
                console.log(`房间 ${roomId} 已清空，删除房间`);
            }
            
            // 清除用户的房间信息
            if (ws.joinedRooms) {
                ws.joinedRooms.delete(roomId);
            }
        } catch (e) {
            console.error('内部离开房间错误:', e);
        }
    }
    
    function handleLeaveRoom(ws, data) {
        try {
            if (!ws.currentUser) {
                console.log('用户未加入任何房间，无法执行离开操作');
                safeSend(ws, {
                    type: 'error',
                    message: '您未加入任何房间'
                });
                return;
            }
            
            const { roomId, userId } = ws.currentUser;
            const leavingRoomId = roomId;
            
            handleLeaveRoomInternal(ws, roomId);
            
            // 发送离开成功消息
            safeSend(ws, {
                type: 'left',
                roomId: leavingRoomId,
                message: `成功离开房间 ${leavingRoomId}`
            });
            
            console.log(`用户 ${userId} 主动离开房间 ${leavingRoomId}`);
            
            // 清除当前用户信息
            ws.currentUser = null;
            
            logCurrentRoomInfo();
        } catch (e) {
            console.error('离开房间错误:', e);
            safeSend(ws, {
                type: 'error',
                message: '离开房间失败'
            });
        }
    }
    
    function handleOffer(ws, data) {
        try {
            if (!ws.currentUser) {
                console.log('用户未加入任何房间，无法发送offer');
                safeSend(ws, {
                    type: 'error',
                    message: '您未加入任何房间'
                });
                return;
            }
            
            const { targetUserId, sdp } = data;
            const { roomId, userId } = ws.currentUser;
            
            if (!targetUserId || !sdp) {
                safeSend(ws, {
                    type: 'error',
                    message: '缺少目标用户ID或SDP数据'
                });
                return;
            }
            
            if (rooms.has(roomId)) {
                const room = rooms.get(roomId);
                
                // 查找目标用户并转发offer
                let targetUserFound = false;
                const disconnectedClients = [];
                
                for (const client of room) {
                    if (client.userId === targetUserId) {
                        if (client.ws.readyState === WebSocket.OPEN) {
                            safeSend(client.ws, {
                                type: 'offer',
                                sdp: sdp,
                                from: userId
                            });
                            targetUserFound = true;
                            console.log(`[${new Date().toISOString()}] 转发offer: ${userId} -> ${targetUserId} (房间: ${roomId})`);
                        } else {
                            disconnectedClients.push(client);
                        }
                        break;
                    }
                }
                
                // 清理断开连接的客户端
                if (disconnectedClients.length > 0) {
                    disconnectedClients.forEach(client => {
                        room.delete(client);
                    });
                }
                
                if (!targetUserFound) {
                    console.log(`在房间 ${roomId} 中未找到目标用户: ${targetUserId}`);
                    safeSend(ws, {
                        type: 'error',
                        message: `目标用户 ${targetUserId} 不存在或已断开连接`
                    });
                }
            } else {
                console.log(`尝试在不存在的房间中发送offer: ${roomId}`);
                safeSend(ws, {
                    type: 'error',
                    message: '房间不存在'
                });
            }
        } catch (e) {
            console.error('处理offer错误:', e);
            safeSend(ws, {
                type: 'error',
                message: '发送offer失败'
            });
        }
    }
    
    function handleAnswer(ws, data) {
        try {
            if (!ws.currentUser) {
                console.log('用户未加入任何房间，无法发送answer');
                safeSend(ws, {
                    type: 'error',
                    message: '您未加入任何房间'
                });
                return;
            }
            
            const { targetUserId, sdp } = data;
            const { roomId, userId } = ws.currentUser;
            
            if (!targetUserId || !sdp) {
                safeSend(ws, {
                    type: 'error',
                    message: '缺少目标用户ID或SDP数据'
                });
                return;
            }
            
            if (rooms.has(roomId)) {
                const room = rooms.get(roomId);
                
                // 查找目标用户并转发answer
                let targetUserFound = false;
                const disconnectedClients = [];
                
                for (const client of room) {
                    if (client.userId === targetUserId) {
                        if (client.ws.readyState === WebSocket.OPEN) {
                            safeSend(client.ws, {
                                type: 'answer',
                                sdp: sdp,
                                from: userId
                            });
                            targetUserFound = true;
                            console.log(`[${new Date().toISOString()}] 转发answer: ${userId} -> ${targetUserId} (房间: ${roomId})`);
                        } else {
                            disconnectedClients.push(client);
                        }
                        break;
                    }
                }
                
                // 清理断开连接的客户端
                if (disconnectedClients.length > 0) {
                    disconnectedClients.forEach(client => {
                        room.delete(client);
                    });
                }
                
                if (!targetUserFound) {
                    console.log(`在房间 ${roomId} 中未找到目标用户: ${targetUserId}`);
                    safeSend(ws, {
                        type: 'error',
                        message: `目标用户 ${targetUserId} 不存在或已断开连接`
                    });
                }
            } else {
                console.log(`尝试在不存在的房间中发送answer: ${roomId}`);
                safeSend(ws, {
                    type: 'error',
                    message: '房间不存在'
                });
            }
        } catch (e) {
            console.error('处理answer错误:', e);
            safeSend(ws, {
                type: 'error',
                message: '发送answer失败'
            });
        }
    }
    
    function handleIceCandidate(ws, data) {
        try {
            if (!ws.currentUser) {
                console.log('用户未加入任何房间，无法发送ICE候选');
                return;
            }
            
            const { targetUserId, candidate, sdpMid, sdpMLineIndex } = data;
            const { roomId, userId } = ws.currentUser;
            
            if (!targetUserId) {
                console.warn('ICE候选缺少目标用户ID');
                return;
            }
            
            if (rooms.has(roomId)) {
                const room = rooms.get(roomId);
                
                // 查找目标用户并转发ICE候选
                const disconnectedClients = [];
                
                for (const client of room) {
                    if (client.userId === targetUserId) {
                        if (client.ws.readyState === WebSocket.OPEN) {
                            safeSend(client.ws, {
                                type: 'iceCandidate',
                                candidate: candidate,
                                sdpMid: sdpMid,
                                sdpMLineIndex: sdpMLineIndex,
                                from: userId
                            });
                            // 减少ICE候选者的日志记录
                            if (Math.random() > 0.9) { // 只记录约10%的ICE候选者消息
                                console.log(`[${new Date().toISOString()}] 转发ICE候选: ${userId} -> ${targetUserId} (房间: ${roomId})`);
                            }
                        } else {
                            disconnectedClients.push(client);
                        }
                        break;
                    }
                }
                
                // 清理断开连接的客户端
                if (disconnectedClients.length > 0) {
                    disconnectedClients.forEach(client => {
                        room.delete(client);
                    });
                }
            }
        } catch (e) {
            // 对于ICE候选者，我们不发送错误消息，只记录错误
            console.error('处理ICE候选错误:', e);
        }
    }
    
    function handleDisconnect(ws) {
        try {
            const connectionId = ws.connectionId;
            console.log(`[${new Date().toISOString()}] 处理客户端断开连接, ID: ${connectionId}`);
            
            // 从全局连接Map中移除
            allConnections.delete(connectionId);
            
            if (ws.currentUser) {
                const { userId, roomId } = ws.currentUser;
                console.log(`用户 ${userId} 断开连接，自动离开房间 ${roomId}`);
                
                // 使用内部方法离开房间
                handleLeaveRoomInternal(ws, roomId);
            }
            
            // 清理所有房间中的该连接
            if (ws.joinedRooms) {
                ws.joinedRooms.forEach(roomId => {
                    if (rooms.has(roomId)) {
                        const room = rooms.get(roomId);
                        const clientsToRemove = [];
                        
                        for (const client of room) {
                            if (client.ws === ws) {
                                clientsToRemove.push(client);
                            }
                        }
                        
                        clientsToRemove.forEach(client => {
                            room.delete(client);
                        });
                        
                        // 如果房间为空，删除房间
                        if (room.size === 0) {
                            rooms.delete(roomId);
                            console.log(`房间 ${roomId} 已清空，删除房间`);
                        }
                    }
                });
            }
            
            console.log(`当前连接数: ${allConnections.size}`);
            logCurrentRoomInfo();
        } catch (e) {
            console.error('处理断开连接错误:', e);
        }
    }
    
    function handleGetRoomInfo(ws, data) {
        try {
            const roomList = [];
            rooms.forEach((room, roomId) => {
                // 过滤掉断开连接的客户端
                const activeClients = [];
                const disconnectedClients = [];
                
                for (const client of room) {
                    if (client.ws.readyState === WebSocket.OPEN) {
                        activeClients.push(client);
                    } else {
                        disconnectedClients.push(client);
                    }
                }
                
                // 清理断开连接的客户端
                if (disconnectedClients.length > 0) {
                    disconnectedClients.forEach(client => {
                        room.delete(client);
                    });
                }
                
                // 如果房间现在为空，跳过
                if (room.size > 0) {
                    const userIds = activeClients.map(client => client.userId);
                    roomList.push({
                        roomId: roomId,
                        userCount: room.size,
                        users: userIds
                    });
                }
            });
            
            safeSend(ws, {
                type: 'roomInfo',
                rooms: roomList,
                totalRooms: rooms.size,
                timestamp: Date.now()
            });
        } catch (e) {
            console.error('获取房间信息错误:', e);
            safeSend(ws, {
                type: 'error',
                message: '获取房间信息失败'
            });
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
                const activeUsers = [];
                const userCount = room.size;
                
                for (const client of room) {
                    if (client.ws.readyState === WebSocket.OPEN) {
                        activeUsers.push(client.userId);
                    } else {
                        // 标记为待清理
                    }
                }
                
                console.log(`  房间 ${roomId}: ${userCount} 人 [${activeUsers.join(', ')}]`);
            });
        }
        console.log('==================');
    }
});

// 定期清理无效连接和房间（每30秒）
setInterval(() => {
    try {
        const now = new Date().toISOString();
        console.log(`[${now}] 定期清理 - 当前连接数: ${allConnections.size}, 房间数: ${rooms.size}`);
        
        // 清理空房间和无效连接
        const emptyRooms = [];
        
        rooms.forEach((room, roomId) => {
            const disconnectedClients = [];
            
            for (const client of room) {
                if (!client.ws || client.ws.readyState !== WebSocket.OPEN) {
                    disconnectedClients.push(client);
                }
            }
            
            // 移除断开连接的客户端
            if (disconnectedClients.length > 0) {
                console.log(`清理房间 ${roomId} 中的 ${disconnectedClients.length} 个断开连接的客户端`);
                disconnectedClients.forEach(client => {
                    room.delete(client);
                });
            }
            
            // 检查是否为空房间
            if (room.size === 0) {
                emptyRooms.push(roomId);
            }
        });
        
        // 删除空房间
        emptyRooms.forEach(roomId => {
            rooms.delete(roomId);
            console.log(`删除空房间: ${roomId}`);
        });
        
        // 检查并清理孤立的WebSocket连接（未在任何房间中但仍连接）
        const inactiveConnections = [];
        allConnections.forEach((ws, connId) => {
            if (ws.readyState !== WebSocket.OPEN) {
                inactiveConnections.push(connId);
            }
        });
        
        inactiveConnections.forEach(connId => {
            allConnections.delete(connId);
        });
        
        console.log(`[${now}] 清理完成 - 连接数: ${allConnections.size}, 房间数: ${rooms.size}`);
    } catch (error) {
        console.error('定期清理错误:', error);
    }
}, 30000);

// 优雅关闭
function shutdown() {
    console.log('正在关闭服务器...');
    
    // 发送断开连接消息给所有客户端
    allConnections.forEach((ws, connId) => {
        try {
            safeSend(ws, {
                type: 'serverShutdown',
                message: '服务器正在关闭'
            });
            ws.close(1000, 'Server shutting down');
        } catch (e) {
            console.error('关闭连接时出错:', e);
        }
    });
    
    // 关闭WebSocket服务器
    wss.close(() => {
        console.log('WebSocket服务器已关闭');
        
        // 关闭HTTP服务器
        server.close(() => {
            console.log('HTTP服务器已关闭');
            process.exit(0);
        });
    });
    
    // 强制退出（如果10秒内没有关闭）
    setTimeout(() => {
        console.error('强制关闭服务器');
        process.exit(1);
    }, 10000);
}

// 监听终止信号
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

const PORT = 8080;
server.listen(PORT, '0.0.0.0', () => {
    console.log(`[${new Date().toISOString()}] 信令服务器运行在端口 ${PORT}`);
    console.log(`在Android模拟器中使用地址: ws://10.0.2.2:${PORT}`);
    console.log(`在真机调试中，请替换为您的本机IP地址`);
    console.log('服务器已启动，等待客户端连接...');
});
