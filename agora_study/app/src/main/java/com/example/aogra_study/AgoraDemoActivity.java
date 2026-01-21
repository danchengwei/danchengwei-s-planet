package com.example.aogra_study;

import android.animation.ObjectAnimator;
import android.os.Bundle;
import android.util.Log;
import android.view.SurfaceView;
import android.view.TextureView;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.widget.TextView;
import android.widget.Toast;
import android.widget.LinearLayout;
import android.Manifest;
import android.content.pm.PackageManager;
import android.app.AlertDialog;
import android.graphics.drawable.Drawable;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import java.util.List;




/**
 * Agora功能演示Activity
 * 展示如何使用Agora服务进行音视频通话、聊天等
 */
public class AgoraDemoActivity extends AppCompatActivity {
    private static final String TAG = "AgoraDemoActivity";
    
    private AgoraServiceManager serviceManager;
    
    // UI组件
    private EditText etChannelName;
    private Button btnJoinChannel;
    private ImageButton btnLeaveChannel;
    private ImageButton btnToggleAudio;
    private ImageButton btnToggleVideo;
    private Button btnSendChat;
    private EditText etChatMessage;
    private FrameLayout flLocalVideo;
    private FrameLayout flRemoteVideo;
    private ImageButton btnToggleChat;
    private ImageButton btnCloseChat;
    private LinearLayout chatPanel;
    private LinearLayout llConnectPrompt;
    private RecyclerView rvChatMessages;
    private ChatMessageAdapter chatMessageAdapter;
    
    // 状态信息显示
    private TextView tvConnectionStatus;
    private TextView tvAudioLabel;
    private TextView tvVideoLabel;
    private TextView tvChatLabel;
    private TextView tvChannelNumber;
    private TextView tvUserCount;
    
    // 视频视图
    private SurfaceView localSurfaceView;
    private SurfaceView remoteSurfaceView;
    private int currentRemoteUid = 0;
    private boolean audioMuted = true;
    private boolean videoMuted = true;

    private static final int PERMISSION_REQ_ID_RECORD_AUDIO = 22;
    private static final int PERMISSION_REQ_ID_CAMERA = 23;
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        // 先设置布局，确保UI能显示
        setContentView(R.layout.activity_agora_demo);
        
        // 初始化UI组件
        initViews();
        
