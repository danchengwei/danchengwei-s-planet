package com.example.webrtctest;

import android.util.Log;

import org.json.JSONException;
import org.json.JSONObject;

import java.net.URISyntaxException;

/**
 * WebRTC信令客户端
 * 负责管理WebSocket连接和处理WebRTC信令消息
 */
public class WebRtcSignalingClient implements WebSocketClientWrapper.WebSocketListener {
    private static final String TAG = "WebRtcSignalingClient";
    
    private WebSocketClientWrapper webSocketClient;
    private String userId;
    private SignalingCallback callback;
    private String currentRoomId;
    private boolean isConnected = false;
    
    public WebRtcSignalingClient(String serverUrl, String userId, SignalingCallback callback) throws URISyntaxException {
        this.userId = userId;
        this.callback = callback;
        this.webSocketClient = new WebSocketClientWrapper(serverUrl);
        this.webSocketClient.setWebSocketListener(this);
    }
    
    /**
     * 异步建立WebSocket连接
     */
    public void connectAsync() {
        if (!isConnected) {
            Log.d(TAG, "开始连接WebSocket服务器...");
            webSocketClient.connect();
        } else {
            Log.d(TAG, "WebSocket已经连接，无需重复连接");
        }
    }
    
    /**
     * 断开连接
     */
    public void disconnect() {
        if (webSocketClient != null) {
            Log.d(TAG, "主动断开WebSocket连接");
            webSocketClient.disconnect();
            isConnected = false;
        }
    }
    
    public void disconnectAsync() {
        disconnect(); // 直接调用disconnect方法实现异步断开连接
    }
    
    /**
     * 创建房间
     */
    public void createRoom(String roomId) {
        if (!isConnected) {
            Log.e(TAG, "无法创建房间: WebSocket未连接");
            if (callback != null) {
                callback.onConnectFailure("无法创建房间: WebSocket未连接");
            }
            return;
        }
        
        this.currentRoomId = roomId;
        Log.d(TAG, "创建房间: " + roomId);
        webSocketClient.createRoom(roomId);
    }
    
    /**
     * 加入房间
     */
    public void joinRoom(String roomId) {
        if (!isConnected) {
            Log.e(TAG, "无法加入房间: WebSocket未连接");
            Log.d(TAG, "当前连接状态: isConnected=" + isConnected);
            Log.d(TAG, "WebSocket客户端状态: " + (webSocketClient != null ? "已创建" : "未创建"));
            if (webSocketClient != null) {
                Log.d(TAG, "WebSocket是否打开: " + webSocketClient.isOpen());
            }
            if (callback != null) {
                callback.onConnectFailure("无法加入房间: WebSocket未连接");
            }
            return;
        }
        
        this.currentRoomId = roomId;
        Log.d(TAG, "加入房间: " + roomId + ", 用户ID: " + userId);
        webSocketClient.joinRoom(roomId, userId);
    }
    
    /**
     * 离开房间
     */
    public void leaveRoom() {
        if (currentRoomId != null && isConnected) {
            Log.d(TAG, "离开房间: " + currentRoomId);
            // 这里可以发送离开房间的消息，但当前WebSocketClientWrapper没有实现这个方法
            // 在实际场景中应该添加此功能
            currentRoomId = null;
        }
    }
    
    /**
     * 发送Offer消息
     */
    public void sendOffer(String sdp, String targetUserId) {
        if (!isConnected) {
            Log.e(TAG, "无法发送Offer: WebSocket未连接");
            return;
        }
        
        try {
            JSONObject message = new JSONObject();
            message.put("type", "offer");
            message.put("targetUserId", targetUserId);
            message.put("sdp", sdp);
            webSocketClient.send(message.toString());
            Log.d(TAG, "已发送Offer给用户: " + targetUserId);
        } catch (JSONException e) {
            Log.e(TAG, "构建Offer消息失败", e);
        }
    }
    
    /**
     * 发送Answer消息
     */
    public void sendAnswer(String sdp, String targetUserId) {
        if (!isConnected) {
            Log.e(TAG, "无法发送Answer: WebSocket未连接");
            return;
        }
        
        try {
            JSONObject message = new JSONObject();
            message.put("type", "answer");
            message.put("targetUserId", targetUserId);
            message.put("sdp", sdp);
            webSocketClient.send(message.toString());
            Log.d(TAG, "已发送Answer给用户: " + targetUserId);
        } catch (JSONException e) {
            Log.e(TAG, "构建Answer消息失败", e);
        }
    }
    
    /**
     * 发送ICE候选
     */
    public void sendIceCandidate(String candidate, String sdpMid, int sdpMLineIndex, String targetUserId) {
        if (!isConnected) {
            Log.e(TAG, "无法发送ICE候选: WebSocket未连接");
            return;
        }
        
        try {
            JSONObject message = new JSONObject();
            message.put("type", "iceCandidate");
            message.put("targetUserId", targetUserId);
            message.put("candidate", candidate);
            message.put("sdpMid", sdpMid);
            message.put("sdpMLineIndex", sdpMLineIndex);
            webSocketClient.send(message.toString());
            Log.d(TAG, "已发送ICE候选给用户: " + targetUserId);
        } catch (JSONException e) {
            Log.e(TAG, "构建ICE候选消息失败", e);
        }
    }
    
