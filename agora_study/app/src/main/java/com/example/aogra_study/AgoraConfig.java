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
    public static final String TEMP_TOKEN = "007eJxTYJjZoL9qiqRSy2FtC/esGpWP76bOkIhzqTi26I8ql6/ruZcKDOYWRhZJZsZmiQZp5iYGQHaKeVJikoVJolmSmZG5SSLH86bMhkBGhvSu9ayMDBAI4rMxGBoZm5iaMTAAACtoHgo=";  // 开发模式使用空Token

    // 是否使用开发模式（不使用Token）
    public static final boolean DEVELOPMENT_MODE = true;

    // 频道名称（可根据需要动态生成）
    public static final String DEFAULT_CHANNEL_NAME = "test_channel";

    // 用户ID（在实际应用中应该从用户系统获取）
    public static final String DEFAULT_USER_ID = "user_" + System.currentTimeMillis();

    // Chat相关配置
    // Chat AppKey
    public static final String CHAT_APP_KEY = "6110009367#1647862";
    // Chat数据中心
    public static final String CHAT_DATA_CENTER = "Singapore";
    // Chat数据中心代码
    public static final String CHAT_AREA_CODE = "SG";
    // Chat WebSocket地址
    public static final String CHAT_IM_SERVER = "msync-api-61.chat.agora.io";
    // Chat REST API地址
    public static final String CHAT_REST_SERVER = "a61.chat.agora.io";
    // Chat测试用户名
    public static final String CHAT_TEST_USERNAME = "test1";
    // 第二个测试用户
    public static final String CHAT_TEST_USERNAME_2 = "test2";
    // test1测试用户的token
    public static final String CHAT_TEST_TOKEN = "007eJxTYODQ+uuzvmvJyq4lle+1llYwM7bNNI5iOHFIjdXI1zzh6CwFBnMLI4skM2OzRIM0cxMDIDvFPCkxycIk0SzJzMjcJHHhh6bMhkBGhoOvKpgYGVgZGIEQxFdhsDA1TjVLMzfQNTA0T9Y1NEwz1LWwSErWNTBONjJIMUwxNrM0AwDRHyXZ";
    // test2测试用户的token
    public static final String CHAT_TEST_TOKEN_2 = "007eJxTYPiwndFD6EOIzWF5rcr5CwTvhGs+f62TN29HvMMf66alqkoKDOYWRhZJZsZmiQZp5iYGQHaKeVJikoVJolmSmZG5SWL/h6bMhkBGhoTFnxgZGVgZGIEQxFdhsDA1TjWxMDPQNTA0T9Y1NEwz1E00ME/VTUsyT7IwNklKTrG0AAAnLCcB";

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