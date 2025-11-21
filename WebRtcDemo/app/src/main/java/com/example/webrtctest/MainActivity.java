package com.example.webrtctest;

import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;

import androidx.activity.EdgeToEdge;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

import com.google.android.material.textfield.TextInputEditText;

import java.net.URISyntaxException;
import java.util.UUID;

public class MainActivity extends AppCompatActivity implements WebSocketClientWrapper.WebSocketListener {
    private static final String TAG = "MainActivity";
    private static final int PERMISSION_REQUEST_CODE = 1001;
    
    private WebSocketClientWrapper webSocketClient;
    private TextInputEditText roomIdInput;
    private Button createRoomButton;
    private Button joinRoomButton;
    private Button checkDeviceButton;
    private TextView connectionStatus;
    private TextView deviceInfoText;

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
        checkAndRequestPermissions(); // 应用启动时自动请求权限
        initWebSocket();
        updateDeviceInfo(); // 初始化时就显示设备信息
    }

    private void initViews() {
        roomIdInput = findViewById(R.id.room_id_input);
        createRoomButton = findViewById(R.id.create_room_button);
        joinRoomButton = findViewById(R.id.join_room_button);
        checkDeviceButton = findViewById(R.id.check_device_button);
        connectionStatus = findViewById(R.id.connection_status);
        deviceInfoText = findViewById(R.id.device_info_text);

        createRoomButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                createRoom();
            }
        });

        joinRoomButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                joinRoom();
            }
        });

        checkDeviceButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                // 跳转到设备信息页面
                Intent intent = new Intent(MainActivity.this, DeviceActivity.class);
                startActivity(intent);
            }
        });

        joinRoomButton.setEnabled(false); // 默认禁用，等WebSocket连接成功后再启用
        createRoomButton.setEnabled(false); // 默认禁用，等WebSocket连接成功后再启用
    }

    private void initWebSocket() {
        try {
            // 使用配置类获取合适的服务器地址
            String serverUrl = NetworkConfig.getSuitableServerUrl();
            webSocketClient = new WebSocketClientWrapper(serverUrl);
            webSocketClient.setWebSocketListener(this);
            webSocketClient.connect();
            String connectingInfo = "正在连接信令服务器...\n" + 
                                  NetworkConfig.getSignalingServerHost() + ":" + 
                                  NetworkConfig.getSignalingServerPort();
            connectionStatus.setText(connectingInfo);
        } catch (URISyntaxException e) {
            Log.e(TAG, "WebSocket URI syntax error", e);
            String errorInfo = "信令服务器地址错误\n" + 
                             NetworkConfig.getSignalingServerHost() + ":" + 
                             NetworkConfig.getSignalingServerPort();
            connectionStatus.setText(errorInfo);
        }
    }

    private void createRoom() {
        String roomId = roomIdInput.getText().toString().trim();
        if (roomId.isEmpty()) {
            Toast.makeText(this, "请输入房间号", Toast.LENGTH_SHORT).show();
            return;
        }
        
        // 直接加入用户输入的房间号
        joinRoom();
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

    // 检查并请求权限
    private void checkAndRequestPermissions() {
        String[] permissions = {
                android.Manifest.permission.CAMERA,
                android.Manifest.permission.RECORD_AUDIO,
                android.Manifest.permission.MODIFY_AUDIO_SETTINGS
        };

        boolean allPermissionsGranted = true;
        for (String permission : permissions) {
            if (ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED) {
                allPermissionsGranted = false;
                break;
            }
        }

        if (!allPermissionsGranted) {
            ActivityCompat.requestPermissions(this, permissions, PERMISSION_REQUEST_CODE);
        }
    }

    // 更新设备信息显示
    private void updateDeviceInfo() {
        String deviceInfo = "设备信息: \n" +
                "- 设备名称: " + Build.MANUFACTURER + " " + Build.MODEL + "\n" +
                "- Android版本: " + Build.VERSION.RELEASE + " (API " + Build.VERSION.SDK_INT + ")\n" +
                "- 设备制造商: " + Build.MANUFACTURER;

        deviceInfoText.setText(deviceInfo);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == PERMISSION_REQUEST_CODE) {
            boolean allPermissionsGranted = true;
            for (int result : grantResults) {
                if (result != PackageManager.PERMISSION_GRANTED) {
                    allPermissionsGranted = false;
                    break;
                }
            }

            if (allPermissionsGranted) {
                Toast.makeText(this, "权限获取成功", Toast.LENGTH_SHORT).show();
            } else {
                Toast.makeText(this, "部分权限被拒绝，可能影响功能使用", Toast.LENGTH_LONG).show();
            }
        }
    }

    @Override
    public void onConnected() {
        runOnUiThread(() -> {
            Log.d(TAG, "WebSocket connected");
            // 显示服务器IP地址和端口号
            String serverInfo = "信令服务器连接成功\n" + 
                              NetworkConfig.getSignalingServerHost() + ":" + 
                              NetworkConfig.getSignalingServerPort();
            connectionStatus.setText(serverInfo);
            joinRoomButton.setEnabled(true);
            createRoomButton.setEnabled(true);
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
            String serverInfo = "信令服务器连接断开\n" + 
                              NetworkConfig.getSignalingServerHost() + ":" + 
                              NetworkConfig.getSignalingServerPort() + 
                              "\n原因: " + reason;
            connectionStatus.setText(serverInfo);
            joinRoomButton.setEnabled(false);
            createRoomButton.setEnabled(false);
        });
    }

    @Override
    public void onError(Exception error) {
        runOnUiThread(() -> {
            Log.e(TAG, "WebSocket error", error);
            String serverInfo = "信令服务器连接错误\n" + 
                              NetworkConfig.getSignalingServerHost() + ":" + 
                              NetworkConfig.getSignalingServerPort() + 
                              "\n错误: " + error.getMessage();
            connectionStatus.setText(serverInfo);
            joinRoomButton.setEnabled(false);
            createRoomButton.setEnabled(false);
        });
    }

    @Override
    protected void onResume() {
        super.onResume();
        // 每次恢复时更新设备信息
        updateDeviceInfo();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (webSocketClient != null) {
            webSocketClient.close();
        }
    }
}