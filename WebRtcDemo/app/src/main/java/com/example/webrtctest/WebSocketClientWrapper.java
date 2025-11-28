package com.example.webrtctest;

import android.util.Log;

import org.java_websocket.client.WebSocketClient;
import org.java_websocket.handshake.ServerHandshake;
import org.json.JSONException;
import org.json.JSONObject;

import java.net.URI;
import java.net.URISyntaxException;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

public class WebSocketClientWrapper extends WebSocketClient {
    // 允许直接调用父类的send方法
    @Override
    public void send(String text) {
        super.send(text);
    }
    private static final String TAG = "WebSocketClient";
    private WebSocketListener mListener;
    private ScheduledExecutorService reconnectExecutor;
    private boolean isReconnecting = false;
    private int reconnectAttempts = 0;
    private static final int MAX_RECONNECT_ATTEMPTS = 10;

    public WebSocketClientWrapper(String serverUri) throws URISyntaxException {
        super(new URI(serverUri));
        reconnectExecutor = Executors.newSingleThreadScheduledExecutor();
    }

    @Override
    public void onOpen(ServerHandshake handshakedata) {
        Log.d(TAG, "WebSocket connection opened");
        reconnectAttempts = 0; // 重置重连计数器
        isReconnecting = false; // 重置重连标志
        if (mListener != null) {
            mListener.onConnected();
        }
    }

    @Override
    public void onMessage(String message) {
        Log.d(TAG, "Received message: " + message);
        if (mListener != null) {
            mListener.onMessageReceived(message);
        }
    }

    @Override
    public void onClose(int code, String reason, boolean remote) {
        Log.d(TAG, "WebSocket connection closed. Code: " + code + ", Reason: " + reason + ", Remote: " + remote);
        if (mListener != null) {
            mListener.onDisconnected(reason, remote);
        }
        
        // 如果不是主动关闭且未达到最大重连次数，尝试重连
        if (code != 1000 && reconnectAttempts < MAX_RECONNECT_ATTEMPTS && !isReconnecting) {
            startReconnect();
        }
    }

    @Override
    public void onError(Exception ex) {
        Log.e(TAG, "WebSocket error: " + ex.getMessage(), ex);
        if (mListener != null) {
            mListener.onError(ex);
        }
        
        // 发生错误时也尝试重连
        if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS && !isReconnecting) {
            startReconnect();
        }
    }

    public void setWebSocketListener(WebSocketListener listener) {
        mListener = listener;
    }

    // 添加创建房间的方法
    public void createRoom(String roomId) {
        if (isOpen()) {
            String message = "{\"type\":\"createRoom\",\"roomId\":\"" + roomId + "\"}";
            send(message);
        } else {
            Log.e(TAG, "Cannot create room: WebSocket is not connected");
        }
    }

    // 添加加入房间的方法（不自动生成userId）
    public void joinRoom(String roomId, String userId) {
        if (isOpen()) {
            String message = "{\"type\":\"joinRoom\",\"roomId\":\"" + roomId + "\",\"userId\":\"" + userId + "\"}";
            send(message);
        } else {
            Log.e(TAG, "Cannot join room: WebSocket is not connected");
        }
    }

    // 添加获取房间信息的方法
    public void getRoomInfo() {
        if (isOpen()) {
            String message = "{\"type\":\"getRoomInfo\"}";
            send(message);
        } else {
            Log.e(TAG, "Cannot get room info: WebSocket is not connected");
        }
    }

    private void startReconnect() {
        if (isReconnecting || isOpen()) return;
        isReconnecting = true;
        reconnectAttempts++;
        
        Log.d(TAG, "Starting reconnect attempt " + reconnectAttempts + "/" + MAX_RECONNECT_ATTEMPTS);
        
        // 指数退避策略：初始延迟1秒，每次重试延迟翻倍，最大30秒
        long delayMs = Math.min(1000 * (1L << (reconnectAttempts - 1)), 30000);
        
        reconnectExecutor.schedule(() -> {
            if (!isOpen() && isReconnecting) {
                try {
                    Log.d(TAG, "Attempting to reconnect...");
                    reconnect();
                } catch (Exception e) {
                    Log.e(TAG, "Reconnect failed: " + e.getMessage(), e);
                    // 如果重连失败，继续尝试
                    if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
                        startReconnect();
                    } else {
                        Log.e(TAG, "Max reconnect attempts reached");
                        isReconnecting = false;
                    }
                }
            } else {
                // 连接成功或其他原因停止重连
                isReconnecting = false;
            }
        }, delayMs, TimeUnit.MILLISECONDS);
    }

    // 添加主动断开连接的方法，避免触发重连
    public void disconnect() {
        isReconnecting = false;
        reconnectAttempts = MAX_RECONNECT_ATTEMPTS; // 防止自动重连
        close();
    }

    public interface WebSocketListener {
        void onConnected();
        void onMessageReceived(String message);
        void onDisconnected(String reason, boolean remote);
        void onError(Exception error);
    }
}