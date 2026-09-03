import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../models/tool_config.dart';
import '../services/agent_engine.dart';
import '../services/agent_tool_registry.dart';
import '../services/llm_client.dart';
import '../services/outbound_http_client_for_config.dart';
import '../services/security_redaction.dart';
import '../services/gitlab_client.dart';
import '../constants/app_constants.dart';

/// Agent 对话标签页：LLM + 工具（读写文件、shell、EMAS、GitLab 等）。
/// 每个项目独立会话记录，支持多轮工具调用。
class ChatTab extends StatefulWidget {
  const ChatTab({super.key, required this.controller});
  final AppController controller;
  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final Map<String, List<_ChatItem>> _itemsByProject = {};
  String? _boundProjectId;
  bool _busy = false;
  static const int _maxAttachedReportChars = 28000;

  List<_ChatItem> _items() {
    final id = widget.controller.activeProject.id;
    return _itemsByProject.putIfAbsent(id, () => []);
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
    if (_busy) setState(() => _busy = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
    });
  }

  String _systemPromptWithAttachment(ToolConfig cfg) {
    var base = cfg.effectiveLlmFreeChatSystemPrompt;
    final r = widget.controller.chatAttachedReport;
    if (r == null) return base;
    const head = '''

----------
【已挂载 EMAS AI 分析报告】当用户希望通过 Claude Code 或本 Agent 改代码时，以报告中的建议为优先依据。不要擅自 commit/push。
----------''';
    final meta = StringBuffer();
    meta.writeln('Digest: ${r.digestHash}');
    meta.writeln('BizModule: ${r.bizModule}');
    meta.writeln('标题: ${r.title}');
    var body = r.reportBody.trim();
    if (body.length > _maxAttachedReportChars) {
      body = '${body.substring(0, _maxAttachedReportChars)}\n\n…（截断）';
    }
    return '$base$head\n${meta.toString().trim()}\n\n【分析报告全文】\n$body';
  }

  String get _defaultSystemPrompt {
    final cfg = widget.controller.config;
    final sys = _systemPromptWithAttachment(cfg);
    if (sys.trim().isNotEmpty) return sys;
    final now = DateTime.now();
    final startMs = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final projPath = cfg.localProjectPath.isNotEmpty ? cfg.localProjectPath : '(未配置)';
    return '''你是一个通用 AI 助手，能读写文件、执行 shell、查 EMAS 数据、搜 GitLab 代码，也能转交复杂任务给 Claude Code CLI。

当前时间: ${DateFormat('yyyy-MM-dd HH:mm').format(now)}
项目路径: $projPath
EMAS 时间范围: $startMs ~ ${now.millisecondsSinceEpoch}

工具列表：
- read_file / write_file / list_directory / search_files / grep — 文件操作
- run_shell — 执行 shell 命令（git log、find 等）
- emas_list_issues / emas_issue_detail — EMAS 崩溃/ANR 数据
- gitlab_search — GitLab 代码搜索
- launch_claude_code — 复杂任务转 Claude Code

保持简洁直接，需要时才调工具。''';
  }

  AgentEngine _createEngine(LlmClient client) {
    final cfg = widget.controller.config;
    final registry = AgentToolRegistry.createStandard(
      config: cfg,
      projectPath: cfg.localProjectPath.isNotEmpty ? cfg.localProjectPath : '.',
      emasQuery: (bizModule, startMs, endMs, {os, pageSize}) async {
        final cli = widget.controller.cliService;
        final r = await cli.getIssues(
          bizModule: bizModule, startTimeMs: startMs, endTimeMs: endMs,
          os: os, pageSize: pageSize ?? 20,
        );
        return const JsonEncoder.withIndent('  ').convert({
          'total': r.total, 'items': r.items.length,
          'list': r.items.map((i) => {'name': i.errorName, 'rate': i.errorRatePercent, 'hash': i.digestHash}).toList(),
        });
      },
      emasIssueDetail: (bizModule, digestHash, startMs, endMs, {os}) async {
        final cli = widget.controller.cliService;
        final d = await cli.getIssue(bizModule: bizModule, digestHash: digestHash, startTimeMs: startMs, endTimeMs: endMs, os: os);
        return const JsonEncoder.withIndent('  ').convert(d);
      },
      gitlabSearch: cfg.gitlabToken.trim().isNotEmpty ? (projectId, query) async {
        final gc = GitLabClient(baseUrl: cfg.gitlabBaseUrl.trim(), privateToken: cfg.gitlabToken.trim(), httpClient: newOutboundHttpClient());
        try {
          final hits = await gc.searchBlobs(projectId: projectId, search: query, ref: cfg.gitlabRef.trim());
          if (hits.isEmpty) return '未找到匹配';
          return hits.take(10).map((h) {
            final d = h.data ?? '';
            return '[${h.basename}:${h.startline}] ${d.length > 300 ? d.substring(0, 300) + "..." : d}';
          }).join('\n\n---\n\n');
        } finally {
          gc.close();
        }
      } : null,
      huatuoGetLogs: (userId, date, devid) => _fetchHuatuoCrashLog(userId, date, devid),
    );
    final engine = AgentEngine(llmClient: client, toolRegistry: registry, temperature: 0.65);
    engine.addSystemPrompt(_defaultSystemPrompt);
    return engine;
  }

  /// 查询华佗崩溃日志（只读）：返回 crashLogFile 元数据 + tombstone 文本内容。
  Future<String> _fetchHuatuoCrashLog(String userId, String date, String devid) async {
    const baseUrl = 'https://huatuo.xesv5.com/api/1.0';
    final url = '$baseUrl/logFile?userId=$userId&devid=$devid&date=$date';

    final client = newOutboundHttpClient();
    try {
      final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        return '华佗日志接口返回 HTTP ${response.statusCode}';
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final inner = data['data'] as Map<String, dynamic>? ?? {};
      final dataList = inner['dataList'] as List<dynamic>? ?? [];

      // 定位 crashLogFile 事件
      Map<String, dynamic>? crashLogFile;
      for (final item in dataList) {
        final m = item as Map<String, dynamic>;
        final d = m['data'] as Map<String, dynamic>? ?? {};
        final eventid = d['eventid'] as String? ?? '';
        if (eventid == 'crashLogFile' || eventid.toLowerCase().contains('crash')) {
          crashLogFile = d;
          break;
        }
      }

      if (crashLogFile == null) {
        return '未找到 crashLogFile 日志（userId=$userId, date=$date, dataList 共 ${dataList.length} 条）';
      }

      final logFileUrl = crashLogFile['logFileUrl'] as String? ?? '';
      final buf = StringBuffer();
      buf.writeln('=== crashLogFile 元数据 ===');
      buf.writeln(const JsonEncoder.withIndent('  ').convert(crashLogFile));
      buf.writeln();

      // 下载 zip 并读取 tombstone 内容（内存中，不落盘）
      if (logFileUrl.isNotEmpty) {
        try {
          final zipResp = await client.get(Uri.parse(logFileUrl)).timeout(const Duration(minutes: 2));
          if (zipResp.statusCode == 200) {
            final tombstone = _extractTombstoneFromZip(zipResp.bodyBytes);
            if (tombstone != null && tombstone.isNotEmpty) {
              buf.writeln('=== tombstone 崩溃主日志（关键段） ===');
              buf.writeln(_extractTombstoneKeySections(tombstone));
            } else {
              buf.writeln('(压缩包内未找到 tombstone 文件)');
            }
          } else {
            buf.writeln('(下载日志压缩包失败 HTTP ${zipResp.statusCode})');
          }
        } catch (e) {
          buf.writeln('(下载/解压日志失败: $e)');
        }
      } else {
        buf.writeln('(无 logFileUrl，无法获取 tombstone)');
      }

      return buf.toString();
    } catch (e) {
      return '华佗日志查询失败: $e';
    } finally {
      client.close();
    }
  }

  /// 从 zip 字节中提取 tombstone 文件内容。
  String? _extractTombstoneFromZip(List<int> zipBytes) {
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes);
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final name = (f.name.split('/').last).toLowerCase();
        if (name.contains('tombstone')) {
          return String.fromCharCodes(f.content as List<int>);
        }
      }
    } catch (_) {}
    return null;
  }

  /// 从完整 tombstone 中提取给模型分析的关键内容。
  ///
  /// 不依赖具体字段名，而是按结构特征保留：
  /// - 头部标识行（Build fingerprint / pid / tid / name 等）
  /// - 异常堆栈块（含 stacktrace / Caused by 之后的多行）
  /// - logcat 段：保留崩溃时间点附近的行，并优先保留 error/fatal/异常/页面跳转等有意义行，
  ///   去重压缩埋点噪音，最终限制在 [maxChars] 以内。
  String _extractTombstoneKeySections(String tombstone, {int maxChars = 8000}) {
    final lines = tombstone.split('\n');
    final out = <String>[];
    var inStack = false;
    var stackLines = 0;

    for (final line in lines) {
      final t = line.trim();
      final lower = t.toLowerCase();

      // 头部标识行：保留
      final isHeader = lower.startsWith('build fingerprint') ||
          lower.startsWith('pid:') ||
          lower.startsWith('signal') ||
          lower.startsWith('abort') ||
          lower.startsWith('name:');

      // 堆栈块标记
      final isStackStart = lower.contains('stacktrace') ||
          lower.contains('caused by') ||
          lower.contains('backtrace') ||
          lower.contains('fatal exception');

      if (isHeader || isStackStart) {
        inStack = true;
        stackLines = 0;
        out.add(line);
        continue;
      }

      if (inStack) {
        // 堆栈缩进行 / at 行 / 连续内容，保留；遇到空行后若已足够长则结束堆栈块
        final isStackLine = t.startsWith('at ') ||
            t.startsWith('at\t') ||
            line.startsWith('\t') ||
            line.startsWith('    ') ||
            t.startsWith('Caused by') ||
            t.startsWith('#');
        if (isStackLine || (t.isNotEmpty && stackLines < 40)) {
          out.add(line);
          stackLines++;
          continue;
        }
        inStack = false;
      }

      // logcat 与其余：优先保留有意义行，压缩重复埋点
      final isNoise = lower.contains('@basebury') ||
          lower.contains('realinnelbasebury') ||
          lower.contains('buryentity');
      final isMeaningful = lower.contains('error') ||
          lower.contains('fatal') ||
          lower.contains('exception') ||
          lower.contains('crash') ||
          lower.contains('onactivity') ||
          lower.contains('onfragment') ||
          lower.contains('page') ||
          lower.contains('activity') ||
          lower.contains('fragment');

      if (isNoise && !isMeaningful) {
        // 跳过重复埋点噪音
        continue;
      }
      if (t.isEmpty) continue;

      out.add(line);
    }

    // 拼接并限制长度
    var result = out.join('\n');
    if (result.length > maxChars) {
      result = '${result.substring(0, maxChars)}\n...[已截断，原文共 ${tombstone.length} 字符]';
    }
    return result;
  }

  Future<void> _showReportLibrarySheet(BuildContext context) async {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: StatefulBuilder(builder: (ctx, setModalState) {
            final list = widget.controller.analysisReportsForActiveProject;
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('报告库', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              SizedBox(height: MediaQuery.sizeOf(context).height * 0.46, child: list.isEmpty
                ? Center(child: Text('暂无已保存报告', style: t.textTheme.bodyMedium?.copyWith(color: cs.outline)))
                : ListView.separated(
                    itemCount: list.length, separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final r = list[i];
                      final dt = DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(r.createdAtMs));
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        title: Text(r.shortTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('$dt · ${r.bizModule} · ${r.digestHash}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: '挂载', icon: const Icon(Icons.chat_bubble_outline), onPressed: () {
                            widget.controller.attachReportToChat(r); Navigator.pop(sheetCtx);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已挂载'), behavior: SnackBarBehavior.floating));
                          }),
                          IconButton(tooltip: '删除', icon: Icon(Icons.delete_outline, color: cs.error), onPressed: () async {
                            final ok = await showDialog<bool>(context: ctx, builder: (dCtx) => AlertDialog(title: const Text('删除'), content: const Text('确定？'), actions: [
                              TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('取消')),
                              FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('删除'))]));
                            if (ok == true && context.mounted) { await widget.controller.deleteAnalysisReport(r.id); if (ctx.mounted) setModalState(() {}); }
                          }),
                        ]),
                      );
                    },
                  ),
              ),
            ]);
          }),
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    final cfg = widget.controller.config;
    final miss = cfg.validateLlm();
    if (miss.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('请先在「配置」填写：${miss.join('、')}')));
      return;
    }
    final items = _items();
    items.add(_ChatItem(role: 'user', content: text));
    _input.clear();
    setState(() => _busy = true);
    _scrollToBottom();

    final client = LlmClient(baseUrl: cfg.llmBaseUrl.trim(), apiKey: cfg.llmApiKey.trim(), model: cfg.llmModel.trim(), chatCompletionsPath: cfg.effectiveLlmChatPath, httpClient: newOutboundHttpClient());
    final engine = _createEngine(client);
    try {
      await for (final step in engine.chat(text)) {
        if (!mounted) return;
        final list = _items();
        switch (step.type) {
          case 'thinking': break;
          case 'tool_call':
            list.add(_ChatItem(role: 'tool_call', toolName: step.toolName, toolParams: step.toolParams));
            setState(() {});
            _scrollToBottom();
          case 'tool_result':
            list.add(_ChatItem(role: 'tool_result', toolName: step.toolName, content: step.toolResult));
            setState(() {});
            _scrollToBottom();
          case 'response':
            list.add(_ChatItem(role: 'assistant', content: step.content));
            setState(() => _busy = false);
            _scrollToBottom();
        }
      }
    } catch (e) {
      if (!mounted) return;
      _items().add(_ChatItem(role: 'assistant', content: '请求失败：${userFacingNetworkError(e)}'));
      setState(() => _busy = false);
      _scrollToBottom();
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: widget.controller, builder: (context, _) {
      _bindProjectIfNeeded();
      final t = Theme.of(context); final cs = t.colorScheme;
      final cfg = widget.controller.config;
      final llmOk = cfg.validateLlm().isEmpty;
      final subtitle = llmOk ? '${cfg.llmModel.trim()} · ${cfg.llmBaseUrl.trim()}' : '请先在「配置」填写大模型';
      final items = _items();
      final attached = widget.controller.chatAttachedReport;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Material(color: cs.surfaceContainerHighest.withValues(alpha: kOpacityLight), child: Padding(padding: const EdgeInsets.fromLTRB(20, 14, 12, 14), child: Row(children: [
          Icon(Icons.forum_outlined, color: cs.primary, size: 26), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Agent 对话', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            if (attached != null) ...[const SizedBox(height: 8), Align(alignment: Alignment.centerLeft, child: Tooltip(message: '移除挂载', child: InputChip(
              avatar: Icon(Icons.article, size: 18, color: cs.primary),
              label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 280), child: Text('上下文：${attached.shortTitle}', maxLines: 1, overflow: TextOverflow.ellipsis)),
              deleteIcon: const Icon(Icons.close, size: 18),
              onDeleted: _busy ? null : () => widget.controller.clearChatAttachedReport(),
            )))],
          ])),
          IconButton(tooltip: '报告库', onPressed: !llmOk || _busy ? null : () => _showReportLibrarySheet(context), icon: const Icon(Icons.library_books_outlined)),
          IconButton(tooltip: '清空对话', onPressed: _busy || items.isEmpty ? null : () => setState(() => items.clear()), icon: const Icon(Icons.delete_outline_rounded)),
        ]))),
        Expanded(child: items.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(
              llmOk ? '支持工具调用（文件读写·shell·EMAS·GitLab·Claude Code）。\n可从报告库挂载分析报告。多轮对话 + 工具调用。'
                     : '请先在「配置」中填写 LLM Base URL、API Key、Model。',
              textAlign: TextAlign.center, style: t.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant, height: 1.45))))
          : Scrollbar(controller: _scroll, thumbVisibility: true, child: ListView.builder(controller: _scroll, physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()), padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), itemCount: items.length, itemBuilder: (_, i) => _buildItem(items[i], cs, t)))),
        if (_busy) LinearProgressIndicator(minHeight: 2, color: cs.primary, backgroundColor: cs.surfaceContainerHighest),
        Material(color: cs.surfaceContainerHighest.withValues(alpha: kOpacityLight), child: Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 14), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: TextField(controller: _input, minLines: 1, maxLines: 6, enabled: !_busy && llmOk, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), decoration: InputDecoration(hintText: llmOk ? '输入消息…' : '请先完成 LLM 配置', filled: true, border: OutlineInputBorder(borderRadius: AppBorderRadius.md), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)))),
          const SizedBox(width: 10),
          FilledButton(onPressed: _busy || !llmOk ? null : _send, child: _busy ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary)) : const Text('发送')),
        ]))),
      ]);
    });
  }

  Widget _buildItem(_ChatItem item, ColorScheme cs, ThemeData t) {
    switch (item.role) {
      case 'user':
        return _Bubble(isUser: true, cs: cs, child: SelectableText(item.content!, style: t.textTheme.bodyMedium?.copyWith(height: 1.4)));
      case 'assistant':
        return _Bubble(isUser: false, cs: cs, child: SelectableText(item.content!, style: t.textTheme.bodyMedium?.copyWith(height: 1.4)));
      case 'tool_call':
        return _ToolCallBubble(toolName: item.toolName!, params: item.toolParams, cs: cs, t: t);
      case 'tool_result':
        return _ToolResultBubble(toolName: item.toolName!, result: item.content!, cs: cs, t: t);
      default:
        return const SizedBox.shrink();
    }
  }
}

