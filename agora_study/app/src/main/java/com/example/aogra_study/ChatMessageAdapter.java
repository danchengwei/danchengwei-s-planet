package com.example.aogra_study;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public class ChatMessageAdapter extends RecyclerView.Adapter<ChatMessageAdapter.ChatMessageViewHolder> {
    private List<ChatMessage> messages = new ArrayList<>();
    private SimpleDateFormat timeFormat = new SimpleDateFormat("HH:mm", Locale.getDefault());

    @NonNull
    @Override
    public ChatMessageViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_chat_message, parent, false);
        return new ChatMessageViewHolder(view);
    }

    @Override
    public void onBindViewHolder(@NonNull ChatMessageViewHolder holder, int position) {
        ChatMessage message = messages.get(position);
        
        if (message.isSelf()) {
            holder.llSelf.setVisibility(View.VISIBLE);
            holder.llOther.setVisibility(View.GONE);
            holder.tvSelfMessage.setText(message.getMessage());
            holder.tvSelfTime.setText(timeFormat.format(new Date(message.getTimestamp())));
        } else {
            holder.llSelf.setVisibility(View.GONE);
            holder.llOther.setVisibility(View.VISIBLE);
            holder.tvOtherUser.setText(message.getUserId());
            holder.tvOtherMessage.setText(message.getMessage());
            holder.tvOtherTime.setText(timeFormat.format(new Date(message.getTimestamp())));
        }
    }

    @Override
    public int getItemCount() {
        return messages.size();
    }

    public void addMessage(ChatMessage message) {
        messages.add(message);
        notifyItemInserted(messages.size() - 1);
    }

    public void clearMessages() {
        messages.clear();
        notifyDataSetChanged();
    }

    static class ChatMessageViewHolder extends RecyclerView.ViewHolder {
        LinearLayout llSelf;
        LinearLayout llOther;
        TextView tvSelfMessage;
        TextView tvSelfTime;
        TextView tvOtherUser;
        TextView tvOtherMessage;
        TextView tvOtherTime;

        public ChatMessageViewHolder(@NonNull View itemView) {
            super(itemView);
            llSelf = itemView.findViewById(R.id.llSelf);
            llOther = itemView.findViewById(R.id.llOther);
            tvSelfMessage = itemView.findViewById(R.id.tvSelfMessage);
            tvSelfTime = itemView.findViewById(R.id.tvSelfTime);
            tvOtherUser = itemView.findViewById(R.id.tvOtherUser);
            tvOtherMessage = itemView.findViewById(R.id.tvOtherMessage);
            tvOtherTime = itemView.findViewById(R.id.tvOtherTime);
        }
    }
}
