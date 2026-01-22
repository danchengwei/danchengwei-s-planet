package com.example.aogra_study;

import android.content.Context;
import android.util.Log;
import android.view.View;

import androidx.lifecycle.MutableLiveData;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.agora.rtc2.RtcEngine;
import io.agora.rtc2.RtcEngineConfig;
import io.agora.rtc2.IRtcEngineEventHandler;
import io.agora.rtc2.ChannelMediaOptions;
import io.agora.rtc2.video.VideoCanvas;
import io.agora.rtc2.Constants;
import io.agora.rtm.RtmClient;
import io.agora.rtm.RtmConfig;
import io.agora.rtm.RtmMessage;
import io.agora.rtm.RtmEventListener;
import io.agora.rtm.PublishOptions;
import io.agora.rtm.RtmConstants.RtmChannelType;
import io.agora.rtm.ResultCallback;
import io.agora.rtm.ErrorInfo;

/**
 * 房间管理器，负责聊天室、连麦申请、房间管理等功能
 * 使用Agora云服务实现
 */
public class RoomManager {
    private static final String TAG = "Agora";

    private RtcEngine rtcEngine;
    private RtmClient rtmClient;

    private String currentUserId;
    private String currentChannelName;
    private String appId;
    private String currentToken;
    private Context context;

    private IRtcEngineEventHandler rtcEventHandler;
    private RtmEventListener rtmEventListener;

    // 存储房间信息
    private Map<String, List<String>> roomMembers = new HashMap<>();
    private Map<String, String> userVideoViews = new HashMap<>();

    // 存储连麦申请
    private Map<String, String> micApplyRequests = new HashMap<>();

    // 房间状态
    private boolean isInRoom = false;
    private boolean isBroadcaster = false;
    private boolean isLeavingRoom = false; // 标记是否正在离开房间
    private boolean isJoiningRoom = false; // 标记是否正在加入房间

    // 房间成员数量的 LiveData
    private MutableLiveData<Integer> memberCountLiveData = new MutableLiveData<>();

    // 设备状态监听器
    private DeviceStatusListener deviceStatusListener;

    // 房间状态监听器
    private RoomStateListener roomStateListener;

    // 标记是否使用外部传入的 RtcEngine
    private boolean useExternalRtcEngine = false;

    public RoomManager(Context context, String appId) {
        this.context = context;
        this.appId = appId;
    }