// === 数据模型 ===

class _ChatItem {
  _ChatItem({required this.role, this.content, this.toolName, this.toolParams});
  final String role;
  final String? content;
  final String? toolName;
  final Map<String, dynamic>? toolParams;
}

// === UI 组件 ===

class _Bubble extends StatelessWidget {
  const _Bubble({required this.isUser, required this.cs, required this.child});
  final bool isUser;
  final ColorScheme cs;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!isUser) ...[CircleAvatar(radius: 16, backgroundColor: cs.secondaryContainer, child: Icon(Icons.smart_toy_outlined, size: 18, color: cs.onSecondaryContainer)), const SizedBox(width: 10)],
        Flexible(child: Container(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(
          color: isUser ? cs.primaryContainer.withValues(alpha: kOpacityHeavy) : cs.surfaceContainerHighest.withValues(alpha: kOpacityMedium),
          borderRadius: BorderRadius.only(topLeft: const Radius.circular(16), topRight: const Radius.circular(16), bottomLeft: Radius.circular(isUser ? 16 : 4), bottomRight: Radius.circular(isUser ? 4 : 16)),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: kOpacityLight))), child: child)),
        if (isUser) ...[const SizedBox(width: 10), CircleAvatar(radius: 16, backgroundColor: cs.primaryContainer, child: Icon(Icons.person_outline_rounded, size: 18, color: cs.onPrimaryContainer))],
      ]),
    );
  }
}

