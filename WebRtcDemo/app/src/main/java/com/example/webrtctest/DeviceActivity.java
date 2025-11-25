package com.example.webrtctest;

import android.Manifest;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.media.AudioTrack;
import android.media.MediaRecorder;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import androidx.activity.EdgeToEdge;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

import org.webrtc.Camera1Enumerator;
import org.webrtc.CameraEnumerator;
import org.webrtc.CameraVideoCapturer;
import org.webrtc.DefaultVideoDecoderFactory;
import org.webrtc.DefaultVideoEncoderFactory;
import org.webrtc.EglBase;
import org.webrtc.MediaConstraints;
import org.webrtc.PeerConnectionFactory;
import org.webrtc.SurfaceTextureHelper;
import org.webrtc.SurfaceViewRenderer;
import org.webrtc.VideoSource;
import org.webrtc.audio.JavaAudioDeviceModule;

import java.util.ArrayList;
import java.util.List;

public class DeviceActivity extends AppCompatActivity implements View.OnClickListener {
    private static final String TAG = "DeviceActivity";
    private static final int PERMISSION_REQUEST_CODE = 1002;
    
    // View IDs缓存，避免在onClick中使用R.id.*导致编译错误
    private static final int START_CAMERA_BUTTON_ID = 1;
    private static final int STOP_CAMERA_BUTTON_ID = 2;
    private static final int START_MICROPHONE_TEST_BUTTON_ID = 3;
    private static final int STOP_MICROPHONE_TEST_BUTTON_ID = 4;
    private static final int START_SPEAKER_TEST_BUTTON_ID = 5;
    private static final int STOP_SPEAKER_TEST_BUTTON_ID = 6;
    
    private TextView deviceInfoText;
    private SurfaceViewRenderer cameraPreview;
    private TextView cameraStatusText;
    private TextView microphoneStatusText;
    private TextView speakerStatusText;
    private ProgressBar microphoneVolumeProgress;
    private Button startCameraButton;
    private Button stopCameraButton;
    private Button startMicrophoneTestButton;
    private Button stopMicrophoneTestButton;
    private Button startSpeakerTestButton;
    private Button stopSpeakerTestButton;
    
    // WebRTC相关
    private EglBase eglBase;
    private PeerConnectionFactory peerConnectionFactory;
    private CameraVideoCapturer cameraVideoCapturer;
    private VideoSource videoSource;
    private org.webrtc.VideoTrack videoTrack;
    private org.webrtc.AudioSource audioSource;
    private org.webrtc.AudioTrack audioTrack;
    private SurfaceTextureHelper surfaceTextureHelper;
    private boolean isCameraActive = false;
    private boolean isMicrophoneTestActive = false;
    private boolean isSpeakerTestActive = false;
    
