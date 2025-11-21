package com.example.webrtctest;

import android.os.Bundle;
import android.widget.ImageButton;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import org.webrtc.AudioTrack;
import org.webrtc.DefaultVideoDecoderFactory;
import org.webrtc.DefaultVideoEncoderFactory;
import org.webrtc.EglBase;
import org.webrtc.IceCandidate;
import org.webrtc.MediaConstraints;
import org.webrtc.PeerConnection;
import org.webrtc.PeerConnectionFactory;
import org.webrtc.SdpObserver;
import org.webrtc.SessionDescription;
import org.webrtc.SurfaceViewRenderer;
import org.webrtc.VideoTrack;
import org.webrtc.audio.JavaAudioDeviceModule;

import java.net.URISyntaxException;

public class WebRtcActivity extends AppCompatActivity implements WebRtcSignalingClient.SignalingCallback {
    private WebRtcSignalingClient signalingClient;
    private PeerConnectionFactory peerConnectionFactory;
    private PeerConnection peerConnection;
    private String currentUserId = "android_" + System.currentTimeMillis(); // 唯一用户 ID
    private String targetUserId; // 通话对方的用户 ID
    private String signalingServerUrl = "ws://your-signaling-server.com:8080/webrtc-signal"; // 项目信令服务器地址
    private Object mediaProjection; // 需要从其他地方获取该对象