class _ToolCallBubble extends StatefulWidget {
  const _ToolCallBubble({required this.toolName, required this.params, required this.cs, required this.t});
  final String toolName; final Map<String, dynamic>? params; final ColorScheme cs; final ThemeData t;
  @override State<_ToolCallBubble> createState() => _ToolCallBubbleState();
}

class _ToolCallBubbleState extends State<_ToolCallBubble> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final paramsStr = widget.params != null && widget.params!.isNotEmpty ? const JsonEncoder.withIndent('  ').convert(widget.params) : null;
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(mainAxisAlignment: MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.handyman_outlined, size: 18, color: widget.cs.tertiary), const SizedBox(width: 8),
      Flexible(child: InkWell(onTap: () => setState(() => _expanded = !_expanded), borderRadius: BorderRadius.circular(10), child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: widget.cs.tertiaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10), border: Border.all(color: widget.cs.tertiary.withValues(alpha: 0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.bolt, size: 14, color: widget.cs.tertiary), const SizedBox(width: 6),
            Text(widget.toolName, style: widget.t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: widget.cs.tertiary, fontFamily: 'monospace')),
            const Spacer(),
            Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 16, color: widget.cs.onSurfaceVariant),
          ]),
          if (_expanded && paramsStr != null) ...[const SizedBox(height: 6), Text(paramsStr, style: widget.t.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', color: widget.cs.onSurfaceVariant, height: 1.4))],
        ]),
      ))),
    ]));
  }
}

