package com.example.aogra_study;

import io.agora.rtm.RtmClient;
import io.agora.rtm.RtmConfig;
import io.agora.rtm.RtmMessage;
import io.agora.rtm.ErrorInfo;
import io.agora.rtm.ResultCallback;
import io.agora.rtm.StreamChannel;
import io.agora.rtm.RtmEventListener;
import io.agora.rtm.PublishOptions;
import io.agora.rtm.RtmConstants.RtmChannelType;
import io.agora.rtm.RtmConstants.RtmErrorCode;
import android.util.Log;
import java.util.List;

public class RTMController {
    private static final String TAG = "RTMController";
    private RtmClient rtmClient;
    private String currentUserId;

    /**
     * 初始化RTM客户端
     */
    public void initializeRtmClient(String appId, String userId, RtmEventListener eventListener) {
        try {
            this.currentUserId = userId;
            RtmConfig rtmConfig = new RtmConfig.Builder(appId, userId)
                    .eventListener(eventListener)
                    .build();
            this.rtmClient = RtmClient.create(rtmConfig);
        } catch (UnsatisfiedLinkError e) {
            Log.e(TAG, "Failed to initialize RTM client due to native library error: " + e.getMessage());
        } catch (Exception e) {
            Log.e(TAG, "Failed to initialize RTM client: " + e.getMessage());
        }
    }

    /**
     * 登录RTM服务
     */
    public void login(String token, ResultCallback<Void> callback) {
        if(rtmClient != null) {
            rtmClient.login(token, callback);
        } else {
            Log.w(TAG, "RTM client is not initialized");
            if (callback != null) {
                callback.onFailure(new ErrorInfo(RtmErrorCode.INVALID_PARAMETER, "RTM client is not initialized"));
            }
        }
    }

    /**
     * 登出RTM服务
     */
    public void logout(ResultCallback<Void> callback) {
        if(rtmClient != null) {
            rtmClient.logout(callback);
        } else {
            Log.w(TAG, "RTM client is not initialized");
            if (callback != null) {
                callback.onFailure(new ErrorInfo(RtmErrorCode.INVALID_PARAMETER, "RTM client is not initialized"));
            }
        }
    }

    /**
     * 发送点对点消息
     */
    public void sendMessageToPeer(String peerId, String message, ResultCallback<Void> callback) {
        if(rtmClient != null) {
            PublishOptions options = new PublishOptions();
            options.setChannelType(RtmChannelType.USER);
            rtmClient.publish(peerId, message, options, callback);
        } else {
            Log.w(TAG, "RTM client is not initialized");
            if (callback != null) {
                callback.onFailure(new ErrorInfo(RtmErrorCode.INVALID_PARAMETER, "RTM client is not initialized"));
            }
        }
    }

    /**
     * 创建流频道
     */
    public StreamChannel createStreamChannel(String channelName) {
        if(rtmClient != null) {
            try {
                return rtmClient.createStreamChannel(channelName);
            } catch (Exception e) {
                e.printStackTrace();
                return null;
            }
        }
        Log.w(TAG, "RTM client is not initialized");
        return null;
    }

    /**
     * 查询用户在线状态
     */
    public void queryPeersOnlineStatus(List<String> peerIds, ResultCallback<List<Boolean>> callback) {
        // RTM SDK中没有queryPeersOnlineStatus方法，该功能可能需要通过presence来实现
        // 这里暂时保留接口但不实现具体逻辑
        if(rtmClient != null) {
            // 实际上RTM SDK中没有这个方法，需要通过其他方式实现
        } else {
            Log.w(TAG, "RTM client is not initialized");
            if (callback != null) {
                callback.onFailure(new ErrorInfo(RtmErrorCode.INVALID_PARAMETER, "RTM client is not initialized"));
            }
        }
    }

    /**
     * 获取RTM客户端实例
     */
    public RtmClient getRtmClient() {
        return rtmClient;
    }

    /**
     * 销毁RTM客户端
     */
    public void destroy() {
        if (rtmClient != null) {
            rtmClient.release();
            rtmClient = null;
        }
    }

    /**
     * 获取当前用户ID
     */
    public String getCurrentUserId() {
        return currentUserId;
    }
}