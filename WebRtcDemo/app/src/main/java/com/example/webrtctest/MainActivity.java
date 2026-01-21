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
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

import com.google.android.material.textfield.TextInputEditText;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.net.URISyntaxException;
import java.util.UUID;

import com.example.webrtctest.WebRtcActivity;

public class MainActivity extends AppCompatActivity implements WebSocketClientWrapper.WebSocketListener {
    private static final String TAG = "MainActivity";
    private static final int PERMISSION_REQUEST_CODE = 1001;
    
    private WebSocketClientWrapper webSocketClient;
    private TextInputEditText roomIdInput;
    private Button createRoomButton;
    private Button joinRoomButton;
    private Button getRoomInfoButton; // 新增获取房间信息按钮
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
        getRoomInfoButton = findViewById(R.id.get_room_info_button); // 初始化新按钮
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

        // 新增获取房间信息按钮的点击事件
        getRoomInfoButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                getRoomInfo();
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
        getRoomInfoButton.setEnabled(false); // 默认禁用，等WebSocket连接成功后再启用
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
        
        // 发送创建房间请求，等待服务器响应后再跳转
        if (webSocketClient != null && webSocketClient.isOpen()) {
            webSocketClient.createRoom(roomId);
            // 不再立即跳转，而是等待服务器响应
            Toast.makeText(this, "正在创建房间: " + roomId, Toast.LENGTH_SHORT).show();
        } else {
            Toast.makeText(this, "信令服务器未连接，请稍后再试", Toast.LENGTH_SHORT).show();
        }
    }

    private void joinRoom() {
        String roomId = roomIdInput.getText().toString().trim();
        if (roomId.isEmpty()) {
            Toast.makeText(this, "请输入房间号", Toast.LENGTH_SHORT).show();
            return;
        }

        // 发送加入房间请求，等待服务器响应后再决定是否跳转
        if (webSocketClient != null && webSocketClient.isOpen()) {
            String userId = "android_" + System.currentTimeMillis();
            webSocketClient.joinRoom(roomId, userId);
            // 不再立即跳转，而是等待服务器响应
            Toast.makeText(this, "正在尝试加入房间: " + roomId, Toast.LENGTH_SHORT).show();
        } else {
            Toast.makeText(this, "信令服务器未连接，请稍后再试", Toast.LENGTH_SHORT).show();
        }
    }

    // 新增获取房间信息的方法
    private void getRoomInfo() {
        if (webSocketClient != null && webSocketClient.isOpen()) {
            webSocketClient.getRoomInfo();
        } else {
            Toast.makeText(this, "信令服务器未连接，请稍后再试", Toast.LENGTH_SHORT).show();
        }
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
            getRoomInfoButton.setEnabled(true); // 连接成功后启用按钮
            Toast.makeText(this, "信令服务器连接成功", Toast.LENGTH_SHORT).show();
        });
    }

    @Override
    public void onMessageReceived(String message) {
        Log.d(TAG, "Message received: " + message);
        // 处理收到的消息
        try {
            JSONObject json = new JSONObject(message);
            String type = json.getString("type");
            
            switch (type) {
                case "roomInfo":
                    handleRoomInfo(json);
                    break;
                case "roomCreated":
                    handleRoomCreated(json);
                    break;
                case "roomExists":  // 添加处理房间已存在的case
                    handleRoomExists(json);
                    break;
                case "joined":  // 添加处理成功加入房间的情况
                    handleRoomJoined(json);
                    break;
                case "error":
                    handleError(json);
                    break;
                default:
                    // 其他消息类型保持原有处理方式
                    break;
            }
        } catch (JSONException e) {
            Log.e(TAG, "JSON解析错误: " + e.getMessage());
        }
    }

    private void handleRoomInfo(JSONObject json) {
        try {
            JSONArray roomsArray = json.getJSONArray("rooms");
            StringBuilder info = new StringBuilder("当前房间信息:\n");
            
            if (roomsArray.length() == 0) {
                info.append("暂无活跃房间");
            } else {
                for (int i = 0; i < roomsArray.length(); i++) {
                    JSONObject room = roomsArray.getJSONObject(i);
                    String roomId = room.getString("roomId");
                    int userCount = room.getInt("userCount");
                    JSONArray users = room.getJSONArray("users");
                    info.append("房间: ").append(roomId)
                        .append(", 用户数: ").append(userCount);
                    
                    // 显示用户列表
                    if (users.length() > 0) {
                        info.append(", 用户列表: ");
                        for (int j = 0; j < users.length(); j++) {
                            if (j > 0) info.append(", ");
                            info.append(users.getString(j));
                        }
                    }
                    info.append("\n");
                }
            }
            
            runOnUiThread(() -> {
                AlertDialog.Builder builder = new AlertDialog.Builder(this);
                builder.setTitle("房间信息")
                       .setMessage(info.toString())
                       .setPositiveButton("确定", null)
                       .show();
            });
        } catch (JSONException e) {
            Log.e(TAG, "房间信息解析错误: " + e.getMessage());
        }
    }

    private void handleRoomCreated(JSONObject json) {
        try {
            String roomId = json.getString("roomId");
            String msg = json.getString("message");
            
            runOnUiThread(() -> {
                Toast.makeText(this, msg, Toast.LENGTH_SHORT).show();
                // 创建房间成功后自动跳转到WebRtcActivity
                Intent intent = new Intent(MainActivity.this, WebRtcActivity.class);
                intent.putExtra("ROOM_ID", roomId);
                startActivity(intent);
            });
        } catch (JSONException e) {
            Log.e(TAG, "房间创建响应解析错误: " + e.getMessage());
        }
    }

    // 添加处理房间已存在的方法
    private void handleRoomExists(JSONObject json) {
        try {
            String roomId = json.getString("roomId");
            String msg = json.getString("message");
            
            runOnUiThread(() -> {
                Toast.makeText(this, msg, Toast.LENGTH_SHORT).show();
                // 房间已存在，直接跳转到WebRtcActivity
                Intent intent = new Intent(MainActivity.this, WebRtcActivity.class);
                intent.putExtra("ROOM_ID", roomId);
                startActivity(intent);
            });
        } catch (JSONException e) {
            Log.e(TAG, "房间存在响应解析错误: " + e.getMessage());
        }
    }

    // 添加处理成功加入房间的方法
    private void handleRoomJoined(JSONObject json) {
        try {
            String roomId = json.getString("roomId");
            String userId = json.getString("userId");
            
            runOnUiThread(() -> {
                Toast.makeText(this, "成功加入房间: " + roomId, Toast.LENGTH_SHORT).show();
                // 成功加入房间后跳转到WebRtcActivity
                Intent intent = new Intent(MainActivity.this, WebRtcActivity.class);
                intent.putExtra("ROOM_ID", roomId);
                startActivity(intent);
            });
        } catch (JSONException e) {
            Log.e(TAG, "房间加入响应解析错误: " + e.getMessage());
        }
    }

    private void handleError(JSONObject json) {
        try {
            String errorMsg = json.getString("message");
            runOnUiThread(() -> {
                Toast.makeText(this, "错误: " + errorMsg, Toast.LENGTH_LONG).show();
            });
        } catch (JSONException e) {
            Log.e(TAG, "错误信息解析错误: " + e.getMessage());
        }
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