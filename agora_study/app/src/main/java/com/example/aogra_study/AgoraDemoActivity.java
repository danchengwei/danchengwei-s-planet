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
import android.widget.GridLayout;
import android.view.View;
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
import java.util.Map;
import java.util.HashMap;
import java.util.ArrayList;


/**
 * Agora功能演示Activity
 * 展示如何使用Agora服务进行音视频通话、聊天等
 */
public class AgoraDemoActivity extends AppCompatActivity {
    private static final String TAG = "AgoraDemoActivity";
    public static final String DEFAULT_CHANNEL_NAME = "123456"; // 固定频道名

    private AgoraServiceManager serviceManager;

    // UI组件
    private Button btnJoinChannel;
    private ImageButton btnLeaveChannel;
    private ImageButton btnToggleAudio;
    private ImageButton btnToggleVideo;
    private ImageButton btnSwitchCamera; // 新增的切换摄像头按钮
    private Button btnSendChat;
    private EditText etChatMessage; // 聊天输入框仍然保留
    private GridLayout videoGridLayout;
    private ImageButton btnToggleChat;
    private ImageButton btnCloseChat;
    private LinearLayout chatPanel;
    private LinearLayout llConnectPrompt;
    private RecyclerView rvChatMessages;
    private ChatMessageAdapter chatMessageAdapter;
    private LinearLayout bottomToolbar;
    private TextView tvChannelPrompt; // 新增：用于显示频道提示
    private FrameLayout loadingOverlay; // 加载遮罩层
    private TextView tvLoadingMessage; // 加载提示文本

    // 状态信息显示
    private TextView tvConnectionStatus;
    private TextView tvAudioLabel;
    private TextView tvVideoLabel;
    private TextView tvChatLabel;
    private TextView tvChannelNumber;
    private TextView tvUserCount;

    // 视频视图管理
    private Map<Integer, View> videoViews = new HashMap<>(); // 用户ID -> 视图
    private SurfaceView localSurfaceView;
    private int currentRemoteUid = 0;
    private boolean audioMuted = true;
    private boolean videoMuted = true;
    private String currentChannelName = DEFAULT_CHANNEL_NAME; // 缓存当前频道名

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

        // 初始UI状态：隐藏视频和工具栏，显示连接提示
        llConnectPrompt.setVisibility(android.view.View.VISIBLE);
        bottomToolbar.setVisibility(android.view.View.GONE);
        chatPanel.setVisibility(android.view.View.GONE);

