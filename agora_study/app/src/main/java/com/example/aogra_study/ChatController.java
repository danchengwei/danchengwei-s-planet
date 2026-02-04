package com.example.aogra_study;

import io.agora.chat.ChatClient;
import io.agora.chat.ChatManager;
import io.agora.chat.Conversation;
import io.agora.chat.ChatMessage;
import io.agora.chat.ChatOptions;
import io.agora.MessageListener;
import io.agora.CallBack;
import android.content.Context;
import android.util.Log;
import java.util.List;
import java.util.Map;

public class ChatController {
    private static final String TAG = "Agora";
    private ChatClient chatClient;
    private ChatManager chatManager;
    private String appId;
    private String currentUsername;
    private boolean isLoggedIn = false;

    public ChatController() {
        this.chatClient = ChatClient.getInstance();
        // 初始化时暂不获取chatManager，因为可能还未初始化
        this.chatManager = null;
    }

    /**
     * 初始化聊天SDK
     */
    private Context context;
    
    public void initChat(Context context, String appId) {
        this.context = context;
        this.appId = AgoraConfig.CHAT_APP_KEY; // 强制使用Chat AppKey，避免使用RTC AppKey
        Log.d(TAG, "开始初始化Chat SDK，使用Chat AppKey: " + this.appId);
        
        try {
            // 只有在SDK未初始化或使用了错误的AppKey时才初始化
            if (!chatClient.isSdkInited()) {
                Log.d(TAG, "Chat SDK尚未初始化，开始初始化...");
                ChatOptions options = new ChatOptions();
                options.setAppKey(this.appId);
                // 设置WebSocket地址
                options.setIMServer(AgoraConfig.CHAT_IM_SERVER);
                // 设置REST API地址
                options.setRestServer(AgoraConfig.CHAT_REST_SERVER);
                // 设置是否自动登录
                options.setAutoLogin(false);
                // 设置其他选项...
                Log.d(TAG, "初始化Chat SDK，AppKey: " + this.appId + "，IMServer: " + AgoraConfig.CHAT_IM_SERVER + "，RestServer: " + AgoraConfig.CHAT_REST_SERVER);
                
                // 检查配置值是否为空
                if (AgoraConfig.CHAT_IM_SERVER == null || AgoraConfig.CHAT_IM_SERVER.isEmpty()) {
                    Log.e(TAG, "CHAT_IM_SERVER为空，登录将失败");
                }
                if (AgoraConfig.CHAT_REST_SERVER == null || AgoraConfig.CHAT_REST_SERVER.isEmpty()) {
                    Log.e(TAG, "CHAT_REST_SERVER为空，登录将失败");
                }
                
                chatClient.init(context, options); // 使用传入的Context
                Log.d(TAG, "Chat SDK初始化成功");
            } else {
                Log.d(TAG, "Chat SDK已初始化，无需重复初始化");
            }
            
            // 初始化完成后获取chatManager
            this.chatManager = chatClient.chatManager();
            Log.d(TAG, "获取chatManager成功");
        } catch (UnsatisfiedLinkError e) {
            Log.e(TAG, "Failed to initialize Chat SDK due to native library error: " + e.getMessage());
            this.chatManager = null;
        } catch (Exception e) {
            Log.e(TAG, "Failed to initialize Chat SDK: " + e.getMessage());
            this.chatManager = null;
        }
    }
    
    /**
     * 登录聊天服务器
     */
    public void login(String username, String token, final CallBack callback) {
        Log.d(TAG, "开始登录聊天服务器，用户名: " + username + "，token长度: " + (token != null ? token.length() : 0));
        
        // 确保ChatManager已初始化，只在未初始化时才初始化
        ensureChatManager();
        if (chatManager == null) {
            Log.e(TAG, "ChatManager未初始化，无法登录");
            if (callback != null) {
                callback.onError(-1, "ChatManager未初始化");
            }
            return;
        }
        
        if (isLoggedIn && currentUsername.equals(username)) {
            Log.d(TAG, "已登录，无需重复登录，当前用户名: " + username);
            if (callback != null) {
                callback.onSuccess();
            }
            return;
        }
        
        // 先登出之前的用户（如果有）
        if (isLoggedIn) {
            Log.d(TAG, "当前已有用户登录，先登出: " + currentUsername);
            chatClient.logout(false, new CallBack() {
                @Override
                public void onSuccess() {
                    Log.d(TAG, "登出成功，准备登录新用户");
                    doLogin(username, token, callback);
                }
                
                @Override
                public void onError(int code, String error) {
                    Log.e(TAG, "登出失败，错误码: " + code + "，错误信息: " + error);
                    // 登出失败也尝试登录新用户
                    doLogin(username, token, callback);
                }
                
                @Override
                public void onProgress(int progress, String status) {
                }
            });
        } else {
            doLogin(username, token, callback);
        }
    }
    
    /**
     * 执行登录操作
     */
    private void doLogin(String username, String token, final CallBack callback) {
        Log.d(TAG, "执行登录操作，用户名: " + username + "，token是否为空: " + (token == null || token.isEmpty()));
        chatClient.loginWithToken(username, token, new CallBack() {
            @Override
            public void onSuccess() {
                Log.d(TAG, "登录成功，用户名: " + username);
                currentUsername = username;
                isLoggedIn = true;
                Log.d(TAG, "当前登录状态: " + isLoggedIn + "，当前用户名: " + currentUsername);
                if (callback != null) {
                    callback.onSuccess();
                }
            }
            
            @Override
            public void onError(int code, String error) {
                Log.e(TAG, "登录失败，用户名: " + username + "，错误码: " + code + "，错误信息: " + error);
                if (callback != null) {
                    callback.onError(code, error);
                }
            }
            
            @Override
            public void onProgress(int progress, String status) {
                Log.d(TAG, "登录进度: " + progress + "%，状态: " + status + "，用户名: " + username);
            }
        });
    }
    
