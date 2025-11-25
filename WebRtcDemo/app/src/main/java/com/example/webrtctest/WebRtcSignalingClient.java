package com.example.webrtctest;

import org.java_websocket.client.WebSocketClient;
import org.java_websocket.drafts.Draft_6455; // WebSocket 标准协议草案（必须）
import org.java_websocket.handshake.ServerHandshake;
import org.json.JSONArray;
import org.json.JSONObject;

import java.net.URI;
import java.net.URISyntaxException;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * WebRTC 信令客户端（基于 Java-WebSocket 库，符合项目规范）
 * 核心功能：WebSocket 连接管理、信令发送（SDP/ICE/房间指令）、信令接收解析、断线重连
 */
public class WebRtcSignalingClient extends WebSocketClient {
    // 信令回调接口：将信令传递给 WebRTC 核心逻辑处理
    public interface SignalingCallback {
        // 连接成功
        void onConnectSuccess();
        // 连接失败
        void onConnectFailure(String errorMsg);
        // 连接断开
        void onDisconnect();
        // 接收 SDP Offer 信令
        void onReceiveOffer(String sdp, String fromUserId);
        // 接收 SDP Answer 信令
        void onReceiveAnswer(String sdp, String fromUserId);
        // 接收 ICE 候选信令
        void onReceiveIceCandidate(String candidate, String sdpMid, int sdpMLineIndex, String fromUserId);
        // 房间相关回调（如加入成功、其他用户加入）
        void onRoomEvent(String eventType, String roomId, String userId);
        // 接收房间内现有用户列表
        void onExistingUsers(String roomId, String[] userIds);
    }

    private final SignalingCallback callback;
    private final ScheduledExecutorService reconnectExecutor; // 断线重连线程池
    private boolean isReconnecting = false; // 重连状态标记（避免重复重连）
    private String currentRoomId; // 当前房间 ID
    private String currentUserId; // 当前用户 ID

    // 初始化信令客户端
    public WebRtcSignalingClient(String signalingServerUrl, String userId, SignalingCallback callback) throws URISyntaxException {
        super(new URI(signalingServerUrl), new Draft_6455()); // 指定 WebSocket 标准协议
        this.currentUserId = userId;
        this.callback = callback;
        this.reconnectExecutor = Executors.newSingleThreadScheduledExecutor();
        // 配置连接参数（可选，根据项目需求调整）
        // 注意：Java-WebSocket库不支持以下方法，需要删除
        // setConnectionTimeout(10000); // 连接超时 10s
        // setReadTimeout(30000); // 读取超时 30s
    }

    // -------------------------- 1. 连接管理（连接、重连、断开）--------------------------
    // 启动连接（主线程外调用，避免阻塞 UI）
    public void connectAsync() {
        if (!isOpen() && !isConnecting()) {
            new Thread(() -> {
                try {
                    connect();
                } catch (Exception e) {
                    callback.onConnectFailure("连接失败: " + e.getMessage());
                }
            }).start();
        }
    }
    
    // 辅助方法：检查是否正在连接
    private boolean isConnecting() {
        // 在Java-WebSocket库中，没有直接的isConnecting方法
        // 我们通过状态判断：不是OPEN、不是CLOSED、不是CLOSING就是CONNECTING
        return !isOpen() && !isClosed() && !isClosing();
    }

    // 断线重连（核心：保障网络波动时信令不中断）
    private void startReconnect() {
        if (isReconnecting || isOpen()) return;
        isReconnecting = true;
        // 3s 后开始重连，每 5s 重试一次，直到连接成功
        reconnectExecutor.scheduleAtFixedRate(() -> {
            if (!isOpen() && !isConnecting()) {
                try {
                    connect();
                } catch (Exception e) {
                    callback.onConnectFailure("重连失败: " + e.getMessage());
                }
            } else {
                isReconnecting = false;
                reconnectExecutor.shutdown(); // 重连成功，关闭线程池
            }
        }, 3, 5, TimeUnit.SECONDS);
    }

    // 主动断开连接（如退出通话、退出 App 时）
    public void disconnectAsync() {
        isReconnecting = false;
        reconnectExecutor.shutdownNow(); // 停止重连
        if (isOpen()) {
            new Thread(() -> {
                try {
                    close();
                } catch (Exception e) {
                    callback.onConnectFailure("关闭连接失败: " + e.getMessage());
                }
            }).start();
        }
    }

    // -------------------------- 2. 房间控制信令（创建/加入/离开）--------------------------
    // 创建房间
    public void createRoom(String roomId) {
        if (!isOpen()) return;
        this.currentRoomId = roomId;
        JSONObject json = new JSONObject();
        try {
            json.put("type", "createRoom");
            json.put("roomId", roomId);
            json.put("userId", currentUserId);
            send(json.toString());
        } catch (Exception e) {
            callback.onConnectFailure("发送创建房间信令失败: " + e.getMessage());
        }
    }

    // 加入房间
    public void joinRoom(String roomId) {
        if (!isOpen()) return;
        this.currentRoomId = roomId;
        JSONObject json = new JSONObject();
        try {
            json.put("type", "joinRoom");
            json.put("roomId", roomId);
            json.put("userId", currentUserId);
            send(json.toString());
        } catch (Exception e) {
            callback.onConnectFailure("发送加入房间信令失败: " + e.getMessage());
        }
    }

