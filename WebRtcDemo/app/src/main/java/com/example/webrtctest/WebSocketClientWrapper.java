package com.example.webrtctest;

import android.util.Log;

import org.java_websocket.client.WebSocketClient;
import org.java_websocket.handshake.ServerHandshake;

import java.net.URI;
import java.net.URISyntaxException;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

public class WebSocketClientWrapper extends WebSocketClient {
    private static final String TAG = "WebSocketClient";
    private WebSocketListener mListener;
    private ScheduledExecutorService reconnectExecutor;
    private boolean isReconnecting = false;

    public WebSocketClientWrapper(String serverUri) throws URISyntaxException {
        super(new URI(serverUri));
        reconnectExecutor = Executors.newSingleThreadScheduledExecutor();
    }

    @Override
    public void onOpen(ServerHandshake handshakedata) {
        Log.d(TAG, "WebSocket connection opened");
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
        Log.d(TAG, "WebSocket connection closed: " + reason);
        if (mListener != null) {
            mListener.onDisconnected(reason, remote);
        }
        
        // 如果是远程断开连接，尝试重连
        if (remote && !isReconnecting) {
            startReconnect();
        }
    }

    @Override
    public void onError(Exception ex) {
        Log.e(TAG, "WebSocket error: " + ex.getMessage());
        if (mListener != null) {
            mListener.onError(ex);
        }
        
        // 发生错误时也尝试重连
        if (!isReconnecting) {
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
        }
    }

    // 添加加入房间的方法
    public void joinRoom(String roomId) {
        if (isOpen()) {
            String message = "{\"type\":\"joinRoom\",\"roomId\":\"" + roomId + "\"}";
            send(message);
        }
    }

    private void startReconnect() {
        if (isReconnecting || isOpen()) return;
        isReconnecting = true;
        
        // 3秒后开始重连，每隔5秒重试一次
        reconnectExecutor.scheduleAtFixedRate(() -> {
            if (!isOpen() && isReconnecting) {
                try {
                    reconnect();
                } catch (Exception e) {
                    Log.e(TAG, "Reconnect failed: " + e.getMessage());
                }
            } else {
                // 连接成功或其他原因停止重连
                isReconnecting = false;
            }
        }, 3, 5, TimeUnit.SECONDS);
    }

    public interface WebSocketListener {
        void onConnected();
        void onMessageReceived(String message);
        void onDisconnected(String reason, boolean remote);
        void onError(Exception error);
    }
}