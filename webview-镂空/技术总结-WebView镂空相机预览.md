# WebView 镂空相机预览 - 技术总结

## 一、项目概述

本项目实现了一个基于 WebView 与原生相机预览融合的功能：H5 页面通过镂空区域透出底层相机画面，原生侧在镂空区域内绘制扫描动效。

---

## 二、核心架构

### 2.1 层级关系（根据实际项目布局）

```xml
<!-- activity_main.xml -->
<FrameLayout>
    <!-- 底层：相机预览 -->
    <TextureView android:id="@+id/cameraTexture" />
    
    <!-- 中层：原生绘制层 -->
    <ScanOverlayView android:id="@+id/scanOverlay" android:elevation="2dp" />
    
    <!-- 顶层：H5 页面 -->
    <WebView android:id="@+id/webView" android:elevation="16dp" />
</FrameLayout>
```

**层级说明**：
- **TextureView**（底层）：显示相机实时画面
- **ScanOverlayView**（中层）：绘制扫描装饰（角标、虚线、粒子）
- **WebView**（顶层）：H5 UI 界面，中间区域透明让相机画面透出

### 2.2 为什么使用 TextureView 而非 SurfaceView？

```java
// MainActivity.java 注释说明
// TextureView 与 WebView 同属普通 View 合成顺序，避免 SurfaceView 盖住 WebView
```

**原因**：SurfaceView 是独立窗口，会覆盖在 WebView 之上；TextureView 是普通 View，可以通过层级关系精确控制。

---

## 三、核心实现

### 3.1 镂空效果实现（H5 端）

#### 实现原理

```css
/* App.css */
.viewfinder-hole-anchor {
  position: absolute;
  left: 50%;
  top: 50%;
  transform: translate(-50%, -50%);
  width: min(82vw, 320px);    /* 宽度：屏幕 82% 或最大 320px */
  height: min(54vh, 400px);   /* 高度：屏幕 54% 或最大 400px */
  border-radius: 20px;
  background: transparent;     /* 中间透明 */
  box-shadow: 0 0 0 9999px rgba(252, 248, 238, 0.96);  /* 四周遮罩 */
}
```

**技巧**：利用 `box-shadow` 的超大扩散半径（9999px）覆盖整个屏幕，形成"取景框"效果。

#### 坐标上报机制

```jsx
// App.jsx
const reportHoleRect = () => {
  const el = holeRef.current
  const r = el.getBoundingClientRect()
  callAndroid(
    'setNativeHoleRect',
    Math.round(r.left),
    Math.round(r.top),
    Math.round(r.width),
    Math.round(r.height)
  )
}

useEffect(() => {
  reportHoleRect()  // 首次上报
  
  const onResize = () => reportHoleRect()
  window.addEventListener('resize', onResize)
  
  let ro
  if (typeof ResizeObserver !== 'undefined') {
    ro = new ResizeObserver(reportHoleRect)
    ro.observe(holeRef.current)
    ro.observe(document.body)
  }
  
  // 延迟再次上报确保渲染完成
  const tReport = window.setTimeout(reportHoleRect, 400)
  
  return () => {
    window.removeEventListener('resize', onResize)
    if (ro) ro.disconnect()
    window.clearTimeout(tReport)
  }
}, [])
```

**上报时机**：
1. 页面加载完成
2. 窗口大小变化（旋转屏幕等）
3. 元素尺寸变化（动态布局调整）
4. 延迟 400ms 后再次上报（确保 CSS 动画完成）

---

### 3.2 坐标转换（核心难点）

#### 问题根源

H5 通过 `getBoundingClientRect()` 获取的是 **CSS 逻辑像素**，而 Android 原生使用的是 **物理像素**，两者存在缩放比例差异。

**示例**：
```
H5 上报: left=37, top=133, width=320, height=400 (CSS 像素)
手机物理屏幕: 1080px 宽
H5 页面 CSS 宽度: 375px
实际缩放比例: 1080 / 375 = 2.88

转换后:
left = 37 * 2.88 = 107px
top = 133 * 2.88 = 383px
width = 320 * 2.88 = 922px
height = 400 * 2.88 = 1152px
```

#### 解决方案

