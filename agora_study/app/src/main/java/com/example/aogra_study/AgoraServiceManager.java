package com.example.aogra_study;

import android.content.Context;
import android.util.Log;

/**
 * Agora服务管理器
 * 统一管理Agora各项服务的初始化和生命周期
 */
public class AgoraServiceManager {
    private static final String TAG = "AgoraServiceManager";
    private Context context;
    private AudioController audioController;
    private VideoController videoController;
    private ChatController chatController;
    private RTMController rtmController;
    private RoomManager roomManager;
    private DeviceManager deviceManager;

    private boolean isInitialized = false;

    public AgoraServiceManager(Context context) {
        this.context = context;
    }

    /**
     * 初始化所有Agora服务
     */
    public void initialize() throws Exception {
        if (isInitialized) {
            Log.d("Agora", "AgoraServiceManager 已经初始化，跳过");
            return;
        }

        String appId = AgoraConfig.getAppId();
        Log.d("Agora", "=== 开始初始化 AgoraServiceManager ===");
        Log.d("Agora", "App ID: " + appId);

        // 初始化DeviceManager
        Log.d("Agora", "初始化 DeviceManager...");
        deviceManager = new DeviceManager(context, appId);
        deviceManager.initialize();
        Log.d("Agora", "DeviceManager 初始化完成");

        // 初始化AudioController和VideoController
        audioController = new AudioController(deviceManager.getRtcEngine());
        videoController = new VideoController(deviceManager.getRtcEngine());
        Log.d("Agora", "AudioController 和 VideoController 初始化完成");

        // 初始化RTMController - 尝试初始化，如果失败则记录错误但继续
        try {
            Log.d("Agora", "初始化 RTMController...");
            rtmController = new RTMController();
            rtmController.initializeRtmClient(appId, AgoraConfig.generateUserId(), null);
            Log.d("Agora", "RTMController 初始化完成");
        } catch (UnsatisfiedLinkError e) {
            Log.e("Agora", "Failed to initialize RTM client due to native library error: " + e.getMessage());
            // 创建一个空的RTMController对象，以便后续不会出现空指针异常
            rtmController = new RTMController();
        } catch (Exception e) {
            Log.e("Agora", "Failed to initialize RTM client: " + e.getMessage());
            rtmController = new RTMController();
        }

        // 初始化ChatController
        Log.d("Agora", "初始化 ChatController...");
        chatController = new ChatController();
        try {
            chatController.initChat(context, appId);
            Log.d("Agora", "ChatController 初始化完成");
        } catch (Exception e) {
            Log.e("Agora", "Failed to initialize ChatController: " + e.getMessage());
            e.printStackTrace(); // 添加堆栈跟踪以帮助调试
            // 创建一个空的chatController对象，以便后续不会出现空指针异常
            chatController = new ChatController();
        }

        // 初始化RoomManager，并传入 DeviceManager 的 RtcEngine 实例
        Log.d("Agora", "初始化 RoomManager...");
        roomManager = new RoomManager(context, appId);
        roomManager.setRtcEngine(deviceManager.getRtcEngine());
        roomManager.initialize();
        Log.d("Agora", "RoomManager 初始化完成");

        // 设置 DeviceManager 的 RoomEventListener，让它能够通知 RoomManager 更新成员列表
        Log.d("Agora", "设置 DeviceManager 和 RoomManager 的事件连接...");
        deviceManager.setRoomEventListener(new DeviceManager.RoomEventListener() {
            @Override
            public void onUserJoined(int uid) {
                Log.d("Agora", "DeviceManager 检测到用户加入: " + uid);
                if (roomManager != null) {
                    roomManager.handleUserJoined(uid);
                } else {
                    Log.e("Agora", "roomManager 为 null，无法处理用户加入事件");
                }
            }

            @Override
            public void onUserLeft(int uid) {
                Log.d("Agora", "DeviceManager 检测到用户离开: " + uid);
                if (roomManager != null) {
                    roomManager.handleUserLeft(uid);
                } else {
                    Log.e("Agora", "roomManager 为 null，无法处理用户离开事件");
                }
            }

            @Override
            public void onJoinChannelSuccess(String channel, int uid, int elapsed) {
                Log.d("Agora", "DeviceManager 检测到加入频道成功: " + channel + ", uid: " + uid);
                if (roomManager != null) {
                    roomManager.handleJoinChannelSuccess(channel, uid, elapsed);
                } else {
                    Log.e("Agora", "roomManager 为 null，无法处理加入频道成功事件");
                }
            }

            @Override
            public void onLeaveChannel() {
                Log.d("Agora", "DeviceManager 检测到离开频道成功");
                if (roomManager != null) {
                    roomManager.handleLeaveChannel();
                } else {
                    Log.e("Agora", "roomManager 为 null，无法处理离开频道事件");
                }
            }
        });
        Log.d("Agora", "DeviceManager 和 RoomManager 事件连接设置完成");

        isInitialized = true;
        Log.d("Agora", "=== AgoraServiceManager 初始化完成 ===");
    }

