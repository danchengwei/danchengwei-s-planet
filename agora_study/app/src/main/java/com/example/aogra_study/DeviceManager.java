package com.example.aogra_study;

import android.content.Context;
import android.util.Log;
import android.view.SurfaceView;
import android.view.TextureView;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.agora.rtc2.RtcEngine;
import io.agora.rtc2.RtcEngineConfig;
import io.agora.rtc2.IRtcEngineEventHandler;
import io.agora.rtc2.video.VideoCanvas;
import io.agora.rtc2.video.VideoEncoderConfiguration;
import io.agora.rtc2.video.CameraCapturerConfiguration;
import io.agora.rtc2.video.VideoSubscriptionOptions;
import io.agora.rtc2.Constants;
import io.agora.rtc2.DeviceInfo;

/**
 * 设备管理和音视频流控制器
 * 负责设备管理、视频流控制、音频流控制、渲染播放等功能
 */
public class DeviceManager {
    private static final String TAG = "DeviceManager";
    
    private RtcEngine rtcEngine;
    private Context context;
    private String appId;
    
    // 存储设备信息
    private Map<String, String> audioDevices = new HashMap<>();
    private Map<String, String> videoDevices = new HashMap<>();
    
    // 存储视频渲染视图
    private Map<Integer, Object> localVideoViews = new HashMap<>(); // uid -> view
    private Map<Integer, Object> remoteVideoViews = new HashMap<>(); // uid -> view
    
    // 流控制状态
    private boolean isLocalVideoEnabled = true;
    private boolean isLocalAudioEnabled = true;
    private boolean isRemoteVideoEnabled = true;
    private boolean isRemoteAudioEnabled = true;
    
    // 房间事件监听器
    private RoomEventListener roomEventListener;
    
    public interface RoomEventListener {
        void onUserJoined(int uid);
        void onUserLeft(int uid);
        void onJoinChannelSuccess(String channel, int uid, int elapsed);
    }
    
    public void setRoomEventListener(RoomEventListener listener) {
        this.roomEventListener = listener;
    }
    
    public DeviceManager(Context context, String appId) {
        this.context = context;
        this.appId = appId;
    }
    
    /**
     * 初始化设备管理器
     */
    public void initialize() throws Exception {
        RtcEngineConfig config = new RtcEngineConfig();
        config.mContext = context;
        config.mAppId = appId;
        config.mEventHandler = new IRtcEngineEventHandler() {
            @Override
            public void onJoinChannelSuccess(String channel, int uid, int elapsed) {
                Log.d("Agora", "=== DeviceManager.onJoinChannelSuccess 被调用 ===");
                Log.d("Agora", "频道名称: " + channel);
                Log.d("Agora", "用户ID: " + uid);
                Log.d("Agora", "耗时: " + elapsed + "ms");
                
                // 加入频道成功
                if (roomEventListener != null) {
                    Log.d("Agora", "DeviceManager 准备通知 RoomManager.onJoinChannelSuccess");
                    roomEventListener.onJoinChannelSuccess(channel, uid, elapsed);
                } else {
                    Log.e("Agora", "roomEventListener 为 null，无法通知 RoomManager");
                }
                
                Log.d("Agora", "=== DeviceManager.onJoinChannelSuccess 完成 ===");
            }
            
            @Override
            public void onUserJoined(int uid, int elapsed) {
                Log.d("Agora", "=== DeviceManager.onUserJoined 被调用 ===");
                Log.d("Agora", "用户ID: " + uid);
                Log.d("Agora", "耗时: " + elapsed + "ms");
                
                // 用户加入
                if (roomEventListener != null) {
                    Log.d("Agora", "DeviceManager 准备通知 RoomManager.onUserJoined");
                    roomEventListener.onUserJoined(uid);
                } else {
                    Log.e("Agora", "roomEventListener 为 null，无法通知 RoomManager");
                }
                
                Log.d("Agora", "=== DeviceManager.onUserJoined 完成 ===");
            }
            
            @Override
            public void onUserOffline(int uid, int reason) {
                Log.d("Agora", "=== DeviceManager.onUserOffline 被调用 ===");
                Log.d("Agora", "用户ID: " + uid);
                Log.d("Agora", "离开原因: " + reason);
                
                // 用户离开
                if (deviceStatusListener != null) {
                    deviceStatusListener.onRemoteVideoStateChanged(uid, false);
                }
                
                if (roomEventListener != null) {
                    Log.d("Agora", "DeviceManager 准备通知 RoomManager.onUserLeft");
                    roomEventListener.onUserLeft(uid);
                } else {
                    Log.e("Agora", "roomEventListener 为 null，无法通知 RoomManager");
                }
                
                Log.d("Agora", "=== DeviceManager.onUserOffline 完成 ===");
            }
            
            @Override
            public void onRemoteVideoStateChanged(int uid, int state, int reason, int elapsed) {
                // 远程视频状态变化
                boolean enabled = (state == Constants.REMOTE_VIDEO_STATE_DECODING || 
                                  state == Constants.REMOTE_VIDEO_STATE_STARTING);
                if (deviceStatusListener != null) {
                    deviceStatusListener.onRemoteVideoStateChanged(uid, enabled);
                }
            }
            
            @Override
            public void onRemoteAudioStateChanged(int uid, int state, int reason, int elapsed) {
                // 远程音频状态变化
                boolean enabled = (state == Constants.REMOTE_AUDIO_STATE_DECODING || 
                                  state == Constants.REMOTE_AUDIO_STATE_STARTING);
                if (deviceStatusListener != null) {
                    deviceStatusListener.onAudioQualityChanged(uid, state);
                }
            }
            
            @Override
            public void onLocalVideoStateChanged(io.agora.rtc2.Constants.VideoSourceType sourceType, int localVideoState, int error) {
                // 本地视频状态变化
                boolean enabled = (localVideoState == Constants.LOCAL_VIDEO_STREAM_STATE_CAPTURING || 
                                  localVideoState == Constants.LOCAL_VIDEO_STREAM_STATE_ENCODING);
                if (deviceStatusListener != null) {
                    deviceStatusListener.onLocalVideoStateChanged(enabled);
                }
            }
            
            @Override
            public void onAudioRouteChanged(int routing) {
                // 音频路由变化
                if (deviceStatusListener != null) {
                    String deviceName = getAudioRouteName(routing);
                    deviceStatusListener.onAudioDeviceChanged(String.valueOf(routing), deviceName);
                }
            }
        };
        
        rtcEngine = RtcEngine.create(config);
        
        // 启用视频模块
        rtcEngine.enableVideo();
    }
    