```java
// MainActivity.java - JsBridge.setNativeHoleRect
@JavascriptInterface
public void setNativeHoleRect(int left, int top, int width, int height) {
    runOnUiThread(() -> {
        // 获取 WebView 物理宽度
        int webViewWidth = webView.getWidth();
        
        // 通过 JS 获取 H5 页面 CSS 宽度
        webView.evaluateJavascript(
            "(function(){return window.innerWidth;})()",
            value -> {
                try {
                    int cssWidth = Integer.parseInt(value.replace("\"", ""));
                    
                    // 计算准确的缩放比例
                    float accurateScale = webViewWidth / (float)cssWidth;
                    
                    // 转换坐标：CSS 像素 → 物理像素
                    int physicalLeft = Math.round(left * accurateScale);
                    int physicalTop = Math.round(top * accurateScale);
                    int physicalWidth = Math.round(width * accurateScale);
                    int physicalHeight = Math.round(height * accurateScale);
                    
                    Log.d("MainActivity", "H5 坐标: left=" + left + ", top=" + top + ", width=" + width + ", height=" + height);
                    Log.d("MainActivity", "CSS 宽度: " + cssWidth + ", 物理宽度: " + webViewWidth + ", 缩放比例: " + accurateScale);
                    Log.d("MainActivity", "物理坐标: left=" + physicalLeft + ", top=" + physicalTop + ", width=" + physicalWidth + ", height=" + physicalHeight);
                    
                    // 更新镂空区域
                    scanOverlay.setHoleFromWeb(physicalLeft, physicalTop, 
                        (float) physicalLeft + physicalWidth, 
                        (float) physicalTop + physicalHeight);
                    
                    // 同步更新 TextureView 位置
                    updateTextureViewBounds();
                } catch (Exception e) {
                    Log.e("MainActivity", "解析 CSS 宽度失败", e);
                }
            }
        );
    });
}
```

**关键要点**：
1. ✅ 不使用 `webView.getScale()`（可能返回 1.0，不准确）
2. ✅ 通过 `window.innerWidth` 动态获取 H5 实际 CSS 宽度
3. ✅ 计算 `accurateScale = 物理宽度 / CSS 宽度`
4. ✅ 所有坐标乘以缩放比例转换为物理像素

---

### 3.3 TextureView 位置同步

```java
private void updateTextureViewBounds() {
    if (!scanOverlay.hasHole()) {
        return;
    }
    
    RectF holeRect = scanOverlay.getHoleRect();
    
    FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) cameraTexture.getLayoutParams();
    params.leftMargin = (int) holeRect.left;
    params.topMargin = (int) holeRect.top;
    params.width = (int) holeRect.width();
    params.height = (int) holeRect.height();
    cameraTexture.setLayoutParams(params);
    
    Log.d("MainActivity", "更新 TextureView 位置: " + holeRect.toString());
}
```

**监听机制**：

```java
private void setupHoleSyncForTextureView() {
    scanOverlay.addOnLayoutChangeListener((v, left, top, right, bottom, 
        oldLeft, oldTop, oldRight, oldBottom) -> {
        if (scanOverlay.hasHole()) {
            updateTextureViewBounds();
        }
    });
}
```

---

### 3.4 原生绘制层（ScanOverlayView）

#### 绘制内容

```java
// ScanOverlayView.java - onDraw 方法
@Override
protected void onDraw(Canvas canvas) {
    // 1. 延伸十字虚线（基于完整镂空区域）
    canvas.drawLine(cx, holeT + inset, cx, holeB - inset, pDash);
    canvas.drawLine(holeL + inset, cy, holeR - inset, cy, pDash);
    
    // 2. 内部装饰区域（95% 比例）
    float innerW = hw * 0.95f;
    float innerH = hh * 0.95f;
    
    // 3. 米字格虚线
    canvas.drawRect(innerL, innerT, innerR, innerB, pDash);
    canvas.drawLine(cx, innerT, cx, innerB, pDash);
    canvas.drawLine(innerL, cy, innerR, cy, pDash);
    canvas.drawLine(innerL, innerT, innerR, innerB, pDash);
    canvas.drawLine(innerL, innerB, innerR, innerT, pDash);
    
    // 4. 四角 L 形白色标记
    drawCornerBracket(canvas, innerL, innerT, bracket, true, true);
    drawCornerBracket(canvas, innerR, innerT, bracket, true, false);
    drawCornerBracket(canvas, innerL, innerB, bracket, false, true);
    drawCornerBracket(canvas, innerR, innerB, bracket, false, false);
    
    // 5. 扫描线（带动画）
    float scanY = innerT + margin + scanPhase * (innerH - 2 * margin);
    canvas.drawLine(innerL - dp(3), scanY, innerR + dp(3), scanY, pCyanLine);
    
    // 6. 扫描线发光效果
    Shader shader = new LinearGradient(cx, scanY, cx, scanY + dp(40),
        new int[]{Color.parseColor("#7722CCFF"), Color.TRANSPARENT},
        new float[]{0f, 1f}, Shader.TileMode.CLAMP);
    
    // 7. 粒子动效
    for (int i = 0; i < 14; i++) {
        double w = (i * 1.1 + now * 0.0018) % 6.28318;
        float ox = cx + (float) Math.cos(w) * innerW * 0.38f;
        canvas.drawCircle(ox, oy, pr, pParticle);
    }
}
```

