package com.example.mydemo;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

public class TestActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        TextView title = new TextView(this);
        title.setText("测试");
        title.setTextSize(24);
        title.setPadding(10, 10, 10, 10);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        
        TextView textView = new TextView(this);
        textView.setText("Hello World!");
        textView.setTextSize(24);
        
        Button okhttpButton = new Button(this);
        okhttpButton.setText("测试OkHttp");
        okhttpButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Intent intent = new Intent(TestActivity.this, OkHttpActivity.class);
                startActivity(intent);
            }
        });
        
        layout.addView(textView);
        layout.addView(okhttpButton);
        
        setContentView(layout);
    }


    @Override
    protected void onDestroy() {
        super.onDestroy();
        Log.d("TestActivity", "onStop");
    }

    @Override
    protected void onPause() {
        super.onPause();
        Log.d("TestActivity", "onStop");
    }

    @Override
    protected void onResume() {
        super.onResume();
        Log.d("TestActivity", "onStop");
    }

    @Override
    protected void onStart() {
        super.onStart();
        Log.d("TestActivity", "onStop");
    }

    @Override
    protected void onStop() {
        super.onStop();
        Log.d("TestActivity", "onStop");
        Log.d("TestActivity", "onStop");
        Log.d("TestActivity", "onStop");
        Log.d("TestActivity", "onStop");
        Log.d("TestActivity", "onStop");
        Log.d("TestActivity", "onStop");

    }

}