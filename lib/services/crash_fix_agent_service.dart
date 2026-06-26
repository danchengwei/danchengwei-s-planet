/// 崩溃修复 Agent 服务。
///
/// 管理 Agent 生命周期、维护对话上下文、协调 LLM 和工具调用。

import 'dart:convert';

import '../models/tool_config.dart';
import 'ai_source_code_analyzer.dart';
import 'crash_fix_agent_prompts.dart';
import 'crash_fix_agent_tools.dart';
import 'llm_client.dart';
import 'outbound_http_client_for_config.dart';

/// 对话消息
class AgentMessage {
  AgentMessage({
    required this.role, // 'user', 'assistant', 'tool'
    required this.content,
    this.toolName,
    this.toolParams,
  });

  final String role;
  final String content;
  final String? toolName;
  final Map<String, dynamic>? toolParams;

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    if (toolName != null) 'tool_name': toolName,
    if (toolParams != null) 'tool_params': toolParams,
  };
}

/// 工具调用请求
class ToolCallRequest {
  ToolCallRequest({
    required this.tool,
    required this.params,
  });

  final String tool;
  final Map<String, dynamic> params;

  factory ToolCallRequest.fromJson(Map<String, dynamic> json) {
    return ToolCallRequest(
      tool: json['tool'] as String? ?? '',
      params: (json['params'] as Map?)?.cast<String, dynamic>() ?? {},
    );
  }
}

/// 单条 Agent 实例
class CrashFixAgent {
  CrashFixAgent({
    required this.config,
    required this.crashHash,
    required this.stackTrace,
    required this.llmClient,
    required this.toolExecutor,
    this.sourceCode,
  }) {
    _conversationHistory = [
      {
        'role': 'system',
        'content': crashFixAgentSystemPrompt,
      }
    ];
    _initializeSystemContext();
  }

  final ToolConfig config;
  final String crashHash;
  final String stackTrace;
  final String? sourceCode;
  final LlmClient llmClient;
  final AgentToolExecutor toolExecutor;

  late final List<Map<String, dynamic>> _conversationHistory;

  /// 初始化系统上下文（包含初始分析）
  void _initializeSystemContext() {
    final context = '''
## 当前分析任务

**Crash Hash**: $crashHash

**堆栈轨迹**:
```
$stackTrace
```
${sourceCode != null ? '''
**相关源码**:
```
$sourceCode
```
''' : ''}

请分析这个崩溃问题。你可以：
1. 直接分析堆栈和源码
2. 调用工具获取更多信息（issue 详情、相似崩溃等）
3. 提供修复建议和代码示例
''';

    _conversationHistory.add({
      'role': 'user',
      'content': context,
    });
  }

  /// 发送用户消息
  Future<String> chat(String userMessage) async {
    // 添加用户消息到历史
    _conversationHistory.add({
      'role': 'user',
      'content': userMessage,
    });

    // 调用 LLM
    String response = await _callLlm();

    // 解析并执行工具调用（如果有）
    while (_containsToolCall(response)) {
      final toolCalls = _extractToolCalls(response);
      if (toolCalls.isEmpty) break;

      // 添加 Agent 的第一次响应
      _conversationHistory.add({
        'role': 'assistant',
        'content': response,
      });

      // 执行工具调用
      final toolResults = StringBuffer();
      for (final call in toolCalls) {
        try {
          final result = await toolExecutor.executeTool(call.tool, call.params);
          toolResults.writeln('### 工具: ${call.tool}');
          toolResults.writeln(result);
          toolResults.writeln('');
        } catch (e) {
          toolResults.writeln('**错误**: $e\n');
        }
      }

      // 添加工具结果
      _conversationHistory.add({
        'role': 'tool',
        'content': toolResults.toString().trim(),
      });

      // 再次调用 LLM（基于工具结果继续分析）
      response = await _callLlm();
    }

    // 添加最终响应
    _conversationHistory.add({
      'role': 'assistant',
      'content': response,
    });

    return response;
  }

  /// 调用 LLM
  Future<String> _callLlm() async {
    // 准备消息（限制历史长度以避免上下文溢出）
    final messages = _prepareLlmMessages();

    try {
      final response = await llmClient.chat(
        messages,
        temperature: 0.3,
      );
      return response;
    } catch (e) {
      throw Exception('LLM 调用失败: $e');
    }
  }

