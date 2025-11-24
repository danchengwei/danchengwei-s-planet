package com.example.webrtctest;

import android.os.Bundle;
import android.util.Log;
import android.widget.ImageButton;
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
import org.webrtc.VideoSource;
import org.webrtc.VideoTrack;
import org.webrtc.audio.JavaAudioDeviceModule;

import java.net.URISyntaxException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class WebRtcActivity extends AppCompatActivity implements WebRtcSignalingClient.SignalingCallback {
    private static final String TAG = "WebRtcActivity";
    
    private WebRtcSignalingClient signalingClient;
    private PeerConnectionFactory peerConnectionFactory;
    private EglBase eglBase;
    private String currentUserId = "android_" + System.currentTimeMillis(); // 唯一用户 ID
    private String roomId; // 新增房间ID字段
    
    // 音视频相关
    private CameraVideoCapturer videoCapturer;
    private VideoSource videoSource;
    private VideoTrack localVideoTrack;
    private AudioTrack localAudioTrack;
    private boolean isAudioMuted = false;
    private boolean isVideoMuted = true; // 默认关闭摄像头
    private boolean isFrontCamera = true;
    private boolean isVideoInitialized = false; // 标记视频是否已初始化
    
    // 多人连接管理
    private Map<String, PeerConnection> peerConnections = new HashMap<>();
    private Map<String, SurfaceViewRenderer> remoteRenderers = new HashMap<>();
    private List<String> remoteUserIds = new ArrayList<>();
    
    // UI组件
    private SurfaceViewRenderer localVideoView;
    private SurfaceViewRenderer remoteVideoView;
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
        }
    }

    private void initUI() {
        localVideoView = findViewById(R.id.local_video_view);
        remoteVideoView = findViewById(R.id.remote_video_view);
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
            
            // 初始化本地视频渲染器
            localVideoView.init(eglBase.getEglBaseContext(), null);
            remoteVideoView.init(eglBase.getEglBaseContext(), null);
            
            // 初始化 PeerConnectionFactory
            PeerConnectionFactory.InitializationOptions initOptions = PeerConnectionFactory.InitializationOptions.builder(this)
                    .setEnableInternalTracer(true)
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
        videoCapturer = createVideoCapturer();
        videoSource = peerConnectionFactory.createVideoSource(false);
        if (videoCapturer != null) {
            videoCapturer.initialize(null, getApplicationContext(), videoSource.getCapturerObserver());
            videoCapturer.startCapture(640, 480, 30);
            localVideoTrack = peerConnectionFactory.createVideoTrack("local_video_track", videoSource);
            localVideoTrack.addSink(localVideoView);
        }
    }
    
    private CameraVideoCapturer createVideoCapturer() {
        CameraEnumerator enumerator = new Camera1Enumerator(false);
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
            muteAudioButton.setBackgroundResource(R.drawable.ic_mic_off);
            Toast.makeText(this, "麦克风已关闭", Toast.LENGTH_SHORT).show();
        } else {
            muteAudioButton.setBackgroundResource(R.drawable.ic_mic_on);
            Toast.makeText(this, "麦克风已开启", Toast.LENGTH_SHORT).show();
        }
    }
    
    private void toggleVideoMute() {
        isVideoMuted = !isVideoMuted;
        if (localVideoTrack != null) {
            localVideoTrack.setEnabled(!isVideoMuted);
        }
        
        if (isVideoMuted) {
            muteVideoButton.setBackgroundResource(R.drawable.ic_videocam_off);
            Toast.makeText(this, "摄像头已关闭", Toast.LENGTH_SHORT).show();
        } else {
            muteVideoButton.setBackgroundResource(R.drawable.ic_videocam_on);
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
    
    private void hangup() {
        // 挂断当前所有连接
        for (PeerConnection peerConnection : peerConnections.values()) {
            peerConnection.close();
            peerConnection.dispose();
        }
        peerConnections.clear();
        remoteUserIds.clear();
        updateParticipantCount();
        Toast.makeText(this, "通话已挂断", Toast.LENGTH_SHORT).show();
    }
    
    // 新增加入房间方法
    private void joinRoom() {
        try {
            if (roomId == null || roomId.isEmpty()) {
                Toast.makeText(this, "请先输入房间号", Toast.LENGTH_SHORT).show();
                return;
            }
            
            signalingClient.joinRoom(roomId);
            Toast.makeText(this, "加入房间: " + roomId, Toast.LENGTH_SHORT).show();
            meetingTitle.setText("房间号: " + roomId);
        } catch (Exception e) {
            Log.e(TAG, "加入房间失败", e);
            Toast.makeText(this, "加入房间失败: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }
    
    private void leaveRoom() {
        try {
            if (signalingClient != null) {
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
    
    private void updateParticipantCount() {
        int count = 1 + remoteUserIds.size(); // 包括自己
        participantCount.setText("参会人员: " + count + "人");
    }

    // -------------------------- WebRtcSignalingClient.SignalingCallback 实现 --------------------------
    @Override
    public void onConnectSuccess() {
        runOnUiThread(() -> {
            Toast.makeText(this, "WebSocket 连接成功", Toast.LENGTH_SHORT).show();
            // 如果有房间号，在连接成功后自动加入房间
            if (roomId != null && !roomId.isEmpty()) {
                joinRoom();
            }
        });
    }

    @Override
    public void onConnectFailure(String errorMsg) {
        runOnUiThread(() -> Toast.makeText(this, "信令连接失败：" + errorMsg, Toast.LENGTH_SHORT).show());
    }

    @Override
    public void onDisconnect() {
        runOnUiThread(() -> {
            Toast.makeText(this, "信令连接断开", Toast.LENGTH_SHORT).show();
            // 断开 WebRTC 连接
            hangup();
        });
    }

    // 接收对方的 SDP Offer → 生成 Answer 并回复
    @Override
    public void onReceiveOffer(String sdp, String fromUserId) {
        runOnUiThread(() -> {
            try {
                // 创建或获取对应用户的PeerConnection
                PeerConnection peerConnection = getOrCreatePeerConnection(fromUserId);
                
                // 1. 设置对方的 SDP Offer 为 RemoteSDP
                SessionDescription offerSdp = new SessionDescription(SessionDescription.Type.OFFER, sdp);
                peerConnection.setRemoteDescription(new SimpleSdpObserver(), offerSdp);

                // 2. 生成 SDP Answer（WebRTC 核心逻辑）
                peerConnection.createAnswer(new SdpObserver() {
                    @Override
                    public void onCreateSuccess(SessionDescription answerSdp) {
                        try {
                            // 3. 设置本地 Answer 为 LocalSDP
                            peerConnection.setLocalDescription(new SimpleSdpObserver(), answerSdp);
                            // 4. 通过 WebSocket 发送 Answer 给对方
                            signalingClient.sendAnswer(answerSdp.description, fromUserId);
                        } catch (Exception e) {
                            onConnectFailure("设置本地描述或发送Answer失败: " + e.getMessage());
                        }
                    }

                    @Override public void onCreateFailure(String s) {
                        onConnectFailure("创建Answer失败: " + s);
                    }
                    
                    @Override public void onSetSuccess() {}
                    @Override public void onSetFailure(String s) {}
                }, new MediaConstraints());
            } catch (Exception e) {
                onConnectFailure("处理Offer失败: " + e.getMessage());
            }
        });
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
                PeerConnection peerConnection = peerConnections.get(fromUserId);
                if (peerConnection != null) {
                    IceCandidate iceCandidate = new IceCandidate(sdpMid, sdpMLineIndex, candidate);
                    peerConnection.addIceCandidate(iceCandidate);
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
                    }
                    
                    // 作为发起方发送 Offer
                    createAndSendOffer(userId);
                } else if ("userLeft".equals(eventType) && !userId.equals(currentUserId)) {
                    // 有用户离开房间
                    if (remoteUserIds.contains(userId)) {
                        remoteUserIds.remove(userId);
                        updateParticipantCount();
                        Toast.makeText(this, "用户 " + userId + " 离开房间", Toast.LENGTH_SHORT).show();
                    }
                    
                    // 清理该用户的连接
                    PeerConnection peerConnection = peerConnections.remove(userId);
                    if (peerConnection != null) {
                        peerConnection.close();
                        peerConnection.dispose();
                    }
                }
            } catch (Exception e) {
                onConnectFailure("处理房间事件失败: " + e.getMessage());
            }
        });
    }
    
    private PeerConnection getOrCreatePeerConnection(String userId) {
        PeerConnection peerConnection = peerConnections.get(userId);
        if (peerConnection == null) {
            peerConnection = createPeerConnection(userId);
            peerConnections.put(userId, peerConnection);
        }
        return peerConnection;
    }
    
    private PeerConnection createPeerConnection(String userId) {
        // 创建PeerConnection配置
        PeerConnection.RTCConfiguration rtcConfig = new PeerConnection.RTCConfiguration(new ArrayList<>());
        
        // 创建PeerConnection
        PeerConnection peerConnection = peerConnectionFactory.createPeerConnection(rtcConfig, 
            new PeerConnectionObserver(userId));
        
        // 添加本地音视频轨道
        if (localAudioTrack != null) {
            peerConnection.addTrack(localAudioTrack);
        }
        if (localVideoTrack != null) {
            peerConnection.addTrack(localVideoTrack);
        }
        
        return peerConnection;
    }

    // 发起方创建并发送 SDP Offer
    private void createAndSendOffer(String targetUserId) {
        try {
            // 1. 获取或创建PeerConnection
            PeerConnection peerConnection = getOrCreatePeerConnection(targetUserId);

            // 2. 生成 SDP Offer 并发送
            peerConnection.createOffer(new SdpObserver() {
                @Override
                public void onCreateSuccess(SessionDescription offerSdp) {
                    try {
                        peerConnection.setLocalDescription(new SimpleSdpObserver(), offerSdp);
                        signalingClient.sendOffer(offerSdp.description, targetUserId);
                    } catch (Exception e) {
                        onConnectFailure("设置本地描述或发送Offer失败: " + e.getMessage());
                    }
                }

                @Override public void onCreateFailure(String s) {
                    onConnectFailure("创建Offer失败: " + s);
                }
                @Override public void onSetSuccess() {}
                @Override public void onSetFailure(String s) {}
            }, new MediaConstraints());
        } catch (Exception e) {
            onConnectFailure("创建并发送Offer失败: " + e.getMessage());
        }
    }

    // 简化的 SdpObserver 实现（WebRTC 要求必须实现，空实现即可）
    private static class SimpleSdpObserver implements SdpObserver {
        @Override public void onCreateSuccess(SessionDescription sessionDescription) {}
        @Override public void onCreateFailure(String s) {}
        @Override public void onSetSuccess() {}
        @Override public void onSetFailure(String s) {}
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
            signalingClient.sendIceCandidate(iceCandidate.sdp, iceCandidate.sdpMid, 
                iceCandidate.sdpMLineIndex, userId);
        }
        
        @Override
        public void onAddStream(MediaStream mediaStream) {
            // 添加远程媒体流
            runOnUiThread(() -> {
                if (!mediaStream.videoTracks.isEmpty()) {
                    VideoTrack remoteVideoTrack = mediaStream.videoTracks.get(0);
                    remoteVideoTrack.addSink(remoteVideoView);
                }
            });
        }
        
        // 其他必须实现的方法
        @Override public void onSignalingChange(PeerConnection.SignalingState signalingState) {}
        @Override public void onIceConnectionChange(PeerConnection.IceConnectionState iceConnectionState) {}
        @Override public void onIceConnectionReceivingChange(boolean b) {}
        @Override public void onIceGatheringChange(PeerConnection.IceGatheringState iceGatheringState) {}
        @Override public void onIceCandidatesRemoved(IceCandidate[] iceCandidates) {}
        @Override public void onRemoveStream(MediaStream mediaStream) {}
        @Override public void onDataChannel(DataChannel dataChannel) {}
        @Override public void onRenegotiationNeeded() {}
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
            
            // 清理本地轨道
            if (localVideoTrack != null) {
                localVideoTrack.dispose();
            }
            if (videoSource != null) {
                videoSource.dispose();
            }
            if (videoCapturer != null) {
                videoCapturer.dispose();
            }
            if (localAudioTrack != null) {
                localAudioTrack.dispose();
            }
            
            // 清理渲染器
            localVideoView.release();
            remoteVideoView.release();
            
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