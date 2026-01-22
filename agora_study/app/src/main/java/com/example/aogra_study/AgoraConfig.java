package com.example.aogra_study;

/**
 * Agora SDK配置类
 * 管理App ID和其他配置信息
 */
public class AgoraConfig {
    // 您的Agora App ID
    public static final String APP_ID = "7828b636a0f74028bd7bab84a6b6274a";

    // Token（在生产环境中应从服务器获取）
    // 在开发测试阶段，可以使用空字符串或临时Token
    // 注意：临时Token通常只有24小时有效期，过期后需要重新生成
    public static final String TEMP_TOKEN = "007eJxTYIjboy7pv/63oJ6YjGPbx5zXLDeU9JZbHX594ULJ7d9W85gUGMwtjCySzIzNEg3SzE0MgOwU86TEJAuTRLMkMyNzk0Tm1QWZDYGMDMvN2BkYoRDEZ2MwNDI2MTVjYAAALNodcg==";  // 开发模式使用空Token

    // 是否使用开发模式（不使用Token）
    public static final boolean DEVELOPMENT_MODE = true;

    // 频道名称（可根据需要动态生成）
    public static final String DEFAULT_CHANNEL_NAME = "test_channel";

    // 用户ID（在实际应用中应该从用户系统获取）
    public static final String DEFAULT_USER_ID = "user_" + System.currentTimeMillis();

    /**
     * 获取App ID
     */
    public static String getAppId() {
        return APP_ID;
    }

    /**
     * 获取默认Token
     * 注意：在生产环境中，Token应该从服务器动态获取
     */
    public static String getDefaultToken() {
        // 使用临时 Token（RTC 需要有效的 Token）
        // RTM 可以在 createChatRoom 中单独处理
        return TEMP_TOKEN;
    }

    /**
     * 生成用户ID
     */
    public static String generateUserId() {
        return "user_" + System.currentTimeMillis() + "_" + (int)(Math.random() * 10000);
    }

    /**
     * 验证App ID格式
     */
    public static boolean isValidAppId(String appId) {
        return appId != null && appId.length() == 32 && appId.matches("[0-9a-f]+");
    }
}