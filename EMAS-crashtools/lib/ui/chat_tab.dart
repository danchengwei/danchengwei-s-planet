import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../models/tool_config.dart';
import '../services/llm_client.dart';
import '../services/outbound_http_client_for_config.dart';
import '../services/security_redaction.dart';

/// 使用当前项目「配置」中的 LLM（Base URL / Key / 模型 / 路径），多轮对话。
/// 每个项目独立保留对话记录；切换项目会切换上下文，回到该项目仍可继续滚动查看历史。
class ChatTab extends StatefulWidget {
  const ChatTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// 按项目 id 持久在本页内存中的多轮消息（user / assistant 交替）。
  final Map<String, List<Map<String, String>>> _messagesByProject = {};

  String? _boundProjectId;
  bool _busy = false;

  /// 发往 API 时携带的最近若干条（避免上下文过长）；界面仍展示该项目的完整记录。
  static const int _maxHistoryMessages = 48;

  /// 挂载报告写入 system 时的正文上限，避免超出模型上下文。
  static const int _maxAttachedReportChars = 28000;

  List<Map<String, String>> _turns() {
    final id = widget.controller.activeProject.id;
    return _messagesByProject.putIfAbsent(id, () => []);
  }

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
    if (_busy) {
      setState(() => _busy = false);
    }
  }

  /// 从某项目的完整记录截取发往 Chat API 的 messages（以 user 开头）。
  List<Map<String, String>> _apiHistoryFrom(List<Map<String, String>> full) {
    if (full.isEmpty) return const [];
    var hist = full.length > _maxHistoryMessages
        ? full.sublist(full.length - _maxHistoryMessages)
        : List<Map<String, String>>.from(full);
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

  String _systemPromptWithAttachment(ToolConfig cfg) {
    var base = cfg.effectiveLlmFreeChatSystemPrompt;
    final r = widget.controller.chatAttachedReport;
    if (r == null) return base;
    const head = '''

----------
【已挂载 EMAS AI 分析报告】
用户在工具中对某条聚合问题（Digest）完成过智能分析，下列为报告元数据与全文。内容通常包含原因、分析、修改建议，以及结合 GitLab 检索的代码线索。

当用户希望你协助通过 **Claude Code、Cursor MCP、或其它本机 MCP** 在仓库里改代码时：
1. 以报告中的「如何处理」「修改意见」及代码块为优先依据；
2. 建议流程：仓库根目录 `git pull` → `cd` 到目标模块 → `git checkout -b bugfix/<简述>` → 修改 → 运行 analyze / test → **不要**擅自 `git add` / `commit` / `push`，除非用户明确要求。

----------''';
    final meta = StringBuffer();
    meta.writeln('Digest: ${r.digestHash}');
    meta.writeln('BizModule: ${r.bizModule}');
    meta.writeln('标题: ${r.title}');
    if (r.stackSnippet != null && r.stackSnippet!.trim().isNotEmpty) {
      meta.writeln('堆栈摘录:\n${r.stackSnippet!.trim()}');
    }
    if (r.gitlabContext != null && r.gitlabContext!.trim().isNotEmpty) {
      meta.writeln(r.gitlabContext!.trim());
    }
    var body = r.reportBody.trim();
    if (body.length > _maxAttachedReportChars) {
      body =
          '${body.substring(0, _maxAttachedReportChars)}\n\n…（报告过长已截断；完整内容可在工具「报告库」中查看同 Digest 的已保存条目）';
    }
    return '$base$head\n${meta.toString().trim()}\n\n【分析报告全文】\n$body';
  }

  Future<void> _showReportLibrarySheet(BuildContext context) async {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final maxN = AppController.maxAnalysisReportsPerProject;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: StatefulBuilder(
              builder: (ctx, setModalState) {
                final list = widget.controller.analysisReportsForActiveProject;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('报告库', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      '每个项目最多保留 $maxN 条；新保存会按时间淘汰最旧条目。可删除任意一条；挂载后发送消息会在 system 中附带报告（有长度上限）。删除不影响已发送的历史气泡。',
                      style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.46,
                      child: list.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  '暂无已保存报告。在列表中点「智能分析」生成后，使用「保存到报告库」。',
                                  textAlign: TextAlign.center,
                                  style: t.textTheme.bodyMedium?.copyWith(color: cs.outline),
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: list.length,
                              separatorBuilder: (context, i) => const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final r = list[i];
                                final dt = DateFormat('MM-dd HH:mm').format(
                                  DateTime.fromMillisecondsSinceEpoch(r.createdAtMs),
                                );
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                  title: Text(r.shortTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                    '$dt · ${r.bizModule} · ${r.digestHash}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: '挂载到上下文',
                                        icon: const Icon(Icons.chat_bubble_outline),
                                        onPressed: () {
                                          widget.controller.attachReportToChat(r);
                                          Navigator.pop(sheetCtx);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('已挂载该报告到对话上下文'),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        },
                                      ),
                                      IconButton(
                                        tooltip: '从报告库删除',
                                        icon: Icon(Icons.delete_outline, color: cs.error),
                                        onPressed: () async {
                                          final ok = await showDialog<bool>(
                                            context: ctx,
                                            builder: (dCtx) => AlertDialog(
                                              title: const Text('删除报告'),
                                              content: const Text('确定从报告库中删除该条？此操作不可恢复。'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(dCtx, false),
                                                  child: const Text('取消'),
                                                ),
                                                FilledButton(
                                                  onPressed: () => Navigator.pop(dCtx, true),
                                                  child: const Text('删除'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (ok == true && context.mounted) {
                                            await widget.controller.deleteAnalysisReport(r.id);
                                            if (ctx.mounted) setModalState(() {});
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
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

    final projectId = widget.controller.activeProject.id;
    final turns = _messagesByProject.putIfAbsent(projectId, () => []);

    setState(() {
      turns.add({'role': 'user', 'content': text});
      _input.clear();
      _busy = true;
    });
    _scrollToBottom();

    final client = LlmClient(
      baseUrl: cfg.llmBaseUrl.trim(),
      apiKey: cfg.llmApiKey.trim(),
      model: cfg.llmModel.trim(),
      chatCompletionsPath: cfg.effectiveLlmChatPath,
      httpClient: newOutboundHttpClient(),
    );
    try {
      final messages = <Map<String, String>>[
        {'role': 'system', 'content': _systemPromptWithAttachment(cfg)},
        ..._apiHistoryFrom(turns),
      ];
      final reply = await client.chat(messages, temperature: 0.65);
      if (!mounted) return;
      final list = _messagesByProject.putIfAbsent(projectId, () => []);
      setState(() {
        list.add({'role': 'assistant', 'content': reply});
        _busy = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      final list = _messagesByProject.putIfAbsent(projectId, () => []);
      setState(() {
        list.add({
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
        final turns = _turns();
        final empty = turns.isEmpty;
        final attached = widget.controller.chatAttachedReport;

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
                          if (attached != null) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Tooltip(
                                message: '移除挂载（不删除报告库中的条目）',
                                child: InputChip(
                                  avatar: Icon(Icons.article, size: 18, color: cs.primary),
                                  label: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 280),
                                    child: Text(
                                      '上下文：${attached.shortTitle}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  deleteIcon: const Icon(Icons.close, size: 18),
                                  onDeleted: _busy ? null : () => widget.controller.clearChatAttachedReport(),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '报告库：挂载已保存的报告',
                      onPressed: !llmOk || _busy
                          ? null
                          : () => _showReportLibrarySheet(context),
                      icon: const Icon(Icons.library_books_outlined),
                    ),
                    IconButton(
                      tooltip: '清空当前项目对话',
                      onPressed: _busy || turns.isEmpty
                          ? null
                          : () => setState(turns.clear),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: empty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          llmOk
                              ? '使用当前项目的 LLM 多轮对话。\n可从「报告库」挂载崩溃智能分析全文，便于结合 Claude Code / MCP 落地改代码。\n切换项目会保留各自对话。'
                              : '请先在侧栏「配置」中填写 LLM Base URL、API Key 与模型名。',
                          textAlign: TextAlign.center,
                          style: t.textTheme.bodyLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ),
                    )
                  : Scrollbar(
                      controller: _scroll,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: ClampingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        itemCount: turns.length,
                        itemBuilder: (context, i) {
                          final m = turns[i];
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
