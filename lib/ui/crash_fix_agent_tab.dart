/// 崩溃修复 Agent 对话标签页 - 优化版。
///
/// 支持自由对话查询 EMAS 数据、获取修复建议。

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../models/tool_config.dart';
import '../services/crash_fix_agent_service.dart';
import '../services/outbound_http_client_for_config.dart';
import '../services/skills_exporter.dart';
import '../aliyun/emas_appmonitor_client.dart';

class CrashFixAgentTab extends StatefulWidget {
  const CrashFixAgentTab({
    super.key,
    required this.controller,
  });

  final AppController controller;

  @override
  State<CrashFixAgentTab> createState() => _CrashFixAgentTabState();
}

class _CrashFixAgentTabState extends State<CrashFixAgentTab> {
  late final CrashFixAgentService _agentService;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  CrashFixAgent? _currentAgent;
  List<AgentMessage> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _agentService = CrashFixAgentService();
    _initializeService();
    _createFreeformAgent();
  }

  void _initializeService() {
    try {
      final config = widget.controller.config;
      _agentService.initialize(
        config: config,
        emasClient: EmasAppMonitorClient(
          accessKeyId: config.accessKeyId,
          accessKeySecret: config.accessKeySecret,
          regionId: config.region,
          httpClient: newOutboundHttpClient(),
        ),
        sourceCodeAnalyzer: widget.controller.sourceCodeAnalyzer,
      );
    } catch (e) {
      _showErrorSnackbar('初始化 Agent 服务失败: $e');
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _agentService.dispose();
    super.dispose();
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.tertiary,
      ),
    );
  }

  Future<void> _exportSkills() async {
    try {
      _showSuccessSnackbar('开始导出 Skills 包...');

      final exporter = SkillsExporter(
        config: widget.controller.config,
        appVersion: 'v1.0.0', // TODO: 从 pubspec.yaml 读取版本
      );

      final outputDir = widget.controller.tempDirectory.path;
      final filePath = await exporter.exportSkillsPackage(outputDir: outputDir);

      if (!mounted) return;

      // 显示成功对话框
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('✅ Skills 导出成功'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('文件已保存到:\n$filePath'),
              const SizedBox(height: 12),
              const Text('您可以:\n'
                  '• 将此包上传到其他 AI 工具\n'
                  '• 在 Claude Code MCP 中使用\n'
                  '• 在 Lobster 中集成'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _copyToClipboard(filePath);
              },
              child: const Text('复制路径'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showErrorSnackbar('导出失败: $e');
    }
  }

  void _copyToClipboard(String text) {
    // TODO: 实现复制到剪贴板
    _showSuccessSnackbar('路径已复制');
  }

  void _createFreeformAgent() {
    try {
      _currentAgent = _agentService.createAgent(
        config: widget.controller.config,
        crashHash: 'freeform',
        stackTrace: '用户自由对话模式 - 可查询任何分析数据',
      );

      setState(() {
        _messages = [
          AgentMessage(
            role: 'assistant',
            content: '👋 欢迎使用崩溃修复 Agent!\n\n'
                '我可以帮你:\n'
                '• 查询 Top10: "查 top10 crash" 或 "show top10 anr"\n'
                '• 分析问题: "分析 digestHash xxxxx"\n'
                '• 获取统计: "过去7天的崩溃趋势"\n'
                '• 代码修复: "如何修复这个 NPE?"\n\n'
                '开始提问吧👇',
          ),
        ];
      });
    } catch (e) {
      _showErrorSnackbar('初始化 Agent 失败: $e');
    }
  }

  Future<void> _sendMessage() async {
    final input = _inputController.text.trim();
    if (input.isEmpty) return;

    if (_currentAgent == null) {
      _showErrorSnackbar('Agent 未初始化');
      return;
    }

    _inputController.clear();

    setState(() {
      _messages.add(AgentMessage(role: 'user', content: input));
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      final response = await _agentService.sendMessage(input);
      setState(() {
        _messages.add(AgentMessage(role: 'assistant', content: response));
      });
    } catch (e) {
      setState(() {
        _messages.add(AgentMessage(
          role: 'assistant',
          content: '❌ 错误: $e',
        ));
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 优化的工具栏
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primaryContainer,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.smart_toy, size: 20, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('崩溃修复助手', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text('智能分析 EMAS 数据', style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.tertiary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('在线', style: t.labelSmall?.copyWith(color: cs.tertiary, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: '导出 OpenClaw Skills 包',
                child: IconButton(
                  onPressed: _exportSkills,
                  icon: const Icon(Icons.download),
                  tooltip: '导出 Skills',
                  style: IconButton.styleFrom(
                    backgroundColor: cs.secondaryContainer,
                    foregroundColor: cs.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 对话区域
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_outlined, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.2)),
                            const SizedBox(height: 12),
                            Text('开始对话', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _messages.length + (_isLoading ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i == _messages.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 1.5, color: cs.primary),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('分析中...', style: t.labelSmall?.copyWith(color: cs.primary)),
                                ],
                              ),
                            );
                          }

                          final msg = _messages[i];
                          final isUser = msg.role == 'user';
                          final isError = msg.content.startsWith('❌');

                          return _buildMessageBubble(msg, isUser, isError, t, cs);
                        },
                      ),
              ),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            ],
          ),
        ),

        // 优化的输入区域
        Container(
          color: cs.surface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      enabled: !_isLoading,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: '输入问题或指令...',
                        hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (_) => _isLoading ? null : _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isLoading ? null : _sendMessage,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      minimumSize: const Size.square(44),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(cs.onPrimary),
                            ),
                          )
                        : Icon(Icons.send_rounded, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '💡 尝试: "查 top10 anr" 或 "分析 crash"',
                  style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(
    AgentMessage msg,
    bool isUser,
    bool isError,
    TextTheme t,
    ColorScheme cs,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isError ? cs.errorContainer : cs.primaryContainer,
              ),
              alignment: Alignment.center,
              child: Icon(
                isError ? Icons.error : Icons.smart_toy,
                size: 14,
                color: isError ? cs.error : cs.primary,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isUser ? cs.primaryContainer : (isError ? cs.errorContainer.withValues(alpha: 0.2) : cs.surfaceVariant.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isUser ? 14 : 2),
                  bottomRight: Radius.circular(isUser ? 2 : 14),
                ),
              ),
              child: SelectableText(
                msg.content,
                style: TextStyle(
                  fontSize: 13,
                  color: isUser ? cs.onPrimaryContainer : (isError ? cs.error : cs.onSurface),
                  height: 1.35,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary),
              alignment: Alignment.center,
              child: const Text('👤', style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}