    // 离开房间
    public void leaveRoom() {
        if (!isOpen() || currentRoomId == null) return;
        JSONObject json = new JSONObject();
        try {
            json.put("type", "leaveRoom");
            json.put("roomId", currentRoomId);
            json.put("userId", currentUserId);
            send(json.toString());
        } catch (Exception e) {
            callback.onConnectFailure("发送离开房间信令失败: " + e.getMessage());
        }
        currentRoomId = null;
    }

    // -------------------------- 3. WebRTC 核心信令（SDP/ICE 发送）--------------------------
    // 发送 SDP Offer 信令
    public void sendOffer(String sdp, String targetUserId) {
        try {
            sendSdpSignaling("offer", sdp, targetUserId);
        } catch (Exception e) {
            callback.onConnectFailure("发送 Offer 信令失败: " + e.getMessage());
        }
    }

    // 发送 SDP Answer 信令
    public void sendAnswer(String sdp, String targetUserId) {
        try {
            sendSdpSignaling("answer", sdp, targetUserId);
        } catch (Exception e) {
            callback.onConnectFailure("发送 Answer 信令失败: " + e.getMessage());
        }
    }

    // 发送 ICE 候选信令
    public void sendIceCandidate(String candidate, String sdpMid, int sdpMLineIndex, String targetUserId) {
        if (!isOpen() || currentRoomId == null) return;
        JSONObject json = new JSONObject();
        try {
            json.put("type", "iceCandidate");
            json.put("roomId", currentRoomId);
            json.put("from", currentUserId);
            json.put("to", targetUserId);
            json.put("candidate", candidate);
            json.put("sdpMid", sdpMid);
            json.put("sdpMLineIndex", sdpMLineIndex);
            send(json.toString());
        } catch (Exception e) {
            callback.onConnectFailure("发送 ICE 候选信令失败: " + e.getMessage());
        }
    }

    // 通用 SDP 发送方法（复用逻辑）
    private void sendSdpSignaling(String sdpType, String sdp, String targetUserId) throws Exception {
        if (!isOpen() || currentRoomId == null) return;
        JSONObject json = new JSONObject();
        json.put("type", sdpType); // "offer" 或 "answer"
        json.put("roomId", currentRoomId);
        json.put("from", currentUserId);
        json.put("to", targetUserId);
        json.put("sdp", sdp);
        send(json.toString());
    }

    // -------------------------- 4. Java-WebSocket 回调重写（信令接收/连接状态）--------------------------
    // 连接成功回调（WebSocket 握手完成）
    @Override
    public void onOpen(ServerHandshake handshakedata) {
        try {
            callback.onConnectSuccess();
            // 连接成功后，若之前有房间未退出，自动重新加入
            if (currentRoomId != null) {
                joinRoom(currentRoomId);
            }
        } catch (Exception e) {
            callback.onConnectFailure("连接成功回调处理失败: " + e.getMessage());
        }
    }

    // 接收信令回调（核心：解析 WebSocket 服务器推送的信令）
    @Override
    public void onMessage(String message) {
        try {
            JSONObject json = new JSONObject(message);
            String type = json.getString("type");
            switch (type) {
                case "offer":
                    // 接收对方的 SDP Offer
                    String offerSdp = json.getString("sdp");
                    String offerFrom = json.getString("from");
                    callback.onReceiveOffer(offerSdp, offerFrom);
                    break;
                case "answer":
                    // 接收对方的 SDP Answer
                    String answerSdp = json.getString("sdp");
                    String answerFrom = json.getString("from");
                    callback.onReceiveAnswer(answerSdp, answerFrom);
                    break;
                case "iceCandidate":
                    // 接收对方的 ICE 候选
                    String iceCandidate = json.getString("candidate");
                    String sdpMid = json.optString("sdpMid", "");
                    int sdpMLineIndex = json.optInt("sdpMLineIndex", -1);
                    String iceFrom = json.getString("from");
                    callback.onReceiveIceCandidate(iceCandidate, sdpMid, sdpMLineIndex, iceFrom);
                    break;
                // 房间事件（如加入成功、其他用户加入/离开）
                case "joined":
                case "userJoined":
                case "userLeft":
                    callback.onRoomEvent(type, json.getString("roomId"), json.getString("userId"));
                    break;
                case "existingUsers":
                    JSONArray usersArray = json.getJSONArray("users");
                    String[] userIds = new String[usersArray.length()];
                    for (int i = 0; i < usersArray.length(); i++) {
                        userIds[i] = usersArray.getString(i);
                    }
                    callback.onExistingUsers(json.getString("roomId"), userIds);
                    break;
                default:
                    // 其他自定义信令（如通话结束、异常通知）
                    break;
            }
        } catch (Exception e) {
            // 信令解析失败（如 JSON 格式错误）
            callback.onConnectFailure("信令解析失败：" + e.getMessage());
        }
    }

    // 连接关闭回调
    @Override
    public void onClose(int code, String reason, boolean remote) {
        try {
            callback.onDisconnect();
            // 远程断开（如服务器重启、网络中断），触发重连；本地主动断开（如 leaveRoom），不重连
            if (remote) {
                startReconnect();
            }
        } catch (Exception e) {
            callback.onConnectFailure("连接关闭回调处理失败: " + e.getMessage());
        }
    }

    // 连接失败回调
    @Override
    public void onError(Exception ex) {
        try {
            callback.onConnectFailure("连接失败：" + ex.getMessage());
            // 连接失败触发重连
            startReconnect();
        } catch (Exception e) {
            // 即使回调处理失败，也要确保重连机制启动
            startReconnect();
        }
    }
}