    /**
     * 根据音频路由值获取设备名称
     */
    private String getAudioRouteName(int routing) {
        switch (routing) {
            case Constants.AUDIO_ROUTE_DEFAULT:
                return "Default";
            case Constants.AUDIO_ROUTE_HEADSET:
                return "Headset";
            case Constants.AUDIO_ROUTE_EARPIECE:
                return "Earpiece";
            case Constants.AUDIO_ROUTE_HEADSETNOMIC:
                return "Headset with Mic";
            case Constants.AUDIO_ROUTE_SPEAKERPHONE:
                return "Speakerphone";
            case Constants.AUDIO_ROUTE_LOUDSPEAKER:
                return "Loud Speaker";
            case Constants.AUDIO_ROUTE_BLUETOOTH_DEVICE_HFP:
                return "Bluetooth HFP";
            case Constants.AUDIO_ROUTE_USBDEVICE:
                return "USB Device";
            case Constants.AUDIO_ROUTE_USB_HEADSET:
                return "USB Headset";
            case Constants.AUDIO_ROUTE_BLUETOOTH_DEVICE_A2DP:
                return "Bluetooth A2DP";
            default:
                return "Unknown Audio Route: " + routing;
        }
    }
    
    /**
     * 获取音频设备信息
     */
    public DeviceInfo getAudioDeviceInfo() {
        if (rtcEngine != null) {
            return rtcEngine.getAudioDeviceInfo();
        }
        return null;
    }
    
    /**
     * 列出可用的音频录制设备
     */
    public List<String> listAudioRecordingDevices() {
        List<String> devices = new ArrayList<>();
        // Agora SDK中没有直接的列出设备API，但可以通过测试获取设备信息
        if (rtcEngine != null) {
            // 这里是示意，实际中需要使用设备测试API
            devices.add("Built-in Microphone");
            devices.add("Bluetooth Headset");
            devices.add("USB Audio Device");
        }
        return devices;
    }
    
    /**
     * 列出可用的音频播放设备
     */
    public List<String> listAudioPlaybackDevices() {
        List<String> devices = new ArrayList<>();
        if (rtcEngine != null) {
            // 这里是示意
            devices.add("Built-in Speaker");
            devices.add("Bluetooth Headset");
            devices.add("Wired Headphones");
        }
        return devices;
    }
    
    /**
     * 列出可用的视频设备
     */
    public List<String> listVideoDevices() {
        List<String> devices = new ArrayList<>();
        if (rtcEngine != null) {
            // 这里是示意
            devices.add("Front Camera");
            devices.add("Back Camera");
        }
        return devices;
    }
    
