package com.example.aogra_study;

import android.content.Context;
import android.util.Log;
import android.view.View;

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
    
    // 设备状态监听器
    private DeviceStatusListener deviceStatusListener;
    
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
    
    public void setDeviceStatusListener(DeviceStatusListener listener) {
        this.deviceStatusListener = listener;
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
            // 设置事件处理器
            // 注意：这里需要重新设置事件处理器，因为外部引擎可能已经有其他处理器
            // 但这可能会导致问题，所以我们暂时不设置
        }
        
        // 启用音频和视频模块
        rtcEngine.enableAudio();
        Log.d(TAG, "RTC 音频模块已启用。");
        rtcEngine.enableVideo();
        Log.d(TAG, "RTC 视频模块已启用。");
        
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
        
        this.currentChannelName = channelName;
        this.currentUserId = userId;
        this.currentToken = token;
        this.isBroadcaster = isBroadcaster;
        
        // 直接加入 RTC 频道，不需要等待 RTM 登录
        Log.d(TAG, "直接加入 RTC 频道（不等待 RTM）...");
        joinChannel(channelName, userId, token, isBroadcaster);
        
        // 尝试初始化 RTM（用于聊天功能）
        try {
            Log.d(TAG, "初始化 RTM 客户端（用于聊天功能）...");
            
            // 在开发测试阶段，如果 Token 为空，使用 App ID 直接登录
            String rtmToken = token;
            if (token == null || token.isEmpty()) {
                Log.d(TAG, "Token 为空，使用 App ID 直接登录 RTM");
                rtmToken = null; // RTM SDK 在开发模式下可以使用 null Token
            }
            
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
        
        Log.d(TAG, "=== RoomManager.createChatRoom 完成 ===");
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
        try {
            Log.d(TAG, "=== RoomManager.joinChannel 开始 ===");
            Log.d(TAG, "频道名称: " + channelName);
            Log.d(TAG, "用户ID: " + userId);
            Log.d(TAG, "是否为主播: " + isBroadcaster);
            
            // 设置频道属性
            rtcEngine.setChannelProfile(Constants.CHANNEL_PROFILE_LIVE_BROADCASTING);
            Log.d(TAG, "已设置频道配置为直播模式");
            
            // 设置用户角色 - 确保至少是主播才能发送音视频流
            if (isBroadcaster) {
                rtcEngine.setClientRole(Constants.CLIENT_ROLE_BROADCASTER);
                Log.d(TAG, "已设置用户角色为主播");
            } else {
                // 观众也需要能接收音视频流，但为了测试，我们设置为主播
                rtcEngine.setClientRole(Constants.CLIENT_ROLE_BROADCASTER);
                Log.d(TAG, "已设置用户角色为主播（观众模式）");
            }
            
            // 准备频道媒体选项
            ChannelMediaOptions options = new ChannelMediaOptions();
            options.autoSubscribeAudio = true;
            options.autoSubscribeVideo = true;
            options.clientRoleType = Constants.CLIENT_ROLE_BROADCASTER;
            options.token = token;
            
            Log.d(TAG, "频道媒体选项配置完成");
            Log.d(TAG, "autoSubscribeAudio: " + options.autoSubscribeAudio);
            Log.d(TAG, "autoSubscribeVideo: " + options.autoSubscribeVideo);
            
            // 加入频道
            Log.d(TAG, "开始调用 rtcEngine.joinChannel...");
            int ret = rtcEngine.joinChannel(token, channelName, userId, 0);
            Log.d(TAG, "joinChannel 返回值: " + ret);
            
            if (ret == 0) {
                Log.d(TAG, "joinChannel 调用成功");
            } else {
                Log.e(TAG, "joinChannel 调用失败，错误码: " + ret);
            }
            
            // 开启本地预览
            rtcEngine.startPreview();
            Log.d(TAG, "本地预览已启动");
            
            Log.d(TAG, "=== RoomManager.joinChannel 完成 ===");
        } catch (Exception e) {
            Log.e("Agora", "加入频道失败", e);
            e.printStackTrace();
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
     */
    public void leaveRoom() {
        if (rtcEngine != null) {
            rtcEngine.leaveChannel();
            rtcEngine.destroy();
            rtcEngine = null;
        }
        
        if (rtmClient != null) {
            rtmClient.logout(new ResultCallback<Void>() {
                @Override
                public void onSuccess(Void responseInfo) {
                    rtmClient.release();
                    rtmClient = null;
                }
                
                @Override
                public void onFailure(ErrorInfo errorInfo) {
                    rtmClient.release();
                    rtmClient = null;
                }
            });
        }
        
        isInRoom = false;
        currentChannelName = null;
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
        
        if (currentChannelName != null && roomMembers.containsKey(currentChannelName)) {
            if (!roomMembers.get(currentChannelName).contains(userId)) {
                roomMembers.get(currentChannelName).add(userId);
                Log.d("Agora", "添加新用户到成员列表: " + userId);
                Log.d("Agora", "当前成员数: " + roomMembers.get(currentChannelName).size());
                Log.d("Agora", "成员列表: " + roomMembers.get(currentChannelName));
            } else {
                Log.d("Agora", "用户已在成员列表中，跳过添加: " + userId);
            }
        } else {
            Log.e("Agora", "无法添加用户: currentChannelName=" + currentChannelName + ", containsKey=" + roomMembers.containsKey(currentChannelName));
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
        
        if (currentChannelName != null && roomMembers.containsKey(currentChannelName)) {
            boolean removed = roomMembers.get(currentChannelName).remove(userId);
            Log.d("Agora", "从成员列表移除用户: " + userId + ", 成功: " + removed);
            Log.d("Agora", "当前成员数: " + roomMembers.get(currentChannelName).size());
            Log.d("Agora", "成员列表: " + roomMembers.get(currentChannelName));
        } else {
            Log.e("Agora", "无法移除用户: currentChannelName=" + currentChannelName + ", containsKey=" + roomMembers.containsKey(currentChannelName));
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
        Log.d("Agora", "耗时: " + elapsed + "ms");
        
        // 添加用户到房间成员列表
        if (!roomMembers.containsKey(channel)) {
            roomMembers.put(channel, new ArrayList<>());
            Log.d("Agora", "创建新的成员列表，频道: " + channel);
        }
        
        if (!roomMembers.get(channel).contains(String.valueOf(uid))) {
            roomMembers.get(channel).add(String.valueOf(uid));
            Log.d("Agora", "添加用户到成员列表: " + uid);
            Log.d("Agora", "当前成员数: " + roomMembers.get(channel).size());
            Log.d("Agora", "成员列表: " + roomMembers.get(channel));
        } else {
            Log.d("Agora", "用户已在成员列表中，跳过添加: " + uid);
        }
        
        // 通知监听器
        if (roomEventListener != null) {
            Log.d("Agora", "通知 UI 加入频道成功: " + uid);
            roomEventListener.onUserJoined(String.valueOf(uid));
        } else {
            Log.e("Agora", "roomEventListener 为 null，无法通知 UI");
        }
        
        Log.d("Agora", "=== handleJoinChannelSuccess 完成 ===");
    }
}