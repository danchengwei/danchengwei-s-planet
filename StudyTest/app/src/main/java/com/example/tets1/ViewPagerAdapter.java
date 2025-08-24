package com.example.tets1;

import androidx.fragment.app.Fragment;
import androidx.fragment.app.FragmentActivity;
import androidx.viewpager2.adapter.FragmentStateAdapter;
import java.util.List;

public class ViewPagerAdapter extends FragmentStateAdapter {
    public ViewPagerAdapter(FragmentActivity fragmentActivity) {
        super(fragmentActivity);
    }

    @Override
    public Fragment createFragment(int position) {
        return ViewPagerFragment.newInstance();
    }

    @Override
    public int getItemCount() {
        return 4; // 四个页面：主页、视频、动画、其他
    }
}