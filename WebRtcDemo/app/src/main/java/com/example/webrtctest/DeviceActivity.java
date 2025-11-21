package com.example.webrtctest;

import android.Manifest;
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
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

import org.webrtc.AudioSource;
import org.webrtc.AudioTrack;
import org.webrtc.Camera1Enumerator;
import org.webrtc.CameraEnumerator;
import org.webrtc.CameraVideoCapturer;
import org.webrtc.DefaultVideoDecoderFactory;
import org.webrtc.DefaultVideoEncoderFactory;
import org.webrtc.EglBase;
import org.webrtc.PeerConnectionFactory;
import org.webrtc.SurfaceTextureHelper;
import org.webrtc.SurfaceViewRenderer;
import org.webrtc.VideoSource;
import org.webrtc.VideoTrack;
import org.webrtc.audio.JavaAudioDeviceModule;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

public class DeviceActivity extends AppCompatActivity {
    private static final String TAG = "DeviceActivity";
    private static final int PERMISSION_REQUEST_CODE = 1002;
    
    private TextView deviceInfoText;
    private SurfaceViewRenderer cameraPreview;
    private TextView cameraStatusText;
    private TextView audioStatusText;
    private Button startCameraButton;
    private Button stopCameraButton;
    private Button startAudioTestButton;
    private Button stopAudioTestButton;
    
    // WebRTC相关
    private EglBase eglBase;
    private PeerConnectionFactory peerConnectionFactory;
    private CameraVideoCapturer cameraVideoCapturer;
    private VideoSource videoSource;
    private VideoTrack videoTrack;
    private AudioSource audioSource;
    private AudioTrack audioTrack;
    private SurfaceTextureHelper surfaceTextureHelper; // 添加SurfaceTextureHelper引用
    private boolean isCameraActive = false;
    private boolean isAudioTestActive = false;

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
        checkAndRequestPermissions();
        showDeviceInfo();
    }
    
    private void initViews() {
        deviceInfoText = findViewById(R.id.device_info_text);
        cameraPreview = findViewById(R.id.camera_preview);
        cameraStatusText = findViewById(R.id.camera_status_text);
        audioStatusText = findViewById(R.id.audio_status_text);
        startCameraButton = findViewById(R.id.start_camera_button);
        stopCameraButton = findViewById(R.id.stop_camera_button);
        startAudioTestButton = findViewById(R.id.start_audio_test_button);
        stopAudioTestButton = findViewById(R.id.stop_audio_test_button);
        
        startCameraButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startCameraPreview();
            }
        });
        
        stopCameraButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                stopCameraPreview();
            }
        });
        
        startAudioTestButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startAudioTest();
            }
        });
        
        stopAudioTestButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                stopAudioTest();
            }
        });
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
        return ActivityCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED;
    }
    
    // 检查并请求权限
    private void checkAndRequestPermissions() {
        List<String> permissionsList = new ArrayList<>();
        
        // 检查摄像头权限
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.CAMERA) 
            != PackageManager.PERMISSION_GRANTED) {
            permissionsList.add(Manifest.permission.CAMERA);
        }
        
        // 检查录音权限
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) 
            != PackageManager.PERMISSION_GRANTED) {
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
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.CAMERA) 
                != PackageManager.PERMISSION_GRANTED) {
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
    
    // 启动音频测试
    private void startAudioTest() {
        if (isAudioTestActive) {
            return;
        }
        
        try {
            if (peerConnectionFactory == null) {
                audioStatusText.setText("PeerConnectionFactory未初始化");
                return;
            }
            
            // 检查录音权限
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) 
                != PackageManager.PERMISSION_GRANTED) {
                audioStatusText.setText("缺少录音权限");
                return;
            }
            
            // 创建音频源和轨道
            audioSource = peerConnectionFactory.createAudioSource(null);
            audioTrack = peerConnectionFactory.createAudioTrack("local_audio_track", audioSource);
            audioTrack.setEnabled(true);
            
            isAudioTestActive = true;
            audioStatusText.setText("音频测试运行中 - 正在录制和播放音频");
            startAudioTestButton.setEnabled(false);
            stopAudioTestButton.setEnabled(true);
            
        } catch (Exception e) {
            Log.e(TAG, "启动音频测试失败", e);
            audioStatusText.setText("启动音频测试失败: " + e.getMessage());
        }
    }
    
    // 停止音频测试
    private void stopAudioTest() {
        if (!isAudioTestActive) {
            return;
        }
        
        try {
            if (audioTrack != null) {
                audioTrack.setEnabled(false);
                audioTrack.dispose();
                audioTrack = null;
            }
            
            if (audioSource != null) {
                audioSource.dispose();
                audioSource = null;
            }
            
            isAudioTestActive = false;
            audioStatusText.setText("音频测试已停止");
            startAudioTestButton.setEnabled(true);
            stopAudioTestButton.setEnabled(false);
            
        } catch (Exception e) {
            Log.e(TAG, "停止音频测试失败", e);
            audioStatusText.setText("停止音频测试失败: " + e.getMessage());
        }
    }
    
    @Override
    protected void onDestroy() {
        super.onDestroy();
        stopCameraPreview();
        stopAudioTest();
        
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
    }
}