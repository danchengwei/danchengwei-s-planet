import 'dart:async';

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
    this.interRequestDelay = const Duration(milliseconds: 800),
  });

  final LlmClient llmClient;
  final AgentToolRegistry toolRegistry;
  final String systemPrompt;
  final int maxToolIterations;
  final double temperature;

  /// 两次 LLM 请求之间的间隔，用于适配小配额网关（如 RPM 5 → 间隔约 13s）。
  final Duration interRequestDelay;

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
      // 轮次间稍作等待，避免连续请求触发网关限流（可通过 interRequestDelay 适配配额）。
      if (iter > 0) {
        await Future<void>.delayed(interRequestDelay);
      }
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

      _messages.add(LlmMessage(
        role: 'assistant',
        content: resp.content ?? '',
        toolCalls: resp.hasToolCalls ? resp.toolCalls : null,
      ));

      for (final tc in resp.toolCalls!) {
        yield AgentStep(
          type: 'tool_call',
          toolName: tc.name,
          toolParams: tc.parsedArgs,
        );

        String result;
        try {
          result = await toolRegistry
              .execute(tc.name, tc.parsedArgs)
              .timeout(const Duration(seconds: 30));
        } on TimeoutException {
          result = '工具执行超时（>30s）：请缩小搜索范围（指定子目录/更精确关键词）后重试。';
        } catch (e) {
          result = '工具执行异常: $e';
        }
        // 限制工具结果大小，避免多轮工具结果累积导致后续请求体过大/超时。
        if (result.length > 6000) {
          result = '${result.substring(0, 6000)}\n...(结果过长已截断；如需更多信息请直接 read_file 关键文件)';
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
          name: tc.name,
        ));
      }
    }

    // 工具轮次耗尽：追加明确指令后再请求一次，要求基于已收集信息给出最终回复。
    _messages.add(LlmMessage(
      role: 'user',
      content: '你已完成必要的源码检索。请基于以上堆栈、tombstone 与读取到的源码，'
          '给出最终分析结论，并按系统提示要求输出一个完整 JSON 对象（直接以 { 开头、} 结尾）。',
    ));
    final finalResp = await llmClient.chatFull(
      _messages,
      temperature: temperature,
    );
    final text = (finalResp.content ?? '').trim();
    if (text.isEmpty) {
      yield AgentStep(
        type: 'response',
        content: '模型在工具调用后未返回有效文本结论（可能因轮次或上下文过长）。请重试或减少分析范围。',
      );
    } else {
      _messages.add(LlmMessage(role: 'assistant', content: text));
      yield AgentStep(type: 'response', content: text);
    }
  }

  /// 重置对话
  void reset() {
    _messages.clear();
    if (systemPrompt.isNotEmpty) {
      _messages.add(LlmMessage(role: 'system', content: systemPrompt));
    }
  }
}
