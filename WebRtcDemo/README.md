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

### 3. 权限管理

- 摄像头权限 (CAMERA)
- 麦克风权限 (RECORD_AUDIO)
- 音频设置权限 (MODIFY_AUDIO_SETTINGS)
- 运行时权限请求
- 应用启动时自动获取权限

### 4. 设备信息显示

- 在主界面显示基础设备信息（设备名称、Android版本等）
- 点击"检查设备"按钮可查看音视频相关设备信息和测试功能
- 设备信息仅显示与音视频通话相关的内容（摄像头、麦克风、系统版本等）
- 设备测试功能包括摄像头预览和音频录制播放测试

### 5. 服务器连接状态显示

- 显示当前连接的服务器IP地址和端口号
- 显示连接状态（连接中、连接成功、连接断开、连接错误）
- 提供详细的错误信息

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
2. MainActivity 自动请求必要权限（摄像头、麦克风等）
3. MainActivity 自动连接本地信令服务器 (ws://10.0.2.2:8080)
4. MainActivity 显示设备信息（设备名称、Android版本等）
5. MainActivity 显示服务器连接状态，包括IP地址和端口号
6. 用户可以点击"检查设备"按钮查看详细设备信息和测试功能
7. 在设备测试页面可以启动摄像头预览和音频测试
8. 用户输入房间号并点击"加入房间"
9. 应用跳转到 WebRtcActivity，并传递房间号参数
10. WebRtcActivity 连接信令服务器并加入指定房间
11. 当有其他用户加入同一房间时，开始 WebRTC 连接过程
12. 通过信令服务器交换 offer/answer 和 ICE candidates
13. 建立点对点的音视频连接

## 运行环境

### Android 端要求

- Android 7.0 (API Level 24) 或更高版本
- 摄像头和麦克风权限
- 网络访问权限
- 扬声器和音频设置权限

### 服务端要求

- Node.js 12.x 或更高版本
- npm 包管理器

## 快速开始

### 启动信令服务器

#### 方法一：使用 npm 命令（推荐）

```bash
cd signaling-server
npm start
```

#### 方法二：直接使用 node 命令

```bash
cd signaling-server
node server.js
```

服务器将监听 8080 端口。

### 验证服务器是否运行

启动服务器后，您会看到类似以下的输出：

```
信令服务器运行在端口 8080
在Android模拟器中使用地址: ws://10.0.2.2:8080
在真机调试中，请替换为您的本机IP地址
```

您也可以通过以下命令验证服务器是否在运行：

```bash
netstat -an | grep 8080
```

如果服务器正在运行，您应该能看到类似这样的输出：
```
tcp4       0      0  *.8080                 *.*                    LISTEN
```

### 停止服务器

在服务器运行的终端窗口中按 `Ctrl+C` 可以停止服务器。

### 开发模式运行（可选）

如果您正在开发服务器代码并希望在文件更改时自动重启服务器，可以使用：

```bash
cd signaling-server
npm run dev
```

这需要先安装 nodemon：
```bash
npm install -g nodemon
```

### 运行 Android 应用

1. 确保信令服务器正在运行
2. 在 Android Studio 中打开项目
3. 构建并运行应用
4. 应用启动后会自动连接信令服务器，并在UI上显示连接状态、IP地址和端口号
5. 点击"检查设备"按钮可查看详细设备信息和测试功能
6. 在设备测试页面可以测试摄像头预览和音频功能
7. 测试功能

## 网络配置

项目使用 [NetworkConfig.java](file:///Users/xiwang/danchangwei/MyRespository/danchengwei-s-planet/WebRtcDemo/app/src/main/java/com/example/webrtctest/NetworkConfig.java) 类来集中管理网络配置，包括服务器地址和端口。

### 默认配置

- 信令服务器地址: `ws://10.8.193.53:8080` (适用于真机调试)
- 模拟器地址: `ws://10.0.2.2:8080` (适用于 Android 模拟器)

### 配置说明

1. **真机调试**: 确保 Android 设备与开发机在同一局域网中，并在 [NetworkConfig.java](file:///Users/xiwang/danchangwei/MyRespository/danchengwei-s-planet/WebRtcDemo/app/src/main/java/com/example/webrtctest/NetworkConfig.java) 中设置正确的开发机 IP 地址
2. **模拟器调试**: 使用默认的 `10.0.2.2` 地址
3. **外网访问**: 需要使用内网穿透工具或部署到公网服务器

### 修改配置

如需修改服务器地址，可以编辑 [NetworkConfig.java](file:///Users/xiwang/danchangwei/MyRespository/danchengwei-s-planet/WebRtcDemo/app/src/main/java/com/example/webrtctest/NetworkConfig.java) 文件中的 `signalingServerHost` 变量，或者在代码中动态设置：

```java
NetworkConfig.setSignalingServerHost("your.server.ip.address");
NetworkConfig.setSignalingServerPort(8080);
```

## 注意事项

1. 该项目仅适用于局域网环境测试
2. 如需外网访问，需要部署公网可访问的信令服务器
3. 需要授予应用摄像头和麦克风权限
4. Android 9.0 及以上版本需要处理网络权限问题
5. 应用启动后应首先点击"检查并获取权限"按钮获取必要权限

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