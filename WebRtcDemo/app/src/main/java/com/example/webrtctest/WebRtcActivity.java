package com.example.webrtctest;
import android.os.Bundle;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.GridLayout;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import org.webrtc.AudioTrack;
import org.webrtc.Camera1Enumerator;
import org.webrtc.CameraEnumerator;
import org.webrtc.CameraVideoCapturer;
import org.webrtc.DataChannel;
import org.webrtc.DefaultVideoDecoderFactory;
import org.webrtc.DefaultVideoEncoderFactory;
import org.webrtc.EglBase;
import org.webrtc.IceCandidate;
import org.webrtc.MediaConstraints;
import org.webrtc.MediaStream;
import org.webrtc.PeerConnection;
import org.webrtc.PeerConnectionFactory;
import org.webrtc.SdpObserver;
import org.webrtc.SessionDescription;
import org.webrtc.SurfaceViewRenderer;
import org.webrtc.VideoTrack;
import org.webrtc.audio.JavaAudioDeviceModule;

import java.net.URISyntaxException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * WebRTC 视频通话主界面
 * 支持多人实时音视频通信
 */
public class WebRtcActivity extends AppCompatActivity implements WebRtcSignalingClient.SignalingCallback {
    private static final String TAG = "WebRtcActivity";
    
    private WebRtcSignalingClient signalingClient;
    private PeerConnectionFactory peerConnectionFactory;
    private EglBase eglBase;
    private EglBase rootEglBase; // 添加rootEglBase变量
    private String currentUserId = "android_" + System.currentTimeMillis() + "_" + (int)(Math.random() * 10000); // 唯一用户 ID
    private String roomId; // 新增房间ID字段
    
    // 音视频相关
    private CameraVideoCapturer videoCapturer;
    private org.webrtc.VideoSource videoSource;
    private org.webrtc.VideoTrack localVideoTrack;
    private AudioTrack localAudioTrack;
    private boolean isAudioMuted = false;
    private boolean isVideoMuted = false; // 默认开启摄像头
    private boolean isFrontCamera = true;
    private boolean isVideoInitialized = false; // 标记视频是否已初始化
    
    // 多人连接管理
    private Map<String, PeerConnection> peerConnections = new HashMap<>();
    private PeerConnection peerConnection; // 添加全局PeerConnection变量
    private Map<String, SurfaceViewRenderer> remoteRenderers = new HashMap<>(); // 为每个远程用户创建独立的渲染器
    private List<String> remoteUserIds = new ArrayList<>();
    
    // 连接状态管理
    private boolean isWebSocketConnected = false; // WebSocket连接状态
    private boolean isInRoom = false; // 是否成功加入房间
    