    /**
     * 使用外部传入的 RtcEngine 实例
     */
    public void setRtcEngine(RtcEngine engine) {
        this.rtcEngine = engine;
        this.useExternalRtcEngine = true;
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

    /**
     * 房间状态回调接口
     */
    public interface RoomStateListener {
        void onJoiningRoom(); // 开始加入房间
        void onJoinedRoom(); // 成功加入房间
        void onLeavingRoom(); // 开始离开房间
        void onLeftRoom(); // 成功离开房间
        void onRoomError(String error); // 房间操作错误
    }

    public void setDeviceStatusListener(DeviceStatusListener listener) {
        this.deviceStatusListener = listener;
    }

    public void setRoomStateListener(RoomStateListener listener) {
        this.roomStateListener = listener;
    }

    /**
     * 获取成员数量的 LiveData
     */
    public MutableLiveData<Integer> getMemberCountLiveData() {
        return memberCountLiveData;
    }

    /**
     * 获取当前房间成员数量
     */
    public int getCurrentMemberCount() {
        if (currentChannelName != null && roomMembers.containsKey(currentChannelName)) {
            return roomMembers.get(currentChannelName).size();
        }
        return 0;
    }

    /**
     * 初始化房间管理器
     */
    public void initialize() throws Exception {
        // 如果没有外部传入的 RtcEngine，则创建一个新的
        if (rtcEngine == null) {
            RtcEngineConfig config = new RtcEngineConfig();
            config.mContext = context;
            config.mAppId = appId;
            config.mEventHandler = rtcEventHandler;
            config.mChannelProfile = Constants.CHANNEL_PROFILE_LIVE_BROADCASTING;

            rtcEngine = RtcEngine.create(config);
            Log.d("RoomManager", "创建了新的 RtcEngine 实例");
        } else {
            Log.d("RoomManager", "使用外部传入的 RtcEngine 实例");
            Log.d("RoomManager", "频道配置和音视频模块已在 DeviceManager 中启用");
        }

        Log.d(TAG, "RTC引擎初始化完成");

        // 初始化RTM客户端
        rtmEventListener = new RtmEventListener() {
            @Override
            public void onMessageEvent(io.agora.rtm.MessageEvent event) {
                // 处理收到的消息
                RtmMessage message = event.getMessage();
                String msgContent = new String((byte[])message.getData()); // 修正类型转换

                // 解析消息类型
                if (msgContent.contains("mic_apply")) {
                    // 连麦申请消息
                    handleMicApplyMessage(msgContent);
                } else if (msgContent.contains("mic_response")) {
                    // 连麦响应消息
                    handleMicResponseMessage(msgContent);
                } else if (msgContent.contains("room_notification")) {
                    // 房间通知消息
                    handleRoomNotification(msgContent);
                } else {
                    // 普通聊天消息
                    if (roomEventListener != null) {
                        roomEventListener.onChatMessageReceived(event.getPublisherId(), msgContent);
                    }
                }
            }

            // 修正事件处理方法
            @Override
            public void onLinkStateEvent(io.agora.rtm.LinkStateEvent event) { // 使用正确的事件类型
                // 处理连接状态变化
            }
        };
    }

    /**
     * 创建聊天室
     */
    public void createChatRoom(String channelName, String userId, String token, boolean isBroadcaster) {
        Log.d(TAG, "=== RoomManager.createChatRoom 开始 ===");
        Log.d(TAG, "频道名称: " + channelName);
        Log.d(TAG, "用户ID: " + userId);
        Log.d(TAG, "是否为主播: " + isBroadcaster);
        Log.d(TAG, "当前状态: isJoiningRoom=" + isJoiningRoom + ", isLeavingRoom=" + isLeavingRoom);

        // 如果正在加入房间，拒绝新的加入请求
        if (isJoiningRoom) {
            Log.w(TAG, "正在加入房间，拒绝新的加入请求");
            if (roomStateListener != null) {
                roomStateListener.onRoomError("正在加入房间，请稍后再试");
            }
            return;
        }

        // 如果正在离开房间，等待片刻再尝试加入
        if (isLeavingRoom) {
            Log.w(TAG, "正在离开房间，等待片刻后加入");
            new Thread(() -> {
                try {
                    // 等待最多3秒让离开操作完成
                    int waited = 0;
                    while (isLeavingRoom && waited < 3000) {
                        Thread.sleep(100);
                        waited += 100;
                    }

                    // 检查是否已经可以加入
                    if (isLeavingRoom) {
                        Log.e(TAG, "等待离开房间超时，强制重置状态");
                        isLeavingRoom = false;
                    }

                    // 递归调用，确保此时不再处于离开状态
                    createChatRoom(channelName, userId, token, isBroadcaster);
                } catch (InterruptedException e) {
                    Log.e(TAG, "等待被中断", e);
                    if (roomStateListener != null) {
                        roomStateListener.onRoomError("加入房间被中断");
                    }
                }
            }).start();
            return;
        }

        // 通知开始加入房间
        isJoiningRoom = true;
        if (roomStateListener != null) {
            roomStateListener.onJoiningRoom();
        }

        // 在后台线程中执行所有操作，避免阻塞主线程
        new Thread(() -> {
            try {
                // 不等待 isLeavingRoom，直接继续
                // Agora SDK 的 joinChannel 会自动处理频道切换
                Log.d(TAG, "开始加入流程，不等待离开完成");

                this.currentChannelName = channelName;
                this.currentUserId = userId;
                this.currentToken = token;
                this.isBroadcaster = isBroadcaster;

                // 预先创建房间成员列表，避免查询时为空
                // 在每次加入房间时都重新初始化成员列表
                if (!roomMembers.containsKey(channelName)) {
                    roomMembers.put(channelName, new ArrayList<>());
                } else {
                    // 清空现有成员列表，确保是从头开始
                    roomMembers.get(channelName).clear();
                }

                // 将当前用户添加到成员列表
                roomMembers.get(channelName).add(userId);
                Log.d(TAG, "预先创建/清空房间成员列表，频道: " + channelName + ", 当前成员数: " + roomMembers.get(channelName).size());

                // 更新成员数量的 LiveData
                memberCountLiveData.postValue(roomMembers.get(channelName).size());

                // 直接加入 RTC 频道，不需要等待 RTM 登录
                Log.d(TAG, "直接加入 RTC 频道（不等待 RTM）...");
                joinChannel(channelName, userId, token, isBroadcaster);

                // 设置超时机制：如果 10 秒内没有收到 handleJoinChannelSuccess 回调，重置状态
                new Thread(() -> {
                    try {
                        Thread.sleep(10000); // 等待 10 秒
                        if (isJoiningRoom) {
                            Log.e(TAG, "加入频道超时（10秒内未收到回调），重置状态");
                            isJoiningRoom = false;
                            if (roomStateListener != null) {
                                roomStateListener.onRoomError("加入频道超时，请检查网络或重试");
                            }
                        }
                    } catch (InterruptedException e) {
                        Log.d(TAG, "超时检测线程被中断");
                    }
                }).start();

                // 注意：不在这里重置 isJoiningRoom，等待 handleJoinChannelSuccess 回调

                // 尝试初始化 RTM（用于聊天功能）
                try {
                    // 先释放旧的 RTM 客户端
                    if (rtmClient != null) {
                        Log.d(TAG, "释放旧的 RTM 客户端");
                        try {
                            rtmClient.logout(null);
                            rtmClient.release();
                        } catch (Exception e) {
                            Log.e(TAG, "释放旧 RTM 客户端失败", e);
                        }
                        rtmClient = null;
                    }

                    Log.d(TAG, "初始化 RTM 客户端（用于聊天功能）...");

                    // RTM 在开发模式下使用 null Token
                    // RTC Token 不能用于 RTM
                    String rtmToken = null;
                    Log.d(TAG, "RTM 使用 null Token（开发模式）");

                    RtmConfig rtmConfig = new RtmConfig.Builder(appId, userId)
                            .eventListener(rtmEventListener)
                            .build();
                    this.rtmClient = RtmClient.create(rtmConfig);
                    Log.d(TAG, "RTM 客户端创建完成");

                    // 登录RTM
                    Log.d(TAG, "开始 RTM 登录...");
                    rtmClient.login(rtmToken, new ResultCallback<Void>() {
                        @Override
                        public void onSuccess(Void responseInfo) {
                            Log.d(TAG, "RTM 登录成功（聊天功能可用）");
                        }

                        @Override
                        public void onFailure(ErrorInfo errorInfo) {
                            Log.w(TAG, "RTM 登录失败（聊天功能不可用）: " + errorInfo.toString());
                            Log.w(TAG, "RTC 功能仍然正常工作");
                        }
                    });
                } catch (Exception e) {
                    Log.w(TAG, "RTM 初始化失败（聊天功能不可用）: " + e.getMessage());
                    Log.w(TAG, "RTC 功能仍然正常工作");
                }

                // RTM 初始化完成，但不重置 isJoiningRoom
                // 等待 handleJoinChannelSuccess 回调后才算真正加入成功

                Log.d(TAG, "=== RoomManager.createChatRoom 完成 ===");
            } catch (Exception e) {
                Log.e(TAG, "创建聊天室失败", e);
                isJoiningRoom = false;
                if (roomStateListener != null) {
                    roomStateListener.onRoomError("加入房间失败: " + e.getMessage());
                }
            }
        }).start();
    }

    /**
     * 加入聊天室
     */
    public void joinChatRoom(String channelName, String userId, String token) {
        this.currentChannelName = channelName;
        this.currentUserId = userId;
        this.currentToken = token; // 设置Token
        this.isBroadcaster = false; // 观众身份加入

        joinChannel(channelName, userId, token, false);
    }

    /**
     * 加入频道
     */
    private void joinChannel(String channelName, String userId, String token, boolean isBroadcaster) {
        Log.d(TAG, "=== RoomManager.joinChannel 开始 ===");
        Log.d(TAG, "频道名称: " + channelName);
        Log.d(TAG, "用户ID: " + userId);
        Log.d(TAG, "是否为主播: " + isBroadcaster);
        Log.d(TAG, "rtcEngine 是否为 null: " + (rtcEngine == null));

        // 检查是否正在离开房间，如果是则取消本次加入
        if (isLeavingRoom) {
            Log.w(TAG, "正在离开房间，取消加入频道");
            // 重置加入标志并通知错误
            isJoiningRoom = false;
            if (roomStateListener != null) {
                roomStateListener.onRoomError("正在离开房间，请稍后再试");
            }
            return;
        }

        if (rtcEngine == null) {
            Log.e(TAG, "rtcEngine 为 null，无法加入频道");
            isJoiningRoom = false;
            if (roomStateListener != null) {
                roomStateListener.onRoomError("RTC 引擎未初始化");
            }
            return;
        }

        try {
            // 更新当前房间状态（这里的 currentChannelName 已在 createChatRoom 中设置）
            this.currentToken = token;
            this.isBroadcaster = isBroadcaster;

            Log.d(TAG, "准备加入频道");
            Log.d(TAG, "注意：不调用 leaveChannel，让 SDK 自动处理频道切换");

            // 诊断：Token 检查
            if (token != null && !token.isEmpty()) {
                Log.d(TAG, "使用 Token 加入（生产模式）");
                Log.d(TAG, "Token 长度: " + token.length());
            } else {
                Log.d(TAG, "使用空 Token 加入（测试模式）");
                token = null; // 确保是 null 而不是空字符串
            }

            // 诊断：检查 RTC Engine 基本响应
            try {
                Log.d(TAG, "诊断：检查 RTC Engine 是否响应...");
                // 不调用可能阻塞的 API，只检查对象是否有效
                Log.d(TAG, "诊断：RTC Engine 对象有效: " + (rtcEngine != null));
            } catch (Exception e) {
                Log.e(TAG, "诊断：RTC Engine 检查失败！", e);
                isJoiningRoom = false;
                if (roomStateListener != null) {
                    roomStateListener.onRoomError("RTC Engine 异常");
                }
                return;
            }

            Log.d(TAG, "准备配置频道媒体选项...");
            // 准备完整的频道媒体选项（包括频道模式和用户角色）
            final ChannelMediaOptions options = new ChannelMediaOptions();
            options.channelProfile = Constants.CHANNEL_PROFILE_LIVE_BROADCASTING; // 直播模式
            options.clientRoleType = Constants.CLIENT_ROLE_BROADCASTER; // 主播角色
            options.autoSubscribeAudio = true; // 自动订阅音频
            options.autoSubscribeVideo = true; // 自动订阅视频
            options.publishMicrophoneTrack = false; // 默认不推麦克风流
            options.publishCameraTrack = false; // 默认不推摄像头流

            Log.d(TAG, "频道媒体选项配置完成");
            Log.d(TAG, "channelProfile: LIVE_BROADCASTING");
            Log.d(TAG, "clientRoleType: BROADCASTER");
            Log.d(TAG, "autoSubscribeAudio: " + options.autoSubscribeAudio);
            Log.d(TAG, "autoSubscribeVideo: " + options.autoSubscribeVideo);
            Log.d(TAG, "publishMicrophoneTrack: " + options.publishMicrophoneTrack);
            Log.d(TAG, "publishCameraTrack: " + options.publishCameraTrack);

            // 使用超时机制调用 joinChannel
            final int[] result = new int[]{-999}; // 使用数组来在内部类中修改值
            final boolean[] completed = new boolean[]{false};
            final String finalToken = token; // 创建 final 副本

            // 创建一个更安全的 joinChannel 调用方式
            final Thread joinThread = new Thread(() -> {
                try {
                    Log.d(TAG, "joinChannel 子线程开始执行...");
                    // 使用带 ChannelMediaOptions 的新 API
                    int ret = rtcEngine.joinChannel(finalToken, channelName, 0, options);
                    synchronized(completed) {
                        result[0] = ret;
                        completed[0] = true;
                    }
                    Log.d(TAG, "joinChannel 子线程执行完成，返回值: " + ret);
                } catch (Throwable e) {
                    Log.e(TAG, "joinChannel 子线程抛出异常", e);
                    synchronized(completed) {
                        completed[0] = true;
                        result[0] = -1000; // 标记为异常
                    }
                }
            });

            // 加入频道 - 使用最简单的 API
            Log.d(TAG, "开始调用 rtcEngine.joinChannel...");
            Log.d(TAG, "使用简化 API: joinChannel(token, channel, uid)");
            Log.d(TAG, "参数: token=" + (token != null && !token.isEmpty() ? "已设置" : "null") + ", channel=" + channelName);

            joinThread.start();

            // 等待最多 5 秒
            int waitCount = 0;
            while (waitCount < 50) {
                synchronized(completed) {
                    if (completed[0]) {
                        break;
                    }
                }
                try {
                    Thread.sleep(100);
                    waitCount++;
                    if (waitCount % 10 == 0) {
                        Log.d(TAG, "等待 joinChannel 完成... (" + (waitCount / 10) + " 秒)");
                    }
                } catch (InterruptedException e) {
                    Log.e(TAG, "等待被中断", e);
                    break;
                }
            }

            int ret;
            synchronized(completed) {
                ret = result[0];
            }

            if (!completed[0]) {
                Log.e(TAG, "joinChannel 调用超时（5秒），强制放弃");
                // 不要中断线程，让它自然结束
                isJoiningRoom = false;
                if (roomStateListener != null) {
                    roomStateListener.onRoomError("加入频道调用超时");
                }
                return;
            }

            Log.d(TAG, "joinChannel 返回值: " + ret);

            if (ret == 0) {
                Log.d(TAG, "joinChannel 调用成功，等待 handleJoinChannelSuccess 回调...");
                Log.d(TAG, "如果 10 秒内未收到回调，将自动超时");
                Log.d(TAG, "音视频已在初始化时启用，默认静音状态");
            } else {
                Log.e(TAG, "joinChannel 调用失败，错误码: " + ret);
                // 加入失败，重置标志并通知错误
                isJoiningRoom = false;
                if (roomStateListener != null) {
                    roomStateListener.onRoomError("加入频道失败，错误码: " + ret);
                }
            }

            Log.d(TAG, "=== RoomManager.joinChannel 完成 ===");
        } catch (Exception e) {
            Log.e(TAG, "加入频道异常", e);
            e.printStackTrace();
            // 异常时重置标志并通知错误
            isJoiningRoom = false;
            if (roomStateListener != null) {
                roomStateListener.onRoomError("加入频道异常: " + e.getMessage());
            }
        }
    }

    /**
     * 发起连麦申请
     */
    public void applyForMic(String anchorUserId) {
        if (rtmClient != null) {
            String messageContent = "{\"type\":\"mic_apply\",\"from_user\":\"" + currentUserId + "\",\"to_user\":\"" + anchorUserId + "\",\"timestamp\":" + System.currentTimeMillis() + "}";

            PublishOptions options = new PublishOptions();
            options.setChannelType(RtmChannelType.USER);

            rtmClient.publish(anchorUserId, messageContent, options, new ResultCallback<Void>() {
                @Override
                public void onSuccess(Void responseInfo) {
                    // 申请发送成功
                }

                @Override
                public void onFailure(ErrorInfo errorInfo) {
                    // 申请发送失败
                }
            });
        }
    }

    /**
     * 处理连麦申请消息
     */
    private void handleMicApplyMessage(String messageContent) {
        // 解析消息内容
        // {"type":"mic_apply","from_user":"xxx","to_user":"xxx","timestamp":xxx}

        // 这里应该解析JSON，简化处理
        if (messageContent.contains("from_user")) {
            // 提取申请人ID
            int fromStart = messageContent.indexOf("\"from_user\":\"") + "\"from_user\":\"".length();
            int fromEnd = messageContent.indexOf("\"", fromStart);
            String applicantId = messageContent.substring(fromStart, fromEnd);

            // 保存连麦申请
            micApplyRequests.put(applicantId, currentChannelName);

            // 通知UI显示连麦申请
            onMicApplyReceived(applicantId);
        }
    }

    /**
     * 处理连麦响应消息
     */
    private void handleMicResponseMessage(String messageContent) {
        // {"type":"mic_response","from_user":"anchor","to_user":"applicant","accepted":true/false,"timestamp":xxx}
        if (messageContent.contains("\"accepted\":true")) {
            // 如果接受连麦，切换为连麦者为主播角色
            rtcEngine.setClientRole(Constants.CLIENT_ROLE_BROADCASTER);
            rtcEngine.startPreview();
        }
    }

    /**
     * 处理房间通知消息
     */
    private void handleRoomNotification(String messageContent) {
        // 处理房间内广播的通知消息
    }

    /**
     * 同意连麦申请
     */
    public void acceptMicApply(String userId) {
        if (rtmClient != null) {
            String messageContent = "{\"type\":\"mic_response\",\"from_user\":\"" + currentUserId + "\",\"to_user\":\"" + userId + "\",\"accepted\":true,\"timestamp\":" + System.currentTimeMillis() + "}";

            PublishOptions options = new PublishOptions();
            options.setChannelType(RtmChannelType.USER);

            rtmClient.publish(userId, messageContent, options, new ResultCallback<Void>() {
                @Override
                public void onSuccess(Void responseInfo) {
                    // 响应发送成功，将用户提升为主播
                    promoteToBroadcaster(userId);
                }

                @Override
                public void onFailure(ErrorInfo errorInfo) {
                    // 响应发送失败
                }
            });
        }
    }

    /**
     * 拒绝连麦申请
     */
    public void rejectMicApply(String userId) {
        if (rtmClient != null) {
            String messageContent = "{\"type\":\"mic_response\",\"from_user\":\"" + currentUserId + "\",\"to_user\":\"" + userId + "\",\"accepted\":false,\"timestamp\":" + System.currentTimeMillis() + "}";

            PublishOptions options = new PublishOptions();
            options.setChannelType(RtmChannelType.USER);

            rtmClient.publish(userId, messageContent, options, new ResultCallback<Void>() {
                @Override
                public void onSuccess(Void responseInfo) {
                    // 响应发送成功
                }

                @Override
                public void onFailure(ErrorInfo errorInfo) {
                    // 响应发送失败
                }
            });
        }
    }

    /**
     * 将用户提升为主播
     */
    private void promoteToBroadcaster(String userId) {
        // 在实际应用中，这里需要通过信令服务器协调
        // 暂时模拟操作
        if (userId.equals(currentUserId)) {
            // 如果是自己，则设置为主播角色
            rtcEngine.setClientRole(Constants.CLIENT_ROLE_BROADCASTER);
            rtcEngine.startPreview();
        }
    }

    /**
     * 设置本地视频视图
     */
    public void setupLocalVideo(View view) {
        if (rtcEngine != null) {
            rtcEngine.setupLocalVideo(new VideoCanvas(view, VideoCanvas.RENDER_MODE_HIDDEN, 0));
            rtcEngine.startPreview();
        }
    }

    /**
     * 设置远程视频视图
     */
    public void setupRemoteVideo(View view, int uid) {
        if (rtcEngine != null) {
            rtcEngine.setupRemoteVideo(new VideoCanvas(view, VideoCanvas.RENDER_MODE_HIDDEN, uid));
        }
    }

    /**
     * 发送聊天消息
     */
    public void sendChatMessage(String channelName, String message) {
        if (rtmClient != null) {
            PublishOptions options = new PublishOptions();
            options.setChannelType(RtmChannelType.MESSAGE); // 发送到频道

            rtmClient.publish(channelName, message, options, new ResultCallback<Void>() {
                @Override
                public void onSuccess(Void responseInfo) {
                    // 消息发送成功
                }

                @Override
                public void onFailure(ErrorInfo errorInfo) {
                    // 消息发送失败
                }
            });
        }
    }

    /**
     * 获取房间成员列表
     */
    public List<String> getRoomMembers(String channelName) {
        Log.d(TAG, "=== RoomManager.getRoomMembers 被调用 === ");
        Log.d(TAG, "请求的频道名称: " + channelName);
        Log.d(TAG, "当前频道名称: " + currentChannelName);
        Log.d(TAG, "所有频道: " + roomMembers.keySet());

        if (roomMembers.containsKey(channelName)) {
            List<String> members = roomMembers.get(channelName);
            Log.d(TAG, "频道 " + channelName + " 的成员数: " + members.size());
            Log.d(TAG, "频道 " + channelName + " 的成员: " + members);
            return new ArrayList<>(members);
        }

        Log.e(TAG, "频道 " + channelName + " 不存在成员列表");
        Log.d(TAG, "=== getRoomMembers 返回空列表 ===");
        return new ArrayList<>();
    }

    /**
     * 离开房间
     * 注意：此方法会发起离开请求，实际状态重置由 SDK 回调完成
     */
    public void leaveRoom() {
        Log.d(TAG, "=== RoomManager.leaveRoom 开始 ===");
        Log.d(TAG, "当前状态: isInRoom=" + isInRoom + ", isLeavingRoom=" + isLeavingRoom + ", isJoiningRoom=" + isJoiningRoom);

        // 如果当前不在房间中，且不需要清理，直接返回
        if (!isInRoom && currentChannelName == null && !isJoiningRoom) {
            Log.d(TAG, "当前不在任何房间中，无需离开");
            // 确保状态完全重置
            isLeavingRoom = false;
            isJoiningRoom = false;
            return;
        }

        // 如果正在离开房间，不重复执行
        if (isLeavingRoom) {
            Log.w(TAG, "已经在离开房间中，跳过重复调用");
            return;
        }

        // 通知开始离开房间
        isLeavingRoom = true;
        if (roomStateListener != null) {
            roomStateListener.onLeavingRoom();
        }

        // 保存当前频道名，供后续清理使用
        final String channelToLeave = currentChannelName;

        // 同步执行离开操作（阻塞当前线程，直到完成或超时）
        final boolean[] leaveCompleted = new boolean[]{false};
        final Thread leaveThread = new Thread(() -> {
            try {
                if (rtcEngine != null) {
                    Log.d(TAG, "准备调用 leaveChannel...");
                    rtcEngine.leaveChannel();
                    Log.d(TAG, "已执行 rtcEngine.leaveChannel()");
                    leaveCompleted[0] = true;
                } else {
                    Log.w(TAG, "rtcEngine 为 null，跳过 leaveChannel");
                    leaveCompleted[0] = true;
                }
            } catch (Exception e) {
                Log.e(TAG, "离开 RTC 频道失败", e);
                leaveCompleted[0] = true;
            }
        });

        leaveThread.start();

        // 等待最多 1 秒，确保 leaveChannel 被调用
        try {
            Log.d(TAG, "等待 leaveChannel 发起请求（最多1秒）...");
            leaveThread.join(1000);
        } catch (InterruptedException e) {
            Log.e(TAG, "等待 leaveChannel 被中断", e);
        }

        if (!leaveCompleted[0]) {
            Log.w(TAG, "leaveChannel 调用超时（1秒），强制标记为完成");
            // 如果调用超时，仍然保持 isLeavingRoom 标志，等待回调或超时处理
            // 但会设置一个定时器，如果长时间没有回调则重置状态
            new Thread(() -> {
                try {
                    Thread.sleep(5000); // 等待5秒
                    if (isLeavingRoom) {
                        Log.e(TAG, "离开频道回调超时（5秒内未收到回调），重置状态");
                        isLeavingRoom = false;
                        isJoiningRoom = false;

                        if (roomStateListener != null) {
                            roomStateListener.onLeftRoom();
                        }
                    }
                } catch (InterruptedException e) {
                    Log.d(TAG, "离开超时检测线程被中断");
                }
            }).start();
        }

        Log.d(TAG, "离开房间操作发起完成，等待回调确认");

        Log.d(TAG, "=== RoomManager.leaveRoom 发起完成 ===");
    }

    /**
     * 处理离开频道成功事件（由 DeviceManager 调用）
     */
    public void handleLeaveChannel() {
        Log.d("Agora", "=== RoomManager.handleLeaveChannel 被调用 ===");
        Log.d("Agora", "当前频道名称: " + currentChannelName);
        Log.d("Agora", "本地用户ID: " + currentUserId);
        Log.d("Agora", "当前状态: isLeavingRoom=" + isLeavingRoom + ", isInRoom=" + isInRoom);

        // 只有在确实正在离开房间时才重置状态
        if (isLeavingRoom) {
            isInRoom = false;
            isLeavingRoom = false;
            isJoiningRoom = false;

            // 重置房间相关信息
            currentChannelName = null;
            currentUserId = null;
            currentToken = null;
            isBroadcaster = false;

            // 清空当前频道的成员列表
            if (currentChannelName != null && roomMembers.containsKey(currentChannelName)) {
                roomMembers.get(currentChannelName).clear();
                Log.d("Agora", "已清空频道 " + currentChannelName + " 的成员列表");
            }

            // 通知监听器
            if (roomStateListener != null) {
                Log.d("Agora", "通知 RoomStateListener 离开房间完成");
                roomStateListener.onLeftRoom();
            } else {
                Log.e("Agora", "roomStateListener 为 null，无法通知 UI");
            }

            // 更新成员数量的 LiveData
            memberCountLiveData.postValue(0);
        } else {
            Log.d("Agora", "非预期的离开频道回调，忽略");
        }

        Log.d("Agora", "=== handleLeaveChannel 完成 ===");
    }

    /**
     * 退出房间回调接口
     */
    public interface OnRoomEventListener {
        void onUserJoined(String userId);
        void onUserLeft(String userId);
        void onMicApplyReceived(String userId);
        void onChatMessageReceived(String userId, String message);
    }

    private OnRoomEventListener roomEventListener;

    public void setOnRoomEventListener(OnRoomEventListener listener) {
        this.roomEventListener = listener;
    }

    private void onMicApplyReceived(String userId) {
        if (roomEventListener != null) {
            roomEventListener.onMicApplyReceived(userId);
        }
    }

    /**
     * 处理用户加入事件（由 DeviceManager 调用）
     */
    public void handleUserJoined(int uid) {
        String userId = String.valueOf(uid);
        Log.d("Agora", "=== RoomManager.handleUserJoined 被调用 ===");
        Log.d("Agora", "用户ID: " + userId);
        Log.d("Agora", "当前频道名称: " + currentChannelName);

        // 使用加入的频道名称，而不是当前频道名称，以处理加入过程中的情况
        String targetChannel = currentChannelName; // 使用当前频道名称

        if (targetChannel != null && roomMembers.containsKey(targetChannel)) {
            if (!roomMembers.get(targetChannel).contains(userId)) {
                roomMembers.get(targetChannel).add(userId);
                Log.d("Agora", "添加新用户到成员列表: " + userId);
                Log.d("Agora", "当前成员数: " + roomMembers.get(targetChannel).size());
                Log.d("Agora", "成员列表: " + roomMembers.get(targetChannel));

                // 更新成员数量的 LiveData
                memberCountLiveData.postValue(roomMembers.get(targetChannel).size());
            } else {
                Log.d("Agora", "用户已在成员列表中，跳过添加: " + userId);
            }
        } else if (targetChannel != null) {
            // 如果频道不存在成员列表，创建一个新的
            List<String> members = new ArrayList<>();
            members.add(userId);
            roomMembers.put(targetChannel, members);
            Log.d("Agora", "为频道创建成员列表并添加用户: " + userId + ", 频道: " + targetChannel);

            // 更新成员数量的 LiveData
            memberCountLiveData.postValue(members.size());
        } else {
            Log.e("Agora", "无法添加用户: 当前频道名称为 null");
        }

        // 通知监听器
        if (roomEventListener != null) {
            Log.d("Agora", "通知 UI 用户加入: " + userId);
            roomEventListener.onUserJoined(userId);
        } else {
            Log.e("Agora", "roomEventListener 为 null，无法通知 UI");
        }

        Log.d("Agora", "=== handleUserJoined 完成 ===");
    }

    /**
     * 处理用户离开事件（由 DeviceManager 调用）
     */
    public void handleUserLeft(int uid) {
        String userId = String.valueOf(uid);
        Log.d("Agora", "=== RoomManager.handleUserLeft 被调用 ===");
        Log.d("Agora", "用户ID: " + userId);
        Log.d("Agora", "当前频道名称: " + currentChannelName);

        String targetChannel = currentChannelName; // 使用当前频道名称

        if (targetChannel != null && roomMembers.containsKey(targetChannel)) {
            boolean removed = roomMembers.get(targetChannel).remove(userId);
            if (removed) {
                Log.d("Agora", "从成员列表移除用户: " + userId + ", 成功: " + removed);
                Log.d("Agora", "当前成员数: " + roomMembers.get(targetChannel).size());
                Log.d("Agora", "成员列表: " + roomMembers.get(targetChannel));

                // 更新成员数量的 LiveData
                memberCountLiveData.postValue(roomMembers.get(targetChannel).size());
            } else {
                Log.d("Agora", "用户不在成员列表中: " + userId);
            }
        } else {
            Log.e("Agora", "无法移除用户: currentChannelName=" + currentChannelName + ", containsKey=" + (targetChannel != null && roomMembers.containsKey(targetChannel)));
        }

        // 通知监听器
        if (roomEventListener != null) {
            Log.d("Agora", "通知 UI 用户离开: " + userId);
            roomEventListener.onUserLeft(userId);
        } else {
            Log.e("Agora", "roomEventListener 为 null，无法通知 UI");
        }

        Log.d("Agora", "=== handleUserLeft 完成 ===");
    }

    /**
     * 处理加入频道成功事件（由 DeviceManager 调用）
     */
    public void handleJoinChannelSuccess(String channel, int uid, int elapsed) {
        isInRoom = true;
        Log.d("Agora", "=== RoomManager.handleJoinChannelSuccess 被调用 ===");
        Log.d("Agora", "频道名称: " + channel);
        Log.d("Agora", "用户ID: " + uid);
        Log.d("Agora", "本地用户ID: " + currentUserId);
        Log.d("Agora", "耗时: " + elapsed + "ms");

        // 添加用户到房间成员列表
        if (!roomMembers.containsKey(channel)) {
            roomMembers.put(channel, new ArrayList<>());
            Log.d("Agora", "创建新的成员列表，频道: " + channel);
        }

        // 只有当用户不是本地用户时才添加（本地用户已在createChatRoom中添加）
        String userIdStr = String.valueOf(uid);
        // 检查用户是否已经在成员列表中，避免重复添加
        if (!roomMembers.get(channel).contains(userIdStr)) {
            roomMembers.get(channel).add(userIdStr);
            Log.d("Agora", "添加用户到成员列表: " + uid);
        } else {
            Log.d("Agora", "用户已在成员列表中，跳过添加: " + uid);
        }

        // 更新成员数量的 LiveData
        memberCountLiveData.postValue(roomMembers.get(channel).size());

        // 标记加入完成，通知 UI
        if (isJoiningRoom) {
            isJoiningRoom = false;
            if (roomStateListener != null) {
                roomStateListener.onJoinedRoom();
            }
            Log.d("Agora", "加入房间流程完成，已通知 UI");
        }

        // 通知监听器（但排除本地用户）
        if (roomEventListener != null) {
            // 只有当加入的用户不是本地用户时，才通知 UI
            if (!String.valueOf(uid).equals(currentUserId)) {
                Log.d("Agora", "通知 UI 远程用户加入频道: " + uid);
                roomEventListener.onUserJoined(String.valueOf(uid));
            } else {
                Log.d("Agora", "本地用户加入频道，不通知 UI 添加视频视图");
            }
        } else {
            Log.e("Agora", "roomEventListener 为 null，无法通知 UI");
        }

        Log.d("Agora", "=== handleJoinChannelSuccess 完成 ===");
    }


}