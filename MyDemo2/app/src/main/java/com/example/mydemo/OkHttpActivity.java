package com.example.mydemo;

import android.app.Activity;
import android.os.Bundle;
import android.widget.Button;
import android.widget.TextView;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.util.Log;
import android.view.View;

import okhttp3.OkHttp;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.Call;
import okhttp3.Callback;

import java.io.IOException;

public class OkHttpActivity extends Activity {
    private static final String TAG = "OkHttpActivity";
    // 提供多个测试地址
    private static final String[] TEST_URLS = {
        "https://httpbin.org/get",
        "https://jsonplaceholder.typicode.com/posts/1",
        "https://api.github.com/users/octocat",
        "https://api.github.com/repos/octocat/Hello-World"
    };
    
    private EditText urlEditText;
    private Button requestButton;
    private TextView responseTextView;
    private OkHttpClient client;
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        // 初始化OkHttpClient
        client = new OkHttpClient();
        
        // 创建UI组件
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        
        urlEditText = new EditText(this);
        urlEditText.setText(TEST_URLS[1]); // 默认使用jsonplaceholder地址
        urlEditText.setHint("请输入URL");
        
        requestButton = new Button(this);
        requestButton.setText("发送请求");
        
        responseTextView = new TextView(this);
        responseTextView.setText("响应内容将显示在这里\n\n推荐测试地址:\n" + 
                               "1. " + TEST_URLS[0] + "\n" +
                               "2. " + TEST_URLS[1] + "\n" +
                               "3. " + TEST_URLS[2] + "\n" +
                               "4. " + TEST_URLS[3]);
        
        // 添加点击事件
        requestButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                sendRequest();
            }
        });
        
        // 添加组件到布局
        layout.addView(urlEditText);
        layout.addView(requestButton);
        layout.addView(responseTextView);
        
        setContentView(layout);
    }
    
    private void sendRequest() {
        String url = urlEditText.getText().toString();
        if (url.isEmpty()) {
            responseTextView.setText("请输入有效的URL");
            return;
        }
        
        // 构建请求
        Request request = new Request.Builder()
                .header("User-Agent", OkHttp.VERSION)//4.9.2
                .url(url)
                .build();
        
        // 在TextView中显示构建的请求信息
        String requestInfo = "请求URL: " + url + "\n" +
                            "请求方法: " + request.method() + "\n" +
                            "请求头: " + (request.headers().toString().isEmpty() ? "无" : request.headers().toString());
        responseTextView.setText("构建的请求信息:\n" + requestInfo + "\n\n正在发送请求...");
        
        // 异步执行请求
        client.newCall(request).enqueue(new Callback() {
            @Override
            public void onFailure(Call call, IOException e) {
                Log.e(TAG, "请求失败", e);
                // 在主线程更新UI
                runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        responseTextView.setText("构建的请求信息:\n" + requestInfo + "\n\n请求失败: " + e.getMessage() + 
                                               "\n\n推荐尝试以下测试地址:\n" + 
                                               "1. " + TEST_URLS[0] + "\n" +
                                               "2. " + TEST_URLS[1] + " (默认推荐)\n" +
                                               "3. " + TEST_URLS[2] + "\n" +
                                               "4. " + TEST_URLS[3]);
                    }
                });
            }
            
            @Override
            public void onResponse(Call call, Response response) throws IOException {
                try {
                    String responseBody = response.body().string();
                    // 在主线程更新UI
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            responseTextView.setText("构建的请求信息:\n" + requestInfo + "\n\n响应状态: " + response.code() + " " + response.message() + "\n响应内容:\n" + responseBody);
                        }
                    });
                } catch (IOException e) {
                    Log.e(TAG, "处理响应失败", e);
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            responseTextView.setText("构建的请求信息:\n" + requestInfo + "\n\n处理响应失败: " + e.getMessage());
                        }
                    });
                }
            }
        });
    }
}