package com.example.webrtctest;

/**
 * 网络配置实体类
 * 用于集中管理应用中的网络相关配置
 */
public class NetworkConfig {
    // 信令服务器地址
    private static String signalingServerHost = "10.8.193.46"; // 默认使用当前获取到的IP地址
    private static int signalingServerPort = 8080;
    
    // 是否为真机调试模式
    private static boolean isRealDeviceDebug = true; // 默认为真机调试
    
    // 获取WebSocket服务器地址
    public static String getWebSocketServerUrl() {
        return "ws://" + signalingServerHost + ":" + signalingServerPort;
    }
    
    // 获取HTTP服务器地址（如果需要）
    public static String getHttpServerUrl() {
        return "http://" + signalingServerHost + ":" + signalingServerPort;
    }
    
    // 获取信令服务器主机地址
    public static String getSignalingServerHost() {
        return signalingServerHost;
    }
    
    // 设置信令服务器主机地址
    public static void setSignalingServerHost(String host) {
        NetworkConfig.signalingServerHost = host;
    }
    
    // 获取信令服务器端口
    public static int getSignalingServerPort() {
        return signalingServerPort;
    }
    
    // 设置信令服务器端口
    public static void setSignalingServerPort(int port) {
        NetworkConfig.signalingServerPort = port;
    }
    
    // 是否为真机调试
    public static boolean isRealDeviceDebug() {
        return isRealDeviceDebug;
    }
    
    // 设置是否为真机调试
    public static void setRealDeviceDebug(boolean realDeviceDebug) {
        isRealDeviceDebug = realDeviceDebug;
    }
    
    // 获取适用于模拟器的地址
    public static String getEmulatorServerUrl() {
        return "ws://10.0.2.2:" + signalingServerPort;
    }
    
    // 根据设备类型获取合适的服务器地址
    public static String getSuitableServerUrl() {
        if (isRealDeviceDebug()) {
            return getWebSocketServerUrl();
        } else {
            return getEmulatorServerUrl();
        }
    }
}