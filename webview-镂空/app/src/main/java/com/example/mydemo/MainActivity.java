package com.example.mydemo;

import android.Manifest;
import android.annotation.SuppressLint;
import android.content.pm.PackageManager;
import android.graphics.RectF;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.view.MotionEvent;
import android.view.Surface;
import android.view.TextureView;
import android.view.View;
import android.widget.FrameLayout;
import android.webkit.ConsoleMessage;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.FocusMeteringAction;
import androidx.camera.core.MeteringPoint;
import androidx.camera.core.Preview;
import androidx.camera.core.SurfaceOrientedMeteringPointFactory;
import androidx.camera.core.SurfaceRequest;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import com.google.common.util.concurrent.ListenableFuture;

import java.io.IOException;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Executor;
import java.util.concurrent.TimeUnit;

public class MainActivity extends AppCompatActivity {

    private WebView webView;
    private TextureView cameraTexture;
    private ScanOverlayView scanOverlay;
    private Camera boundCamera;
    private final RectF holeForTouch = new RectF();
    private static final int CAMERA_PERMISSION_REQUEST = 1001;
    /** 用户从 H5 点了开启相机后，若当时无权限，授权成功再绑预览 */
    private boolean pendingOpenCameraAfterPermission;
    /** 防止连续点击多次 startCamera */
    private boolean isCameraStarting;
    /** 相机未开启时镂空区域的深色底（原生扫描动画画在其上） */
    private static final int PLACEHOLDER_WHEN_CAMERA_OFF = 0xFF1A1F28;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        if (getSupportActionBar() != null) {
            getSupportActionBar().hide();
        }

        webView = findViewById(R.id.webView);
        cameraTexture = findViewById(R.id.cameraTexture);
        scanOverlay = findViewById(R.id.scanOverlay);

        // 根底色保持为深色：相机未开启时从镂空透出成“黑色取景框”；
        // 相机开启后 TextureView 会覆盖这一底色，显示实时画面。
        View root = findViewById(R.id.activity_root);
        root.setBackgroundColor(PLACEHOLDER_WHEN_CAMERA_OFF);
        // TextureView 和 ScanOverlay 始终可见：未绑定相机时 TextureView 保持透明，
        // 深色底透出；ScanOverlay 依据 H5 上报的 holeRect 绘制角标/扫描线/粒子。

        initWebView();
        setupHoleTouchFocus();
        setupHoleSyncForTextureView();