    // 音频测试相关
    private Handler audioHandler = new Handler(Looper.getMainLooper());
    private Runnable audioLevelRunnable;
    private AudioTrack audioPlayer;
    private AudioRecord audioRecord;
    private Thread audioRecordThread;
    // 生成测试音频数据（440Hz正弦波）
    private byte[] audioTestData;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        EdgeToEdge.enable(this);
        setContentView(R.layout.activity_device);
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.main), (v, insets) -> {
            Insets systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars());
            v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom);
            return insets;
        });
        
        initViews();
        initWebRTC();
        generateAudioTestData();
        checkAndRequestPermissions();
        showDeviceInfo();
    }
    
    private void initViews() {
        deviceInfoText = findViewById(R.id.device_info_text);
        cameraPreview = findViewById(R.id.camera_preview);
        cameraStatusText = findViewById(R.id.camera_status_text);
        microphoneStatusText = findViewById(R.id.microphone_status_text);
        speakerStatusText = findViewById(R.id.speaker_status_text);
        microphoneVolumeProgress = findViewById(R.id.microphone_volume_progress);
        startCameraButton = findViewById(R.id.start_camera_button);
        stopCameraButton = findViewById(R.id.stop_camera_button);
        startMicrophoneTestButton = findViewById(R.id.start_microphone_test_button);
        stopMicrophoneTestButton = findViewById(R.id.stop_microphone_test_button);
        startSpeakerTestButton = findViewById(R.id.start_speaker_test_button);
        stopSpeakerTestButton = findViewById(R.id.stop_speaker_test_button);
        
        // 设置按钮ID以避免使用R.id.*
        startCameraButton.setId(START_CAMERA_BUTTON_ID);
        stopCameraButton.setId(STOP_CAMERA_BUTTON_ID);
        startMicrophoneTestButton.setId(START_MICROPHONE_TEST_BUTTON_ID);
        stopMicrophoneTestButton.setId(STOP_MICROPHONE_TEST_BUTTON_ID);
        startSpeakerTestButton.setId(START_SPEAKER_TEST_BUTTON_ID);
        stopSpeakerTestButton.setId(STOP_SPEAKER_TEST_BUTTON_ID);
        
        startCameraButton.setOnClickListener(this);
        stopCameraButton.setOnClickListener(this);
        startMicrophoneTestButton.setOnClickListener(this);
        stopMicrophoneTestButton.setOnClickListener(this);
        startSpeakerTestButton.setOnClickListener(this);
        stopSpeakerTestButton.setOnClickListener(this);
    }
    
    // 实现OnClickListener接口
    @Override
    public void onClick(View v) {
        switch (v.getId()) {
            case START_CAMERA_BUTTON_ID:
                startCameraPreview();
                break;
            case STOP_CAMERA_BUTTON_ID:
                stopCameraPreview();
                break;
            case START_MICROPHONE_TEST_BUTTON_ID:
                startMicrophoneTest();
                break;
            case STOP_MICROPHONE_TEST_BUTTON_ID:
                stopMicrophoneTest();
                break;
            case START_SPEAKER_TEST_BUTTON_ID:
                startSpeakerTest();
                break;
            case STOP_SPEAKER_TEST_BUTTON_ID:
                stopSpeakerTest();
                break;
        }
    }
    
    private void initWebRTC() {
        try {
            eglBase = EglBase.create();
            cameraPreview.init(eglBase.getEglBaseContext(), null);
            
            // 初始化PeerConnectionFactory
            PeerConnectionFactory.InitializationOptions initializationOptions = 
                PeerConnectionFactory.InitializationOptions.builder(this)
                    .setEnableInternalTracer(true)
                    .createInitializationOptions();
            PeerConnectionFactory.initialize(initializationOptions);
            
            PeerConnectionFactory.Options options = new PeerConnectionFactory.Options();
            
            peerConnectionFactory = PeerConnectionFactory.builder()
                .setOptions(options)
                .setVideoEncoderFactory(new DefaultVideoEncoderFactory(
                    eglBase.getEglBaseContext(), true, true))
                .setVideoDecoderFactory(new DefaultVideoDecoderFactory(eglBase.getEglBaseContext()))
                .setAudioDeviceModule(JavaAudioDeviceModule.builder(this).createAudioDeviceModule())
                .createPeerConnectionFactory();
                
        } catch (Exception e) {
            Log.e(TAG, "初始化WebRTC失败", e);
            cameraStatusText.setText("WebRTC初始化失败: " + e.getMessage());
        }
    }
    
    private void showDeviceInfo() {
        StringBuilder deviceInfo = new StringBuilder();
        deviceInfo.append("音视频设备信息\n\n");
        
        // 摄像头信息
        deviceInfo.append("摄像头信息:\n");
        CameraEnumerator enumerator = new Camera1Enumerator(false);
        String[] deviceNames = enumerator.getDeviceNames();
        if (deviceNames.length > 0) {
            for (int i = 0; i < deviceNames.length; i++) {
                String facing = enumerator.isFrontFacing(deviceNames[i]) ? "前置摄像头" : "后置摄像头";
                deviceInfo.append("  摄像头").append(i + 1).append(": ").append(deviceNames[i]).append(" (").append(facing).append(")\n");
            }
        } else {
            deviceInfo.append("  未检测到摄像头\n");
        }
        
        deviceInfo.append("\n");
        
        // 音频信息
        deviceInfo.append("音频设备信息:\n");
        deviceInfo.append("  麦克风: ").append(checkPermission(Manifest.permission.RECORD_AUDIO) ? "可用" : "无权限").append("\n");
        deviceInfo.append("  扬声器: 系统默认\n");
        
        deviceInfo.append("\n");
        
        // 系统信息（仅与音视频相关的部分）
        deviceInfo.append("系统信息:\n");
        deviceInfo.append("  Android版本: ").append(Build.VERSION.RELEASE).append(" (API ").append(Build.VERSION.SDK_INT).append(")\n");
        deviceInfo.append("  设备名称: ").append(Build.MANUFACTURER).append(" ").append(Build.MODEL).append("\n");
        
        deviceInfoText.setText(deviceInfo.toString());
    }
    
    // 检查权限状态
    private boolean checkPermission(String permission) {
        return ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED;
    }
    
    // 检查并请求权限
    private void checkAndRequestPermissions() {
        List<String> permissionsList = new ArrayList<>();
        
        // 检查摄像头权限
        if (!checkPermission(Manifest.permission.CAMERA)) {
            permissionsList.add(Manifest.permission.CAMERA);
        }
        
        // 检查录音权限
        if (!checkPermission(Manifest.permission.RECORD_AUDIO)) {
            permissionsList.add(Manifest.permission.RECORD_AUDIO);
        }
        
        if (!permissionsList.isEmpty()) {
            String[] permissions = new String[permissionsList.size()];
            permissions = permissionsList.toArray(permissions);
            ActivityCompat.requestPermissions(this, permissions, PERMISSION_REQUEST_CODE);
        }
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
            
            if (!allPermissionsGranted) {
                Toast.makeText(this, "部分权限被拒绝，摄像头和音频测试功能可能无法正常工作", Toast.LENGTH_LONG).show();
            }
            
            // 更新设备信息显示
            showDeviceInfo();
        }
    }
    
    // 启动摄像头预览
    private void startCameraPreview() {
        if (isCameraActive) {
            return;
        }
        
        try {
            if (peerConnectionFactory == null) {
                cameraStatusText.setText("PeerConnectionFactory未初始化");
                return;
            }
            
            // 检查摄像头权限
            if (!checkPermission(Manifest.permission.CAMERA)) {
                cameraStatusText.setText("缺少摄像头权限");
                return;
            }
            
            // 创建摄像头捕获器
            CameraEnumerator enumerator = new Camera1Enumerator(false);
            String[] deviceNames = enumerator.getDeviceNames();
            
            if (deviceNames.length == 0) {
                cameraStatusText.setText("未找到摄像头设备");
                return;
            }
            
            // 使用第一个可用的摄像头
            for (String deviceName : deviceNames) {
                if (enumerator.isFrontFacing(deviceName)) {
                    cameraVideoCapturer = enumerator.createCapturer(deviceName, null);
                    break;
                }
            }
            
            // 如果没有前置摄像头，使用后置摄像头
            if (cameraVideoCapturer == null) {
                cameraVideoCapturer = enumerator.createCapturer(deviceNames[0], null);
            }
            
            if (cameraVideoCapturer == null) {
                cameraStatusText.setText("无法创建摄像头捕获器");
                return;
            }
            
            // 创建视频源和轨道
            videoSource = peerConnectionFactory.createVideoSource(false);
            
            // 创建SurfaceTextureHelper并正确初始化摄像头捕获器
            surfaceTextureHelper = SurfaceTextureHelper.create("CaptureThread", eglBase.getEglBaseContext());
            cameraVideoCapturer.initialize(surfaceTextureHelper, this, videoSource.getCapturerObserver());
            cameraVideoCapturer.startCapture(640, 480, 30);
            
            videoTrack = peerConnectionFactory.createVideoTrack("local_video_track", videoSource);
            videoTrack.addSink(cameraPreview);
            
            isCameraActive = true;
            cameraStatusText.setText("摄像头运行中");
            startCameraButton.setEnabled(false);
            stopCameraButton.setEnabled(true);
            
        } catch (Exception e) {
            Log.e(TAG, "启动摄像头预览失败", e);
            cameraStatusText.setText("启动摄像头失败: " + e.getMessage());
        }
    }
    
    // 停止摄像头预览
    private void stopCameraPreview() {
        if (!isCameraActive) {
            return;
        }
        
        try {
            if (videoTrack != null) {
                videoTrack.removeSink(cameraPreview);
                videoTrack.dispose();
                videoTrack = null;
            }
            
            if (cameraVideoCapturer != null) {
                cameraVideoCapturer.stopCapture();
                cameraVideoCapturer.dispose();
                cameraVideoCapturer = null;
            }
            
            if (videoSource != null) {
                videoSource.dispose();
                videoSource = null;
            }
            
            // 释放SurfaceTextureHelper
            if (surfaceTextureHelper != null) {
                surfaceTextureHelper.dispose();
                surfaceTextureHelper = null;
            }
            
            isCameraActive = false;
            cameraStatusText.setText("摄像头已停止");
            startCameraButton.setEnabled(true);
            stopCameraButton.setEnabled(false);
            
        } catch (Exception e) {
            Log.e(TAG, "停止摄像头预览失败", e);
            cameraStatusText.setText("停止摄像头失败: " + e.getMessage());
        }
    }
    
    // 生成测试音频数据
    private void generateAudioTestData() {
        int sampleRate = 44100;
        int frequency = 440; // 440Hz 正弦波 (A4音符)
        int durationMillis = 1000; // 1秒
        int numSamples = sampleRate * durationMillis / 1000;
        
        audioTestData = new byte[numSamples * 2]; // 16位音频 = 2字节/采样
        
        for (int i = 0; i < numSamples; i++) {
            // 生成正弦波
            double angle = 2 * Math.PI * i * frequency / sampleRate;
            short sample = (short) (Math.sin(angle) * Short.MAX_VALUE * 0.1); // 降低音量避免刺耳
            
            // 转换为小端序字节
            audioTestData[i * 2] = (byte) (sample & 0xFF);
            audioTestData[i * 2 + 1] = (byte) ((sample >> 8) & 0xFF);
        }
    }
    
    // 启动麦克风测试
    private void startMicrophoneTest() {
        if (isMicrophoneTestActive) {
            return;
        }
        
        try {
            // 检查录音权限
            if (!checkPermission(Manifest.permission.RECORD_AUDIO)) {
                microphoneStatusText.setText("缺少录音权限");
                return;
            }
            
            int sampleRate = 44100;
            int channelConfig = AudioFormat.CHANNEL_IN_MONO;
            int audioFormat = AudioFormat.ENCODING_PCM_16BIT;
            
            int bufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat);
            if (bufferSize == AudioRecord.ERROR || bufferSize == AudioRecord.ERROR_BAD_VALUE) {
                bufferSize = sampleRate * 2; // 默认缓冲区大小
            }
            
            // 创建AudioRecord用于录制测试音频
            audioRecord = new AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                channelConfig,
                audioFormat,
                bufferSize
            );
            
            isMicrophoneTestActive = true;
            microphoneStatusText.setText("麦克风测试运行中 - 监听中...");
            microphoneVolumeProgress.setVisibility(View.VISIBLE);
            startMicrophoneTestButton.setEnabled(false);
            stopMicrophoneTestButton.setEnabled(true);
            
            // 开始监听音频级别
            startAudioLevelMonitoring();
            
        } catch (Exception e) {
            Log.e(TAG, "启动麦克风测试失败", e);
            microphoneStatusText.setText("启动麦克风测试失败: " + e.getMessage());
            isMicrophoneTestActive = false;
        }
    }
    
    // 停止麦克风测试
    private void stopMicrophoneTest() {
        if (!isMicrophoneTestActive) {
            return;
        }
        
        try {
            // 停止监听音频级别
            stopAudioLevelMonitoring();
            
            if (audioRecord != null) {
                if (audioRecord.getRecordingState() == AudioRecord.RECORDSTATE_RECORDING) {
                    audioRecord.stop();
                }
                audioRecord.release();
                audioRecord = null;
            }
            
            isMicrophoneTestActive = false;
            microphoneStatusText.setText("麦克风测试已停止");
            microphoneVolumeProgress.setVisibility(View.GONE);
            microphoneVolumeProgress.setProgress(0);
            startMicrophoneTestButton.setEnabled(true);
            stopMicrophoneTestButton.setEnabled(false);
            
        } catch (Exception e) {
            Log.e(TAG, "停止麦克风测试失败", e);
            microphoneStatusText.setText("停止麦克风测试失败: " + e.getMessage());
        }
    }
    
    // 开始监听音频级别
    private void startAudioLevelMonitoring() {
        if (audioRecord != null) {
            audioRecord.startRecording();
        }
        
        audioRecordThread = new Thread(new Runnable() {
            @Override
            public void run() {
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO);
                short[] buffer = new short[1024];
                
                while (isMicrophoneTestActive && audioRecord != null) {
                    try {
                        int readSize = audioRecord.read(buffer, 0, buffer.length);
                        if (readSize > 0) {
                            // 计算音量级别
                            long sum = 0;
                            for (int i = 0; i < readSize; i++) {
                                sum += Math.abs(buffer[i]);
                            }
                            double average = sum / (double) readSize;
                            final int levelPercent = (int) (average / 32768.0 * 100); // 转换为百分比
                            
                            // 更新UI显示音量级别
                            runOnUiThread(new Runnable() {
                                @Override
                                public void run() {
                                    microphoneStatusText.setText("麦克风测试运行中 - 音量级别: " + levelPercent + "%");
                                    microphoneVolumeProgress.setProgress(levelPercent);
                                }
                            });
                        }
                        
                        // 短暂休眠以控制更新频率
                        Thread.sleep(100);
                    } catch (Exception e) {
                        Log.e(TAG, "音频级别监测异常", e);
                        break;
                    }
                }
            }
        });
        audioRecordThread.start();
    }
    
    // 停止监听音频级别
    private void stopAudioLevelMonitoring() {
        if (audioRecordThread != null) {
            try {
                audioRecordThread.join(1000); // 等待最多1秒
            } catch (InterruptedException e) {
                Log.w(TAG, "等待音频记录线程结束时被中断", e);
            }
            audioRecordThread = null;
        }
    }
    
    // 启动扬声器测试
    private void startSpeakerTest() {
        if (isSpeakerTestActive) {
            return;
        }
        
        try {
            // 创建AudioTrack用于播放测试音频
            int sampleRate = 44100;
            int channelConfig = AudioFormat.CHANNEL_OUT_MONO;
            int audioFormat = AudioFormat.ENCODING_PCM_16BIT;
            
            int bufferSize = AudioTrack.getMinBufferSize(sampleRate, channelConfig, audioFormat);
            if (bufferSize == AudioTrack.ERROR || bufferSize == AudioTrack.ERROR_BAD_VALUE) {
                bufferSize = sampleRate * 2; // 默认缓冲区大小
            }
            
            // 兼容性处理：在不同Android版本上使用不同的创建方式
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                audioPlayer = new AudioTrack.Builder()
                    .setAudioAttributes(new android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build())
                    .setAudioFormat(new AudioFormat.Builder()
                        .setSampleRate(sampleRate)
                        .setChannelMask(channelConfig)
                        .setEncoding(audioFormat)
                        .build())
                    .setBufferSizeInBytes(bufferSize)
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .build();
            } else {
                audioPlayer = new AudioTrack(
                    AudioManager.STREAM_MUSIC,
                    sampleRate,
                    channelConfig,
                    audioFormat,
                    bufferSize,
                    AudioTrack.MODE_STATIC
                );
            }
            
            // 加载测试音频数据
            audioPlayer.write(audioTestData, 0, audioTestData.length);
            
            isSpeakerTestActive = true;
            speakerStatusText.setText("扬声器测试运行中 - 播放测试音频...");
            startSpeakerTestButton.setEnabled(false);
            stopSpeakerTestButton.setEnabled(true);
            
            // 开始播放
            audioPlayer.play();
            
            // 播放完成后自动停止
            audioHandler.postDelayed(new Runnable() {
                @Override
                public void run() {
                    stopSpeakerTest();
                }
            }, 1000); // 1秒后停止
            
        } catch (Exception e) {
            Log.e(TAG, "启动扬声器测试失败", e);
            speakerStatusText.setText("启动扬声器测试失败: " + e.getMessage());
            isSpeakerTestActive = false;
            startSpeakerTestButton.setEnabled(true);
            stopSpeakerTestButton.setEnabled(false);
        }
    }
    
    // 停止扬声器测试
    private void stopSpeakerTest() {
        if (!isSpeakerTestActive) {
            return;
        }
        
        try {
            if (audioPlayer != null) {
                if (audioPlayer.getPlayState() == AudioTrack.PLAYSTATE_PLAYING) {
                    audioPlayer.stop();
                }
                audioPlayer.release();
                audioPlayer = null;
            }
            
            isSpeakerTestActive = false;
            speakerStatusText.setText("扬声器测试已停止");
            startSpeakerTestButton.setEnabled(true);
            stopSpeakerTestButton.setEnabled(false);
            
        } catch (Exception e) {
            Log.e(TAG, "停止扬声器测试失败", e);
            speakerStatusText.setText("停止扬声器测试失败: " + e.getMessage());
        }
    }
    
    @Override
    protected void onDestroy() {
        super.onDestroy();
        stopCameraPreview();
        stopMicrophoneTest();
        stopSpeakerTest();
        
        if (cameraPreview != null) {
            cameraPreview.release();
        }
        
        if (eglBase != null) {
            eglBase.release();
        }
        
        // 确保释放SurfaceTextureHelper
        if (surfaceTextureHelper != null) {
            surfaceTextureHelper.dispose();
            surfaceTextureHelper = null;
        }
        
        // 清理音频处理相关的Handler回调
        if (audioHandler != null) {
            audioHandler.removeCallbacksAndMessages(null);
        }
    }
}