        updateChannelInfo(DEFAULT_CHANNEL_NAME); // 更新顶部栏的频道号提示
        updateUserCount(); // 初始用户数量可能为0
    }

    private void initializeAgora() {
        // 初始化Agora服务管理器
        try {
            serviceManager = new AgoraServiceManager(this);
            serviceManager.initialize();

            // 初始化后隐藏视频相关UI，显示连接提示
            llConnectPrompt.setVisibility(android.view.View.VISIBLE);
            bottomToolbar.setVisibility(android.view.View.GONE);
            chatPanel.setVisibility(android.view.View.GONE);

            // 设置默认静音状态
            serviceManager.getDeviceManager().muteLocalAudio(true);
            serviceManager.getDeviceManager().muteLocalVideo(true); // 默认关闭本地视频流

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
                        // 现在不需要手动更新用户数量，因为LiveData会自动更新
                        // updateUserCount();  // 移除这行，由LiveData自动更新

                        // 不在这里添加视频视图，等待视频流可用时再添加
                        // 视频视图会在 onRemoteVideoStateChanged 回调中添加
                        Log.d("Agora", "用户加入，等待视频流可用...");
                    });
                    Log.d("Agora", "=== UI 处理用户加入事件完成 ===");
                }

                @Override
                public void onUserLeft(String userId) {
                    Log.d("Agora", "=== UI 收到用户离开事件 ===");
                    Log.d("Agora", "用户ID: " + userId);
                    runOnUiThread(() -> {
                        Toast.makeText(AgoraDemoActivity.this, getString(R.string.user_left_msg, userId), Toast.LENGTH_SHORT).show();

                        // 移除对应的视频视图
                        try {
                            int uid = Integer.parseInt(userId);
                            removeVideoView(uid);
                        } catch (NumberFormatException e) {
                            Log.e("Agora", "解析用户ID失败", e);
                        }

                        // 现在不需要手动更新用户数量，因为LiveData会自动更新
                        // updateUserCount();  // 移除这行，由LiveData自动更新
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
                    if (enabled) {
                        // 当远程视频流可用时，创建并设置远程视频视图
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
                    if (enabled && !videoViews.containsKey(uid)) {
                        // 当远程视频流可用且我们还没有设置视图时，创建并设置远程视频视图
                        runOnUiThread(() -> setupRemoteVideoView(uid));
                    } else if (!enabled && videoViews.containsKey(uid)) {
                        // 当远程视频流不可用时，移除视频视图
                        runOnUiThread(() -> {
                            removeVideoView(uid);
                            updateUserCount(); // 更新人数和视图数量
                        });
                    }
                }

                @Override
                public void onAudioQualityChanged(int uid, int quality) {
                    Log.d(TAG, "用户ID " + uid + " 音频质量改变，质量: " + quality);
                }
            });

            // 设置房间状态监听器
            serviceManager.getRoomManager().setRoomStateListener(new RoomManager.RoomStateListener() {
                @Override
                public void onJoiningRoom() {
                    Log.d(TAG, "房间状态：开始加入房间");
                    runOnUiThread(() -> showLoading("正在加入房间..."));
                }

                @Override
                public void onJoinedRoom() {
                    Log.d(TAG, "房间状态：成功加入房间");
                    runOnUiThread(() -> {
                        hideLoading();
                        // 加入成功后立即更新用户数量
                        updateUserCount();
                        
                        // 监听成员数量变化
                        serviceManager.getRoomManager().getMemberCountLiveData().observe(AgoraDemoActivity.this, count -> {
                            runOnUiThread(() -> {
                                if (tvUserCount != null) {
                                    tvUserCount.setText(getString(R.string.user_count_prefix, count));
                                    Log.d("Agora", "通过LiveData更新用户数量: " + count);
                                }
                            });
                        });
                    });
                }

                @Override
                public void onLeavingRoom() {
                    Log.d(TAG, "房间状态：开始离开房间");
                    runOnUiThread(() -> showLoading("正在离开房间..."));
                }

                @Override
                public void onLeftRoom() {
                    Log.d(TAG, "房间状态：成功离开房间");
                    runOnUiThread(() -> hideLoading());
                }

                @Override
                public void onRoomError(String error) {
                    Log.e(TAG, "房间错误：" + error);
                    runOnUiThread(() -> {
                        hideLoading();
                        Toast.makeText(AgoraDemoActivity.this, error, Toast.LENGTH_LONG).show();
                    });
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
        // 从XML布局中获取视图引用
        btnJoinChannel = findViewById(R.id.btnJoinChannel);
        btnLeaveChannel = findViewById(R.id.btnLeaveChannel);
        btnToggleAudio = findViewById(R.id.btnToggleAudio);
        btnToggleVideo = findViewById(R.id.btnToggleVideo);
        btnSwitchCamera = findViewById(R.id.btnSwitchCamera); // 新增的切换摄像头按钮
        btnSendChat = findViewById(R.id.btnSendChat);
        etChatMessage = findViewById(R.id.etChatMessage); // 聊天输入框仍然保留
        videoGridLayout = findViewById(R.id.videoGridLayout);
        btnToggleChat = findViewById(R.id.btnToggleChat);
        btnCloseChat = findViewById(R.id.btnCloseChat);
        chatPanel = findViewById(R.id.chatPanel);
        llConnectPrompt = findViewById(R.id.llConnectPrompt);
        bottomToolbar = findViewById(R.id.bottomToolbar); // 初始化底部工具栏
        tvChannelPrompt = findViewById(R.id.tvChannelPrompt); // 初始化频道提示TextView
        loadingOverlay = findViewById(R.id.loadingOverlay); // 初始化加载遮罩层
        tvLoadingMessage = findViewById(R.id.tvLoadingMessage); // 初始化加载提示文本

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

        if (tvChannelPrompt != null) {
            tvChannelPrompt.setText(getString(R.string.current_channel_prompt, DEFAULT_CHANNEL_NAME));
        }
        if (tvChannelNumber != null) {
            tvChannelNumber.setText(getString(R.string.channel_info_prefix, DEFAULT_CHANNEL_NAME));
        }
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
            tvChannelNumber.setText(getString(R.string.channel_info_prefix, channelName));
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

            // 使用缓存的频道名称
            String channelName = currentChannelName;
            Log.d("Agora", "使用缓存的频道名称: " + channelName);

            if (channelName == null || channelName.isEmpty()) {
                Log.e("Agora", "频道名称为空");
                tvUserCount.setText("人数: 0");
                return;
            }

            List<String> members = roomManager.getRoomMembers(channelName);
            int count = members != null ? members.size() : 0;

            Log.d("Agora", "获取到的成员列表: " + members);
            Log.d("Agora", "成员数量: " + count);

            tvUserCount.setText(getString(R.string.user_count_prefix, count));

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
        btnSwitchCamera.setOnClickListener(v -> switchCamera());
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

        String channelName = DEFAULT_CHANNEL_NAME; // 使用固定频道名

        try {
            String userId = AgoraConfig.generateUserId();
            Log.d("Agora", "=== 开始加入频道流程 ===");
            Log.d("Agora", "频道名称: " + channelName);
            Log.d("Agora", "用户ID: " + userId);

            // serviceManager.createRoom 会处理之前的状态清理
            serviceManager.createRoom(channelName, userId, true);

            updateConnectionStatus("已连接");
            updateChannelInfo(channelName);

            // 显示底部工具栏和网格布局，隐藏连接提示
            llConnectPrompt.setVisibility(android.view.View.GONE);
            bottomToolbar.setVisibility(android.view.View.VISIBLE);
            videoGridLayout.setVisibility(android.view.View.VISIBLE);

            Toast.makeText(this, getString(R.string.joined_channel_msg, channelName), Toast.LENGTH_SHORT).show();

            // 成功加入频道后，不自动开启视频，等待用户手动点击按钮
            // 人数更新会在 onJoinedRoom 回调中处理
            Log.d("Agora", "加入频道完成，等待用户手动开启视频");
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

        // 启动异步离开操作，加载状态由 RoomStateListener 管理
        new Thread(() -> {
            try {
                Log.d("Agora", "调用 serviceManager.leaveRoom()");
                serviceManager.leaveRoom();
                Log.d("Agora", "leaveRoom 调用完成");

                // 在UI线程更新UI
                runOnUiThread(() -> {
                    // 清空视频视图
                    videoGridLayout.removeAllViews();
                    videoViews.clear();
                    localSurfaceView = null;
                    currentRemoteUid = 0;

                    // 重置状态
                    audioMuted = true;
                    videoMuted = true;

                    // 更新UI状态
                    btnToggleAudio.setImageResource(R.drawable.ic_mic_off);
                    tvAudioLabel.setTextColor(0xFFFF3B30);
                    btnToggleVideo.setImageResource(R.drawable.ic_videocam_off);
                    tvVideoLabel.setTextColor(0xFFFF3B30);

                    llConnectPrompt.setVisibility(android.view.View.VISIBLE);
                    bottomToolbar.setVisibility(android.view.View.GONE);
                    chatPanel.setVisibility(android.view.View.GONE);
                    videoGridLayout.setVisibility(android.view.View.GONE);

                    updateConnectionStatus("未连接");
                    updateChannelInfo("-");
                    tvUserCount.setText("人数: 0");

                    Toast.makeText(this, getString(R.string.left_channel_msg), Toast.LENGTH_SHORT).show();
                });
            } catch (Exception e) {
                Log.e("Agora", "离开频道失败", e);
                runOnUiThread(() -> {
                    Toast.makeText(this, getString(R.string.leave_failed, e.getMessage()), Toast.LENGTH_LONG).show();
                });
            }
        }).start();
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
            Log.d(TAG, "=== 切换音频 ===");
            Log.d(TAG, "新状态: " + (audioMuted ? "静音" : "开启"));

            serviceManager.getDeviceManager().muteLocalAudio(audioMuted);
            Log.d(TAG, "已调用 muteLocalAudio(" + audioMuted + ")");

            if (audioMuted) {
                btnToggleAudio.setImageResource(R.drawable.ic_mic_off);
                tvAudioLabel.setTextColor(0xFFFF3B30);
                Toast.makeText(this, getString(R.string.audio_muted), Toast.LENGTH_SHORT).show();
                Log.d(TAG, "音频已静音，停止推流");
            } else {
                serviceManager.getDeviceManager().enableLocalAudio(true);
                Log.d(TAG, "已调用 enableLocalAudio(true)");
                btnToggleAudio.setImageResource(R.drawable.ic_mic_on);
                tvAudioLabel.setTextColor(0xFFFFFFFF);
                Toast.makeText(this, getString(R.string.audio_unmuted), Toast.LENGTH_SHORT).show();
                Log.d(TAG, "音频已开启，开始推流");
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
            Log.d(TAG, "=== 切换视频 ===");
            Log.d(TAG, "新状态: " + (videoMuted ? "关闭" : "开启"));

            if (videoMuted) {
                serviceManager.getDeviceManager().muteLocalVideo(true);
                serviceManager.getDeviceManager().stopPreview();
                Log.d(TAG, "已调用 muteLocalVideo(true) 和 stopPreview()");

                btnToggleVideo.setImageResource(R.drawable.ic_videocam_off);
                tvVideoLabel.setTextColor(0xFFFF3B30);
                Toast.makeText(this, getString(R.string.video_muted), Toast.LENGTH_SHORT).show();

                // 移除本地视频视图
                removeVideoView(0); // 本地视频使用 uid 0
                localSurfaceView = null;

                // 验证人数和网格布局的view数是否一致
                updateUserCount();

                Log.d(TAG, "视频已关闭，停止推流");
            } else {
                // 先更新 UI 状态
                btnToggleVideo.setImageResource(R.drawable.ic_videocam);
                tvVideoLabel.setTextColor(0xFFFFFFFF);

                Log.d(TAG, "准备添加本地视频视图...");
                if (localSurfaceView == null) {
                    localSurfaceView = new SurfaceView(this);
                    Log.d(TAG, "创建新的 SurfaceView");
                }

                // 先添加本地视频到网格布局（UI 操作）
                final SurfaceView surfaceToSetup = localSurfaceView;
                addVideoView(0, localSurfaceView, "我"); // 本地视频使用 uid 0

                // 在后台线程设置视频，避免阻塞主线程
                new Thread(() -> {
                    try {
                        int setupResult = serviceManager.getDeviceManager().setupLocalVideo(surfaceToSetup, 1);
                        Log.d(TAG, "setupLocalVideo 返回值: " + setupResult);

                        if (setupResult == 0) {
                            serviceManager.getDeviceManager().enableLocalVideo(true);
                            serviceManager.getDeviceManager().muteLocalVideo(false);
                            serviceManager.getDeviceManager().startPreview();
                            Log.d(TAG, "已调用 enableLocalVideo(true), muteLocalVideo(false), startPreview()");

                            runOnUiThread(() -> {
                                Toast.makeText(this, getString(R.string.video_unmuted), Toast.LENGTH_SHORT).show();
                                // 验证人数和网格布局的view数是否一致
                                updateUserCount();
                            });

                            Log.d(TAG, "视频已开启，开始推流");
                        } else {
                            runOnUiThread(() -> {
                                Toast.makeText(this, "设置本地视频失败，错误码: " + setupResult, Toast.LENGTH_LONG).show();
                            });
                            Log.e(TAG, "设置本地视频失败，错误码: " + setupResult);
                        }
                    } catch (Exception e) {
                        Log.e(TAG, "设置本地视频异常", e);
                        runOnUiThread(() -> {
                            Toast.makeText(this, "设置本地视频异常: " + e.getMessage(), Toast.LENGTH_LONG).show();
                        });
                    }
                }).start();
            }
        } catch (Exception e) {
            Log.e(TAG, "切换视频失败", e);
            Toast.makeText(this, getString(R.string.toggle_video_failed, e.getMessage()), Toast.LENGTH_LONG).show();
        }
    }

    /**
     * 切换摄像头
     */
    private void switchCamera() {
        if (serviceManager == null || !serviceManager.isInitialized()) {
            Toast.makeText(this, "Agora服务未初始化", Toast.LENGTH_SHORT).show();
            return;
        }
        serviceManager.getDeviceManager().switchCamera();
        Toast.makeText(this, "摄像头已切换", Toast.LENGTH_SHORT).show();
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
            String channelName = DEFAULT_CHANNEL_NAME; // 使用固定频道名
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
        Log.d(TAG, "准备添加远程视频视图，uid: " + uid);

        // 添加远程视频到网格布局
        addVideoView(uid, null, String.valueOf(uid));
    }

    /**
     * 添加视频视图到网格布局
     */
    private void addVideoView(int uid, SurfaceView surfaceView, String userName) {
        Log.d(TAG, "=== 添加视频视图 ===");
        Log.d(TAG, "用户ID: " + uid + ", 用户名: " + userName);

        // 如果该用户ID已存在，先移除旧视图（不更新布局）
        if (videoViews.containsKey(uid)) {
            View oldView = videoViews.get(uid);
            videoGridLayout.removeView(oldView);
            videoViews.remove(uid);
            Log.d(TAG, "已移除旧的视频视图");
        }

        // 创建视频视图项
        View videoView = getLayoutInflater().inflate(R.layout.item_video_view, videoGridLayout, false);
        SurfaceView videoSurface;
        TextView tvUserName = videoView.findViewById(R.id.tvUserName);

        // 设置用户名
        tvUserName.setText(userName);

        // 如果是本地视频，使用传入的 SurfaceView
        if (uid == 0) {
            // 本地视频，使用传入的 SurfaceView 或创建新的
            if (surfaceView != null) {
                videoSurface = surfaceView;
            } else {
                videoSurface = new SurfaceView(this);
            }
        } else {
            // 远程视频，创建新的 SurfaceView
            videoSurface = new SurfaceView(this);
        }

        // 设置视频 SurfaceView
        FrameLayout videoContainer = (FrameLayout) videoView;
        videoContainer.addView(videoSurface, 0);

        // 添加到网格布局
        videoGridLayout.addView(videoView);

        // 保存到 map
        videoViews.put(uid, videoView);

        // 更新网格布局的行列数
        updateGridLayout();

        // 在后台线程设置视频，避免阻塞主线程
        final SurfaceView finalVideoSurface = videoSurface;
        new Thread(() -> {
            try {
                int setupResult;
                if (uid == 0) {
                    // 本地视频
                    setupResult = serviceManager.getDeviceManager().setupLocalVideo(finalVideoSurface, 1);
                    Log.d(TAG, "setupLocalVideo 返回值: " + setupResult);
                } else {
                    // 远程视频
                    setupResult = serviceManager.getDeviceManager().setupRemoteVideo(finalVideoSurface, uid, 1);
                    Log.d(TAG, "setupRemoteVideo 返回值: " + setupResult);
                }

                if (setupResult != 0) {
                    Log.e(TAG, "设置视频失败，错误码: " + setupResult);
                }
            } catch (Exception e) {
                Log.e(TAG, "设置视频异常", e);
            }
        }).start();

        Log.d(TAG, "=== 添加视频视图完成 ===");
    }

    /**
     * 移除视频视图
     */
    private void removeVideoView(int uid) {
        Log.d(TAG, "=== 移除视频视图 ===");
        Log.d(TAG, "用户ID: " + uid);

        // 从 map 中获取视图
        View videoView = videoViews.get(uid);
        if (videoView != null) {
            // 从网格布局中移除
            videoGridLayout.removeView(videoView);

            // 从 map 中移除
            videoViews.remove(uid);

            // 解除视图与 Agora RTC 引擎的绑定
            if (serviceManager != null && serviceManager.getDeviceManager() != null) {
                if (uid == 0) { // 本地视频
                    serviceManager.getDeviceManager().removeLocalVideoView();
                    Log.d(TAG, "已解除本地视频视图绑定");
                } else { // 远程视频
                    serviceManager.getDeviceManager().removeRemoteVideoView(uid);
                    Log.d(TAG, "已解除远程视频视图绑定，用户ID: " + uid);
                }
            } else {
                Log.e(TAG, "serviceManager 或 DeviceManager 为 null，无法解除视频视图绑定");
            }

            Log.d(TAG, "已移除视频视图");
        }

        // 更新网格布局的行列数
        updateGridLayout();

        Log.d(TAG, "=== 移除视频视图完成 ===");
    }

    /**
     * 更新网格布局的行列数
     */
    private void updateGridLayout() {
        // 使用网格布局中的实际子视图数量，而不是 videoViews.size()
        int videoCount = videoGridLayout.getChildCount();
        Log.d(TAG, "=== 更新网格布局 ===");
        Log.d(TAG, "网格布局中的视图数量: " + videoCount);

        // 根据视频数量计算行列数
        int columnCount = 2;
        int rowCount = Math.max(1, (videoCount + 1) / 2); // 至少保留1行

        videoGridLayout.setColumnCount(columnCount);
        videoGridLayout.setRowCount(rowCount);

        Log.d(TAG, "列数: " + columnCount + ", 行数: " + rowCount);
    }

    /**
     * 显示加载遮罩层
     */
    private void showLoading(String message) {
        if (loadingOverlay != null) {
            loadingOverlay.setVisibility(View.VISIBLE);
        }
        if (tvLoadingMessage != null) {
            tvLoadingMessage.setText(message);
        }

        // 禁用按钮，防止重复点击
        if (btnJoinChannel != null) {
            btnJoinChannel.setEnabled(false);
        }
        if (btnLeaveChannel != null) {
            btnLeaveChannel.setEnabled(false);
        }
    }

    /**
     * 隐藏加载遮罩层
     */
    private void hideLoading() {
        if (loadingOverlay != null) {
            loadingOverlay.setVisibility(View.GONE);
        }

        // 恢复按钮可用状态
        if (btnJoinChannel != null) {
            btnJoinChannel.setEnabled(true);
        }
        if (btnLeaveChannel != null) {
            btnLeaveChannel.setEnabled(true);
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