    /**
     * 获取房间信息
     */
    public void getRoomInfo() {
        if (!isConnected) {
            Log.e(TAG, "无法获取房间信息: WebSocket未连接");
            return;
        }
        
        webSocketClient.getRoomInfo();
    }
    
    @Override
    public void onConnected() {
        Log.d(TAG, "WebSocket连接成功");
        isConnected = true;
        if (callback != null) {
            callback.onConnectSuccess();
        }
    }
    
    @Override
    public void onMessageReceived(String message) {
        Log.d(TAG, "收到信令消息: " + message);
        try {
            JSONObject json = new JSONObject(message);
            String type = json.getString("type");
            
            switch (type) {
                case "joined":
                    // 加入房间成功
                    Log.d(TAG, "成功加入房间");
                    if (callback != null) {
                        callback.onConnectSuccess();
                    }
                    break;
                case "existingUsers":
                    // 收到房间内现有用户列表
                    if (json.has("users")) {
                        org.json.JSONArray usersArray = json.getJSONArray("users");
                        String[] userIds = new String[usersArray.length()];
                        for (int i = 0; i < usersArray.length(); i++) {
                            userIds[i] = usersArray.getString(i);
                        }
                        Log.d(TAG, "收到现有用户列表，共" + userIds.length + "个用户");
                        if (callback != null) {
                            callback.onExistingUsers(json.getString("roomId"), userIds);
                        }
                    }
                    break;
                case "userJoined":
                    // 有新用户加入房间
                    Log.d(TAG, "用户加入房间: " + json.getString("userId"));
                    if (callback != null) {
                        callback.onRoomEvent("userJoined", json.getString("roomId"), json.getString("userId"));
                    }
                    break;
                case "userLeft":
                    // 有用户离开房间
                    Log.d(TAG, "用户离开房间: " + json.getString("userId"));
                    if (callback != null) {
                        callback.onRoomEvent("userLeft", json.getString("roomId"), json.getString("userId"));
                    }
                    break;
                case "offer":
                    // 收到Offer
                    Log.d(TAG, "收到Offer，来自用户: " + json.getString("from"));
                    if (callback != null) {
                        callback.onReceiveOffer(json.getString("sdp"), json.getString("from"));
                    }
                    break;
                case "answer":
                    // 收到Answer
                    Log.d(TAG, "收到Answer，来自用户: " + json.getString("from"));
                    if (callback != null) {
                        callback.onReceiveAnswer(json.getString("sdp"), json.getString("from"));
                    }
                    break;
                case "iceCandidate":
                    // 收到ICE候选
                    Log.d(TAG, "收到ICE候选，来自用户: " + json.getString("from"));
                    if (callback != null) {
                        callback.onReceiveIceCandidate(
                                json.getString("candidate"),
                                json.getString("sdpMid"),
                                json.getInt("sdpMLineIndex"),
                                json.getString("from")
                        );
                    }
                    break;
                case "error":
                    // 错误消息
                    String errorMsg = json.optString("message", "未知错误");
                    Log.e(TAG, "服务器错误: " + errorMsg);
                    if (callback != null) {
                        callback.onConnectFailure(errorMsg);
                    }
                    break;
                default:
                    Log.d(TAG, "未知消息类型: " + type);
            }
        } catch (JSONException e) {
            Log.e(TAG, "解析信令消息失败: " + message, e);
            if (callback != null) {
                callback.onConnectFailure("解析信令消息失败: " + e.getMessage());
            }
        }
    }
    
    @Override
    public void onDisconnected(String reason, boolean remote) {
        Log.d(TAG, "WebSocket连接断开. 原因: " + reason + ", 远程断开: " + remote);
        isConnected = false;
        if (callback != null) {
            callback.onDisconnect();
        }
    }
    
    @Override
    public void onError(Exception error) {
        Log.e(TAG, "WebSocket错误: " + error.getMessage(), error);
        isConnected = false;
        if (callback != null) {
            callback.onConnectFailure("WebSocket错误: " + error.getMessage());
        }
    }
    
    /**
     * 检查连接状态
     */
    public boolean isConnected() {
        return isConnected && webSocketClient != null && webSocketClient.isOpen();
    }
    
    /**
     * 信令回调接口
     */
    public interface SignalingCallback {
        void onConnectSuccess();
        void onConnectFailure(String errorMsg);
        void onDisconnect();
        void onReceiveOffer(String sdp, String fromUserId);
        void onReceiveAnswer(String sdp, String fromUserId);
        void onReceiveIceCandidate(String candidate, String sdpMid, int sdpMLineIndex, String fromUserId);
        void onRoomEvent(String eventType, String roomId, String userId);
        void onExistingUsers(String roomId, String[] userIds);
    }
}