package com.example.webrtctest;

import android.util.Log;

import org.java_websocket.client.WebSocketClient;
import org.java_websocket.handshake.ServerHandshake;

import java.net.URI;
import java.net.URISyntaxException;

public class WebSocketClientWrapper extends WebSocketClient {
    private static final String TAG = "WebSocketClient";
    private WebSocketListener mListener;

    public WebSocketClientWrapper(String serverUri) throws URISyntaxException {
        super(new URI(serverUri));
    }

    @Override
    public void onOpen(ServerHandshake handshakedata) {
        Log.d(TAG, "WebSocket connection opened");
        if (mListener != null) {
            mListener.onConnected();
        }
    }

    @Override
    public void onMessage(String message) {
        Log.d(TAG, "Received message: " + message);
        if (mListener != null) {
            mListener.onMessageReceived(message);
        }
    }

    @Override
    public void onClose(int code, String reason, boolean remote) {
        Log.d(TAG, "WebSocket connection closed: " + reason);
        if (mListener != null) {
            mListener.onDisconnected(reason, remote);
        }
    }

    @Override
    public void onError(Exception ex) {
        Log.e(TAG, "WebSocket error: " + ex.getMessage());
        if (mListener != null) {
            mListener.onError(ex);
        }
    }

    public void setWebSocketListener(WebSocketListener listener) {
        mListener = listener;
    }

    public interface WebSocketListener {
        void onConnected();
        void onMessageReceived(String message);
        void onDisconnected(String reason, boolean remote);
        void onError(Exception error);
    }
}