    /**
     * 设置音频录制设备
     */
    public int setAudioRecordingDevice(String deviceId) {
        if (rtcEngine != null) {
            // Agora SDK通常自动管理音频设备，但可以设置参数
            return 0; // 模拟成功
        }
        return -1; // 失败
    }
    
    /**
     * 设置音频播放设备
     */
    public int setAudioPlaybackDevice(String deviceId) {
        if (rtcEngine != null) {
            // Agora SDK通常自动管理音频设备
            return 0; // 模拟成功
        }
        return -1; // 失败
    }
    
    /**
     * 设置视频设备
     */
    public int setVideoDevice(String deviceId) {
        if (rtcEngine != null) {
            // 设置摄像头配置
            CameraCapturerConfiguration configuration;
            if (deviceId.contains("Front")) {
                configuration = new CameraCapturerConfiguration(CameraCapturerConfiguration.CAMERA_DIRECTION.CAMERA_FRONT);
            } else {
                configuration = new CameraCapturerConfiguration(CameraCapturerConfiguration.CAMERA_DIRECTION.CAMERA_REAR);
            }
            
            return rtcEngine.setCameraCapturerConfiguration(configuration);
        }
        return -1; // 失败
    }
    
    /**
     * 启动音频录制设备测试
     */
    public int startAudioRecordingDeviceTest(int indicationInterval) {
        if (rtcEngine != null) {
            return rtcEngine.startRecordingDeviceTest(indicationInterval);
        }
        return -1; // 失败
    }
    
    /**
     * 停止音频录制设备测试
     */
    public int stopAudioRecordingDeviceTest() {
        if (rtcEngine != null) {
            return rtcEngine.stopRecordingDeviceTest();
        }
        return -1; // 失败
    }
    
    /**
     * 启动音频播放设备测试
     */
    public int startAudioPlaybackDeviceTest(String testAudioFilePath) {
        if (rtcEngine != null) {
            return rtcEngine.startPlaybackDeviceTest(testAudioFilePath);
        }
        return -1; // 失败
    }
    
    /**
     * 停止音频播放设备测试
     */
    public int stopAudioPlaybackDeviceTest() {
        if (rtcEngine != null) {
            return rtcEngine.stopPlaybackDeviceTest();
        }
        return -1; // 失败
    }
    
    /**
     * 切换摄像头
     */
    public int switchCamera() {
        if (rtcEngine != null) {
            return rtcEngine.switchCamera();
        }
        return -1; // 失败
    }
    
    /**
     * 启用本地视频
     */
    public int enableLocalVideo(boolean enabled) {
        if (rtcEngine != null) {
            int result = rtcEngine.enableLocalVideo(enabled);
            this.isLocalVideoEnabled = enabled;
            return result;
        }
        return -1; // 失败
    }
    
    /**
     * 启用本地音频
     */
    public int enableLocalAudio(boolean enabled) {
        if (rtcEngine != null) {
            int result = enabled ? rtcEngine.enableAudio() : rtcEngine.disableAudio();
            this.isLocalAudioEnabled = enabled;
            return result;
        }
        return -1; // 失败
    }
    
    /**
     * 静音本地音频
     */
    public int muteLocalAudio(boolean muted) {
        if (rtcEngine != null) {
            int result = rtcEngine.muteLocalAudioStream(muted);
            this.isLocalAudioEnabled = !muted;
            return result;
        }
        return -1; // 失败
    }
    
    /**
     * 静音本地视频
     */
    public int muteLocalVideo(boolean muted) {
        if (rtcEngine != null) {
            int result = rtcEngine.muteLocalVideoStream(muted);
            this.isLocalVideoEnabled = !muted;
            return result;
        }
        return -1; // 失败
    }
    
    /**
     * 静音远程音频
     */
    public int muteRemoteAudio(int uid, boolean muted) {
        if (rtcEngine != null) {
            return rtcEngine.muteRemoteAudioStream(uid, muted);
        }
        return -1; // 失败
    }
    
    /**
     * 静音远程视频
     */
    public int muteRemoteVideo(int uid, boolean muted) {
        if (rtcEngine != null) {
            return rtcEngine.muteRemoteVideoStream(uid, muted);
        }
        return -1; // 失败
    }
    
    /**
     * 静音所有远程音频
     */
    public int muteAllRemoteAudio(boolean muted) {
        if (rtcEngine != null) {
            return rtcEngine.muteAllRemoteAudioStreams(muted);
        }
        return -1; // 失败
    }
    
    /**
     * 静音所有远程视频
     */
    public int muteAllRemoteVideo(boolean muted) {
        if (rtcEngine != null) {
            return rtcEngine.muteAllRemoteVideoStreams(muted);
        }
        return -1; // 失败
    }
    