  /// 准备发送给 LLM 的消息
  List<Map<String, String>> _prepareLlmMessages() {
    const maxMessages = 20;
    final msgs = <Map<String, String>>[];

    // 系统消息必须保留
    msgs.add({
      'role': 'system',
      'content': crashFixAgentSystemPrompt,
    });

    // 保留最近的消息（不包括系统消息）
    final recentMessages = _conversationHistory.skip(1).toList();
    final startIdx = recentMessages.length > maxMessages
        ? recentMessages.length - maxMessages
        : 0;

    for (int i = startIdx; i < recentMessages.length; i++) {
      final msg = recentMessages[i];
      msgs.add({
        'role': msg['role'] as String? ?? 'user',
        'content': msg['content'] as String? ?? '',
      });
    }

    return msgs;
  }

  /// 检查响应中是否包含工具调用
  bool _containsToolCall(String response) {
    return response.contains('<tool_call>') && response.contains('</tool_call>');
  }

  /// 提取工具调用请求
  List<ToolCallRequest> _extractToolCalls(String response) {
    final results = <ToolCallRequest>[];
    final regex = RegExp(r'<tool_call>\s*([\s\S]*?)\s*</tool_call>');

    for (final match in regex.allMatches(response)) {
      try {
        final json = jsonDecode(match.group(1) ?? '{}') as Map<String, dynamic>;
        results.add(ToolCallRequest.fromJson(json));
      } catch (e) {
        // 忽略解析错误
      }
    }

    return results;
  }

  /// 重置对话
  void reset() {
    _conversationHistory.clear();
    _conversationHistory.add({
      'role': 'system',
      'content': crashFixAgentSystemPrompt,
    });
    _initializeSystemContext();
  }

  /// 获取对话历史
  List<AgentMessage> getHistory() {
    return _conversationHistory
        .where((msg) => msg['role'] != 'system')
        .map((msg) => AgentMessage(
          role: msg['role'] as String? ?? 'user',
          content: msg['content'] as String? ?? '',
        ))
        .toList();
  }
}

/// 崩溃修复 Agent 服务（单例）
class CrashFixAgentService {
  CrashFixAgentService._();

  static final CrashFixAgentService _instance = CrashFixAgentService._();

  factory CrashFixAgentService() {
    return _instance;
  }

  CrashFixAgent? _currentAgent;
  LlmClient? _llmClient;
  AgentToolExecutor? _toolExecutor;

  /// 初始化服务
  void initialize({
    required ToolConfig config,
    required dynamic emasClient,
    required AiSourceCodeAnalyzer sourceCodeAnalyzer,
  }) {
    _llmClient = LlmClient(
      baseUrl: config.llmBaseUrl,
      apiKey: config.llmApiKey,
      model: config.llmModel,
      chatCompletionsPath: config.llmChatCompletionsPath,
      httpClient: newOutboundHttpClient(),
    );

    _toolExecutor = AgentToolExecutor(
      config: config,
      emasClient: emasClient,
      sourceCodeAnalyzer: sourceCodeAnalyzer,
    );
  }

  /// 创建 Agent 实例
  CrashFixAgent createAgent({
    required ToolConfig config,
    required String crashHash,
    required String stackTrace,
    String? sourceCode,
  }) {
    if (_llmClient == null || _toolExecutor == null) {
      throw Exception('CrashFixAgentService 未初始化，请先调用 initialize()');
    }

    _currentAgent = CrashFixAgent(
      config: config,
      crashHash: crashHash,
      stackTrace: stackTrace,
      sourceCode: sourceCode,
      llmClient: _llmClient!,
      toolExecutor: _toolExecutor!,
    );

    return _currentAgent!;
  }

  /// 获取当前 Agent
  CrashFixAgent? get currentAgent => _currentAgent;

  /// 发送消息到当前 Agent
  Future<String> sendMessage(String message) async {
    if (_currentAgent == null) {
      throw Exception('未创建 Agent 实例');
    }
    return _currentAgent!.chat(message);
  }

  /// 重置服务
  void reset() {
    _currentAgent = null;
  }

  /// 清理资源
  void dispose() {
    _llmClient?.close();
    _currentAgent = null;
    _toolExecutor = null;
    _llmClient = null;
  }
}
