const WebSocket = require('ws');

// 配置
const SERVER_URL = 'ws://localhost:8080';
const TEST_ROOM = 'test-room-123';

// 创建测试客户端
function createTestClient(clientId) {
    return new Promise((resolve, reject) => {
        console.log(`[客户端${clientId}] 正在连接到服务器...`);
        const ws = new WebSocket(SERVER_URL, {
            headers: {
                'User-Agent': 'WebSocket-Test-Client'
            }
        });
        
        ws.on('open', () => {
            console.log(`[客户端${clientId}] 连接成功`);
            
            // 加入房间
            const joinMessage = {
                type: 'joinRoom',
                roomId: TEST_ROOM,
                userId: `user${clientId}`
            };
            ws.send(JSON.stringify(joinMessage));
            console.log(`[客户端${clientId}] 已发送加入房间请求`);
        });
        
        ws.on('message', (data) => {
            const message = JSON.parse(data.toString());
            console.log(`[客户端${clientId}] 收到消息:`, message);
            
            if (message.type === 'joined') {
                console.log(`[客户端${clientId}] 成功加入房间`);
                resolve(ws);
            }
        });
        
        ws.on('error', (error) => {
            console.error(`[客户端${clientId}] 连接错误:`, error);
            reject(error);
        });
        
        setTimeout(() => {
            reject(new Error(`[客户端${clientId}] 连接超时`));
        }, 5000);
    });
}

// 测试信令转发
async function testSignaling() {
    try {
        console.log('===== 开始信令测试 =====');
        
        // 创建两个客户端
        const client1 = await createTestClient(1);
        const client2 = await createTestClient(2);
        
        // 等待一段时间确保两个客户端都已加入房间
        await new Promise(resolve => setTimeout(resolve, 1000));
        
        // 客户端1发送Offer给客户端2
        const offerMessage = {
            type: 'offer',
            targetUserId: 'user2',
            sdp: 'test-offer-sdp-data'
        };
        
        client1.send(JSON.stringify(offerMessage));
        console.log('[客户端1] 已发送Offer给客户端2');
        
        // 客户端2发送Answer给客户端1
        setTimeout(() => {
            const answerMessage = {
                type: 'answer',
                targetUserId: 'user1',
                sdp: 'test-answer-sdp-data'
            };
            
            client2.send(JSON.stringify(answerMessage));
            console.log('[客户端2] 已发送Answer给客户端1');
        }, 1000);
        
        // 客户端1发送ICE候选给客户端2
        setTimeout(() => {
            const iceMessage = {
                type: 'iceCandidate',
                targetUserId: 'user2',
                candidate: 'test-ice-candidate-data',
                sdpMid: '0',
                sdpMLineIndex: 0
            };
            
            client1.send(JSON.stringify(iceMessage));
            console.log('[客户端1] 已发送ICE候选给客户端2');
        }, 2000);
        
        // 等待测试完成
        setTimeout(() => {
            console.log('===== 测试完成 =====');
            client1.close();
            client2.close();
            process.exit(0);
        }, 5000);
        
    } catch (error) {
        console.error('测试失败:', error);
        process.exit(1);
    }
}

// 运行测试
testSignaling();