    // UI组件
    private SurfaceViewRenderer localVideoView;
    private GridLayout remoteVideoContainer; // 使用GridLayout容器显示多个远程视频
    private ImageButton muteAudioButton;
    private ImageButton muteVideoButton;
    private ImageButton joinRoomButton;
    private ImageButton hangupButton;
    private ImageButton leaveRoomButton; // 新增退出房间按钮
    private ImageButton switchCameraButton;
    private TextView meetingTitle;
    private TextView participantCount;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_webrtc);
        
        // 获取从MainActivity传递过来的房间号
        roomId = getIntent().getStringExtra("ROOM_ID");
        
        // 初始化UI组件
        initUI();
        
        // 初始化WebRTC
        initWebRTC();
        
        // 2. 初始化信令客户端（Java-WebSocket）
        try {
            String serverUrl = NetworkConfig.getSuitableServerUrl();
            signalingClient = new WebRtcSignalingClient(serverUrl, currentUserId, this);
            signalingClient.connectAsync(); // 异步建立 WebSocket 连接
        } catch (URISyntaxException e) {
            Log.e(TAG, "信令服务器地址错误", e);
            Toast.makeText(this, "信令服务器地址错误", Toast.LENGTH_SHORT).show();
        }
        
        // 3. 设置按钮点击事件
        setupButtonListeners();
        
        // 如果房间号不为空，则直接加入房间
        if (roomId != null && !roomId.isEmpty()) {
            meetingTitle.setText("房间号: " + roomId);
            // 延迟加入房间，确保信令连接已建立
            new android.os.Handler().postDelayed(() -> {
                joinRoom();
            }, 1000);
        }
    }
    
    private void initUI() {
        localVideoView = findViewById(R.id.local_video_view);
        remoteVideoContainer = findViewById(R.id.remote_video_container); // 使用LinearLayout容器显示多个远程视频
        muteAudioButton = findViewById(R.id.btn_mute_audio);
        muteVideoButton = findViewById(R.id.btn_mute_video);
        joinRoomButton = findViewById(R.id.btn_join_room);
        hangupButton = findViewById(R.id.btn_hangup);
        leaveRoomButton = findViewById(R.id.btn_leave_room); // 添加退出房间按钮引用
        switchCameraButton = findViewById(R.id.btn_switch_camera);
        meetingTitle = findViewById(R.id.meeting_title);
        participantCount = findViewById(R.id.participant_count);
    }
    
    private void initWebRTC() {
        try {
            eglBase = EglBase.create();
            rootEglBase = eglBase; // 初始化rootEglBase
            
            // 初始化本地视频渲染器
            localVideoView.init(eglBase.getEglBaseContext(), null);
            
            // 初始化 PeerConnectionFactory
            PeerConnectionFactory.InitializationOptions initOptions = PeerConnectionFactory.InitializationOptions.builder(this)
                    .createInitializationOptions();
            PeerConnectionFactory.initialize(initOptions);
            
            peerConnectionFactory = PeerConnectionFactory.builder()
                    .setVideoEncoderFactory(new DefaultVideoEncoderFactory(eglBase.getEglBaseContext(), true, true))
                    .setVideoDecoderFactory(new DefaultVideoDecoderFactory(eglBase.getEglBaseContext()))
                    .setAudioDeviceModule(JavaAudioDeviceModule.builder(this).createAudioDeviceModule())
                    .createPeerConnectionFactory();
            
            // 初始化本地音视频轨道
            createLocalAudioTrack();
            createLocalVideoTrack();
            
            // 设置本地视频显示
            localVideoView.setMirror(true);
            localVideoView.setZOrderMediaOverlay(true);
        } catch (Exception e) {
            Log.e(TAG, "初始化WebRTC失败", e);
            Toast.makeText(this, "初始化WebRTC失败: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }
    
    private void createLocalAudioTrack() {
        localAudioTrack = peerConnectionFactory.createAudioTrack("local_audio_track", 
            peerConnectionFactory.createAudioSource(new MediaConstraints()));
        localAudioTrack.setEnabled(!isAudioMuted);
    }
    
    private void createLocalVideoTrack() {
        try {
            // 初始化视频源
            videoSource = peerConnectionFactory.createVideoSource(false);
            
            videoCapturer = createVideoCapturer();
            if (videoCapturer != null) {
                org.webrtc.SurfaceTextureHelper surfaceTextureHelper = org.webrtc.SurfaceTextureHelper.create("CaptureThread", eglBase.getEglBaseContext());
                videoCapturer.initialize(surfaceTextureHelper, getApplicationContext(), videoSource.getCapturerObserver());
                videoCapturer.startCapture(640, 480, 30);
                localVideoTrack = peerConnectionFactory.createVideoTrack("local_video_track", videoSource);
                localVideoTrack.addSink(localVideoView);
                isVideoInitialized = true;
            }
        } catch (Exception e) {
            Log.e(TAG, "创建本地视频轨道失败", e);
        }
    }
    
    private CameraVideoCapturer createVideoCapturer() {
        Camera1Enumerator enumerator = new Camera1Enumerator(false);
        String[] deviceNames = enumerator.getDeviceNames();
        
        for (String deviceName : deviceNames) {
            if (isFrontCamera && enumerator.isFrontFacing(deviceName)) {
                return enumerator.createCapturer(deviceName, null);
            } else if (!isFrontCamera && enumerator.isBackFacing(deviceName)) {
                return enumerator.createCapturer(deviceName, null);
            }
        }
        
        // 如果找不到指定摄像头，使用第一个可用的
        if (deviceNames.length > 0) {
            return enumerator.createCapturer(deviceNames[0], null);
        }
        
        return null;
    }
    
    private void setupButtonListeners() {
        // 麦克风开关
        muteAudioButton.setOnClickListener(v -> {
            toggleAudioMute();
        });
        
        // 视频开关
        muteVideoButton.setOnClickListener(v -> {
            toggleVideoMute();
        });
        
        // 加入房间
        joinRoomButton.setOnClickListener(v -> {
            joinRoom();
        });
        
        // 挂断
        hangupButton.setOnClickListener(v -> {
            hangup();
        });
        
        // 退出房间
        leaveRoomButton.setOnClickListener(v -> {
            leaveRoom();
        });
        
        // 切换摄像头
        switchCameraButton.setOnClickListener(v -> {
            switchCamera();
        });
    }
    
    private void toggleAudioMute() {
        isAudioMuted = !isAudioMuted;
        if (localAudioTrack != null) {
            localAudioTrack.setEnabled(!isAudioMuted);
        }
        
        if (isAudioMuted) {
            muteAudioButton.setImageResource(R.drawable.ic_mic_off);
            Toast.makeText(this, "麦克风已关闭", Toast.LENGTH_SHORT).show();
        } else {
            muteAudioButton.setImageResource(R.drawable.ic_mic_on);
            Toast.makeText(this, "麦克风已开启", Toast.LENGTH_SHORT).show();
        }
    }
    
    private void toggleVideoMute() {
        isVideoMuted = !isVideoMuted;
        if (localVideoTrack != null) {
            localVideoTrack.setEnabled(!isVideoMuted);
        }
        
        if (isVideoMuted) {
            muteVideoButton.setImageResource(R.drawable.ic_videocam_off);
            Toast.makeText(this, "摄像头已关闭", Toast.LENGTH_SHORT).show();
        } else {
            muteVideoButton.setImageResource(R.drawable.ic_videocam_on);
            Toast.makeText(this, "摄像头已开启", Toast.LENGTH_SHORT).show();
        }
    }
    
    private void switchCamera() {
        if (videoCapturer instanceof CameraVideoCapturer) {
            CameraVideoCapturer cameraVideoCapturer = (CameraVideoCapturer) videoCapturer;
            cameraVideoCapturer.switchCamera(new CameraVideoCapturer.CameraSwitchHandler() {
                @Override
                public void onCameraSwitchDone(boolean b) {
                    isFrontCamera = b;
                    runOnUiThread(() -> Toast.makeText(WebRtcActivity.this, 
                         b ? "已切换到前置摄像头" : "已切换到后置摄像头", Toast.LENGTH_SHORT).show());
                }

                @Override
                public void onCameraSwitchError(String s) {
                    runOnUiThread(() -> Toast.makeText(WebRtcActivity.this, 
                        "切换摄像头失败: " + s, Toast.LENGTH_SHORT).show());
                }
            });
        }
    }
    
    private void joinRoom() {
        try {
            if (roomId == null || roomId.isEmpty()) {
                Toast.makeText(this, "请先输入房间号", Toast.LENGTH_SHORT).show();
                return;
            }
            
            // 检查WebSocket连接状态
            Log.d(TAG, "加入房间 - WebSocket连接状态: " + isWebSocketConnected);
            Log.d(TAG, "加入房间 - 是否已在房间中: " + isInRoom);
            Log.d(TAG, "加入房间 - 信令客户端是否为空: " + (signalingClient == null));
            
            // 只有在未加入房间时才显示加入房间的Toast
            if (!isInRoom) {
                if (signalingClient != null) {
                    if (isWebSocketConnected) {
                        signalingClient.joinRoom(roomId);
                        Toast.makeText(this, "正在加入房间: " + roomId, Toast.LENGTH_SHORT).show();
                        meetingTitle.setText("房间号: " + roomId);
                    } else {
                        Toast.makeText(this, "WebSocket未连接，请稍后再试", Toast.LENGTH_SHORT).show();
                        // 尝试重新连接
                        if (signalingClient != null) {
                            Log.d(TAG, "尝试重新连接WebSocket");
                            signalingClient.connectAsync();
                        }
                    }
                } else {
                    Toast.makeText(this, "信令客户端未初始化", Toast.LENGTH_SHORT).show();
                }
            } else {
                Log.d(TAG, "已在房间中，不重复加入");
            }
        } catch (Exception e) {
            Log.e(TAG, "加入房间失败", e);
            Toast.makeText(this, "加入房间失败: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }
    
    private void leaveRoom() {
        try {
            if (signalingClient != null) {
                isInRoom = false;
                Log.d(TAG, "主动退出房间，重置房间状态");
                signalingClient.leaveRoom();
                Toast.makeText(this, "已退出房间: " + roomId, Toast.LENGTH_SHORT).show();
                // 清理所有连接
                hangup();
                // 关闭当前Activity
                finish();
            }
        } catch (Exception e) {
            Log.e(TAG, "退出房间失败", e);
            Toast.makeText(this, "退出房间失败: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }
    
    private void hangup() {
        // 清理所有连接和资源
        leaveRoom();
        if (peerConnectionFactory != null) {
            peerConnectionFactory.dispose();
            peerConnectionFactory = null;
        }
        if (localAudioTrack != null) {
            localAudioTrack.dispose();
            localAudioTrack = null;
        }
        if (localVideoTrack != null) {
            localVideoTrack.dispose();
            localVideoTrack = null;
        }
        if (videoSource != null) {
            videoSource.dispose();
            videoSource = null;
        }
        if (videoCapturer != null) {
            videoCapturer.dispose();
            videoCapturer = null;
        }
        isVideoInitialized = false;
    }

    private void updateParticipantCount() {
        int count = 0;
        
        // 只有WebSocket连接成功且成功加入房间，才计入参会人数
        if (isWebSocketConnected && isInRoom) {
            count = 1; // 包括自己
            count += remoteUserIds.size(); // 加上房间内的其他用户
        }
        
        participantCount.setText("参会人员: " + count + "人");
        Log.d(TAG, "更新参会人数: " + count + 
                  " (WebSocket连接: " + isWebSocketConnected + 
                  ", 在房间中: " + isInRoom + 
                  ", 远程用户数: " + remoteUserIds.size() + ")");
        Log.d(TAG, "远程用户列表: " + remoteUserIds.toString());
    }

    // -------------------------- WebRtcSignalingClient.SignalingCallback 实现 --------------------------
    @Override
    public void onConnectSuccess() {
        runOnUiThread(() -> {
            isWebSocketConnected = true;
            Log.d(TAG, "WebSocket连接成功，更新连接状态");
            Toast.makeText(this, "WebSocket 连接成功", Toast.LENGTH_SHORT).show();
            updateParticipantCount();
            
            // 如果有房间号且未加入房间，在连接成功后延迟自动加入房间
            if (roomId != null && !roomId.isEmpty() && !isInRoom) {
                new android.os.Handler().postDelayed(() -> {
                    joinRoom();
                }, 1000);
            }
        });
    }

    @Override
    public void onConnectFailure(String errorMsg) {
        runOnUiThread(() -> {
            Log.e(TAG, "连接失败: " + errorMsg);
            Toast.makeText(this, "信令连接失败：" + errorMsg, Toast.LENGTH_SHORT).show();
            
            // 如果是WebSocket未连接的错误，尝试重新连接
            if (errorMsg.contains("WebSocket未连接")) {
                Log.d(TAG, "检测到WebSocket未连接，尝试重新连接");
                if (signalingClient != null) {
                    signalingClient.connectAsync();
                }
            }
        });
    }

    @Override
    public void onDisconnect() {
        runOnUiThread(() -> {
            isWebSocketConnected = false;
            isInRoom = false;
            Log.d(TAG, "WebSocket连接断开，重置状态");
            Toast.makeText(this, "信令连接断开", Toast.LENGTH_SHORT).show();
            updateParticipantCount();
            
            // 断开 WebRTC 连接
            hangup();
        });
    }

    // 接收对方的 SDP Offer → 生成 Answer 并回复
    @Override
    public void onReceiveOffer(String sdp, String fromUserId) {
        runOnUiThread(() -> {
            try {
                Log.d(TAG, "收到来自用户 " + fromUserId + " 的Offer");
                
                // 创建或获取对应用户的PeerConnection
                PeerConnection peerConnection = getOrCreatePeerConnection(fromUserId);
                
                // 1. 设置对方的 SDP Offer 为 RemoteSDP
                SessionDescription offerSdp = new SessionDescription(SessionDescription.Type.OFFER, sdp);
                peerConnection.setRemoteDescription(new SimpleSdpObserver() {
                    @Override
                    public void onSetSuccess() {
                        Log.d(TAG, "成功设置远程描述，开始创建Answer");
                        // 2. 生成 SDP Answer（WebRTC 核心逻辑）
                        // 在设置远程描述成功后再创建Answer
                        createAnswerAfterRemoteSet(peerConnection, fromUserId);
                    }
                    
                    @Override
                    public void onSetFailure(String error) {
                        Log.e(TAG, "设置远程描述失败: " + error);
                        onConnectFailure("设置远程描述失败: " + error);
                    }
                }, offerSdp);
            } catch (Exception e) {
                Log.e(TAG, "处理Offer失败", e);
                onConnectFailure("处理Offer失败: " + e.getMessage());
            }
        });
    }
    
    // 在设置远程描述成功后创建Answer
    private void createAnswerAfterRemoteSet(PeerConnection peerConnection, String fromUserId) {
        // 创建MediaConstraints
        MediaConstraints mediaConstraints = new MediaConstraints();
        // 添加必要的约束
        mediaConstraints.mandatory.add(new MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"));
        mediaConstraints.mandatory.add(new MediaConstraints.KeyValuePair("OfferToReceiveVideo", "true"));
        
        peerConnection.createAnswer(new SdpObserver() {
            @Override
            public void onCreateSuccess(SessionDescription answerSdp) {
                Log.d(TAG, "成功创建Answer，开始设置本地描述");
                try {
                    // 3. 设置本地 Answer 为 LocalSDP
                    peerConnection.setLocalDescription(new SimpleSdpObserver() {
                        @Override
                        public void onSetSuccess() {
                            Log.d(TAG, "成功设置本地描述，发送Answer");
                            // 4. 通过 WebSocket 发送 Answer 给对方
                            signalingClient.sendAnswer(answerSdp.description, fromUserId);
                        }
                        
                        @Override
                        public void onSetFailure(String error) {
                            Log.e(TAG, "设置本地描述失败: " + error);
                            onConnectFailure("设置本地描述失败: " + error);
                        }
                    }, answerSdp);
                } catch (Exception e) {
                    Log.e(TAG, "设置本地描述或发送Answer失败", e);
                    onConnectFailure("设置本地描述或发送Answer失败: " + e.getMessage());
                }
            }

            @Override 
            public void onCreateFailure(String error) {
                Log.e(TAG, "创建Answer失败: " + error);
                onConnectFailure("创建Answer失败: " + error);
            }
            
            @Override 
            public void onSetSuccess() {}
            
            @Override 
            public void onSetFailure(String error) {
                Log.e(TAG, "设置Answer失败: " + error);
                onConnectFailure("设置Answer失败: " + error);
            }
        }, mediaConstraints);
    }

    // 接收对方的 SDP Answer → 设置为 RemoteSDP
    @Override
    public void onReceiveAnswer(String sdp, String fromUserId) {
        runOnUiThread(() -> {
            try {
                PeerConnection peerConnection = peerConnections.get(fromUserId);
                if (peerConnection != null) {
                    SessionDescription answerSdp = new SessionDescription(SessionDescription.Type.ANSWER, sdp);
                    peerConnection.setRemoteDescription(new SimpleSdpObserver(), answerSdp);
                }
            } catch (Exception e) {
                onConnectFailure("处理Answer失败: " + e.getMessage());
            }
        });
    }

    // 接收对方的 ICE 候选 → 添加到 PeerConnection
    @Override
    public void onReceiveIceCandidate(String candidate, String sdpMid, int sdpMLineIndex, String fromUserId) {
        runOnUiThread(() -> {
            try {
                Log.d(TAG, "收到ICE候选 from user: " + fromUserId + " sdpMid: " + sdpMid + " mLineIndex: " + sdpMLineIndex);
                PeerConnection peerConnection = peerConnections.get(fromUserId);
                if (peerConnection != null) {
                    IceCandidate iceCandidate = new IceCandidate(sdpMid, sdpMLineIndex, candidate);
                    peerConnection.addIceCandidate(iceCandidate);
                    Log.d(TAG, "已添加ICE候选 to PeerConnection for user: " + fromUserId);
                } else {
                    Log.e(TAG, "未找到用户 " + fromUserId + " 的PeerConnection，无法添加ICE候选");
                }
            } catch (Exception e) {
                onConnectFailure("处理ICE候选失败: " + e.getMessage());
            }
        });
    }

    // 房间事件（如其他用户加入，触发 WebRTC 连接建立）
    @Override
    public void onRoomEvent(String eventType, String roomId, String userId) {
        runOnUiThread(() -> {
            try {
                if ("userJoined".equals(eventType) && !userId.equals(currentUserId)) {
                    // 有其他用户加入房间
                    if (!remoteUserIds.contains(userId)) {
                        remoteUserIds.add(userId);
                        updateParticipantCount();
                        Toast.makeText(this, "用户 " + userId + " 加入房间", Toast.LENGTH_SHORT).show();
                        // 创建该用户的远程视频渲染器
                        createRemoteRenderer(userId);
                    }
                    
                    // 作为发起方发送 Offer
                    createAndSendOffer(userId);
                } else if ("userLeft".equals(eventType) && !userId.equals(currentUserId)) {
                    // 有用户离开房间
                    if (remoteUserIds.contains(userId)) {
                        remoteUserIds.remove(userId);
                        updateParticipantCount();
                        Toast.makeText(this, "用户 " + userId + " 离开房间", Toast.LENGTH_SHORT).show();
                        
                        // 移除该用户的远程渲染器
                        SurfaceViewRenderer renderer = remoteRenderers.remove(userId);
                        if (renderer != null) {
                            remoteVideoContainer.removeView(renderer);
                            renderer.release();
                            
                            // 重新排列剩余的远程视频视图
                            rearrangeRemoteRenderers();
                        }
                    }
                    
                    // 清理该用户的连接
                    PeerConnection peerConnection = peerConnections.remove(userId);
                    if (peerConnection != null) {
                        peerConnection.close();
                        peerConnection.dispose();
                    }
                } else if ("joined".equals(eventType)) {
                    // 自己成功加入房间 - 只有状态真正变化时才显示Toast
                    if (!isInRoom) {
                        isInRoom = true;
                        Log.d(TAG, "成功加入房间，设置房间状态");
                        Toast.makeText(this, "成功加入房间: " + roomId, Toast.LENGTH_SHORT).show();
                        updateParticipantCount(); // 更新参会人数
                    }
                }
            } catch (Exception e) {
                onConnectFailure("处理房间事件失败: " + e.getMessage());
            }
        });
    }
    
    // 接收房间内现有用户列表
    @Override
    public void onExistingUsers(String roomId, String[] userIds) {
        runOnUiThread(() -> {
            try {
                Log.d(TAG, "收到现有用户列表，房间: " + roomId + " 用户数: " + userIds.length);
                Log.d(TAG, "现有用户: " + java.util.Arrays.toString(userIds));
                
                for (String userId : userIds) {
                    if (!userId.equals(currentUserId) && !remoteUserIds.contains(userId)) {
                        Log.d(TAG, "添加远程用户: " + userId);
                        remoteUserIds.add(userId);
                        updateParticipantCount();
                        // 只有真正发现新用户时才显示Toast
                        Toast.makeText(this, "发现房间内用户: " + userId, Toast.LENGTH_SHORT).show();
                        
                        // 创建该用户的远程视频渲染器
                        createRemoteRenderer(userId);
                    }
                }
                
                // 向现有用户发送 Offer
                for (String userId : userIds) {
                    if (!userId.equals(currentUserId)) {
                        Log.d(TAG, "向用户发送Offer: " + userId);
                        createAndSendOffer(userId);
                    }
                }
            } catch (Exception e) {
                onConnectFailure("处理现有用户失败: " + e.getMessage());
            }
        });
    }

    // 获取或创建 PeerConnection
    private PeerConnection getOrCreatePeerConnection(String userId) {
        if (peerConnection == null) {
            Log.d(TAG, "创建新的PeerConnection，用户ID: " + userId);
            peerConnection = createPeerConnection();
        } else {
            Log.d(TAG, "使用现有PeerConnection，用户ID: " + userId);
        }
        return peerConnection;
    }
    
    // 创建 PeerConnection
    private PeerConnection createPeerConnection() {
        Log.d(TAG, "开始创建PeerConnection");
        
        // 1. 创建 PeerConnectionFactory
        PeerConnectionFactory.InitializationOptions initializationOptions =
                PeerConnectionFactory.InitializationOptions.builder(this).createInitializationOptions();
        PeerConnectionFactory.initialize(initializationOptions);
        PeerConnectionFactory.Builder factoryBuilder = PeerConnectionFactory.builder()
                .setVideoEncoderFactory(new DefaultVideoEncoderFactory(
                        rootEglBase.getEglBaseContext(), true, true))
                .setVideoDecoderFactory(new DefaultVideoDecoderFactory(rootEglBase.getEglBaseContext()));
        PeerConnectionFactory factory = factoryBuilder.createPeerConnectionFactory();

        // 2. 配置 STUN/TURN 服务器
        List<PeerConnection.IceServer> iceServers = new ArrayList<>();
        iceServers.add(PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer());
        
        // 3. 创建 PeerConnection
        PeerConnection.RTCConfiguration rtcConfig = new PeerConnection.RTCConfiguration(iceServers);
        rtcConfig.tcpCandidatePolicy = PeerConnection.TcpCandidatePolicy.ENABLED;
        rtcConfig.bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE;
        rtcConfig.rtcpMuxPolicy = PeerConnection.RtcpMuxPolicy.REQUIRE;
        rtcConfig.continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY;
        rtcConfig.iceTransportsType = PeerConnection.IceTransportsType.ALL;

        // 使用现有的PeerConnectionObserver类
        PeerConnection peerConnection = factory.createPeerConnection(rtcConfig, new PeerConnectionObserver(""));

        // 4. 添加本地媒体流
        if (localVideoTrack != null) {
            Log.d(TAG, "添加本地视频轨道到PeerConnection");
            MediaStream mediaStream = factory.createLocalMediaStream("ARDAMS");
            mediaStream.addTrack(localVideoTrack);
            if (localAudioTrack != null) {
                Log.d(TAG, "添加本地音频轨道到PeerConnection");
                mediaStream.addTrack(localAudioTrack);
            }
            peerConnection.addStream(mediaStream);
        } else {
            Log.w(TAG, "本地视频轨道为空，未添加到PeerConnection");
        }
        
        Log.d(TAG, "PeerConnection创建完成");
        return peerConnection;
    }

    // 发起方创建并发送 SDP Offer
    private void createAndSendOffer(String targetUserId) {
        try {
            Log.d(TAG, "开始为用户 " + targetUserId + " 创建Offer");
            
            // 1. 获取或创建PeerConnection
            PeerConnection peerConnection = getOrCreatePeerConnection(targetUserId);

            // 创建MediaConstraints
            MediaConstraints mediaConstraints = new MediaConstraints();
            // 添加必要的约束
            mediaConstraints.mandatory.add(new MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"));
            mediaConstraints.mandatory.add(new MediaConstraints.KeyValuePair("OfferToReceiveVideo", "true"));

            // 2. 生成 SDP Offer 并发送
            peerConnection.createOffer(new SdpObserver() {
                @Override
                public void onCreateSuccess(SessionDescription offerSdp) {
                    Log.d(TAG, "成功创建Offer，开始设置本地描述");
                    try {
                        peerConnection.setLocalDescription(new SimpleSdpObserver() {
                            @Override
                            public void onSetSuccess() {
                                Log.d(TAG, "成功设置本地描述，发送Offer");
                                signalingClient.sendOffer(offerSdp.description, targetUserId);
                            }
                            
                            @Override
                            public void onSetFailure(String error) {
                                Log.e(TAG, "设置本地描述失败: " + error);
                                onConnectFailure("设置本地描述失败: " + error);
                            }
                        }, offerSdp);
                    } catch (Exception e) {
                        Log.e(TAG, "设置本地描述或发送Offer失败", e);
                        onConnectFailure("设置本地描述或发送Offer失败: " + e.getMessage());
                    }
                }

                @Override 
                public void onCreateFailure(String error) {
                    Log.e(TAG, "创建Offer失败: " + error);
                    onConnectFailure("创建Offer失败: " + error);
                }
                
                @Override 
                public void onSetSuccess() {}
                
                @Override 
                public void onSetFailure(String error) {
                    Log.e(TAG, "设置Offer失败: " + error);
                    onConnectFailure("设置Offer失败: " + error);
                }
            }, mediaConstraints);
        } catch (Exception e) {
            Log.e(TAG, "创建并发送Offer失败", e);
            onConnectFailure("创建并发送Offer失败: " + e.getMessage());
        }
    }

    // 简化的 SdpObserver 实现（WebRTC 要求必须实现，空实现即可）
    private static class SimpleSdpObserver implements SdpObserver {
        @Override 
        public void onCreateSuccess(SessionDescription sessionDescription) {
            Log.d("SimpleSdpObserver", "创建SDP成功");
        }
        
        @Override 
        public void onCreateFailure(String error) {
            Log.e("SimpleSdpObserver", "创建SDP失败: " + error);
        }
        
        @Override 
        public void onSetSuccess() {
            Log.d("SimpleSdpObserver", "设置SDP成功");
        }
        
        @Override 
        public void onSetFailure(String error) {
            Log.e("SimpleSdpObserver", "设置SDP失败: " + error);
        }
    }
    
    // 为远程用户创建视频渲染器
    private void createRemoteRenderer(String userId) {
        SurfaceViewRenderer remoteView = new SurfaceViewRenderer(this);
        remoteView.init(eglBase.getEglBaseContext(), null);
        
        // 计算当前用户在网格中的位置
        int position = remoteRenderers.size();
        int row = position / 2; // 2列布局
        int col = position % 2;
        
        // 设置渲染器大小和布局参数
        int width = (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 160, getResources().getDisplayMetrics());
        int height = (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 120, getResources().getDisplayMetrics());
        
        // 创建GridLayout.LayoutParams并设置行列
        GridLayout.LayoutParams params = new GridLayout.LayoutParams();
        params.width = width;
        params.height = height;
        params.setMargins(10, 10, 10, 10);
        params.rowSpec = GridLayout.spec(row);
        params.columnSpec = GridLayout.spec(col);
        
        remoteView.setLayoutParams(params);
        
        // 添加到远程视频容器中的指定位置
        remoteVideoContainer.addView(remoteView);
        
        // 保存引用
        remoteRenderers.put(userId, remoteView);
        
        Log.d(TAG, "为用户 " + userId + " 创建远程视频渲染器，位置: 行=" + row + ", 列=" + col);
    }
    
    // 重新排列远程视频视图
    private void rearrangeRemoteRenderers() {
        // 清空当前所有视图
        remoteVideoContainer.removeAllViews();
        
        // 重新添加所有远程视频视图，确保按顺序排列
        int position = 0;
        for (Map.Entry<String, SurfaceViewRenderer> entry : remoteRenderers.entrySet()) {
            String userId = entry.getKey();
            SurfaceViewRenderer renderer = entry.getValue();
            
            // 计算新的位置
            int row = position / 2; // 2列布局
            int col = position % 2;
            
            // 创建新的布局参数
            int width = (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 160, getResources().getDisplayMetrics());
            int height = (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 120, getResources().getDisplayMetrics());
            
            GridLayout.LayoutParams params = new GridLayout.LayoutParams();
            params.width = width;
            params.height = height;
            params.setMargins(10, 10, 10, 10);
            params.rowSpec = GridLayout.spec(row);
            params.columnSpec = GridLayout.spec(col);
            
            renderer.setLayoutParams(params);
            
            // 添加到容器中
            remoteVideoContainer.addView(renderer);
            
            Log.d(TAG, "重新排列用户 " + userId + " 的视频渲染器，新位置: 行=" + row + ", 列=" + col);
            
            position++;
        }
    }
    
    // PeerConnection 回调观察者
    private class PeerConnectionObserver implements PeerConnection.Observer {
        private String userId;
        
        public PeerConnectionObserver(String userId) {
            this.userId = userId;
        }
        
        @Override
        public void onIceCandidate(IceCandidate iceCandidate) {
            // 发送 ICE 候选到对方
            Log.d(TAG, "收到ICE候选: " + iceCandidate.sdp);
            signalingClient.sendIceCandidate(iceCandidate.sdp, iceCandidate.sdpMid, 
                iceCandidate.sdpMLineIndex, userId);
        }
        
        @Override
        public void onAddStream(MediaStream mediaStream) {
            // 添加远程媒体流
            Log.d(TAG, "收到远程媒体流 from user: " + userId);
            runOnUiThread(() -> {
                if (!mediaStream.videoTracks.isEmpty()) {
                    VideoTrack remoteVideoTrack = mediaStream.videoTracks.get(0);
                    SurfaceViewRenderer remoteRenderer = remoteRenderers.get(userId);
                    if (remoteRenderer != null) {
                        Log.d(TAG, "将视频流绑定到渲染器 for user: " + userId);
                        remoteVideoTrack.addSink(remoteRenderer);
                    } else {
                        Log.e(TAG, "未找到用户 " + userId + " 的渲染器");
                        // 使用类成员变量localVideoView而不是remoteVideoView
                        remoteVideoTrack.addSink(localVideoView);
                    }
                }
            });
        }
        
        // 其他必须实现的方法
        @Override public void onSignalingChange(PeerConnection.SignalingState signalingState) {
            Log.d(TAG, "信令状态变化 for user " + userId + ": " + signalingState);
        }
        
        @Override public void onIceConnectionChange(PeerConnection.IceConnectionState iceConnectionState) {
            Log.d(TAG, "ICE连接状态变化 for user " + userId + ": " + iceConnectionState);
            
            if (iceConnectionState == PeerConnection.IceConnectionState.CONNECTED) {
                Log.d(TAG, "与用户 " + userId + " 的ICE连接已建立");
            } else if (iceConnectionState == PeerConnection.IceConnectionState.COMPLETED) {
                Log.d(TAG, "与用户 " + userId + " 的ICE连接已完成");
            } else if (iceConnectionState == PeerConnection.IceConnectionState.FAILED) {
                Log.e(TAG, "与用户 " + userId + " 的ICE连接失败");
                runOnUiThread(() -> onConnectFailure("ICE连接失败: " + iceConnectionState));
            } else if (iceConnectionState == PeerConnection.IceConnectionState.DISCONNECTED) {
                Log.w(TAG, "与用户 " + userId + " 的ICE连接已断开");
            } else if (iceConnectionState == PeerConnection.IceConnectionState.CLOSED) {
                Log.w(TAG, "与用户 " + userId + " 的ICE连接已关闭");
            }
        }
        
        @Override public void onIceConnectionReceivingChange(boolean b) {
            Log.d(TAG, "ICE连接接收状态变化 for user " + userId + ": " + b);
        }
        
        @Override public void onIceGatheringChange(PeerConnection.IceGatheringState iceGatheringState) {
            Log.d(TAG, "ICE收集状态变化 for user " + userId + ": " + iceGatheringState);
        }
        
        @Override public void onIceCandidatesRemoved(IceCandidate[] iceCandidates) {
            Log.d(TAG, "ICE候选被移除 for user " + userId + ", 数量: " + iceCandidates.length);
        }
        
        @Override public void onRemoveStream(MediaStream mediaStream) {
            Log.d(TAG, "移除远程媒体流 for user: " + userId);
        }
        
        @Override public void onDataChannel(DataChannel dataChannel) {
            Log.d(TAG, "数据通道已创建 for user: " + userId);
        }
        
        @Override public void onRenegotiationNeeded() {
            Log.d(TAG, "需要重新协商 for user: " + userId);
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        try {
            // 清理所有PeerConnection
            for (PeerConnection peerConnection : peerConnections.values()) {
                peerConnection.close();
                peerConnection.dispose();
            }
            peerConnections.clear();
            
            // 清理远程渲染器
            for (SurfaceViewRenderer renderer : remoteRenderers.values()) {
                renderer.release();
            }
            remoteRenderers.clear();
            
            // 清理本地视频渲染器
            localVideoView.release();
            
            // 清理EGL上下文
            if (eglBase != null) {
                eglBase.release();
            }
            
            // 断开信令连接
            if (signalingClient != null) {
                signalingClient.disconnectAsync();
            }
        } catch (Exception e) {
            Log.e(TAG, "销毁资源失败", e);
            Toast.makeText(this, "销毁资源失败: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }
}
