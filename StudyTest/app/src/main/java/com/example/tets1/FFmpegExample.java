package com.example.tets1;

import android.util.Log;
import com.arthenica.ffmpegkit.FFmpegKit;
import com.arthenica.ffmpegkit.ReturnCode;

/**
 * FFmpeg使用示例类
 */
public class FFmpegExample {
    private static final String TAG = "FFmpegExample";

    /**
     * 执行FFmpeg命令的示例方法
     * @param command FFmpeg命令
     */
    public static void executeFFmpegCommand(String command) {
        FFmpegKit.executeAsync(command, session -> {
            if (ReturnCode.isSuccess(session.getReturnCode())) {
                Log.i(TAG, "FFmpeg命令执行成功");
            } else if (ReturnCode.isCancel(session.getReturnCode())) {
                Log.i(TAG, "FFmpeg命令被取消");
            } else {
                Log.i(TAG, "FFmpeg命令执行失败，返回码: " + session.getReturnCode());
            }
        });
    }

    /**
     * 获取视频信息的示例方法
     * @param videoPath 视频文件路径
     */
    public static void getVideoInfo(String videoPath) {
        String command = "-i " + videoPath;
        FFmpegKit.executeAsync(command, session -> {
            Log.i(TAG, "视频信息: " + session.getOutput());
        });
    }
}