    /**
     * 登出聊天服务器
     */
    public void logout(final CallBack callback) {
        Log.d(TAG, "开始登出聊天服务器");
        if (!isLoggedIn) {
            Log.d(TAG, "未登录，无需登出");
            if (callback != null) {
                callback.onSuccess();
            }
            return;
        }
        
        chatClient.logout(true, new CallBack() {
            @Override
            public void onSuccess() {
                Log.d(TAG, "登出成功");
                currentUsername = null;
                isLoggedIn = false;
                if (callback != null) {
                    callback.onSuccess();
                }
            }
            
            @Override
            public void onError(int code, String error) {
                Log.e(TAG, "登出失败，错误码: " + code + "，错误信息: " + error);
                if (callback != null) {
                    callback.onError(code, error);
                }
            }
            
            @Override
            public void onProgress(int progress, String status) {
                Log.d(TAG, "登出进度: " + progress + "%，状态: " + status);
            }
        });
    }
    
    /**
     * 检查SDK是否已初始化
     */
    public boolean isSdkInited() {
        try {
            return chatClient != null && chatClient.isSdkInited();
        } catch (Exception e) {
            Log.e(TAG, "Error checking SDK status: " + e.getMessage());
            return false;
        }
    }
    
    /**
     * 确保chatManager已初始化
     */
    private void ensureChatManager() {
        if (chatManager == null && appId != null && context != null) {
            initChat(context, appId);
        }
    }

    /**
     * 发送文本消息
     */
    public ChatMessage sendTextMessage(String content, String toChatUsername) {
        Log.d(TAG, "开始发送文本消息，内容: " + content + "，接收方: " + toChatUsername + "，当前登录用户名: " + currentUsername);
        ensureChatManager();
        if (chatManager == null) {
            Log.e(TAG, "ChatManager未初始化，无法发送消息");
            throw new IllegalStateException("ChatManager not initialized");
        }
        
        if (!isLoggedIn) {
            Log.e(TAG, "未登录，无法发送消息");
            throw new IllegalStateException("Not logged in");
        }
        
        ChatMessage message = ChatMessage.createTxtSendMessage(content, toChatUsername);
        Log.d(TAG, "创建文本消息成功，消息ID: " + message.getMsgId() + "，消息类型: " + message.getType());
        chatManager.sendMessage(message);
        Log.d(TAG, "文本消息发送成功，消息ID: " + message.getMsgId() + "，发送方: " + currentUsername + "，接收方: " + toChatUsername);
        return message;
    }

    /**
     * 发送图片消息
     */
    public ChatMessage sendImageMessage(String imagePath, String toChatUsername) {
        ensureChatManager();
        if (chatManager == null) {
            throw new IllegalStateException("ChatManager not initialized");
        }
        
        ChatMessage message = ChatMessage.createImageSendMessage(imagePath, false, toChatUsername);
        chatManager.sendMessage(message);
        return message;
    }

    /**
     * 发送语音消息
     */
    public ChatMessage sendVoiceMessage(String filePath, int length, String toChatUsername) {
        ensureChatManager();
        if (chatManager == null) {
            throw new IllegalStateException("ChatManager not initialized");
        }
        
        ChatMessage message = ChatMessage.createVoiceSendMessage(filePath, length, toChatUsername);
        chatManager.sendMessage(message);
        return message;
    }

    /**
     * 加载历史消息
     */
    public List<ChatMessage> loadHistoryMessages(String conversationId, int count) {
        ensureChatManager();
        if (chatManager == null) {
            return null;
        }
        
        Conversation conversation = chatManager.getConversation(conversationId);
        if (conversation != null) {
            return conversation.loadMoreMsgFromDB(null, count);
        }
        return null;
    }

    /**
     * 注册消息监听器
     */
    public void addMessageListener(MessageListener listener) {
        Log.d(TAG, "开始注册消息监听器，当前登录用户名: " + currentUsername + "，登录状态: " + isLoggedIn);
        ensureChatManager();
        if (chatManager != null) {
            chatManager.addMessageListener(listener);
            Log.d(TAG, "消息监听器注册成功");
        } else {
            Log.e(TAG, "ChatManager未初始化，无法注册消息监听器");
        }
    }

    /**
     * 移除消息监听器
     */
    public void removeMessageListener(MessageListener listener) {
        ensureChatManager();
        if (chatManager != null) {
            chatManager.removeMessageListener(listener);
        }
    }

    /**
     * 获取会话列表
     */
    public Map<String, Conversation> getAllConversations() {
        ensureChatManager();
        if (chatManager == null) {
            return null;
        }
        return chatManager.getAllConversations();
    }

    /**
     * 删除会话
     */
    public void deleteConversation(String conversationId, boolean deleteMessages) {
        ensureChatManager();
        if (chatManager != null) {
            chatManager.deleteConversation(conversationId, deleteMessages);
        }
    }
}