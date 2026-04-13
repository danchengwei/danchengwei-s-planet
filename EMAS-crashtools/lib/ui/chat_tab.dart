import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../services/llm_client.dart';
import '../services/security_redaction.dart';

/// 使用当前项目「配置」中的 LLM（Base URL / Key / 模型 / 路径），多轮对话。
class ChatTab extends StatefulWidget {
  const ChatTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String? _boundProjectId;

  /// 交替 `user` / `assistant`，与 OpenAI Chat 消息列表一致（不含 system）。
  final List<Map<String, String>> _turns = [];
  bool _busy = false;

  static const int _maxHistoryMessages = 24;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _bindProjectIfNeeded() {
    final id = widget.controller.activeProject.id;
    if (_boundProjectId == id) return;
    _boundProjectId = id;
    _turns.clear();
    _busy = false;
    _input.clear();
  }

  List<Map<String, String>> _historySliceForApi() {
    if (_turns.isEmpty) return const [];
    var hist = _turns.length > _maxHistoryMessages
        ? _turns.sublist(_turns.length - _maxHistoryMessages)
        : List<Map<String, String>>.from(_turns);
    while (hist.isNotEmpty && (hist.first['role'] ?? '') != 'user') {
      hist = hist.sublist(1);
    }
    return hist;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;

    final cfg = widget.controller.config;
    final miss = cfg.validateLlm();
    if (miss.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在「配置」填写：${miss.join('、')}')),
      );
      return;
    }

    setState(() {
      _turns.add({'role': 'user', 'content': text});
      _input.clear();
      _busy = true;
    });
    _scrollToBottom();

    final client = LlmClient(
      baseUrl: cfg.llmBaseUrl.trim(),
      apiKey: cfg.llmApiKey.trim(),
      model: cfg.llmModel.trim(),
      chatCompletionsPath: cfg.effectiveLlmChatPath,
    );
    try {
      final messages = <Map<String, String>>[
        {'role': 'system', 'content': cfg.effectiveLlmFreeChatSystemPrompt},
        ..._historySliceForApi(),
      ];
      final reply = await client.chat(messages, temperature: 0.65);
      if (!mounted) return;
      setState(() {
        _turns.add({'role': 'assistant', 'content': reply});
        _busy = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _turns.add({
          'role': 'assistant',
          'content': '请求失败：${userFacingNetworkError(e)}',
        });
        _busy = false;
      });
      _scrollToBottom();
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        _bindProjectIfNeeded();
        final t = Theme.of(context);
        final cs = t.colorScheme;
        final cfg = widget.controller.config;
        final llmOk = cfg.validateLlm().isEmpty;
        final subtitle =
            llmOk ? '${cfg.llmModel.trim()} · ${cfg.llmBaseUrl.trim()}' : '请先在「配置」填写大模型';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
                child: Row(
                  children: [
                    Icon(Icons.forum_outlined, color: cs.primary, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '对话',
                            style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '清空本轮对话',
                      onPressed: _busy || _turns.isEmpty
                          ? null
                          : () => setState(() => _turns.clear()),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _turns.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          llmOk
                              ? '使用当前项目的 LLM 配置进行多轮对话。\n切换项目会清空本页记录。'
                              : '请先在侧栏「配置」中填写 LLM Base URL、API Key 与模型名。',
                          textAlign: TextAlign.center,
                          style: t.textTheme.bodyLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      itemCount: _turns.length,
                      itemBuilder: (context, i) {
                        final m = _turns[i];
                        final isUser = m['role'] == 'user';
                        final content = m['content'] ?? '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            mainAxisAlignment:
                                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isUser) ...[
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: cs.secondaryContainer,
                                  child: Icon(Icons.smart_toy_outlined, size: 18, color: cs.onSecondaryContainer),
                                ),
                                const SizedBox(width: 10),
                              ],
                              Flexible(
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isUser
                                        ? cs.primaryContainer.withValues(alpha: 0.65)
                                        : cs.surfaceContainerHighest.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                                      bottomRight: Radius.circular(isUser ? 4 : 16),
                                    ),
                                    border: Border.all(
                                      color: cs.outlineVariant.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: SelectableText(
                                    content,
                                    style: t.textTheme.bodyMedium?.copyWith(height: 1.4),
                                  ),
                                ),
                              ),
                              if (isUser) ...[
                                const SizedBox(width: 10),
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: cs.primaryContainer,
                                  child: Icon(Icons.person_outline_rounded, size: 18, color: cs.onPrimaryContainer),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (_busy)
              LinearProgressIndicator(
                minHeight: 2,
                color: cs.primary,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            Material(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 6,
                        enabled: !_busy && llmOk,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: llmOk ? '输入消息后回车发送…' : '请先完成 LLM 配置',
                          filled: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _busy || !llmOk ? null : _send,
                      child: _busy
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onPrimary,
                              ),
                            )
                          : const Text('发送'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
