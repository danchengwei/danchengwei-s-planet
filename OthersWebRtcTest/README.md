# WebRTC测试项目

这是一个基于WebRTC技术的视频通话测试应用，用于演示浏览器间的实时通信功能。该项目支持摄像头控制、媒体编解码选择、以及基于房间号的连接管理。

## 项目功能

- 📹 摄像头启动与停止控制
- 🔊 麦克风静音控制
- 🌐 房间号管理与连接
- 📱 编解码能力选择
- 💻 设备信息展示
- ✅ 连接状态反馈
- 📱 响应式UI设计

## 技术栈

- **前端框架**: React
- **构建工具**: Vite
- **实时通信**: WebRTC API + WebSocket
- **后端服务**: Express + ws (WebSocket服务器)
- **UI组件**: CSS + FontAwesome图标
- **状态管理**: React Hooks

## 项目结构

```
├── index.html         # 入口HTML文件
├── package.json       # 项目配置和依赖
├── server.js          # WebSocket信令服务器
├── src/               # 源代码目录
│   ├── App.jsx        # 主应用组件
│   ├── App.css        # 应用样式
│   ├── index.css      # 全局样式
│   └── main.jsx       # React渲染入口
├── temp/              # 临时文件目录
│   ├── index.html     # 临时演示HTML
│   └── webrtc_demo.js # WebRTC演示脚本
└── vite.config.js     # Vite配置文件
```

## 核心模块说明

### 1. 媒体流管理

负责摄像头和麦克风的访问控制，包括权限请求、流获取和释放。

### 2. WebRTC连接管理

处理PeerConnection的创建、配置、媒体轨道添加以及通过WebSocket的信令交换。

### 3. 房间号系统

实现基于房间号的连接标识，用户需要输入房间号才能启动摄像头。

### 4. 编解码选择

提供H.264和VP8等编解码器的选择功能，影响视频传输质量和兼容性。

### 5. UI控制界面

包含摄像头控制、麦克风控制、编解码选择和状态展示的用户界面。

## 如何使用

### 安装依赖

```bash
npm install
```

### 启动开发服务器

```bash
npm run dev
```

### 启动信令服务器

```bash
npm run server
```

### 构建生产版本

```bash
npm run build
```

### 运行步骤

1. 首先启动信令服务器：`npm run server`
2. 启动开发服务器：`npm run dev`
3. 打开浏览器访问应用（通常是 http://localhost:5173）
4. 输入房间号或创建新房间
5. 点击"开始摄像头"按钮
6. 浏览器会请求摄像头和麦克风权限
7. 授权后，应用会通过信令服务器建立WebRTC连接
8. 可以使用界面上的控制按钮进行操作

### 信令服务器说明

信令服务器运行在 http://localhost:8080，WebSocket服务地址为 ws://localhost:8080/webrtc。

信令服务器主要功能：
- 房间创建和管理
- 用户连接管理
- WebRTC信令消息转发
- 用户状态同步
- 聊天消息广播

## 代码逻辑说明

### 核心函数

#### `startCamera()`
- 检查WebRTC支持
- 请求媒体权限
- 获取用户媒体流
- 设置本地视频预览
- 调用setupLocalConnection建立连接

#### `setupLocalConnection()`
- 创建PeerConnection对象
- 设置房间号标识
- 添加本地媒体轨道
- 创建和设置Offer
- 模拟信令交换
- 设置远程描述

#### `stopCamera()`
- 停止所有媒体轨道
- 关闭PeerConnection
- 重置状态

## 扩展说明

### 关于房间号功能

该项目实现了完整的房间号功能，包括：

1. 基于WebSocket的信令服务器
2. 房间创建和加入逻辑
3. 多用户连接管理
4. 信令消息转发和处理
5. 用户状态同步

### WebRTC连接限制

- 需要使用HTTPS协议或localhost
- 某些浏览器可能限制自动播放音频和视频
- 网络环境（如NAT穿透）可能影响连接质量

## 浏览器兼容性

- Chrome 74+
- Firefox 66+
- Safari 13+
- Edge 80+

## 许可证

该项目仅供学习和测试使用。