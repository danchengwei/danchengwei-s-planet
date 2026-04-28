# 汉字测评取景框 —— WebView 镂空融合相机技术报告

## 1. 项目概述

本项目通过 **原生 Android + H5 React** 的混合方案，实现了一个汉字测评的"取景框"交互界面：H5 负责整页 UI（状态栏、标题 Tab、米白色遮罩、底部快门/相册按钮等），**仅在取景框区域做"镂空"**；原生 Android 侧在 WebView 之下放置 [TextureView](app/src/main/res/layout/activity_main.xml#L10-L13) 实时显示相机预览，再在两者之间放置 [ScanOverlayView](app/src/main/java/com/example/mydemo/ScanOverlayView.java) 绘制扫描线、粒子、L 角标等动画。

核心思路：
- WebView 设为背景透明且位于顶层（`elevation=16dp`），内部用 `box-shadow: 0 0 0 9999px` 刷满米白色做遮罩，取景框位置则是一块透明的 DOM 元素——从而"镂空"出一个洞。
- CameraX 的预览通过 `TextureView`（位于最底层）从这个洞里透出。
- H5 通过 `getBoundingClientRect()` 把镂空坐标通过 `JavascriptInterface` 回传给原生，原生据此同步 `TextureView` 的 `LayoutParams` 与 `ScanOverlayView` 的绘制区域。

视图合成顺序（从底到顶）：[activity_main.xml](app/src/main/res/layout/activity_main.xml)

1. `FrameLayout` 根容器（深色底 `#1A1F28`，相机未开启前的占位色）
2. `TextureView cameraTexture`（相机预览，默认 match_parent，后续被 JS 回传的洞口坐标裁剪）
3. `ScanOverlayView scanOverlay`（`elevation=2dp`，软件层绘制）
4. `WebView webView`（`elevation=16dp`，顶层，背景透明）

---

## 2. 客户端（Android / Java）

### 2.1 工程配置

[app/build.gradle](app/build.gradle)

- `compileSdk 31`, `minSdk 21`, `targetSdk 31`，Java 1.8。
- 关键依赖：
  - `androidx.camera:camera-core / camera-camera2 / camera-lifecycle / camera-view` 1.1.0
  - `com.google.guava:guava:30.1.1-android`（`ListenableFuture`）
  - `androidx.appcompat:appcompat:1.3.0`、`material:1.4.0`
- `preBuild.dependsOn('copyH5ToAssets')`：构建 APK 前自动把 `h5/dist` 拷贝到 [app/src/main/assets/h5](app/src/main/assets/h5)，供离线模式使用。

[AndroidManifest.xml](app/src/main/AndroidManifest.xml)

- 权限：`CAMERA`、`INTERNET`、`ACCESS_NETWORK_STATE`、读写外部存储。
- `usesCleartextTraffic="true"`：允许明文 HTTP（dev server 为 `http://`）。
- `Theme.MyDemo` 继承 `Theme.MaterialComponents.DayNight.DarkActionBar`，`onCreate` 中通过 [getSupportActionBar().hide()](app/src/main/java/com/example/mydemo/MainActivity.java#L64-L66) 隐藏 ActionBar。

### 2.2 MainActivity 主要职责

[MainActivity.java](app/src/main/java/com/example/mydemo/MainActivity.java) 主要字段：

- `WebView webView`、`TextureView cameraTexture`、`ScanOverlayView scanOverlay`。
- `Camera boundCamera`：CameraX 返回的相机实例（焦点/测光用）。
- `isCameraStarting`、`pendingOpenCameraAfterPermission`：去重与权限回调状态位。
- `PLACEHOLDER_WHEN_CAMERA_OFF = 0xFF1A1F28`：相机未绑定前取景框里"透出"的深色底。

#### 2.2.1 WebView 初始化

[initWebView()](app/src/main/java/com/example/mydemo/MainActivity.java#L118-L207) 关键点：

- `WebView.setWebContentsDebuggingEnabled(true)`：允许 `chrome://inspect` 远程调试。
- `WebSettings`：`JavaScriptEnabled`、`DomStorageEnabled`、`AllowFileAccess`、`UseWideViewPort`、`LoadWithOverviewMode`；在 `JELLY_BEAN+` 开放 `AllowFileAccessFromFileURLs` / `AllowUniversalAccessFromFileURLs`，`LOLLIPOP+` 设 `MIXED_CONTENT_ALWAYS_ALLOW`（兼容 dev server 的 http）。
- `WebViewClient`:
  - 重写 `shouldOverrideUrlLoading`（新旧签名各一份）默认返回 `false`（交给 WebView 自己处理）。
  - `onReceivedError`（新/旧）打印日志并在主 frame 出错时 `Toast` 提示。
  - `onPageFinished` 里延迟 500ms 执行一段 `evaluateJavascript`，检查 `#root` 是否渲染出子节点，验证 H5 是否可用：[MainActivity.java:177-181](app/src/main/java/com/example/mydemo/MainActivity.java#L177-L181)。
- `WebChromeClient.onConsoleMessage`：把 H5 侧 `console.*` 通过 `Log.i("H5Console", ...)` 打进 logcat，方便调试。
- `webView.addJavascriptInterface(new JsBridge(), "Android")`：把 `JsBridge` 暴露为 `window.Android`。
- `webView.setBackgroundColor(0)` + `setLayerType(LAYER_TYPE_HARDWARE, null)`：**把 WebView 背景置为完全透明**（这是镂空方案能看到底层相机的前提），同时启用硬件层避免透明区域出现黑块。

#### 2.2.2 加载策略

[loadH5Page()](app/src/main/java/com/example/mydemo/MainActivity.java#L112-L116) 当前硬编码为 `http://10.8.227.13:5173/`，直连 Vite dev server。离线模式（`file:///android_asset/h5/index.html`）由 `copyH5ToAssets` Gradle 任务提供素材，但代码当前走的是 dev 联调。

### 2.3 JsBridge —— JS ↔ Native 通道

[JsBridge 内部类](app/src/main/java/com/example/mydemo/MainActivity.java#L329-L397) 暴露了 5 个方法，所有方法都包了 `runOnUiThread` 保证 UI 线程安全：

| JS 调用 | 原生处理 |
|---|---|
| `Android.openCamera()` | 申请权限、绑定 CameraX 预览，幂等 |
| `Android.takePhoto()` | 当前仅 Toast + log（未实现真正的 ImageCapture） |
| `Android.chooseFromAlbum()` | 当前仅 Toast + log |
| `Android.showMessage(msg)` | Toast + log，供 H5 通用提示 |
| `Android.setNativeHoleRect(l,t,w,h)` | 接收 H5 的取景框坐标，转换为物理像素后同步给 `ScanOverlayView` 与 `TextureView` |

#### 2.3.1 CSS → 物理像素转换（关键）

[setNativeHoleRect()](app/src/main/java/com/example/mydemo/MainActivity.java#L363-L396) 是整个视图对齐的关键。因为 H5 的 `getBoundingClientRect()` 给出的是 **CSS 像素**，而 Android 视图坐标是 **物理像素**：

```java
int webViewWidth = webView.getWidth();
webView.evaluateJavascript(
    "(function(){return window.innerWidth;})()",
    value -> {
        int cssWidth = Integer.parseInt(value.replace("\"", ""));
        float accurateScale = webViewWidth / (float) cssWidth;
        int physicalLeft   = Math.round(left   * accurateScale);
        int physicalTop    = Math.round(top    * accurateScale);
        int physicalWidth  = Math.round(width  * accurateScale);
        int physicalHeight = Math.round(height * accurateScale);
        scanOverlay.setHoleFromWeb(physicalLeft, physicalTop,
                physicalLeft + physicalWidth, physicalTop + physicalHeight);
        updateTextureViewBounds();
    });
```

该逻辑先读取 WebView 的物理宽度，再通过 `evaluateJavascript` 回读 `window.innerWidth`（CSS 宽度），用两者比值作为缩放因子。375 只作为备用基准（见 `cssPixelRatio` 的 fallback），真实使用的是回读到的 `cssWidth` 做精确缩放。

### 2.4 镂空同步到 TextureView

[updateTextureViewBounds()](app/src/main/java/com/example/mydemo/MainActivity.java#L241-L256) 把 `cameraTexture` 的 `FrameLayout.LayoutParams` 的 `leftMargin / topMargin / width / height` 设置为镂空矩形。这样 **TextureView 只在洞口大小内显示**，不会在遮罩覆盖区也继续绘制相机画面（节约 GPU 合成开销）。

[setupHoleSyncForTextureView()](app/src/main/java/com/example/mydemo/MainActivity.java#L232-L239) 通过给 `ScanOverlayView` 挂 `OnLayoutChangeListener`，在 Overlay 布局变化时（如旋屏、尺寸变化）重新同步 TextureView 位置。

### 2.5 相机权限与 CameraX 绑定

- [openCameraPreviewFromUser()](app/src/main/java/com/example/mydemo/MainActivity.java#L90-L97) 有两个幂等保护：已有 `boundCamera` 或正在 `isCameraStarting` 时直接返回，避免 H5 多次触发（包括 `useEffect` 里自动开启 + 用户再次点）。
- [checkCameraPermissionForOpen()](app/src/main/java/com/example/mydemo/MainActivity.java#L104-L110) 未授权时调 `ActivityCompat.requestPermissions`，回调 `onRequestPermissionsResult` 里根据 `pendingOpenCameraAfterPermission` 决定是否 `startCamera()`。
- [startCamera()](app/src/main/java/com/example/mydemo/MainActivity.java#L278-L294) 通过 `ProcessCameraProvider.getInstance(this)` 拿到异步 `ListenableFuture`，回调在主线程执行 `bindPreview`。
- [bindPreview()](app/src/main/java/com/example/mydemo/MainActivity.java#L296-L307)：构建 `Preview`，选后置摄像头 `LENS_FACING_BACK`，`setSurfaceProvider` 中把 `SurfaceRequest` post 到 `cameraTexture` 线程后交给内部类 `SurfaceTextureHolder.attach`。

### 2.6 SurfaceTextureHolder —— CameraX → TextureView 粘合

[SurfaceTextureHolder](app/src/main/java/com/example/mydemo/MainActivity.java#L419-L458) 把 CameraX 的 `SurfaceRequest` 对接 `TextureView`：

- 若 `TextureView` 的 `SurfaceTexture` 已就绪，直接 `connect`。
- 否则注册 `SurfaceTextureListener.onSurfaceTextureAvailable`，在首帧 surface 可用时再 connect（监听器用完立即置 null，防止重复）。
- `connect` 中：调用 `setDefaultBufferSize(size.getWidth(), size.getHeight())` 让 SurfaceTexture 的内部缓冲与 CameraX 建议的分辨率一致，然后 `new Surface(st)` 交给 `request.provideSurface(...)`；完成回调负责 `surface.release()`。

### 2.7 点击对焦

[setupHoleTouchFocus()](app/src/main/java/com/example/mydemo/MainActivity.java#L209-L226) + [focusPreviewAt()](app/src/main/java/com/example/mydemo/MainActivity.java#L258-L276)：

- 在 WebView 上挂 `OnTouchListener`（WebView 在最顶层，所以先拿到触摸事件，返回 `false` 再让 WebView 自行处理点击事件）。
- `ACTION_DOWN` 时，若 `scanOverlay.hasHole()` 且点位落在 `holeRect` 内，则执行对焦。
- 使用 `SurfaceOrientedMeteringPointFactory` 而非 `DisplayOrientedMeteringPointFactory`，因为预览是走 `TextureView` 而不是 `PreviewView`：工厂输入为 `cameraTexture.getWidth/Height`，再以视图坐标创建测光点（`size=0.1f`）。
- `FocusMeteringAction` 构造后 `setAutoCancelDuration(3, SECONDS)`，调用 `boundCamera.getCameraControl().startFocusAndMetering(action)`。

### 2.8 ScanOverlayView —— 镂空内部的原生动画

[ScanOverlayView.java](app/src/main/java/com/example/mydemo/ScanOverlayView.java) 是一个自定义 `View`，软件层（`LAYER_TYPE_SOFTWARE`），负责在 H5 传回的 `holeRect` 内绘制：

- `init()`: 初始化 5 支 `Paint`
  - `pWhiteStroke`：白色实线，画 L 角标
  - `pDash`：`#D9FFFFFF` 白 + `DashPathEffect({dp(5), dp(4)})`，画十字虚线、内框、对角线（"米字格"）
  - `pCyanLine`：`#FF66EEFF` 宽 `dp(2.2f)`，水平扫描线
  - `pGlow`：动态 `LinearGradient`（`#7722CCFF` → 透明）叠加在扫描线下方做辉光
  - `pParticle`：填充，动态 alpha，绘制粒子
- `startAnimator()`：一个 `ValueAnimator` 2400ms 线性循环，驱动 `scanPhase ∈ [0,1]`；每帧 `invalidate()`。`onDetachedFromWindow` 中 cancel 防泄漏。
- [setHoleFromWeb()](app/src/main/java/com/example/mydemo/ScanOverlayView.java#L89-L93)：保存矩形，`holeReady = width>8 && height>8`，一并 `invalidate()`。
- [onDraw()](app/src/main/java/com/example/mydemo/ScanOverlayView.java#L120-L200) 流程：
  1. 计算 `innerRect`：占 `holeRect` 的 95% 居中，即取景框再向内缩 5%。
  2. `clipPath` 用 `addRoundRect(holeL..holeB, cornerRx=dp(16))` 裁剪为圆角矩形，后续绘制都在这个 clip 内（所以边缘不会超出 H5 的圆角）。
  3. 画"米字 + 十字"虚线：中心竖线、中心横线、内框四边、两条对角线，全部使用 `pDash`。
  4. 画 4 个 L 形白色角标（`drawCornerBracket` 按象限处理方向）。
  5. 画扫描线：`scanY = innerT + dp(14) + scanPhase * (innerH - 28)`，横跨内框并稍微外延 `dp(3)`。
  6. 扫描线下方画 48dp 的竖向渐变辉光矩形（`pGlow` shader 每帧重建）。
  7. 画 14 个粒子：坐标结合 `Math.cos/sin` + `System.currentTimeMillis() * 0.0018` 漂移，半径 `dp(1.8+i%4*0.6)`，alpha 由 `sin(now*0.004+i*0.7)` 驱动在 40~255 之间。

这部分 UI 故意放在原生而非 H5，原因是 **WebView 的透明 + box-shadow 遮罩方案** 下，若把扫描动画也放在 WebView 里会与遮罩层叠，发生 compositing 干扰；放到 TextureView 和 WebView 之间（`elevation=2dp` < `16dp`）则始终位于相机画面上、米白色遮罩下，视觉层级正确。

### 2.9 生命周期

- `onBackPressed`：优先 `webView.goBack()`，无历史则 super。
- `onDestroy`：`webView.destroy()`。
- CameraX 的释放由 `bindToLifecycle(this, ...)` 自动托管，无需手动 unbind。

---

## 3. 前端（H5 / React + Vite）

### 3.1 工程配置

[h5/package.json](h5/package.json)

- 依赖：`react@^19.2.5`、`react-dom@^19.2.5`。
- 构建：`vite@^8`、`@vitejs/plugin-react@^6`、`eslint@^10`。

[vite.config.js](h5/vite.config.js) 针对 **Android WebView** 的兼容性做了 4 点定制：

1. **自定义插件 `stripScriptModuleType`**（仅 build）：`transformIndexHtml` 的 post 阶段移除 `type="module"` 与 `crossorigin` 属性——WebView 在 `file://` 下不执行 `type=module` 脚本，带 `crossorigin` 也会被 CORS 拒绝。
2. **oxc target: es2019**：Vite 8 用 oxc 处理源码，降级后避免 `??=` 等 ES2020 特性让旧 WebView 报 `Unexpected token '='`。
3. **optimizeDeps.rolldownOptions.transform.target = 'es2019'**：`react-dom` 内含 `??=`，node_modules 预打包也需要降级。
4. **build 单包 IIFE**：`rollupOptions.output.format = 'iife'`, `inlineDynamicImports: true`, `cssCodeSplit: false`, `target: 'es2015'`——打成一个自执行函数，`index.html` 用普通 `<script>` 就能加载，兼容 `file:///android_asset/` 场景。
5. **server.host: 0.0.0.0 + hmr.host: 10.8.227.21**：允许 Android 设备直连 dev server；HMR 必须写设备能路由到的电脑 IP 而不是 `localhost`。

### 3.2 入口

[main.jsx](h5/src/main.jsx)

```jsx
createRoot(document.getElementById('root')).render(
  <StrictMode><App /></StrictMode>
)
```

[index.css](h5/src/index.css) 全局重置 margin/padding/box-sizing，禁止 `html/body overflow`，字体栈以 `-apple-system, BlinkMacSystemFont` 开头。

### 3.3 App 组件结构

[App.jsx](h5/src/App.jsx) 的视图树自上而下：

- `.status-bar`（44px 时间/信号/电量）
- `.header`（54px 返回按钮 + 单/多字测评 Tab）
- `.camera-section > .camera-section-inner`
  - `#h5-viewfinder-hole.viewfinder-hole-anchor` —— **唯一的真实镂空元素**，`ref={holeRef}`
  - `.viewfinder-white-ring` —— 白色 2px 边框，独立 DOM，`z-index:2`，不参与镂空
  - `.left-decoration > .monkey-icon`（🐵 装饰）
  - `.instruction` 文案："请将汉字居中放入方框内拍摄"
- `.bottom-controls`（快门 80px + 相册按钮）
- `.bottom-indicator`（iOS 式底部胶囊）

`activeTab` 本地状态用 `useState('single')`，点击 Tab 切换。

### 3.4 镂空实现 —— 核心 CSS

[App.css](h5/src/App.css#L165-L178) 是整个方案的灵魂：

```css
.viewfinder-hole-anchor {
  position: absolute;
  left: 50%; top: 50%;
  transform: translate(-50%, -50%);
  width: min(82vw, 320px);
  height: min(54vh, 400px);
  max-height: 440px;
  border-radius: 20px;
  background: transparent;
  box-shadow: 0 0 0 9999px rgba(252, 248, 238, 0.96);
  pointer-events: none;
}
```

原理：

- 元素自身 **透明**，但向外做一圈极宽（9999px）的实色 `box-shadow`，颜色即整页的"米白色遮罩"。
- 向外发散的阴影覆盖了屏幕上所有非镂空区域，视觉上看起来就像"中间挖了个洞"。
- `border-radius: 20px` 让洞口是圆角矩形，与原生 `ScanOverlayView.clipPath` 的 `dp(16)` 基本对齐。
- `pointer-events: none` 让触摸事件穿透到 WebView —— 再由原生 `webView.setOnTouchListener` 判断命中并触发对焦。

白色边框是独立元素 [.viewfinder-white-ring](h5/src/App.css#L180-L193)，尺寸与锚点一模一样、`z-index:2`；与镂空分离的好处是可以独立调整视觉层次，不会被 `box-shadow` 吃掉。

其他 UI 层（status-bar / header / bottom-controls / bottom-indicator）都有自己的 **不透明背景**（米白渐变 `#fdfbf5→#f7f3ea` 等）与 `z-index: 3`，高于 box-shadow 的 0 层级，保证它们在视觉上覆盖在遮罩之上、结构清晰。

### 3.5 与原生的坐标同步

[App.jsx useEffect](h5/src/App.jsx#L38-L57) 是前后端对齐的关键：

```jsx
useEffect(() => {
  reportHoleRect()
  const tAutoOpen = window.setTimeout(() => callAndroid('openCamera'), 350)
  const onResize = () => reportHoleRect()
  window.addEventListener('resize', onResize)
  let ro
  if (typeof ResizeObserver !== 'undefined') {
    ro = new ResizeObserver(reportHoleRect)
    if (holeRef.current) ro.observe(holeRef.current)
    ro.observe(document.body)
  }
  const tReport = window.setTimeout(reportHoleRect, 400)
  return () => { /* 解绑 */ }
}, [])
```

触发上报的 4 个时机：

1. 挂载时立即上报一次。
2. `window.resize`（旋屏 / 软键盘弹起）。
3. `ResizeObserver` 同时观察镂空元素与 `document.body`（捕获 Flex 布局变化、安全区变化等）。
4. 400ms 后再兜底上报一次（应对首帧 body 尺寸尚未稳定的情况）。

[reportHoleRect()](h5/src/App.jsx#L25-L36) 调用 `holeRef.current.getBoundingClientRect()` 并把 `left/top/width/height` 四舍五入后通过 `callAndroid('setNativeHoleRect', ...)` 回传。

[callAndroid()](h5/src/App.jsx#L13-L23) 是统一的桥接封装：检查 `window.Android[method]` 存在，`try/catch` 打日志，返回 bool 指示是否调用成功——这让同一套代码在浏览器预览（无 `window.Android`）下也不会崩溃。

### 3.6 自动开启相机

挂载 350ms 后调用 `callAndroid('openCamera')`，由原生侧做权限申请与幂等保护（见 2.5 节）。用户也可通过其他交互再次触发，原生 `boundCamera != null || isCameraStarting` 判断会直接跳过重复请求。

### 3.7 底部按钮与桥接调用

- 快门按钮 → `callAndroid('takePhoto')`
- 相册按钮 → `callAndroid('chooseFromAlbum')`
- 返回按钮 → `callAndroid('showMessage', '返回')`（目前仅 toast，未做业务）

按钮样式细节（[App.css](h5/src/App.css)）：

- `.shutter-button`: 80px 圆形，5px 白描边，双层渐变（外壳 `#fff1b8→#ffcb3a`，内核 radial `#fff9c4→#ffd54f→#ffa800`），`box-shadow` + `:active transform: scale(0.93)` 做按压反馈。
- `.album-thumb` 是纯 CSS 画的"相册图"：`::before` 作顶部横线，`::after` 通过多重 `box-shadow` 叠出 3 条平行线构成"照片堆"效果。
- `@media (max-width: 360px)`：小屏下 padding 收紧、快门按钮降到 72px。

---

## 4. 通信链路总览

```
┌────────────────── WebView (elevation=16dp，透明) ──────────────────┐
│  React App                                                          │
│    getBoundingClientRect() ──► window.Android.setNativeHoleRect()   │
│    openCamera / takePhoto / chooseFromAlbum / showMessage ─► Android│
└─────────────────────────────────▲───────────────────────────────────┘
                                  │ box-shadow 遮罩外，镂空内透明
                                  │
┌────────────────── ScanOverlayView (elevation=2dp) ─────────────────┐
│  holeRect 接收 → onDraw: 角标 / 虚线米字 / 扫描线 / 辉光 / 粒子       │
└─────────────────────────────────▲───────────────────────────────────┘
                                  │
┌───────────────────── TextureView (底层，随洞口缩放) ────────────────┐
│  CameraX Preview → SurfaceRequest → SurfaceTexture → Surface        │
│  点击对焦: SurfaceOrientedMeteringPointFactory → FocusMeteringAction │
└─────────────────────────────────────────────────────────────────────┘
```

**关键一次镂空同步流程（以旋屏为例）**：

1. WebView 宽度变化 → `ResizeObserver` 触发 → React 调 `reportHoleRect()`。
2. `window.Android.setNativeHoleRect(left, top, w, h)`（CSS 像素）。
3. 原生 `evaluateJavascript("window.innerWidth")` 读取 CSS 宽度。
4. 按 `webView.getWidth() / cssWidth` 缩放为物理像素。
5. `scanOverlay.setHoleFromWeb(...)` → `invalidate()`，`updateTextureViewBounds()` 更新 `TextureView` 的 `LayoutParams`。
6. `ScanOverlayView` 的 `OnLayoutChangeListener` 若 overlay 自身布局再次变化，会再次 `updateTextureViewBounds()` 作为兜底。

---

## 5. 已实现功能一览与边界

已实现：

- React + Vite 的汉字测评 UI（状态栏、Tab、镂空取景框、指令文案、快门/相册按钮、底部指示器）。
- CSS `box-shadow` 镂空方案 + H5 ↔ 原生坐标同步（`setNativeHoleRect`）。
- CameraX 后置摄像头预览绑定到 `TextureView`，预览区只在镂空范围内布局。
- 镂空区域点击对焦（`SurfaceOrientedMeteringPointFactory` + `FocusMeteringAction`）。
- 原生取景框动效（白色 L 角标、米字虚线网格、蓝青扫描线 + 渐变辉光、14 粒粒子）。
- 首帧进入自动申请相机权限并开启预览，含幂等与权限被拒的状态回退。
- `WebChromeClient.onConsoleMessage` / `onPageFinished` 渲染自检等调试通道。
- Vite 构建产物对旧 WebView 的兼容：es2019/es2015 降级、移除 `type="module"` / `crossorigin`、IIFE 单包。

当前未实现（代码中仅 Toast 占位）：

- [takePhoto](app/src/main/java/com/example/mydemo/MainActivity.java#L335-L345)：未接入 CameraX `ImageCapture`。
- [chooseFromAlbum](app/src/main/java/com/example/mydemo/MainActivity.java#L347-L353)：未接入 `ACTION_PICK` / `PhotoPicker`。
- 离线加载：`copyH5ToAssets` 已配置，但 [loadH5Page](app/src/main/java/com/example/mydemo/MainActivity.java#L112-L116) 仍硬编码 dev server URL（IP `10.8.227.13:5173`）。

---

## 6. 值得注意的工程细节

1. **WebView 透明的三件套**：`webView.setBackgroundColor(0)` + `setLayerType(HARDWARE, null)` + 根 FrameLayout 深色底。三者配合才能让 box-shadow 镂空出来的洞是"真·透明"——少一样就可能出现黑底、白底或花屏。
2. **elevation 而非 Z 顺序**：`TextureView` 默认层级已高于普通 View，改用 `elevation` 明确 WebView 最顶（16dp）、Overlay 次之（2dp）、TextureView 最底，避免 `SurfaceView` 类的合成顺序坑。
3. **CSS 宽度回读而非 densityDpi**：H5 的 `window.innerWidth` 是 WebView 视口逻辑宽度，和 `DisplayMetrics.density` 并不总一致（WebView 内部可缩放）。用 `evaluateJavascript` 实测是最鲁棒的。
4. **ResizeObserver + 400ms 兜底**：避免首次布局尚未稳定就上报错误尺寸；也覆盖 StrictMode 双渲染 / 字体加载后布局微调 / 底部导航栏滑出等场景。
5. **SurfaceOrientedMeteringPointFactory**：因为没有用 `PreviewView`，所以不能用 `DisplayOrientedMeteringPointFactory`；以 TextureView 尺寸构建即可正确映射触摸坐标到传感器平面。
6. **Canvas 软件层**：`ScanOverlayView.setLayerType(LAYER_TYPE_SOFTWARE, null)` —— 扫描线的 `LinearGradient` 每帧重建 shader，软件层能避免部分硬件驱动对 shader 缓存的异常；对这种小区域、低成本绘制无明显性能影响。
