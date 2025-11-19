package com.example.tets1;

import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.widget.ImageView;
import android.widget.TextView;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;
import androidx.viewpager2.widget.ViewPager2;
import com.google.android.material.tabs.TabLayout;
import com.google.android.material.tabs.TabLayoutMediator;
import java.util.ArrayList;
import java.util.List;

public class MainActivity extends AppCompatActivity {
    private ViewPager2 viewPager;
    private ViewPagerAdapter viewPagerAdapter;
    private TabLayout tabLayout;
    
    // 页面标题
    private String[] tabTitles = {"主页", "视频", "动画", "其他"};
    
    // 页面图标
    private int[] tabIcons = {
        R.drawable.ic_home,
        R.drawable.ic_video,
        R.drawable.ic_animation,
        R.drawable.ic_other
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        // 设置沉浸式状态栏
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                        | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        );
        
        setContentView(R.layout.activity_main);

        // 初始化视图
        initViews();
        
        // 设置适配器
        setupViewPager();
        
        // 设置自定义TabLayout
        setupCustomTabLayout();
    }

    private void initViews() {
        viewPager = findViewById(R.id.viewPager);
        tabLayout = findViewById(R.id.tabLayout);
    }

    private void setupViewPager() {
        viewPagerAdapter = new ViewPagerAdapter(this);
        viewPager.setAdapter(viewPagerAdapter);
    }
    
    private void setupCustomTabLayout() {
        new TabLayoutMediator(tabLayout, viewPager,
                (tab, position) -> {
                    // 创建自定义Tab视图
                    View customView = LayoutInflater.from(this).inflate(R.layout.custom_tab_item, null);
                    ImageView tabIcon = customView.findViewById(R.id.tab_icon);
                    TextView tabText = customView.findViewById(R.id.tab_text);
                    
                    // 设置图标和文本
                    tabIcon.setImageResource(tabIcons[position]);
                    tabText.setText(tabTitles[position]);
                    
                    // 默认选中第一个tab
                    if (position == 0) {
                        tabIcon.setColorFilter(ContextCompat.getColor(this, R.color.purple_500));
                        tabText.setTextColor(ContextCompat.getColor(this, R.color.purple_500));
                    } else {
                        tabIcon.setColorFilter(ContextCompat.getColor(this, R.color.black));
                        tabText.setTextColor(ContextCompat.getColor(this, R.color.black));
                    }
                    
                    tab.setCustomView(customView);
                }
        ).attach();
        
        // 设置Tab选择监听器
        tabLayout.addOnTabSelectedListener(new TabLayout.OnTabSelectedListener() {
            @Override
            public void onTabSelected(TabLayout.Tab tab) {
                // 选中时设置深色样式
                View customView = tab.getCustomView();
                if (customView != null) {
                    ImageView tabIcon = customView.findViewById(R.id.tab_icon);
                    TextView tabText = customView.findViewById(R.id.tab_text);
                    tabIcon.setColorFilter(ContextCompat.getColor(MainActivity.this, R.color.purple_500));
                    tabText.setTextColor(ContextCompat.getColor(MainActivity.this, R.color.purple_500));
                }
            }


            @Override
            public void onTabUnselected(TabLayout.Tab tab) {
                // 未选中时设置普通样式
                View customView = tab.getCustomView();
                if (customView != null) {
                    ImageView tabIcon = customView.findViewById(R.id.tab_icon);
                    TextView tabText = customView.findViewById(R.id.tab_text);
                    tabIcon.setColorFilter(ContextCompat.getColor(MainActivity.this, R.color.black));
                    tabText.setTextColor(ContextCompat.getColor(MainActivity.this, R.color.black));
                }
            }

            @Override
            public void onTabReselected(TabLayout.Tab tab) {
                // 重新选择时不需要处理
            }
        });
    }
}