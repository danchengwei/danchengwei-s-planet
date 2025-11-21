package com.example.webrtctest;

import android.os.Bundle;
import android.util.Log;

import androidx.activity.EdgeToEdge;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

import java.net.URISyntaxException;

public class MainActivity extends AppCompatActivity implements WebSocketClientWrapper.WebSocketListener {
    private static final String TAG = "MainActivity";
    private WebSocketClientWrapper webSocketClient;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        EdgeToEdge.enable(this);
        setContentView(R.layout.activity_main);
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.main), (v, insets) -> {
            Insets systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars());
            v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom);
            return insets;
        });

        initWebSocket();
    }

    private void initWebSocket() {
        try {
            // 注意：这里需要替换为实际的信令服务器地址
            webSocketClient = new WebSocketClientWrapper("ws://10.0.2.2:8080");
            webSocketClient.setWebSocketListener(this);
            webSocketClient.connect();
        } catch (URISyntaxException e) {
            Log.e(TAG, "WebSocket URI syntax error", e);
        }
    }

    @Override
    public void onConnected() {
        Log.d(TAG, "WebSocket connected");
        // 可以在这里发送初始化消息
        // webSocketClient.send("{\"type\": \"register\", \"userId\": \"user123\"}");
    }

    @Override
    public void onMessageReceived(String message) {
        Log.d(TAG, "Message received: " + message);
        // 处理收到的消息
    }

    @Override
    public void onDisconnected(String reason, boolean remote) {
        Log.d(TAG, "WebSocket disconnected: " + reason);
    }

    @Override
    public void onError(Exception error) {
        Log.e(TAG, "WebSocket error", error);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (webSocketClient != null) {
            webSocketClient.close();
        }
    }
}