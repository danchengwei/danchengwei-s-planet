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
        void onLeaveChannel();
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
                Log.d(TAG, "=== onRemoteVideoStateChanged ===");
                Log.d(TAG, "用户ID: " + uid + ", 状态: " + state + ", 原因: " + reason + ", 耗时: " + elapsed + "ms");

                String stateName = getRemoteVideoStateName(state);
                Log.d(TAG, "远程视频状态: " + stateName);

                // 判断视频是否可用：只有 DECODING 和 STARTING 状态才算可用
                boolean enabled = (state == Constants.REMOTE_VIDEO_STATE_DECODING ||
                        state == Constants.REMOTE_VIDEO_STATE_STARTING);
                Log.d(TAG, "是否启用: " + enabled);

                // 如果视频状态为 STOPPED、FROZEN 或 FAILED，也通知移除视图
                if (state == Constants.REMOTE_VIDEO_STATE_STOPPED ||
                        state == Constants.REMOTE_VIDEO_STATE_FROZEN ||
                        state == Constants.REMOTE_VIDEO_STATE_FAILED) {
                    Log.d(TAG, "远程视频已停止/冻结/失败，将移除视图");
                    enabled = false;
                }

                if (deviceStatusListener != null) {
                    deviceStatusListener.onRemoteVideoStateChanged(uid, enabled);
                    Log.d(TAG, "已通知 DeviceStatusListener 远程视频状态改变");
                } else {
                    Log.e(TAG, "deviceStatusListener 为空，无法通知远程视频状态改变");
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
                Log.d(TAG, "本地视频状态改变回调。视频源类型: " + sourceType + ", 状态: " + localVideoState + ", 错误码: " + error);
                // 本地视频状态变化
                boolean enabled = (localVideoState == Constants.LOCAL_VIDEO_STREAM_STATE_CAPTURING ||
                        localVideoState == Constants.LOCAL_VIDEO_STREAM_STATE_ENCODING);
                if (deviceStatusListener != null) {
                    deviceStatusListener.onLocalVideoStateChanged(enabled);
                    Log.d(TAG, "通知 DeviceStatusListener 本地视频状态改变。启用: " + enabled);
                } else {
                    Log.e(TAG, "deviceStatusListener 为空，无法通知本地视频状态改变。");
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

            @Override
            public void onError(int err) {
                Log.e(TAG, "=== Agora SDK 错误 ===");
                Log.e(TAG, "错误码: " + err);
                Log.e(TAG, "错误描述: " + getErrorDescription(err));

                // 根据错误码处理不同的错误
                switch (err) {
                    case 2: // ERR_INVALID_ARGUMENT
                        Log.e(TAG, "错误原因: 无效的参数");
                        break;
                    case 3: // ERR_NOT_READY
                        Log.e(TAG, "错误原因: SDK 未准备好");
                        break;
                    case 7: // ERR_NOT_INITIALIZED
                        Log.e(TAG, "错误原因: SDK 未初始化");
                        break;
                    case 10: // ERR_INVALID_APP_ID
                        Log.e(TAG, "错误原因: 无效的 App ID");
                        break;
                    case 17: // ERR_JOIN_CHANNEL_REJECTED
                        Log.e(TAG, "错误原因: 加入频道被拒绝");
                        break;
                    case 101: // ERR_INVALID_CHANNEL_NAME
                        Log.e(TAG, "错误原因: 无效的频道名称");
                        break;
                    default:
                        Log.e(TAG, "错误原因: 未知错误");
                        break;
                }
            }

            @Override
            public void onConnectionStateChanged(int state, int reason) {
                Log.d(TAG, "=== onConnectionStateChanged ===");
                Log.d(TAG, "连接状态: " + getConnectionStateName(state) + ", 原因: " + getConnectionStateChangedReasonName(reason));

                // 检查是否是离开频道的状态变化
                // 使用硬编码的值，对应 CONNECTION_CHANGED_REASON_LEAVE_CHANNEL (7) 和 CONNECTION_CHANGED_REASON_DISCONNECTED (2)
                boolean isLeaveChannelReason = (reason == 2 || reason == 5 || reason == 7);
                
                if (state == io.agora.rtc2.Constants.CONNECTION_STATE_DISCONNECTED && isLeaveChannelReason) {
                    Log.d(TAG, "检测到离开频道事件，通知 RoomManager");
                    if (roomEventListener != null) {
                        roomEventListener.onLeaveChannel();
                    }
                }
            }
        };

        Log.d(TAG, "尝试创建 RtcEngine，App ID: " + appId);
        rtcEngine = RtcEngine.create(config);
        Log.d(TAG, "RtcEngine 创建成功。");

        // 注意：暂时不设置频道配置，使用默认配置
        // 频道配置会在 joinChannel 时通过 ChannelMediaOptions 传递
        Log.d(TAG, "使用默认配置，不预先设置频道模式");

        // 启用音频模块
        Log.d(TAG, "尝试启用音频模块。");
        rtcEngine.enableAudio();
        Log.d(TAG, "音频模块已启用。");

        // 启用视频模块
        Log.d(TAG, "尝试启用视频模块。");
        rtcEngine.enableVideo();
        Log.d(TAG, "视频模块已启用。");

        // 设置适合手机的视频编码配置（竖屏）
        Log.d(TAG, "设置视频编码配置。");
        VideoEncoderConfiguration videoConfig = new VideoEncoderConfiguration(
                480, 854,  // 分辨率：480x854 (适合竖屏手机)
                VideoEncoderConfiguration.FRAME_RATE.FRAME_RATE_FPS_15,  // 15fps
                VideoEncoderConfiguration.STANDARD_BITRATE,  // 标准码率
                VideoEncoderConfiguration.ORIENTATION_MODE.ORIENTATION_MODE_ADAPTIVE  // 自适应方向
        );
        int configResult = rtcEngine.setVideoEncoderConfiguration(videoConfig);
        Log.d(TAG, "视频编码配置设置完成，结果: " + configResult);
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
     * 根据远程视频状态值获取状态名称
     */
    private String getRemoteVideoStateName(int state) {
        switch (state) {
            case Constants.REMOTE_VIDEO_STATE_STOPPED:
                return "STOPPED (已停止)";
            case Constants.REMOTE_VIDEO_STATE_STARTING:
                return "STARTING (启动中)";
            case Constants.REMOTE_VIDEO_STATE_DECODING:
                return "DECODING (解码中)";
            case Constants.REMOTE_VIDEO_STATE_FROZEN:
                return "FROZEN (已冻结)";
            case Constants.REMOTE_VIDEO_STATE_FAILED:
                return "FAILED (失败)";
            default:
                return "UNKNOWN (未知状态: " + state + ")";
        }
    }

    /**
     * 根据错误码获取错误描述
     */
    private String getErrorDescription(int err) {
        switch (err) {
            case 1:
                return "ERR_FAILED (一般错误)";
            case 2:
                return "ERR_INVALID_ARGUMENT (无效的参数)";
            case 3:
                return "ERR_NOT_READY (SDK 未准备好)";
            case 4:
                return "ERR_NOT_SUPPORTED (不支持的功能)";
            case 5:
                return "ERR_BUFFER_TOO_SMALL (缓冲区太小)";
            case 6:
                return "ERR_NOT_INITIALIZED (SDK 未初始化)";
            case 7:
                return "ERR_INVALID_STATE (无效的状态)";
            case 8:
                return "ERR_NO_PERMISSION (没有权限)";
            case 9:
                return "ERR_TIMEDOUT (超时)";
            case 10:
                return "ERR_INVALID_APP_ID (无效的 App ID)";
            case 11:
                return "ERR_INVALID_CHANNEL_NAME (无效的频道名称)";
            case 12:
                return "ERR_TOKEN_EXPIRED (Token 已过期)";
            case 13:
                return "ERR_INVALID_TOKEN (无效的 Token)";
            case 14:
                return "ERR_CONNECTION_INTERRUPTED (连接中断)";
            case 15:
                return "ERR_CONNECTION_LOST (连接丢失)";
            case 16:
                return "ERR_NOT_IN_CHANNEL (不在频道中)";
            case 17:
                return "ERR_TOO_OFTEN (调用过于频繁)";
            case 18:
                return "ERR_USE_POLLING_MODE (使用轮询模式)";
            case 19:
                return "ERR_JOIN_CHANNEL_REJECTED (加入频道被拒绝)";
            case 20:
                return "ERR_LEAVE_CHANNEL_REJECTED (离开频道被拒绝)";
            case 101:
                return "ERR_INVALID_CHANNEL_NAME (无效的频道名称)";
            case 102:
                return "ERR_CHANNEL_KEY_EXPIRED (频道 Key 已过期)";
            case 109:
                return "ERR_TOKEN_EXPIRED (Token 已过期)";
            case 110:
                return "ERR_INVALID_TOKEN (无效的 Token)";
            default:
                return "UNKNOWN (未知错误码: " + err + ")";
        }
    }

    /**
     * 根据连接状态值获取状态名称
     */
    private String getConnectionStateName(int state) {
        switch (state) {
            case io.agora.rtc2.Constants.CONNECTION_STATE_DISCONNECTED:
                return "CONNECTION_STATE_DISCONNECTED (已断开连接)";
            case io.agora.rtc2.Constants.CONNECTION_STATE_CONNECTING:
                return "CONNECTION_STATE_CONNECTING (连接中)";
            case io.agora.rtc2.Constants.CONNECTION_STATE_CONNECTED:
                return "CONNECTION_STATE_CONNECTED (已连接)";
            case io.agora.rtc2.Constants.CONNECTION_STATE_RECONNECTING:
                return "CONNECTION_STATE_RECONNECTING (重连中)";
            case io.agora.rtc2.Constants.CONNECTION_STATE_FAILED:
                return "CONNECTION_STATE_FAILED (连接失败)";
            default:
                return "UNKNOWN (未知状态: " + state + ")";
        }
    }

    /**
     * 根据连接状态变化原因获取名称
     */
    private String getConnectionStateChangedReasonName(int reason) {
        switch (reason) {
            case 0: // CONNECTION_CHANGED_REASON_CONNECTING - 可能没有公开的常量
                return "CONNECTION_CHANGED_REASON_CONNECTING";
            case 1: // CONNECTION_CHANGED_REASON_CONNECTED
                return "CONNECTION_CHANGED_REASON_CONNECTED";
            case 2: // CONNECTION_CHANGED_REASON_DISCONNECTED
                return "CONNECTION_CHANGED_REASON_DISCONNECTED";
            case 3: // CONNECTION_CHANGED_REASON_RECONNECTING
                return "CONNECTION_CHANGED_REASON_RECONNECTING";
            case 4: // CONNECTION_CHANGED_REASON_RECONNECTED
                return "CONNECTION_CHANGED_REASON_RECONNECTED";
            case 5: // CONNECTION_CHANGED_REASON_ABORTED
                return "CONNECTION_CHANGED_REASON_ABORTED";
            case 6: // CONNECTION_CHANGED_REASON_KEEP_ALIVE_TIMEOUT
                return "CONNECTION_CHANGED_REASON_KEEP_ALIVE_TIMEOUT";
            case 7: // CONNECTION_CHANGED_REASON_LEAVE_CHANNEL
                return "CONNECTION_CHANGED_REASON_LEAVE_CHANNEL";
            case 8: // CONNECTION_CHANGED_REASON_REMOTE_OFFLINE
                return "CONNECTION_CHANGED_REASON_REMOTE_OFFLINE";
            case 9: // CONNECTION_CHANGED_REASON_IP_CHANGED
                return "CONNECTION_CHANGED_REASON_IP_CHANGED";
            case 10: // CONNECTION_CHANGED_REASON_CLIENT_IP_CHANGED
                return "CONNECTION_CHANGED_REASON_CLIENT_IP_CHANGED";
            case 11: // CONNECTION_CHANGED_REASON_CLIENT_IP_PORT_CHANGED
                return "CONNECTION_CHANGED_REASON_CLIENT_IP_PORT_CHANGED";
            case 12: // CONNECTION_CHANGED_REASON_REMOTE_REQUEST_QUIT
                return "CONNECTION_CHANGED_REASON_REMOTE_REQUEST_QUIT";
            case 13: // CONNECTION_CHANGED_REASON_RECEIVED_SERVER_MESSAGE_FAILED
                return "CONNECTION_CHANGED_REASON_RECEIVED_SERVER_MESSAGE_FAILED";
            case 14: // CONNECTION_CHANGED_REASON_SOCK_DISCONNECTED
                return "CONNECTION_CHANGED_REASON_SOCK_DISCONNECTED";
            case 15: // CONNECTION_CHANGED_REASON_INVALID_APP_ID
                return "CONNECTION_CHANGED_REASON_INVALID_APP_ID";
            case 16: // CONNECTION_CHANGED_REASON_INVALID_CHANNEL_NAME
                return "CONNECTION_CHANGED_REASON_INVALID_CHANNEL_NAME";
            case 17: // CONNECTION_CHANGED_REASON_INTERNAL_FAILED
                return "CONNECTION_CHANGED_REASON_INTERNAL_FAILED";
            default:
                return "UNKNOWN (未知原因: " + reason + ")";
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
        Log.d(TAG, "调用 switchCamera，尝试切换摄像头。");
        if (rtcEngine != null) {
            int result = rtcEngine.switchCamera();
            Log.d(TAG, "rtcEngine.switchCamera 返回结果: " + result);
            return result;
        }
        Log.e(TAG, "切换摄像头失败，rtcEngine 为空。");
        return -1; // 失败
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
     * 检查RtcEngine是否可用
     */
    private boolean isRtcEngineAvailable() {
        return rtcEngine != null;
    }

    /**
     * 启用本地视频
     */
    public int enableLocalVideo(boolean enabled) {
        Log.d(TAG, "调用 enableLocalVideo，启用状态: " + enabled);
        if (isRtcEngineAvailable()) {
            int result = rtcEngine.enableLocalVideo(enabled);
            this.isLocalVideoEnabled = enabled;
            Log.d(TAG, "rtcEngine.enableLocalVideo 返回结果: " + result);
            return result;
        }
        Log.e(TAG, "启用本地视频失败，rtcEngine 为空。");
        return -1; // 失败
    }

    /**
     * 启用本地音频
     */
    public int enableLocalAudio(boolean enabled) {
        if (isRtcEngineAvailable()) {
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
        Log.d(TAG, "=== muteLocalAudio ===");
        Log.d(TAG, "静音状态: " + muted);
        if (isRtcEngineAvailable()) {
            int result = rtcEngine.muteLocalAudioStream(muted);
            this.isLocalAudioEnabled = !muted;
            Log.d(TAG, "rtcEngine.muteLocalAudioStream 返回结果: " + result);
            Log.d(TAG, "本地音频推流状态: " + (muted ? "停止" : "开启"));
            return result;
        }
        Log.e(TAG, "静音本地音频失败，rtcEngine 为空。");
        return -1; // 失败
    }

    /**
     * 静音本地视频
     */
    public int muteLocalVideo(boolean muted) {
        Log.d(TAG, "=== muteLocalVideo ===");
        Log.d(TAG, "静音状态: " + muted);
        if (isRtcEngineAvailable()) {
            int result = rtcEngine.muteLocalVideoStream(muted);
            this.isLocalVideoEnabled = !muted;
            Log.d(TAG, "rtcEngine.muteLocalVideoStream 返回结果: " + result);
            Log.d(TAG, "本地视频推流状态: " + (muted ? "停止" : "开启"));
            return result;
        }
        Log.e(TAG, "静音本地视频失败，rtcEngine 为空。");
        return -1; // 失败
    }

    /**
     * 设置本地视频渲染视图
     */
    public int setupLocalVideo(Object view, int renderMode) {
        Log.d(TAG, "=== setupLocalVideo ===");
        Log.d(TAG, "视图: " + view + ", 渲染模式: " + renderMode);
        if (isRtcEngineAvailable() && view != null) {
            if (view instanceof SurfaceView || view instanceof TextureView) {
                VideoCanvas canvas = new VideoCanvas((android.view.View) view, renderMode, 0);
                int result = rtcEngine.setupLocalVideo(canvas);
                Log.d(TAG, "rtcEngine.setupLocalVideo 返回结果: " + result);
                if (result == 0) {
                    localVideoViews.put(0, view);
                    Log.d(TAG, "本地视频视图已成功存储，view: " + view);
                    Log.d(TAG, "本地视频渲染已设置");
                } else {
                    Log.e(TAG, "设置本地视频失败，返回码: " + result);
                }
                return result;
            } else {
                Log.e(TAG, "设置本地视频失败，视图类型不正确: " + view.getClass().getSimpleName());
            }
        } else {
            Log.e(TAG, "设置本地视频失败，rtcEngine 或 view 为空。rtcEngine: " + (isRtcEngineAvailable()) + ", view: " + (view != null));
        }
        return -1; // 失败
    }

    /**
     * 设置远程视频渲染视图
     */
    public int setupRemoteVideo(Object view, int uid, int renderMode) {
        Log.d(TAG, "=== setupRemoteVideo ===");
        Log.d(TAG, "视图: " + view + ", 用户ID: " + uid + ", 渲染模式: " + renderMode);
        if (isRtcEngineAvailable() && view != null) {
            if (view instanceof SurfaceView || view instanceof TextureView) {
                VideoCanvas canvas = new VideoCanvas((android.view.View) view, renderMode, uid);
                int result = rtcEngine.setupRemoteVideo(canvas);
                Log.d(TAG, "rtcEngine.setupRemoteVideo 返回结果: " + result);
                if (result == 0) {
                    remoteVideoViews.put(uid, view);
                    Log.d(TAG, "远程视频视图已成功存储，用户ID: " + uid + ", view: " + view);
                    Log.d(TAG, "远程视频渲染已设置，开始接收视频流");
                } else {
                    Log.e(TAG, "设置远程视频失败，返回码: " + result);
                }
                return result;
            } else {
                Log.e(TAG, "设置远程视频失败，视图类型不正确: " + view.getClass().getSimpleName());
            }
        } else {
            Log.e(TAG, "设置远程视频失败，rtcEngine 或 view 为空。rtcEngine: " + (isRtcEngineAvailable()) + ", view: " + (view != null));
        }
        return -1; // 失败
    }

    /**
     * 启用视频模块
     */
    public int enableVideo() {
        if (isRtcEngineAvailable()) {
            return rtcEngine.enableVideo();
        }
        return -1; // 失败
    }

    /**
     * 禁用视频模块
     */
    public int disableVideo() {
        if (isRtcEngineAvailable()) {
            return rtcEngine.disableVideo();
        }
        return -1; // 失败
    }

    /**
     * 开始预览
     */
    public int startPreview() {
        Log.d(TAG, "调用 startPreview，尝试开启本地视频预览。");
        if (isRtcEngineAvailable()) {
            int result = rtcEngine.startPreview();
            Log.d(TAG, "rtcEngine.startPreview 返回结果: " + result);
            return result;
        }
        Log.e(TAG, "开启预览失败，rtcEngine 为空。");
        return -1; // 失败
    }

    /**
     * 停止预览
     */
    public int stopPreview() {
        Log.d(TAG, "调用 stopPreview，尝试停止本地视频预览。");
        if (isRtcEngineAvailable()) {
            int result = rtcEngine.stopPreview();
            Log.d(TAG, "rtcEngine.stopPreview 返回结果: " + result);
            return result;
        }
        Log.e(TAG, "停止预览失败，rtcEngine 为空。");
        return -1; // 失败
    }

    /**
     * 设置视频编码配置
     */
    public int setVideoEncoderConfiguration(VideoEncoderConfiguration configuration) {
        if (isRtcEngineAvailable()) {
            return rtcEngine.setVideoEncoderConfiguration(configuration);
        }
        return -1; // 失败
    }

    /**
     * 设置远程视频订阅选项
     */
    public int setRemoteVideoSubscriptionOptions(int uid, VideoSubscriptionOptions options) {
        if (isRtcEngineAvailable()) {
            return rtcEngine.setRemoteVideoSubscriptionOptions(uid, options);
        }
        return -1; // 失败
    }

    /**
     * 调整用户播放信号音量
     */
    public int adjustUserPlaybackSignalVolume(int uid, int volume) {
        if (isRtcEngineAvailable()) {
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