#### 动画实现

```java
private void startAnimator() {
    animator = ValueAnimator.ofFloat(0f, 1f);
    animator.setDuration(2400);  // 2.4 秒完成一次扫描
    animator.setRepeatCount(ValueAnimator.INFINITE);
    animator.setInterpolator(new LinearInterpolator());
    animator.addUpdateListener(a -> {
        scanPhase = (float) a.getAnimatedValue();
        invalidate();  // 触发重绘
    });
    animator.start();
}
```

#### 内部装饰比例调整过程

```java
// 最初版本：内部装饰太小（62%）
float innerW = Math.min(hw * 0.62f, hh * 0.72f);

// 调整 1：占满整个区域（100%）- 外框被遮挡
float innerW = hw;
float innerH = hh;

// 调整 2：90% 比例 - 还是偏小
float innerW = hw * 0.9f;
float innerH = hh * 0.9f;

// 最终版本：95% 比例 - 合适
float innerW = hw * 0.95f;
float innerH = hh * 0.95f;
```

---

### 3.5 触摸对焦功能

```java
private void setupHoleTouchFocus() {
    webView.setOnTouchListener((v, event) -> {
        if (event.getAction() != MotionEvent.ACTION_DOWN) {
            return false;
        }
        if (!scanOverlay.hasHole()) {
            return false;
        }
        float x = event.getX();
        float y = event.getY();
        holeForTouch.set(scanOverlay.getHoleRect());
        
        // 点击镂空区域才触发对焦
        if (holeForTouch.contains(x, y)) {
            focusPreviewAt(x, y);
        }
        return false;
    });
}

private void focusPreviewAt(float viewX, float viewY) {
    if (boundCamera == null || cameraTexture.getWidth() <= 0 || cameraTexture.getHeight() <= 0) {
        return;
    }
    
    SurfaceOrientedMeteringPointFactory factory = new SurfaceOrientedMeteringPointFactory(
            (float) cameraTexture.getWidth(), 
            (float) cameraTexture.getHeight()
    );
    
    MeteringPoint point = factory.createPoint(viewX, viewY, 0.1f);
    
    FocusMeteringAction action = new FocusMeteringAction.Builder(point)
            .setAutoCancelDuration(3, TimeUnit.SECONDS)
            .build();
    boundCamera.getCameraControl().startFocusAndMetering(action);
}
```

---

## 四、关键配置

### 4.1 WebView 配置

```java
private void initWebView() {
    // 允许 Chrome 远程调试
    WebView.setWebContentsDebuggingEnabled(true);
    
    WebSettings webSettings = webView.getSettings();
    webSettings.setJavaScriptEnabled(true);
    webSettings.setDomStorageEnabled(true);
    webSettings.setAllowFileAccess(true);
    webSettings.setUseWideViewPort(true);
    webSettings.setLoadWithOverviewMode(true);
    
    // 允许混合内容（dev server 走 http）
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        webSettings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
    }
    
    // 透明背景
    webView.setBackgroundColor(0);
    webView.setLayerType(WebView.LAYER_TYPE_HARDWARE, null);
    
    // 注册 JS Bridge
    webView.addJavascriptInterface(new JsBridge(), "Android");
}
```

### 4.2 CameraX 配置

```java
private void bindPreview(ProcessCameraProvider cameraProvider) {
    Preview preview = new Preview.Builder().build();
    CameraSelector cameraSelector = new CameraSelector.Builder()
            .requireLensFacing(CameraSelector.LENS_FACING_BACK)
            .build();
    
    Executor executor = ContextCompat.getMainExecutor(this);
    preview.setSurfaceProvider(request -> 
        cameraTexture.post(() -> attachSurfaceRequest(request, executor))
    );
    
    boundCamera = cameraProvider.bindToLifecycle(this, cameraSelector, preview);
}
```

