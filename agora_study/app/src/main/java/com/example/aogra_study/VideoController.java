package com.example.aogra_study;

import android.view.View;
import io.agora.rtc2.RtcEngine;
import io.agora.rtc2.video.VideoCanvas;
import io.agora.rtc2.video.VideoEncoderConfiguration;
import io.agora.rtc2.video.VideoEncoderConfiguration.FRAME_RATE;

public class VideoController {
    private RtcEngine rtcEngine;

    public VideoController(RtcEngine rtcEngine) {
        this.rtcEngine = rtcEngine;
    }

    /**
     * 启用视频模块
     */
    public void enableVideo() {
        rtcEngine.enableVideo();
    }

    /**
     * 禁用视频模块
     */
    public void disableVideo() {
        rtcEngine.disableVideo();
    }

    /**
     * 启用/禁用本地视频
     */
    public void muteLocalVideo(boolean muted) {
        rtcEngine.muteLocalVideoStream(muted);
    }

    /**
     * 设置视频配置
     */
    public void setVideoProfile(int width, int height, int frameRate, int bitrate) {
        FRAME_RATE frameRateEnum;
        switch(frameRate) {
            case 1:
                frameRateEnum = FRAME_RATE.FRAME_RATE_FPS_1;
                break;
            case 7:
                frameRateEnum = FRAME_RATE.FRAME_RATE_FPS_7;
                break;
            case 10:
                frameRateEnum = FRAME_RATE.FRAME_RATE_FPS_10;
                break;
            case 15:
                frameRateEnum = FRAME_RATE.FRAME_RATE_FPS_15;
                break;
            case 24:
                frameRateEnum = FRAME_RATE.FRAME_RATE_FPS_24;
                break;
            case 30:
                frameRateEnum = FRAME_RATE.FRAME_RATE_FPS_30;
                break;
            case 60:
                frameRateEnum = FRAME_RATE.FRAME_RATE_FPS_60;
                break;
            default:
                frameRateEnum = FRAME_RATE.FRAME_RATE_FPS_15; // 默认15fps
                break;
        }
        
        VideoEncoderConfiguration configuration = new VideoEncoderConfiguration(
            width, height, 
            frameRateEnum, 
            bitrate,
            VideoEncoderConfiguration.ORIENTATION_MODE.ORIENTATION_MODE_ADAPTIVE
        );
        rtcEngine.setVideoEncoderConfiguration(configuration);
    }

    /**
     * 设置本地视频渲染视图
     */
    public void setupLocalVideo(View view) {
        rtcEngine.setupLocalVideo(new VideoCanvas(view, VideoCanvas.RENDER_MODE_HIDDEN, 0));
    }

    /**
     * 设置远程视频渲染视图
     */
    public void setupRemoteVideo(View view, int uid) {
        rtcEngine.setupRemoteVideo(new VideoCanvas(view, VideoCanvas.RENDER_MODE_HIDDEN, uid));
    }

    /**
     * 开始预览视频
     */
    public void startPreview() {
        rtcEngine.startPreview();
    }

    /**
     * 停止预览视频
     */
    public void stopPreview() {
        rtcEngine.stopPreview();
    }

    /**
     * 切换摄像头
     */
    public void switchCamera() {
        rtcEngine.switchCamera();
    }

    /**
     * 启用/禁用本地视频渲染
     */
    public void enableLocalVideo(boolean enabled) {
        rtcEngine.enableLocalVideo(enabled);
    }
}