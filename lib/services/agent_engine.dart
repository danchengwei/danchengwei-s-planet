import 'agent_tool_registry.dart';
import 'llm_client.dart';

/// Agent 中间步骤事件
class AgentStep {
  AgentStep({this.type = 'thinking', this.toolName, this.toolParams, this.toolResult, this.content});

  final String type; // thinking | tool_call | tool_result | response
  final String? toolName;
  final Map<String, dynamic>? toolParams;
  final String? toolResult;
  final String? content;
}

/// 通用 AI Agent 引擎。
///
/// 管理提示词、对话上下文、工具调用循环。
class AgentEngine {
  AgentEngine({
    required this.llmClient,
    required this.toolRegistry,
    this.systemPrompt = '',
    this.maxToolIterations = 10,
    this.temperature = 0.3,
  });

  final LlmClient llmClient;
  final AgentToolRegistry toolRegistry;
  final String systemPrompt;
  final int maxToolIterations;
  final double temperature;

  final List<LlmMessage> _messages = [];

  List<LlmMessage> get messages => List.unmodifiable(_messages);

  /// 初始化系统提示词
  void addSystemPrompt(String prompt) {
    if (prompt.isNotEmpty) {
      _messages.add(LlmMessage(role: 'system', content: prompt));
    }
  }

  /// 发送用户消息，返回 Agent 的每次中间步骤
  Stream<AgentStep> chat(String userMessage) async* {
    _messages.add(LlmMessage(role: 'user', content: userMessage));

    final tools = toolRegistry.llmTools;

    for (int iter = 0; iter < maxToolIterations; iter++) {
      yield AgentStep(type: 'thinking');

      final resp = await llmClient.chatFull(
        _messages,
        temperature: temperature,
        tools: tools,
      );

      if (!resp.hasToolCalls) {
        final text = resp.content ?? '';
        if (text.isNotEmpty) {
          _messages.add(LlmMessage(role: 'assistant', content: text));
          yield AgentStep(type: 'response', content: text);
        }
        return;
      }

      _messages.add(LlmMessage(role: 'assistant', content: resp.content ?? ''));

      for (final tc in resp.toolCalls!) {
        yield AgentStep(
          type: 'tool_call',
          toolName: tc.name,
          toolParams: tc.parsedArgs,
        );

        String result;
        try {
          result = await toolRegistry.execute(tc.name, tc.parsedArgs);
        } catch (e) {
          result = '工具执行异常: $e';
        }

        yield AgentStep(
          type: 'tool_result',
          toolName: tc.name,
          toolResult: result,
        );

        _messages.add(LlmMessage(
          role: 'tool',
          content: result,
          toolCallId: tc.id,
        ));
      }
    }

    final finalResp = await llmClient.chatFull(
      _messages,
      temperature: temperature,
    );
    final text = finalResp.content ?? '已达到最大工具调用次数';
    _messages.add(LlmMessage(role: 'assistant', content: text));
    yield AgentStep(type: 'response', content: text);
  }

  /// 重置对话
  void reset() {
    _messages.clear();
    if (systemPrompt.isNotEmpty) {
      _messages.add(LlmMessage(role: 'system', content: systemPrompt));
    }
  }
}