    /**
     * 设置本地视频渲染视图
     */
    public int setupLocalVideo(Object view, int renderMode) {
        if (rtcEngine != null && view != null) {
            // 确保view是SurfaceView或TextureView类型
            if (view instanceof SurfaceView || view instanceof TextureView) {
                VideoCanvas canvas = new VideoCanvas((android.view.View) view, renderMode, 0);
                int result = rtcEngine.setupLocalVideo(canvas);
                if (result == 0) {
                    localVideoViews.put(0, view); // 本地视频使用uid 0
                }
                return result;
            }
        }
        return -1; // 失败
    }
    
    /**
     * 设置远程视频渲染视图
     */
    public int setupRemoteVideo(Object view, int uid, int renderMode) {
        if (rtcEngine != null && view != null) {
            // 确保view是SurfaceView或TextureView类型
            if (view instanceof SurfaceView || view instanceof TextureView) {
                VideoCanvas canvas = new VideoCanvas((android.view.View) view, renderMode, uid);
                int result = rtcEngine.setupRemoteVideo(canvas);
                if (result == 0) {
                    remoteVideoViews.put(uid, view);
                }
                return result;
            }
        }
        return -1; // 失败
    }
    
    /**
     * 启用视频模块
     */
    public int enableVideo() {
        if (rtcEngine != null) {
            return rtcEngine.enableVideo();
        }
        return -1; // 失败
    }
    
    /**
     * 禁用视频模块
     */
    public int disableVideo() {
        if (rtcEngine != null) {
            return rtcEngine.disableVideo();
        }
        return -1; // 失败
    }
    
    /**
     * 开始预览
     */
    public int startPreview() {
        if (rtcEngine != null) {
            return rtcEngine.startPreview();
        }
        return -1; // 失败
    }
    
    /**
     * 停止预览
     */
    public int stopPreview() {
        if (rtcEngine != null) {
            return rtcEngine.stopPreview();
        }
        return -1; // 失败
    }
    
    /**
     * 设置视频编码配置
     */
    public int setVideoEncoderConfiguration(VideoEncoderConfiguration configuration) {
        if (rtcEngine != null) {
            return rtcEngine.setVideoEncoderConfiguration(configuration);
        }
        return -1; // 失败
    }
    
    /**
     * 设置远程视频订阅选项
     */
    public int setRemoteVideoSubscriptionOptions(int uid, VideoSubscriptionOptions options) {
        if (rtcEngine != null) {
            return rtcEngine.setRemoteVideoSubscriptionOptions(uid, options);
        }
        return -1; // 失败
    }
    
    /**
     * 调整用户播放信号音量
     */
    public int adjustUserPlaybackSignalVolume(int uid, int volume) {
        if (rtcEngine != null) {
            return rtcEngine.adjustUserPlaybackSignalVolume(uid, volume);
        }
        return -1; // 失败
    }
    
    /**
     * 获取本地视频启用状态
     */
    public boolean isLocalVideoEnabled() {
        return isLocalVideoEnabled;
    }
    
    /**
     * 获取本地音频启用状态
     */
    public boolean isLocalAudioEnabled() {
        return isLocalAudioEnabled;
    }
    
    /**
     * 获取远程视频启用状态
     */
    public boolean isRemoteVideoEnabled() {
        return isRemoteVideoEnabled;
    }
    
    /**
     * 获取远程音频启用状态
     */
    public boolean isRemoteAudioEnabled() {
        return isRemoteAudioEnabled;
    }
    
    /**
     * 销毁设备管理器
     */
    public void destroy() {
        if (rtcEngine != null) {
            rtcEngine.destroy();
            rtcEngine = null;
        }
        
        localVideoViews.clear();
        remoteVideoViews.clear();
        audioDevices.clear();
        videoDevices.clear();
    }
    
    /**
     * 获取RtcEngine实例
     */
    public RtcEngine getRtcEngine() {
        return rtcEngine;
    }
    
    /**
     * 设备状态回调接口
     */
    public interface DeviceStatusListener {
        void onAudioDeviceChanged(String deviceId, String deviceName);
        void onVideoDeviceChanged(String deviceId, String deviceName);
        void onLocalVideoStateChanged(boolean enabled);
        void onRemoteVideoStateChanged(int uid, boolean enabled);
        void onAudioQualityChanged(int uid, int quality);
    }
    
    private DeviceStatusListener deviceStatusListener;
    
    public void setDeviceStatusListener(DeviceStatusListener listener) {
        this.deviceStatusListener = listener;
    }
}