---

## 五、调试技巧

### 5.1 日志查看

```bash
# 查看 MainActivity 日志
adb logcat -s MainActivity

# 查看 H5 控制台日志
adb logcat -s H5Console

# 同时查看多个标签
adb logcat | grep -E "MainActivity|H5Console"
```

### 5.2 Chrome 远程调试

1. 确保 `WebView.setWebContentsDebuggingEnabled(true)` 已启用
2. 手机连接电脑，开启 USB 调试
3. Chrome 浏览器访问：`chrome://inspect`
4. 点击 "inspect" 打开 DevTools

### 5.3 关键日志输出

```java
// 坐标转换日志
Log.d("MainActivity", "H5 坐标: left=" + left + ", top=" + top + ", width=" + width + ", height=" + height);
Log.d("MainActivity", "CSS 宽度: " + cssWidth + ", 物理宽度: " + webViewWidth + ", 缩放比例: " + accurateScale);
Log.d("MainActivity", "物理坐标: left=" + physicalLeft + ", top=" + physicalTop + ", width=" + physicalWidth + ", height=" + physicalHeight);

// TextureView 同步日志
Log.d("MainActivity", "更新 TextureView 位置: " + holeRect.toString());
```

---

## 六、常见问题总结

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| 内部装饰太小 | 比例设置过小（62%） | 调整为 95% |
| 外层边框被遮挡 | 内部区域占满（100%） | 留出 5% 边距 |
| 坐标不准确 | 直接使用 CSS 像素 | 通过 `window.innerWidth` 计算缩放比例 |
| 相机画面不显示 | 使用了 SurfaceView | 改用 TextureView |
| H5 内容不加载 | 未允许混合内容 | 设置 `MIXED_CONTENT_ALWAYS_ALLOW` |

---

## 七、技术要点总结

### 7.1 核心难点

1. **CSS 像素与物理像素转换**
   - 不使用 `webView.getScale()`
   - 通过 `window.innerWidth` 动态计算准确比例

2. **层级关系控制**
   - TextureView（底层）→ ScanOverlayView（中层）→ WebView（顶层）
   - 使用 `elevation` 控制 Z 轴顺序

3. **镂空效果实现**
   - `box-shadow: 0 0 0 9999px` 超大扩散半径

### 7.2 关键配置

```java
// 1. WebView 透明
webView.setBackgroundColor(0);

// 2. 根布局深色背景（相机未开启时显示）
root.setBackgroundColor(0xFF1A1F28);

// 3. TextureView 动态定位
params.leftMargin = (int) holeRect.left;
params.topMargin = (int) holeRect.top;
params.width = (int) holeRect.width();
params.height = (int) holeRect.height();
```

### 7.3 代码亮点

1. **幂等性保护**：`openCamera()` 防重复调用
2. **权限处理**：异步申请相机权限后自动重试
3. **资源释放**：`onDestroy()` 中销毁 WebView
4. **动画优化**：`ValueAnimator` + `LinearInterpolator` 实现流畅扫描
5. **错误处理**：JS Bridge 调用失败捕获

---

## 八、文件结构

```
webview-镂空/
├── app/src/main/
│   ├── java/com/example/mydemo/
│   │   ├── MainActivity.java          ← 主 Activity、JS Bridge、相机控制
│   │   └── ScanOverlayView.java       ← 原生绘制层（装饰动效）
│   ├── res/layout/
│   │   └── activity_main.xml          ← 三层布局（TextureView/ScanOverlay/WebView）
│   └── AndroidManifest.xml
└── h5/src/
    ├── App.jsx                        ← H5 主组件、坐标上报
    └── App.css                        ← 镂空效果、UI 样式
```

---

## 九、依赖版本

### Android 端

```gradle
// app/build.gradle
dependencies {
    implementation 'androidx.camera:camera-core:1.2.0'
    implementation 'androidx.camera:camera-camera2:1.2.0'
    implementation 'androidx.camera:camera-lifecycle:1.2.0'
    implementation 'androidx.appcompat:appcompat:1.6.1'
}
```

### H5 端

```json
{
  "dependencies": {
    "react": "^19.2.5",
    "react-dom": "^19.2.5"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^6.0.1",
    "vite": "^8.0.10"
  }
}
```

---

**总结日期**：2026-04-28  
**核心亮点**：CSS 像素精准转换、三层 View 叠加、原生高性能绘制