    // UI组件
    private SurfaceViewRenderer localVideoView;
    private SurfaceViewRenderer remoteVideoView;
    private ImageButton muteAudioButton;
    private ImageButton muteVideoButton;
    private ImageButton joinRoomButton;
    private ImageButton hangupButton;
    private ImageButton switchCameraButton;
    private TextView meetingTitle;
    private TextView participantCount;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_webrtc);

        // 初始化UI组件
        initUI();

        // 1. 初始化 WebRTC 核心工厂（之前已讲，此处简化）
        initPeerConnectionFactory();

        // 2. 初始化信令客户端（Java-WebSocket）
        try {
            signalingClient = new WebRtcSignalingClient(signalingServerUrl, currentUserId, this);
            signalingClient.connectAsync(); // 异步建立 WebSocket 连接
        } catch (URISyntaxException e) {
            e.printStackTrace();
            Toast.makeText(this, "信令服务器地址错误", Toast.LENGTH_SHORT).show();
        }

        // 3. 设置按钮点击事件
        setupButtonListeners();
    }

    private void initUI() {
        localVideoView = findViewById(R.id.local_video_view);
        remoteVideoView = findViewById(R.id.remote_video_view);
        muteAudioButton = findViewById(R.id.btn_mute_audio);
        muteVideoButton = findViewById(R.id.btn_mute_video);
        joinRoomButton = findViewById(R.id.btn_join_room);
        hangupButton = findViewById(R.id.btn_hangup);
        switchCameraButton = findViewById(R.id.btn_switch_camera);
        meetingTitle = findViewById(R.id.meeting_title);
        participantCount = findViewById(R.id.participant_count);
    }

    private void setupButtonListeners() {
        // 麦克风开关
        muteAudioButton.setOnClickListener(v -> {
            // 实现麦克风开关逻辑
            Toast.makeText(this, "麦克风开关", Toast.LENGTH_SHORT).show();
        });

        // 视频开关
        muteVideoButton.setOnClickListener(v -> {
            // 实现摄像头开关逻辑
            Toast.makeText(this, "摄像头开关", Toast.LENGTH_SHORT).show();
        });

        // 加入房间
        joinRoomButton.setOnClickListener(v -> {
            try {
                signalingClient.joinRoom("test_room_123");
                Toast.makeText(this, "加入房间", Toast.LENGTH_SHORT).show();
            } catch (Exception e) {
                Toast.makeText(this, "加入房间失败: " + e.getMessage(), Toast.LENGTH_SHORT).show();
            }
        });

        // 挂断
        hangupButton.setOnClickListener(v -> {
            // 实现挂断逻辑
            try {
                if (signalingClient != null) {
                    signalingClient.leaveRoom();
                }
                Toast.makeText(this, "挂断", Toast.LENGTH_SHORT).show();
            } catch (Exception e) {
                Toast.makeText(this, "挂断失败: " + e.getMessage(), Toast.LENGTH_SHORT).show();
            }
        });

        // 切换摄像头
        switchCameraButton.setOnClickListener(v -> {
            // 实现切换摄像头逻辑
            Toast.makeText(this, "切换摄像头", Toast.LENGTH_SHORT).show();
        });
    }

    // 初始化 PeerConnectionFactory（WebRTC 核心，之前已详细讲解）
    private void initPeerConnectionFactory() {
        try {
            EglBase eglBase = EglBase.create();
            PeerConnectionFactory.InitializationOptions initOptions = PeerConnectionFactory.InitializationOptions.builder(this)
                    .setEnableInternalTracer(true)
                    .createInitializationOptions();
            PeerConnectionFactory.initialize(initOptions);
            peerConnectionFactory = PeerConnectionFactory.builder()
                    .setVideoEncoderFactory(new DefaultVideoEncoderFactory(eglBase.getEglBaseContext(), true, true))
                    .setVideoDecoderFactory(new DefaultVideoDecoderFactory(eglBase.getEglBaseContext()))
                    .setAudioDeviceModule(JavaAudioDeviceModule.builder(this).createAudioDeviceModule())
                    .createPeerConnectionFactory();
        } catch (Exception e) {
            Toast.makeText(this, "初始化PeerConnectionFactory失败: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    // -------------------------- WebRtcSignalingClient.SignalingCallback 实现 --------------------------
    @Override
    public void onConnectSuccess() {
        runOnUiThread(() -> Toast.makeText(this, "WebSocket 连接成功", Toast.LENGTH_SHORT).show());
    }

    @Override
    public void onConnectFailure(String errorMsg) {
        runOnUiThread(() -> Toast.makeText(this, "信令连接失败：" + errorMsg, Toast.LENGTH_SHORT).show());
    }

    @Override
    public void onDisconnect() {
        runOnUiThread(() -> Toast.makeText(this, "信令连接断开", Toast.LENGTH_SHORT).show());
        // 断开 WebRTC 连接
        if (peerConnection != null) {
            try {
                peerConnection.close();
                peerConnection.dispose();
            } catch (Exception e) {
                Toast.makeText(this, "关闭PeerConnection失败: " + e.getMessage(), Toast.LENGTH_SHORT).show();
            }
        }
    }

    // 接收对方的 SDP Offer → 生成 Answer 并回复
    @Override
    public void onReceiveOffer(String sdp, String fromUserId) {
        try {
            targetUserId = fromUserId;
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
                        signalingClient.sendAnswer(answerSdp.description, targetUserId);
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
    }

    // 接收对方的 SDP Answer → 设置为 RemoteSDP
    @Override
    public void onReceiveAnswer(String sdp, String fromUserId) {
        try {
            SessionDescription answerSdp = new SessionDescription(SessionDescription.Type.ANSWER, sdp);
            peerConnection.setRemoteDescription(new SimpleSdpObserver(), answerSdp);
        } catch (Exception e) {
            onConnectFailure("处理Answer失败: " + e.getMessage());
        }
    }

    // 接收对方的 ICE 候选 → 添加到 PeerConnection
    @Override
    public void onReceiveIceCandidate(String candidate, String sdpMid, int sdpMLineIndex, String fromUserId) {
        try {
            IceCandidate iceCandidate = new IceCandidate(sdpMid, sdpMLineIndex, candidate);
            peerConnection.addIceCandidate(iceCandidate);
        } catch (Exception e) {
            onConnectFailure("处理ICE候选失败: " + e.getMessage());
        }
    }

    // 房间事件（如其他用户加入，触发 WebRTC 连接建立）
    @Override
    public void onRoomEvent(String eventType, String roomId, String userId) {
        try {
            if ("userJoined".equals(eventType) && !userId.equals(currentUserId)) {
                // 有其他用户加入房间，作为发起方发送 Offer
                targetUserId = userId;
                createAndSendOffer();
            }
        } catch (Exception e) {
            onConnectFailure("处理房间事件失败: " + e.getMessage());
        }
    }

    // 发起方创建并发送 SDP Offer
    private void createAndSendOffer() {
        try {
            // 1. 捕获麦克风+屏幕流（之前已讲，此处简化，假设已创建 audioTrack 和 videoTrack）
            AudioTrack audioTrack = createAudioTrack();
            VideoTrack videoTrack = createScreenVideoTrack(mediaProjection); // mediaProjection 需提前申请

            // 2. 创建 PeerConnection（配置 STUN/TURN 服务器）
            createPeerConnection();

            // 3. 添加音视频轨道到 PeerConnection
            if (peerConnection != null && audioTrack != null) {
                peerConnection.addTrack(audioTrack);
            }
            if (peerConnection != null && videoTrack != null) {
                peerConnection.addTrack(videoTrack);
            }

            // 4. 生成 SDP Offer 并发送
            if (peerConnection != null) {
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
            }
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
    
    // 缺失的方法需要补充完整
    private void createPeerConnection() {
        // 实现创建PeerConnection的逻辑
        try {
            // 这里应该实现PeerConnection的创建逻辑
        } catch (Exception e) {
            onConnectFailure("创建PeerConnection失败: " + e.getMessage());
        }
    }
    
    private AudioTrack createAudioTrack() {
        // 实现创建AudioTrack的逻辑
        try {
            // 这里应该实现AudioTrack的创建逻辑
            return null;
        } catch (Exception e) {
            onConnectFailure("创建AudioTrack失败: " + e.getMessage());
            return null;
        }
    }
    
    private VideoTrack createScreenVideoTrack(Object mediaProjection) {
        // 实现创建Screen Video Track的逻辑
        try {
            // 这里应该实现VideoTrack的创建逻辑
            return null;
        } catch (Exception e) {
            onConnectFailure("创建VideoTrack失败: " + e.getMessage());
            return null;
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        try {
            if (signalingClient != null) {
                signalingClient.disconnectAsync();
            }
            if (peerConnection != null) {
                peerConnection.close();
                peerConnection.dispose();
            }
        } catch (Exception e) {
            Toast.makeText(this, "销毁资源失败: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }
}