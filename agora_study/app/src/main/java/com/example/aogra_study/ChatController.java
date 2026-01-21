package com.example.aogra_study;

import io.agora.chat.ChatClient;
import io.agora.chat.ChatManager;
import io.agora.chat.Conversation;
import io.agora.chat.ChatMessage;
import io.agora.chat.ChatOptions;
import io.agora.MessageListener;
import android.content.Context;
import android.util.Log;
import java.util.List;
import java.util.Map;

public class ChatController {
    private ChatClient chatClient;
    private ChatManager chatManager;
    private String appId;

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
        this.appId = appId;
        
        try {
            // 如果尚未初始化，则初始化Chat SDK
            if (!chatClient.isSdkInited()) {
                ChatOptions options = new ChatOptions();
                options.setAppKey(appId);
                // 设置其他选项...
                chatClient.init(context, options); // 使用传入的Context
            }
            
            // 初始化完成后获取chatManager
            this.chatManager = chatClient.chatManager();
        } catch (UnsatisfiedLinkError e) {
            Log.e("ChatController", "Failed to initialize Chat SDK due to native library error: " + e.getMessage());
        } catch (Exception e) {
            Log.e("ChatController", "Failed to initialize Chat SDK: " + e.getMessage());
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
        ensureChatManager();
        if (chatManager == null) {
            throw new IllegalStateException("ChatManager not initialized");
        }
        
        ChatMessage message = ChatMessage.createTxtSendMessage(content, toChatUsername);
        chatManager.sendMessage(message);
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
        ensureChatManager();
        if (chatManager != null) {
            chatManager.addMessageListener(listener);
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