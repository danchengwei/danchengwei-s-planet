package com.example.aogra_study;

import io.agora.rtc2.RtcEngine;

public class AudioController {
    private RtcEngine rtcEngine;

    public AudioController(RtcEngine rtcEngine) {
        this.rtcEngine = rtcEngine;
    }

    /**
     * 启用/禁用音频
     */
    public void enableAudio(boolean enabled) {
        if (enabled) {
            rtcEngine.enableAudio();
        } else {
            rtcEngine.disableAudio();
        }
    }

    /**
     * 启用/禁用本地音频
     */
    public void muteLocalAudio(boolean muted) {
        rtcEngine.muteLocalAudioStream(muted);
    }

    /**
     * 启用/禁用扬声器
     */
    public void setEnableSpeakerphone(boolean enabled) {
        rtcEngine.setEnableSpeakerphone(enabled);
    }

    /**
     * 设置音频路由
     */
    public void setAudioRoute(boolean audioRoute) {
        rtcEngine.setDefaultAudioRoutetoSpeakerphone(audioRoute);
    }

    /**
     * 启用/禁用音频音效
     */
    public void enableAudioEffect(boolean enabled) {
        // IAudioEffectManager没有setEnabled方法，使用音效控制方法
        if (enabled) {
            rtcEngine.setEffectsVolume(100); // 设置音效音量为100%
        } else {
            rtcEngine.setEffectsVolume(0); // 设置音效音量为0%
        }
    }

    /**
     * 设置音频场景
     */
    public void setAudioProfile(int audioProfile, int scenario) {
        rtcEngine.setAudioProfile(audioProfile, scenario);
    }

    /**
     * 获取音频状态
     */
    public boolean isAudioEnabled() {
        return rtcEngine != null;
    }
    
    /**
     * 调节录音音量
     */
    public void adjustRecordingSignalVolume(int volume) {
        rtcEngine.adjustRecordingSignalVolume(volume);
    }
    
    /**
     * 调节播放音量
     */
    public void adjustPlaybackSignalVolume(int volume) {
        rtcEngine.adjustPlaybackSignalVolume(volume);
    }
}