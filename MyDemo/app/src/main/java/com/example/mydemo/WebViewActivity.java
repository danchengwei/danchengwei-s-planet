package com.example.mydemo;

import android.os.Bundle;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.net.Network;
import android.content.Context;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import android.util.Log;
import java.net.InetAddress;
import java.net.UnknownHostException;

public class WebViewActivity extends AppCompatActivity {

    public static final String EXTRA_URL = "url";
    private static final String TAG = "WebViewActivity";
    private WebView webView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_webview);

        webView = findViewById(R.id.webview);
        WebSettings webSettings = webView.getSettings();
        webSettings.setJavaScriptEnabled(true);
        webSettings.setDomStorageEnabled(true);
        webSettings.setAllowContentAccess(true);
        webSettings.setAllowFileAccess(true);
        webSettings.setUseWideViewPort(true);
        webSettings.setLoadWithOverviewMode(true);
        // 添加更多设置以提高兼容性
        webSettings.setDatabaseEnabled(true);
        webSettings.setCacheMode(WebSettings.LOAD_DEFAULT);

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                Log.d(TAG, "Loading URL: " + url);
                // 在加载前检查网络
                if (!isNetworkAvailable()) {
                    return true;
                }
                view.loadUrl(url);
                return true;
            }
            
            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                Log.d(TAG, "Page finished loading: " + url);
            }
            
            @Override
            public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {
                Log.e(TAG, "Error loading page: " + description + " URL: " + failingUrl + " Error code: " + errorCode);
                Toast.makeText(WebViewActivity.this, "加载失败: " + description, Toast.LENGTH_LONG).show();
                
                // 根据错误码提供更具体的错误信息
                String detailedError = getDetailedErrorMessage(errorCode, description);
            }
            
            // 添加对 SSL 错误的处理
            @Override
            public void onReceivedSslError(WebView view, android.webkit.SslErrorHandler handler, android.net.http.SslError error) {
                Log.e(TAG, "SSL Error: " + error.toString());
                // 在生产环境中，您应该正确处理SSL错误
                // 这里为了测试目的，我们选择继续加载页面
                handler.proceed(); // 仅用于测试，生产环境应正确处理SSL错误
            }
        });

        // Check network connectivity
        if (isNetworkAvailable()) {
            // Load a URL from intent or use default
            String url = getIntent().getStringExtra(EXTRA_URL);
            if (url == null) {
                url = "http://localhost:5174/";  // 使用localhost:5173作为默认值
            }
            Log.d(TAG, "Loading initial URL: " + url);
            webView.loadUrl(url);
        } else {
            Toast.makeText(this, "无网络连接", Toast.LENGTH_LONG).show();
        }
    }

    private String getDetailedErrorMessage(int errorCode, String description) {
        switch (errorCode) {
            case WebViewClient.ERROR_HOST_LOOKUP:
                return "找不到服务器地址，请检查网络连接或URL是否正确。可能的原因：DNS解析失败、网络连接问题、防火墙阻止";
            case WebViewClient.ERROR_CONNECT:
                return "连接服务器失败，可能是网络问题或服务器未响应。如果您正在使用本地开发服务器，请确保服务器正在运行且可以从设备访问。";
            case WebViewClient.ERROR_TIMEOUT:
                return "连接超时，请检查网络连接";
            case WebViewClient.ERROR_REDIRECT_LOOP:
                return "页面重定向循环，请稍后重试";
            case WebViewClient.ERROR_UNSUPPORTED_SCHEME:
                return "不支持的协议";
            case WebViewClient.ERROR_FAILED_SSL_HANDSHAKE:
                return "SSL握手失败，请检查网络环境";
            default:
                return description;
        }
    }

    private boolean isNetworkAvailable() {
        ConnectivityManager connectivityManager = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
        NetworkInfo activeNetworkInfo = connectivityManager.getActiveNetworkInfo();
        boolean isConnected = activeNetworkInfo != null && activeNetworkInfo.isConnected();
        Log.d(TAG, "Network available: " + isConnected);
        
        // 添加更多网络诊断信息
        if (activeNetworkInfo != null) {
            Log.d(TAG, "Network type: " + activeNetworkInfo.getTypeName());
            Log.d(TAG, "Network state: " + activeNetworkInfo.getState());
        }
        
        return isConnected;
    }


    @Override
    public void onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }
}