        // 检查权限并初始化Agora
        if (hasPermission(Manifest.permission.RECORD_AUDIO) && hasPermission(Manifest.permission.CAMERA)) {
            // 已经有权限，直接初始化
            initializeAgora();
        } else {
            // 检查是否需要显示权限请求对话框
            if (shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO) || 
                shouldShowRequestPermissionRationale(Manifest.permission.CAMERA)) {
                // 用户之前拒绝过权限，显示说明对话框
                showPermissionRationaleDialog();
            } else {
                // 首次请求权限
                requestPermissions();
            }
            // 即使没有权限，也显示UI，只是功能受限
            updateConnectionStatus("等待权限授权...");
        }

        Log.d(TAG, "AgoraDemoActivity初始化完成");
    }

    private void initializeAgora() {
        // 初始化Agora服务管理器
        try {
            serviceManager = new AgoraServiceManager(this);
            serviceManager.initialize();
            
            // 设置默认静音状态
            serviceManager.getDeviceManager().muteLocalAudio(true);
            serviceManager.getDeviceManager().muteLocalVideo(true);
            
            // 更新UI图标显示默认静音状态
            btnToggleAudio.setImageResource(R.drawable.ic_mic_off);
            tvAudioLabel.setTextColor(0xFFFF3B30);
            btnToggleVideo.setImageResource(R.drawable.ic_videocam_off);
            tvVideoLabel.setTextColor(0xFFFF3B30);
            
            updateConnectionStatus("Agora服务已初始化");
            
            // 设置房间事件监听器
            Log.d("Agora", "=== 设置房间事件监听器 ===");
            serviceManager.getRoomManager().setOnRoomEventListener(new RoomManager.OnRoomEventListener() {
                @Override
                public void onUserJoined(String userId) {
                    Log.d("Agora", "=== UI 收到用户加入事件 ===");
                    Log.d("Agora", "用户ID: " + userId);
                    runOnUiThread(() -> {
                        Toast.makeText(AgoraDemoActivity.this, getString(R.string.user_joined_msg, userId), Toast.LENGTH_SHORT).show();
                        updateUserCount();
                        
                        // 自动设置远程视频视图
                        try {
                            int uid = Integer.parseInt(userId);
                            if (remoteSurfaceView == null) {
                                setupRemoteVideoView(uid);
                            }
                        } catch (NumberFormatException e) {
                            Log.e("Agora", "解析用户ID失败", e);
                        }
                    });
                    Log.d("Agora", "=== UI 处理用户加入事件完成 ===");
                }
                
                @Override
                public void onUserLeft(String userId) {
                    Log.d("Agora", "=== UI 收到用户离开事件 ===");
                    Log.d("Agora", "用户ID: " + userId);
                    runOnUiThread(() -> {
                        Toast.makeText(AgoraDemoActivity.this, getString(R.string.user_left_msg, userId), Toast.LENGTH_SHORT).show();
                        
                        // 清除对应的远程视频视图
                        flRemoteVideo.removeAllViews();
                        remoteSurfaceView = null;
                        currentRemoteUid = 0;
                        updateUserCount();
                    });
                    Log.d("Agora", "=== UI 处理用户离开事件完成 ===");
                }
                
                @Override
                public void onMicApplyReceived(String userId) {
                    Log.d("Agora", "收到连麦申请: " + userId);
                    runOnUiThread(() -> Toast.makeText(AgoraDemoActivity.this, getString(R.string.mic_apply_msg, userId), Toast.LENGTH_LONG).show());
                }
                
                @Override
                public void onChatMessageReceived(String userId, String message) {
                    Log.d("Agora", "收到聊天消息: " + userId + ": " + message);
                    runOnUiThread(() -> {
                        // 添加消息到聊天列表
                        ChatMessage chatMessage = new ChatMessage(userId, message, false);
                        chatMessageAdapter.addMessage(chatMessage);
                        rvChatMessages.scrollToPosition(chatMessageAdapter.getItemCount() - 1);
                        
                        // 显示Toast提示
                        Toast.makeText(AgoraDemoActivity.this, getString(R.string.message_received, userId + ": " + message), Toast.LENGTH_SHORT).show();
                    });
                }
            });
            Log.d("Agora", "=== 房间事件监听器设置完成 ===");
            
            // 设置设备状态监听器
            serviceManager.getDeviceManager().setDeviceStatusListener(new DeviceManager.DeviceStatusListener() {
                @Override
                public void onAudioDeviceChanged(String deviceId, String deviceName) {
                    Log.d(TAG, "音频设备改变: " + deviceName);
                }
                
                @Override
                public void onVideoDeviceChanged(String deviceId, String deviceName) {
                    Log.d(TAG, "视频设备改变: " + deviceName);
                }
                
                @Override
                public void onLocalVideoStateChanged(boolean enabled) {
                    Log.d(TAG, "本地视频状态改变: " + enabled);
                }
                
                @Override
                public void onRemoteVideoStateChanged(int uid, boolean enabled) {
                    Log.d(TAG, "远程视频状态改变，用户ID " + uid + ": " + enabled);
                    if (enabled && remoteSurfaceView == null) {
                        // 当远程视频流可用且我们还没有设置视图时，创建并设置远程视频视图
                        runOnUiThread(() -> setupRemoteVideoView(uid));
                    }
                }
                
                @Override
                public void onAudioQualityChanged(int uid, int quality) {
                    Log.d(TAG, "用户ID " + uid + " 音频质量改变，质量: " + quality);
                }
            });
            
            // 设置RoomManager的设备状态监听器
            serviceManager.getRoomManager().setDeviceStatusListener(new RoomManager.DeviceStatusListener() {
                @Override
                public void onAudioDeviceChanged(String deviceId, String deviceName) {
                    Log.d(TAG, "音频设备改变: " + deviceName);
                }
                
                @Override
                public void onVideoDeviceChanged(String deviceId, String deviceName) {
                    Log.d(TAG, "视频设备改变: " + deviceName);
                }
                
                @Override
                public void onLocalVideoStateChanged(boolean enabled) {
                    Log.d(TAG, "本地视频状态改变: " + enabled);
                }
                
                @Override
                public void onRemoteVideoStateChanged(int uid, boolean enabled) {
                    Log.d(TAG, "远程视频状态改变，用户ID " + uid + ": " + enabled);
                    if (enabled && remoteSurfaceView == null) {
                        // 当远程视频流可用且我们还没有设置视图时，创建并设置远程视频视图
                        runOnUiThread(() -> setupRemoteVideoView(uid));
                    }
                }
                
                @Override
                public void onAudioQualityChanged(int uid, int quality) {
                    Log.d(TAG, "用户ID " + uid + " 音频质量改变，质量: " + quality);
                }
            });
            
            // 初始化成功提示
            Log.d(TAG, "Agora服务管理器初始化成功");
            updateConnectionStatus("Agora服务已初始化");
            
        } catch (Exception e) {
            Log.e(TAG, "初始化Agora服务管理器失败", e);
            Toast.makeText(this, getString(R.string.init_failed, e.getMessage()), Toast.LENGTH_LONG).show();
            updateConnectionStatus("初始化失败: " + e.getMessage());
        }
        
        // 设置点击事件
        setClickListeners();
    }
    
    // 检查单个权限的工具方法，避免与 Context 中的同名方法冲突
    private boolean hasPermission(String permission) {
        return ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED;
    }

    private void requestPermissions() {
        ActivityCompat.requestPermissions(
                this,
                new String[]{Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA},
                PERMISSION_REQ_ID_RECORD_AUDIO
        );
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == PERMISSION_REQ_ID_RECORD_AUDIO) {
            boolean allGranted = true;
            for (int i = 0; i < grantResults.length; i++) {
                if (grantResults[i] != PackageManager.PERMISSION_GRANTED) {
                    allGranted = false;
                    break;
                }
            }
            // 再次检查权限状态，确保权限已授予
            if (allGranted && hasPermission(Manifest.permission.RECORD_AUDIO) && hasPermission(Manifest.permission.CAMERA)) {
                // 权限已授予，初始化Agora
                initializeAgora();
            } else {
                // 权限被拒绝
                showPermissionDeniedDialog();
            }
        }
    }

    private void showPermissionRationaleDialog() {
        new AlertDialog.Builder(this)
                .setTitle(R.string.permission_rational_title)
                .setMessage(R.string.permission_rational_message)
                .setPositiveButton("授予权限", (dialog, which) -> requestPermissions())
                .setNegativeButton("取消", (dialog, which) -> {
                    updateConnectionStatus("权限未授权");
                })
                .show();
    }
    
    private void showPermissionDeniedDialog() {
        new AlertDialog.Builder(this)
                .setTitle(R.string.permission_rational_title)
                .setMessage(R.string.permission_denied_message)
                .setPositiveButton("确定", (dialog, which) -> finish())
                .show();
    }
    
    /**
     * 初始化视图组件
     */
    private void initViews() {
        etChannelName = findViewById(R.id.etChannelName);
        btnJoinChannel = findViewById(R.id.btnJoinChannel);
        btnLeaveChannel = findViewById(R.id.btnLeaveChannel);
        btnToggleAudio = findViewById(R.id.btnToggleAudio);
        btnToggleVideo = findViewById(R.id.btnToggleVideo);
        btnSendChat = findViewById(R.id.btnSendChat);
        etChatMessage = findViewById(R.id.etChatMessage);
        flLocalVideo = findViewById(R.id.flLocalVideo);
        flRemoteVideo = findViewById(R.id.flRemoteVideo);
        btnToggleChat = findViewById(R.id.btnToggleChat);
        btnCloseChat = findViewById(R.id.btnCloseChat);
        chatPanel = findViewById(R.id.chatPanel);
        llConnectPrompt = findViewById(R.id.llConnectPrompt);
        
        tvConnectionStatus = findViewById(R.id.tvConnectionStatus);
        tvAudioLabel = findViewById(R.id.tvAudioLabel);
        tvVideoLabel = findViewById(R.id.tvVideoLabel);
        tvChatLabel = findViewById(R.id.tvChatLabel);
        tvChannelNumber = findViewById(R.id.tvChannelNumber);
        tvUserCount = findViewById(R.id.tvUserCount);
        
        // 初始化聊天消息列表
        rvChatMessages = findViewById(R.id.rvChatMessages);
        chatMessageAdapter = new ChatMessageAdapter();
        rvChatMessages.setLayoutManager(new LinearLayoutManager(this));
        rvChatMessages.setAdapter(chatMessageAdapter);
    }
    
    /**
     * 更新连接状态显示
     */
    private void updateConnectionStatus(String status) {
        if (tvConnectionStatus != null) {
            tvConnectionStatus.setText(status);
            if (status.contains("已连接")) {
                tvConnectionStatus.setTextColor(0xFF34C759);
            } else if (status.contains("未连接") || status.contains("失败")) {
                tvConnectionStatus.setTextColor(0xFFFF6B6B);
            } else {
                tvConnectionStatus.setTextColor(0xFFFFA500);
            }
        }
    }
    
    /**
     * 更新频道信息显示
     */
    private void updateChannelInfo(String channelName) {
        if (tvChannelNumber != null) {
            tvChannelNumber.setText("频道: " + channelName);
        }
    }
    
    private void updateUserCount() {
        Log.d("Agora", "=== 开始更新用户数量 ===");
        
        if (tvUserCount == null) {
            Log.e("Agora", "tvUserCount 为 null");
            return;
        }
        
        if (serviceManager == null) {
            Log.e("Agora", "serviceManager 为 null");
            return;
        }
        
        try {
            RoomManager roomManager = serviceManager.getRoomManager();
            if (roomManager == null) {
                Log.e("Agora", "roomManager 为 null");
                return;
            }
            
            String channelName = etChannelName.getText().toString().trim();
            Log.d("Agora", "当前频道名称: " + channelName);
            
            if (channelName.isEmpty()) {
                Log.e("Agora", "频道名称为空");
                return;
            }
            
            List<String> members = roomManager.getRoomMembers(channelName);
            int count = members != null ? members.size() : 0;
            
            Log.d("Agora", "获取到的成员列表: " + members);
            Log.d("Agora", "成员数量: " + count);
            
            tvUserCount.setText("人数: " + count);
            Log.d("Agora", "=== 用户数量更新完成 ===");
        } catch (Exception e) {
            Log.e("Agora", "更新用户数量失败", e);
        }
    }
    
    /**
     * 设置点击事件监听器
     */
    private void setClickListeners() {
        btnJoinChannel.setOnClickListener(v -> joinChannel());
        btnLeaveChannel.setOnClickListener(v -> leaveChannel());
        btnToggleAudio.setOnClickListener(v -> toggleAudio());
        btnToggleVideo.setOnClickListener(v -> toggleVideo());
        btnSendChat.setOnClickListener(v -> sendChatMessage());
        btnToggleChat.setOnClickListener(v -> toggleChatPanel());
        btnCloseChat.setOnClickListener(v -> closeChatPanel());
    }

    private void toggleChatPanel() {
        if (chatPanel.getVisibility() == android.view.View.GONE) {
            chatPanel.setVisibility(android.view.View.VISIBLE);
            tvChatLabel.setTextColor(0xFF007AFF);
            
            ObjectAnimator animator = ObjectAnimator.ofFloat(chatPanel, "translationY", 400f, 0f);
            animator.setDuration(300);
            animator.start();
        } else {
            closeChatPanel();
        }
    }

    private void closeChatPanel() {
        ObjectAnimator animator = ObjectAnimator.ofFloat(chatPanel, "translationY", 0f, 400f);
        animator.setDuration(300);
        animator.start();
        
        animator.addListener(new android.animation.AnimatorListenerAdapter() {
            @Override
            public void onAnimationEnd(android.animation.Animator animation) {
                chatPanel.setVisibility(android.view.View.GONE);
                tvChatLabel.setTextColor(0xFFFFFFFF);
            }
        });
    }

    private void joinChannel() {
        if (serviceManager == null || !serviceManager.isInitialized()) {
            Toast.makeText(this, "Agora服务未初始化，请重启应用", Toast.LENGTH_LONG).show();
            updateConnectionStatus("服务未初始化");
            return;
        }
        
        String channelName = etChannelName.getText().toString().trim();
        if (channelName.isEmpty()) {
            channelName = "123456";
            etChannelName.setText(channelName);
        }
        
        try {
            String userId = AgoraConfig.generateUserId();
            Log.d("Agora", "=== 开始加入频道流程 ===");
            Log.d("Agora", "频道名称: " + channelName);
            Log.d("Agora", "用户ID: " + userId);
            
            serviceManager.createRoom(channelName, userId, true);
            
            llConnectPrompt.setVisibility(android.view.View.GONE);
            updateConnectionStatus("已连接");
            updateChannelInfo(channelName);
            
            // 延迟更新用户数量，确保成员列表已更新
            runOnUiThread(() -> {
                new android.os.Handler().postDelayed(() -> {
                    Log.d("Agora", "=== 延迟1秒后更新用户数量 ===");
                    updateUserCount();
                }, 1000);
            });
            
            Toast.makeText(this, getString(R.string.joined_channel_msg, channelName), Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            Log.e("Agora", "加入频道失败", e);
            Toast.makeText(this, getString(R.string.join_failed, e.getMessage()), Toast.LENGTH_LONG).show();
            updateConnectionStatus("连接失败: " + e.getMessage());
        }
    }
    
    /**
     * 离开频道
     */
    private void leaveChannel() {
        Log.d("Agora", "=== 开始离开频道流程 ===");
        
        if (serviceManager == null) {
            Log.e("Agora", "serviceManager 为 null");
            Toast.makeText(this, "Agora服务未初始化", Toast.LENGTH_SHORT).show();
            return;
        }
        
        try {
            Log.d("Agora", "调用 serviceManager.leaveRoom()");
            serviceManager.leaveRoom();
            
            flLocalVideo.removeAllViews();
            flRemoteVideo.removeAllViews();
            localSurfaceView = null;
            remoteSurfaceView = null;
            currentRemoteUid = 0;
            
            llConnectPrompt.setVisibility(android.view.View.VISIBLE);
            updateConnectionStatus("未连接");
            updateChannelInfo("-");
            tvUserCount.setText("人数: 0");
            
            Log.d("Agora", "离开频道完成");
            Toast.makeText(this, getString(R.string.left_channel_msg), Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            Log.e("Agora", "离开频道失败", e);
            Toast.makeText(this, getString(R.string.leave_failed, e.getMessage()), Toast.LENGTH_LONG).show();
        }
    }
    
    /**
     * 切换音频
     */
    private void toggleAudio() {
        if (serviceManager == null || !serviceManager.isInitialized()) {
            Toast.makeText(this, "Agora服务未初始化", Toast.LENGTH_SHORT).show();
            return;
        }

        try {
            audioMuted = !audioMuted;
            serviceManager.getDeviceManager().muteLocalAudio(audioMuted);

            if (audioMuted) {
                btnToggleAudio.setImageResource(R.drawable.ic_mic_off);
                tvAudioLabel.setTextColor(0xFFFF3B30);
                Toast.makeText(this, getString(R.string.audio_muted), Toast.LENGTH_SHORT).show();
            } else {
                btnToggleAudio.setImageResource(R.drawable.ic_mic_on);
                tvAudioLabel.setTextColor(0xFFFFFFFF);
                Toast.makeText(this, getString(R.string.audio_unmuted), Toast.LENGTH_SHORT).show();
            }
        } catch (Exception e) {
            Log.e(TAG, "切换音频失败", e);
            Toast.makeText(this, getString(R.string.toggle_audio_failed, e.getMessage()), Toast.LENGTH_LONG).show();
        }
    }
    
    /**
     * 切换视频
     */
    private void toggleVideo() {
        if (serviceManager == null || !serviceManager.isInitialized()) {
            Toast.makeText(this, "Agora服务未初始化", Toast.LENGTH_SHORT).show();
            return;
        }

        try {
            videoMuted = !videoMuted;
            
            if (videoMuted) {
                serviceManager.getDeviceManager().muteLocalVideo(true);
                serviceManager.getDeviceManager().stopPreview();
                
                btnToggleVideo.setImageResource(R.drawable.ic_videocam_off);
                tvVideoLabel.setTextColor(0xFFFF3B30);
                Toast.makeText(this, getString(R.string.video_muted), Toast.LENGTH_SHORT).show();
                
                flLocalVideo.removeAllViews();
                localSurfaceView = null;
            } else {
                btnToggleVideo.setImageResource(R.drawable.ic_videocam);
                tvVideoLabel.setTextColor(0xFFFFFFFF);
                
                if (localSurfaceView == null) {
                    localSurfaceView = new SurfaceView(this);
                    flLocalVideo.removeAllViews();
                    flLocalVideo.addView(localSurfaceView);
                    
                    int setupResult = serviceManager.getDeviceManager().setupLocalVideo(localSurfaceView, 1);
                    Log.d(TAG, "setupLocalVideo result: " + setupResult);
                    
                    if (setupResult == 0) {
                        serviceManager.getDeviceManager().enableLocalVideo(true);
                        serviceManager.getDeviceManager().muteLocalVideo(false);
                        serviceManager.getDeviceManager().startPreview();
                        Toast.makeText(this, getString(R.string.video_unmuted), Toast.LENGTH_SHORT).show();
                    } else {
                        Toast.makeText(this, "设置本地视频失败，错误码: " + setupResult, Toast.LENGTH_LONG).show();
                    }
                } else {
                    serviceManager.getDeviceManager().enableLocalVideo(true);
                    serviceManager.getDeviceManager().muteLocalVideo(false);
                    serviceManager.getDeviceManager().startPreview();
                    Toast.makeText(this, getString(R.string.video_unmuted), Toast.LENGTH_SHORT).show();
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "切换视频失败", e);
            Toast.makeText(this, getString(R.string.toggle_video_failed, e.getMessage()), Toast.LENGTH_LONG).show();
        }
    }
    
    /**
     * 发送聊天消息
     */
    private void sendChatMessage() {
        if (serviceManager == null || !serviceManager.isInitialized()) {
            Toast.makeText(this, "Agora服务未初始化", Toast.LENGTH_SHORT).show();
            return;
        }
        
        String message = etChatMessage.getText().toString().trim();
        if (message.isEmpty()) {
            Toast.makeText(this, getString(R.string.please_enter_message), Toast.LENGTH_SHORT).show();
            return;
        }
        
        try {
            String channelName = etChannelName.getText().toString().trim();
            if (channelName.isEmpty()) {
                channelName = "123456";
            }
            
            serviceManager.getRoomManager().sendChatMessage(channelName, message);
            etChatMessage.setText(""); // 清空输入框
            
            // 添加消息到聊天列表
            ChatMessage chatMessage = new ChatMessage("我", message, true);
            chatMessageAdapter.addMessage(chatMessage);
            rvChatMessages.scrollToPosition(chatMessageAdapter.getItemCount() - 1);
            
            Toast.makeText(this, getString(R.string.message_sent), Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            Log.e(TAG, "发送聊天消息失败", e);
            Toast.makeText(this, getString(R.string.send_msg_failed, e.getMessage()), Toast.LENGTH_LONG).show();
        }
    }
    
    /**
     * 设置远程视频视图
     */
    private void setupRemoteVideoView(int uid) {
        if (remoteSurfaceView == null) {
            currentRemoteUid = uid;
            remoteSurfaceView = new SurfaceView(this);
            flRemoteVideo.removeAllViews();
            flRemoteVideo.addView(remoteSurfaceView);
            
            Log.d(TAG, "设置远程视频视图，uid: " + uid);
            
            // 设置远程视频视图
            int result = serviceManager.getDeviceManager().setupRemoteVideo(remoteSurfaceView, uid, 1); // RENDER_MODE_HIDDEN
            Log.d(TAG, "setupRemoteVideo 返回值: " + result);
            
            if (result == 0) {
                Toast.makeText(this, "已连接到用户: " + uid, Toast.LENGTH_SHORT).show();
            } else {
                Toast.makeText(this, "设置远程视频失败，错误码: " + result, Toast.LENGTH_LONG).show();
            }
        }
    }
    
    @Override
    protected void onDestroy() {
        super.onDestroy();
        
        if (serviceManager != null) {
            serviceManager.destroy();
        }
    }
}