package com.example.demo1;

import android.app.Activity;
import android.content.Context;
import android.graphics.Bitmap;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.util.Log;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import org.json.JSONException;
import org.json.JSONObject;

public class WebViewActivity extends Activity {
    private WebView webView;
    private WebAppInterface webAppInterface;
    private static final String TAG = "WebViewActivity";

    // 创建一个JavaScript接口类
    public class WebAppInterface {
        Context mContext;

        WebAppInterface(Context context) {
            mContext = context;
        }

        // 显示Toast消息
        @JavascriptInterface
        public void showToast(String toast) {
            Toast.makeText(mContext, toast, Toast.LENGTH_SHORT).show();
        }

        // 获取设备信息
        @JavascriptInterface
        public String getDeviceInfo() {
            JSONObject deviceInfo = new JSONObject();
            try {
                deviceInfo.put("model", Build.MODEL);
                deviceInfo.put("manufacturer", Build.MANUFACTURER);
                deviceInfo.put("version", Build.VERSION.RELEASE);
                deviceInfo.put("sdk", Build.VERSION.SDK_INT);
            } catch (JSONException e) {
                Log.e(TAG, "Error creating device info JSON", e);
            }
            return deviceInfo.toString();
        }

        // 获取设备唯一标识符
        @JavascriptInterface
        public String getDeviceId() {
            return Settings.Secure.getString(mContext.getContentResolver(), Settings.Secure.ANDROID_ID);
        }

        // 关闭应用
        @JavascriptInterface
        public void closeApp() {
            ((Activity) mContext).finish();
        }

        // 发送数据到Android
        @JavascriptInterface
        public void sendData(String data) {
            Log.d(TAG, "从JavaScript接收到数据: " + data);
            Toast.makeText(mContext, "接收到数据: " + data, Toast.LENGTH_LONG).show();
        }

        // 获取应用版本信息
        @JavascriptInterface
        public String getAppVersion() {
            try {
                return mContext.getPackageManager()
                        .getPackageInfo(mContext.getPackageName(), 0).versionName;
            } catch (Exception e) {
                Log.e(TAG, "获取应用版本信息失败", e);
                return "unknown";
            }
        }

        // 设置页面标题
        @JavascriptInterface
        public void setPageTitle(String title) {
            ((Activity) mContext).runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    ((Activity) mContext).setTitle(title);
                }
            });
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_webview);

        webView = findViewById(R.id.webview);
        
        // 创建WebAppInterface实例
        webAppInterface = new WebAppInterface(this);
        
        // 将Java对象添加到WebView中，使其可以在JavaScript中访问
        webView.addJavascriptInterface(webAppInterface, "NativeAndroid");
        
        // 配置WebView设置
        WebSettings webSettings = webView.getSettings();
        webSettings.setJavaScriptEnabled(true);                 // 启用JavaScript
        webSettings.setDomStorageEnabled(true);                 // 启用DOM存储API
        webSettings.setLoadWithOverviewMode(true);              // 以概览模式加载页面
        webSettings.setUseWideViewPort(true);                   // 启用viewport元标签
        webSettings.setBuiltInZoomControls(true);               // 启用内置缩放控件
        webSettings.setDisplayZoomControls(false);              // 隐藏缩放控件
        webSettings.setSupportZoom(true);                       // 支持缩放
        
        // 为Android 5.0及以上版本启用混合内容模式
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
            webSettings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        }
        
        // 设置WebView客户端，用于处理页面导航和事件
        webView.setWebViewClient(new WebViewClient() {
            // 页面开始加载时调用
            @Override
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
                super.onPageStarted(view, url, favicon);
                Log.d(TAG, "页面开始加载: " + url);
            }

            // 页面加载完成时调用
            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                Log.d(TAG, "页面加载完成: " + url);
            }

            // 页面加载错误时调用
            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                super.onReceivedError(view, request, error);
                String errorMsg = "加载资源错误: " + request.getUrl() + 
                                  ", 错误信息: " + error.getDescription();
                Log.e(TAG, errorMsg);
                Toast.makeText(WebViewActivity.this, errorMsg, Toast.LENGTH_LONG).show();
                
                // 只有在主框架错误时才显示错误页面
                if (request.isForMainFrame()) {
                    webView.loadUrl("file:///android_asset/no_network.html");
                }
            }
        });
        
        // 加载指定的H5地址
        webView.loadUrl("http://10.92.42.129:5173/");
    }

    @Override
    public void onBackPressed() {
        // 如果WebView可以返回，则返回上一页，否则退出Activity
        if (webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }
}