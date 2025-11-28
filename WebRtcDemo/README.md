# WebRtcDemo

这是一个基于WebRTC的Android视频通话应用示例。

## 项目结构

- `app/` - Android客户端代码
- `signaling-server/` - 信令服务器代码

## 环境要求

- Android Studio
- Node.js (用于信令服务器)
- WebSocket连接支持

## 快速开始

### 1. 启动信令服务器

```bash
cd signaling-server
npm install
node server.js
```

或者使用开发模式（需要全局安装nodemon）：

```bash
cd signaling-server
npm install
npm run dev
```

服务器默认运行在端口8080。

### 2. 配置Android客户端

确保在[NetworkConfig.java](file:///Users/xiwang/danchangwei/MyRespository/danchengwei-s-planet/WebRtcDemo/app/src/main/java/com/example/webrtctest/NetworkConfig.java)中正确设置了信令服务器地址：

```java
public class NetworkConfig {
    // 信令服务器主机地址（根据实际部署环境修改）
    private static final String SIGNALING_SERVER_HOST = "10.0.2.2"; // Android模拟器访问本机地址
    
    // 信令服务器端口
    private static final int SIGNALING_SERVER_PORT = 8080;
    
    // ... 其余代码不变
}
```

对于真机调试，请将`SIGNALING_SERVER_HOST`修改为运行信令服务器的计算机的实际IP地址。

### 3. 构建和运行Android应用

使用Android Studio打开项目，构建并运行应用。

## 功能特性

- 视频通话（支持前置/后置摄像头切换）
- 音频控制（麦克风开关）
- 多人房间支持
- 房间管理（创建房间、加入房间、获取房间信息）

## 使用说明

1. 启动应用后，首先会自动连接信令服务器
2. 输入房间号：
   - 点击"创建房间"创建一个新的房间
   - 点击"加入房间"加入一个已存在的房间
   - 点击"获取房间信息"查看当前所有活跃房间的信息
3. 点击"检查设备"可以检测设备信息和测试音频功能

注意：只能加入已经创建的房间，不能随意加入不存在的房间。
