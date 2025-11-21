# WebRtcDemo 项目说明

这是一个基于 Android 平台的 WebRTC 视频通话演示项目，实现了点对点的音视频通信功能。

## 项目结构

```
WebRtcDemo/
├── app/                    # Android 应用主模块
│   ├── src/main/java/com/example/webrtctest/
│   │   ├── MainActivity.java           # 主界面，用于输入房间号和加入房间
│   │   ├── WebRtcActivity.java         # WebRTC 核心功能实现
│   │   ├── WebRtcSignalingClient.java  # 信令客户端，处理 WebSocket 通信
│   │   └── WebSocketClientWrapper.java # WebSocket 客户端包装类
│   └── src/main/res/       # 资源文件
│       ├── layout/         # 布局文件
│       └── ...             # 其他资源文件
├── signaling-server/       # 信令服务器
│   ├── server.js           # WebSocket 信令服务器实现
│   └── package.json        # 服务器依赖配置
├── gradle/                 # Gradle 配置
├── build.gradle            # 项目级构建配置
├── settings.gradle         # 项目设置
└── gradle.properties       # Gradle 属性配置
```

## 功能模块

### 1. Android 客户端

#### 主要组件

1. **MainActivity**
   - 应用入口界面
   - 负责建立 WebSocket 连接
   - 提供房间号输入和加入房间功能
   - 连接成功后跳转到 WebRtcActivity

2. **WebRtcActivity**
   - WebRTC 核心功能实现
   - 音视频流的捕获、传输和渲染
   - 用户界面控制（麦克风开关、摄像头开关、挂断等）
   - 与信令服务器通信

3. **WebRtcSignalingClient**
   - 信令客户端实现
   - 处理 WebSocket 连接和消息通信
   - 负责发送和接收 WebRTC 信令（offer/answer/ICE candidates）

4. **WebSocketClientWrapper**
   - 对 Java-WebSocket 库的封装
   - 提供更简单的 WebSocket 客户端接口

### 2. 信令服务器

- 基于 Node.js 和 ws 库实现
- 负责在客户端之间转发 WebRTC 信令消息
- 支持房间管理功能
- 处理用户加入/离开事件

## 技术框架

### Android 端

- **WebRTC** - Google 开源的实时通信框架
- **Java-WebSocket** - Java WebSocket 客户端库
- **Material Design** - Google 的设计语言
- **AndroidX** - Android 官方支持库

### 服务端

- **Node.js** - JavaScript 运行时环境
- **ws** - Node.js WebSocket 库

## 工作流程

1. 用户打开应用，进入 MainActivity
2. MainActivity 自动连接本地信令服务器 (ws://10.0.2.2:8080)
3. 用户输入房间号并点击"加入房间"
4. 应用跳转到 WebRtcActivity，并传递房间号参数
5. WebRtcActivity 连接信令服务器并加入指定房间
6. 当有其他用户加入同一房间时，开始 WebRTC 连接过程
7. 通过信令服务器交换 offer/answer 和 ICE candidates
8. 建立点对点的音视频连接

## 运行环境

### Android 端要求

- Android 7.0 (API Level 24) 或更高版本
- 摄像头和麦克风权限
- 网络访问权限

### 服务端要求

- Node.js 12.x 或更高版本
- npm 包管理器

## 快速开始

### 启动信令服务器

```bash
cd signaling-server
npm install
npm start
```

服务器将监听 8080 端口。

### 运行 Android 应用

1. 确保信令服务器正在运行
2. 在 Android Studio 中打开项目
3. 构建并运行应用
4. 在设备或模拟器上测试功能

## 网络配置

- 信令服务器地址: `ws://10.0.2.2:8080` (适用于 Android 模拟器)
- 局域网访问: 需要将地址修改为实际的服务器 IP
- 外网访问: 需要使用内网穿透工具或部署到公网服务器

## 注意事项

1. 该项目仅适用于局域网环境测试
2. 如需外网访问，需要部署公网可访问的信令服务器
3. 需要授予应用摄像头和麦克风权限
4. Android 9.0 及以上版本需要处理网络权限问题

## 依赖库

### Android 依赖

```toml
[versions]
webrtc = "1.0.43591"
javawebsocket = "1.5.3"
material = "1.13.0"
appcompat = "1.7.1"
```

### 服务端依赖

```json
{
  "dependencies": {
    "ws": "^8.0.0"
  }
}
```