class _ToolResultBubble extends StatefulWidget {
  const _ToolResultBubble({required this.toolName, required this.result, required this.cs, required this.t});
  final String toolName; final String result; final ColorScheme cs; final ThemeData t;
  @override State<_ToolResultBubble> createState() => _ToolResultBubbleState();
}

class _ToolResultBubbleState extends State<_ToolResultBubble> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final lines = widget.result.split('\n');
    final preview = lines.length > 4 ? '${lines.take(4).join('\n')}\n...' : widget.result;
    return Padding(padding: const EdgeInsets.only(bottom: 8, left: 26), child: InkWell(onTap: () => setState(() => _expanded = !_expanded), borderRadius: BorderRadius.circular(10), child: Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.74), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: widget.cs.surfaceContainerHighest.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(10), border: Border.all(color: widget.cs.outlineVariant.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline, size: 14, color: widget.cs.tertiary), const SizedBox(width: 6),
          Text('${widget.toolName} 返回', style: widget.t.textTheme.labelSmall?.copyWith(color: widget.cs.onSurfaceVariant)),
          const Spacer(),
          Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 16, color: widget.cs.onSurfaceVariant),
        ]),
        const SizedBox(height: 4),
        Text(_expanded ? widget.result : preview, style: widget.t.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', color: widget.cs.onSurfaceVariant, height: 1.35)),
      ]),
    )));
  }
}