    /**
     * 获取音频控制器
     */
    public AudioController getAudioController() {
        if (!isInitialized) {
            throw new IllegalStateException("AgoraServiceManager not initialized");
        }
        return audioController;
    }

    /**
     * 设置音频控制器（外部注入）
     */
    public void setAudioController(AudioController audioController) {
        this.audioController = audioController;
    }

    /**
     * 获取视频控制器
     */
    public VideoController getVideoController() {
        if (!isInitialized) {
            throw new IllegalStateException("AgoraServiceManager not initialized");
        }
        return videoController;
    }

    /**
     * 设置视频控制器（外部注入）
     */
    public void setVideoController(VideoController videoController) {
        this.videoController = videoController;
    }

    /**
     * 获取聊天控制器
     */
    public ChatController getChatController() {
        if (!isInitialized) {
            throw new IllegalStateException("AgoraServiceManager not initialized");
        }
        return chatController;
    }

    /**
     * 获取RTM控制器
     */
    public RTMController getRtmController() {
        if (!isInitialized) {
            throw new IllegalStateException("AgoraServiceManager not initialized");
        }
        return rtmController;
    }

    /**
     * 获取房间管理器
     */
    public RoomManager getRoomManager() {
        if (!isInitialized) {
            throw new IllegalStateException("AgoraServiceManager not initialized");
        }
        return roomManager;
    }

    /**
     * 获取设备管理器
     */
    public DeviceManager getDeviceManager() {
        if (!isInitialized) {
            throw new IllegalStateException("AgoraServiceManager not initialized");
        }
        return deviceManager;
    }

    /**
     * 加入房间
     */
    public void joinRoom(String channelName, String userId, boolean isBroadcaster) {
        if (roomManager != null) {
            roomManager.joinChatRoom(channelName, userId, AgoraConfig.getDefaultToken());
        }
    }

    /**
     * 创建房间
     */
    public void createRoom(String channelName, String userId, boolean isBroadcaster) {
        if (roomManager != null) {
            // 不再主动调用 leaveRoom，让 joinChannel 自己处理频道切换
            // 这样可以避免 leaveChannel 阻塞导致的问题
            Log.d(TAG, "直接调用 createChatRoom，让 SDK 自动处理频道切换");
            roomManager.createChatRoom(channelName, userId, AgoraConfig.getDefaultToken(), isBroadcaster);
        }
    }

    /**
     * 离开房间
     */
    public void leaveRoom() {
        if (roomManager != null) {
            roomManager.leaveRoom();
        }
    }

    /**
     * 销毁所有服务
     */
    public void destroy() {
        if (roomManager != null) {
            roomManager.leaveRoom();
        }

        if (deviceManager != null) {
            deviceManager.destroy();
        }

        if (rtmController != null) {
            rtmController.destroy();
        }

        isInitialized = false;
    }

    /**
     * 检查是否已初始化
     */
    public boolean isInitialized() {
        return isInitialized;
    }
}