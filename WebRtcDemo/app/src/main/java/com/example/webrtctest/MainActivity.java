package com.example.webrtctest;

import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;

import androidx.activity.EdgeToEdge;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

import com.google.android.material.textfield.TextInputEditText;

import java.net.URISyntaxException;

public class MainActivity extends AppCompatActivity implements WebSocketClientWrapper.WebSocketListener {
    private static final String TAG = "MainActivity";
    private WebSocketClientWrapper webSocketClient;
    private TextInputEditText roomIdInput;
    private Button joinRoomButton;
    private TextView connectionStatus;

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

        initViews();
        initWebSocket();
    }

    private void initViews() {
        roomIdInput = findViewById(R.id.room_id_input);
        joinRoomButton = findViewById(R.id.join_room_button);
        connectionStatus = findViewById(R.id.connection_status);

        joinRoomButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                joinRoom();
            }
        });

        joinRoomButton.setEnabled(false); // 默认禁用，等WebSocket连接成功后再启用
    }

    private void initWebSocket() {
        try {
            // 注意：这里需要替换为实际的信令服务器地址
            webSocketClient = new WebSocketClientWrapper("ws://10.0.2.2:8080");
            webSocketClient.setWebSocketListener(this);
            webSocketClient.connect();
            connectionStatus.setText("正在连接信令服务器...");
        } catch (URISyntaxException e) {
            Log.e(TAG, "WebSocket URI syntax error", e);
            connectionStatus.setText("信令服务器地址错误");
        }
    }

    private void joinRoom() {
        String roomId = roomIdInput.getText().toString().trim();
        if (roomId.isEmpty()) {
            Toast.makeText(this, "请输入房间号", Toast.LENGTH_SHORT).show();
            return;
        }

        // 跳转到WebRtcActivity
        Intent intent = new Intent(MainActivity.this, WebRtcActivity.class);
        intent.putExtra("ROOM_ID", roomId);
        startActivity(intent);
    }

    @Override
    public void onConnected() {
        runOnUiThread(() -> {
            Log.d(TAG, "WebSocket connected");
            connectionStatus.setText("信令服务器连接成功");
            joinRoomButton.setEnabled(true);
            Toast.makeText(this, "信令服务器连接成功", Toast.LENGTH_SHORT).show();
        });
    }

    @Override
    public void onMessageReceived(String message) {
        Log.d(TAG, "Message received: " + message);
        // 处理收到的消息
    }

    @Override
    public void onDisconnected(String reason, boolean remote) {
        runOnUiThread(() -> {
            Log.d(TAG, "WebSocket disconnected: " + reason);
            connectionStatus.setText("信令服务器连接断开: " + reason);
            joinRoomButton.setEnabled(false);
        });
    }

    @Override
    public void onError(Exception error) {
        runOnUiThread(() -> {
            Log.e(TAG, "WebSocket error", error);
            connectionStatus.setText("信令服务器连接错误: " + error.getMessage());
            joinRoomButton.setEnabled(false);
        });
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (webSocketClient != null) {
            webSocketClient.close();
        }
    }
}