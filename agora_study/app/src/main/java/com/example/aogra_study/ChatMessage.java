package com.example.aogra_study;

public class ChatMessage {
    private String userId;
    private String message;
    private long timestamp;
    private boolean isSelf;

    public ChatMessage(String userId, String message, boolean isSelf) {
        this.userId = userId;
        this.message = message;
        this.isSelf = isSelf;
        this.timestamp = System.currentTimeMillis();
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }

    public long getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(long timestamp) {
        this.timestamp = timestamp;
    }

    public boolean isSelf() {
        return isSelf;
    }

    public void setSelf(boolean self) {
        isSelf = self;
    }
}