        loadH5Page();
    }

    /**
     * H5 调用 {@code Android.openCamera()} 时：申请权限并绑定 CameraX 预览。
     * 方法是幂等的，可被多次调用（自动去重）。
     */
    private void openCameraPreviewFromUser() {
        if (boundCamera != null || isCameraStarting) {
            return;
        }
        isCameraStarting = true;
        pendingOpenCameraAfterPermission = true;
        checkCameraPermissionForOpen();
    }

    private void resetCameraUiAfterPermissionDenied() {
        isCameraStarting = false;
        pendingOpenCameraAfterPermission = false;
    }

    private void checkCameraPermissionForOpen() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.CAMERA}, CAMERA_PERMISSION_REQUEST);
        } else {
            startCamera();
        }
    }

    private void loadH5Page() {
        // 开发联调：直接加载局域网 dev server
        webView.loadUrl("http://10.8.227.13:5173/");
        Log.i("MainActivity", "加载 H5 dev server: http://10.8.227.13:5173/");
    }

    @SuppressLint({"SetJavaScriptEnabled", "ClickableViewAccessibility"})
    private void initWebView() {
        // 允许 chrome://inspect 远程调试
        WebView.setWebContentsDebuggingEnabled(true);

        WebSettings webSettings = webView.getSettings();
        webSettings.setJavaScriptEnabled(true);
        webSettings.setDomStorageEnabled(true);
        webSettings.setAllowFileAccess(true);
        webSettings.setUseWideViewPort(true);
        webSettings.setLoadWithOverviewMode(true);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
            webSettings.setAllowFileAccessFromFileURLs(true);
            webSettings.setAllowUniversalAccessFromFileURLs(true);
        }
        // 允许 http 资源（dev server 走 http）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            webSettings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        }

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return false;
            }

            @SuppressWarnings("deprecation")
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                return false;
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                super.onReceivedError(view, request, error);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && request != null) {
                    String url = request.getUrl() == null ? "?" : request.getUrl().toString();
                    int code = error == null ? 0 : error.getErrorCode();
                    CharSequence desc = error == null ? "" : error.getDescription();
                    Log.e("WebViewErr", "url=" + url + " code=" + code + " desc=" + desc + " mainFrame=" + request.isForMainFrame());
                    if (request.isForMainFrame()) {
                        Toast.makeText(MainActivity.this,
                                "H5 加载失败 code=" + code + " " + desc,
                                Toast.LENGTH_LONG).show();
                    }
                }
            }

            @Override
            public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                super.onPageStarted(view, url, favicon);
                Log.i("MainActivity", "WebView onPageStarted: " + url);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                Log.i("MainActivity", "WebView onPageFinished: " + url);
                // 500ms 后检查是否真的渲染出了内容
                view.postDelayed(() -> view.evaluateJavascript(
                        "JSON.stringify({root: !!document.getElementById('root'), " +
                                "childs: (document.getElementById('root')||{}).childElementCount||0, " +
                                "ua: navigator.userAgent})",
                        value -> Log.i("MainActivity", "H5 render check: " + value)), 500);
            }

            @SuppressWarnings("deprecation")
            @Override
            public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {
                super.onReceivedError(view, errorCode, description, failingUrl);
                Log.e("WebViewErr", "legacy url=" + failingUrl + " code=" + errorCode + " desc=" + description);
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                    Toast.makeText(MainActivity.this, "H5 加载失败: " + description, Toast.LENGTH_LONG).show();
                }
            }
        });

        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onConsoleMessage(ConsoleMessage msg) {
                Log.i("H5Console", "[" + msg.messageLevel() + "] " + msg.message()
                        + " (" + msg.sourceId() + ":" + msg.lineNumber() + ")");
                return true;
            }
        });
        webView.addJavascriptInterface(new JsBridge(), "Android");

        webView.setBackgroundColor(0);
        webView.setLayerType(WebView.LAYER_TYPE_HARDWARE, null);
    }

    @SuppressLint("ClickableViewAccessibility")
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
            if (holeForTouch.contains(x, y)) {
                focusPreviewAt(x, y);
            }
            return false;
        });
    }

    /**
     * 监听镂空区域变化，同步调整 TextureView 的位置和大小，
     * 确保相机预览正好填充 H5 的镂空区域。
     */
    private void setupHoleSyncForTextureView() {
        // 在 ScanOverlay 布局变化时更新 TextureView 位置
        scanOverlay.addOnLayoutChangeListener((v, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom) -> {
            if (scanOverlay.hasHole()) {
                updateTextureViewBounds();
            }
        });
    }

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

    private void focusPreviewAt(float viewX, float viewY) {
        if (boundCamera == null || cameraTexture.getWidth() <= 0 || cameraTexture.getHeight() <= 0) {
            return;
        }
        
        // 创建基于 Surface 的测光点工厂（适用于 TextureView）
        SurfaceOrientedMeteringPointFactory factory = new SurfaceOrientedMeteringPointFactory(
                (float) cameraTexture.getWidth(), 
                (float) cameraTexture.getHeight()
        );
        
        // 创建测光点，使用视图坐标（会自动转换为归一化坐标）
        MeteringPoint point = factory.createPoint(viewX, viewY, 0.1f);
        
        FocusMeteringAction action = new FocusMeteringAction.Builder(point)
                .setAutoCancelDuration(3, TimeUnit.SECONDS)
                .build();
        boundCamera.getCameraControl().startFocusAndMetering(action);
    }

    private void startCamera() {
        ListenableFuture<ProcessCameraProvider> cameraProviderFuture = ProcessCameraProvider.getInstance(this);

        cameraProviderFuture.addListener(() -> {
            try {
                ProcessCameraProvider cameraProvider = cameraProviderFuture.get();
                bindPreview(cameraProvider);
                pendingOpenCameraAfterPermission = false;
            } catch (ExecutionException | InterruptedException e) {
                Log.e("MainActivity", "启动相机失败", e);
                Toast.makeText(this, "启动相机失败", Toast.LENGTH_SHORT).show();
                pendingOpenCameraAfterPermission = false;
                isCameraStarting = false;
                resetCameraUiAfterPermissionDenied();
            }
        }, ContextCompat.getMainExecutor(this));
    }

    private void bindPreview(ProcessCameraProvider cameraProvider) {
        Preview preview = new Preview.Builder().build();
        CameraSelector cameraSelector = new CameraSelector.Builder()
                .requireLensFacing(CameraSelector.LENS_FACING_BACK)
                .build();

        Executor executor = ContextCompat.getMainExecutor(this);
        preview.setSurfaceProvider(request -> cameraTexture.post(() -> attachSurfaceRequest(request, executor)));

        boundCamera = cameraProvider.bindToLifecycle(this, cameraSelector, preview);
        isCameraStarting = false;
    }

    private void attachSurfaceRequest(@NonNull SurfaceRequest request, @NonNull Executor executor) {
        SurfaceTextureHolder.attach(cameraTexture, request, executor);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == CAMERA_PERMISSION_REQUEST) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Toast.makeText(this, "摄像头权限已授予", Toast.LENGTH_SHORT).show();
                if (pendingOpenCameraAfterPermission) {
                    startCamera();
                }
            } else {
                Toast.makeText(this, "需要摄像头权限才能预览", Toast.LENGTH_SHORT).show();
                resetCameraUiAfterPermissionDenied();
            }
        }
    }

    class JsBridge {
        @JavascriptInterface
        public void openCamera() {
            runOnUiThread(MainActivity.this::openCameraPreviewFromUser);
        }

        @JavascriptInterface
        public void takePhoto() {
            runOnUiThread(() -> {
                if (boundCamera == null) {
                    Toast.makeText(MainActivity.this, "请先点击开启相机", Toast.LENGTH_SHORT).show();
                    return;
                }
                Toast.makeText(MainActivity.this, "拍照", Toast.LENGTH_SHORT).show();
                Log.d("JSBridge", "拍照");
            });
        }

        @JavascriptInterface
        public void chooseFromAlbum() {
            runOnUiThread(() -> {
                Toast.makeText(MainActivity.this, "从相册选择", Toast.LENGTH_SHORT).show();
                Log.d("JSBridge", "从相册选择");
            });
        }

        @JavascriptInterface
        public void showMessage(String message) {
            runOnUiThread(() -> {
                Toast.makeText(MainActivity.this, message, Toast.LENGTH_SHORT).show();
                Log.d("JSBridge", "收到消息: " + message);
            });
        }

        @JavascriptInterface
        public void setNativeHoleRect(int left, int top, int width, int height) {
            runOnUiThread(() -> {
                // H5 传来的是 CSS 像素（逻辑像素），需要转换为物理像素
                // 使用更准确的缩放计算：物理屏幕宽度 / WebView 内容宽度
                int webViewWidth = webView.getWidth();
                float cssPixelRatio = webViewWidth > 0 ? webViewWidth / 375f : 1.0f; // 假设 H5 设计稿基准宽度 375
                
                // 也可以通过 window.innerWidth 获取实际 CSS 宽度
                webView.evaluateJavascript(
                    "(function(){return window.innerWidth;})()",
                    value -> {
                        try {
                            int cssWidth = Integer.parseInt(value.replace("\"", ""));
                            float accurateScale = webViewWidth / (float)cssWidth;
                            
                            int physicalLeft = Math.round(left * accurateScale);
                            int physicalTop = Math.round(top * accurateScale);
                            int physicalWidth = Math.round(width * accurateScale);
                            int physicalHeight = Math.round(height * accurateScale);
                            
                            Log.d("MainActivity", "H5 坐标: left=" + left + ", top=" + top + ", width=" + width + ", height=" + height);
                            Log.d("MainActivity", "CSS 宽度: " + cssWidth + ", 物理宽度: " + webViewWidth + ", 缩放比例: " + accurateScale);
                            Log.d("MainActivity", "物理坐标: left=" + physicalLeft + ", top=" + physicalTop + ", width=" + physicalWidth + ", height=" + physicalHeight);
                            
                            scanOverlay.setHoleFromWeb(physicalLeft, physicalTop, (float) physicalLeft + physicalWidth, (float) physicalTop + physicalHeight);
                            updateTextureViewBounds();
                        } catch (Exception e) {
                            Log.e("MainActivity", "解析 CSS 宽度失败", e);
                        }
                    }
                );
            });
        }
    }

    @Override
    public void onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
        }
        super.onDestroy();
    }

    /**
     * 将 CameraX 的 SurfaceRequest 接到 TextureView 的 SurfaceTexture。
     */
    private static final class SurfaceTextureHolder {
        private SurfaceTextureHolder() {
        }

        static void attach(TextureView textureView, SurfaceRequest request, Executor executor) {
            android.graphics.SurfaceTexture st = textureView.getSurfaceTexture();
            if (st != null) {
                connect(textureView, request, st, executor);
                return;
            }
            textureView.setSurfaceTextureListener(new TextureView.SurfaceTextureListener() {
                @Override
                public void onSurfaceTextureAvailable(@NonNull android.graphics.SurfaceTexture surface, int width, int height) {
                    textureView.setSurfaceTextureListener(null);
                    connect(textureView, request, surface, executor);
                }

                @Override
                public void onSurfaceTextureSizeChanged(@NonNull android.graphics.SurfaceTexture surface, int width, int height) {
                }

                @Override
                public boolean onSurfaceTextureDestroyed(@NonNull android.graphics.SurfaceTexture surface) {
                    return false;
                }

                @Override
                public void onSurfaceTextureUpdated(@NonNull android.graphics.SurfaceTexture surface) {
                }
            });
        }

        private static void connect(TextureView textureView, SurfaceRequest request,
                @NonNull android.graphics.SurfaceTexture st, Executor executor) {
            android.util.Size size = request.getResolution();
            st.setDefaultBufferSize(size.getWidth(), size.getHeight());
            Surface surface = new Surface(st);
            request.provideSurface(surface, executor, result -> surface.release());
        }
    }
}
