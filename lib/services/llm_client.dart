import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_retry_policy.dart';
import 'network_transport_policy.dart';

/// 将 Base URL 与相对路径合成最终请求地址。
Uri buildLlmChatCompletionsUri(String baseUrl, String chatCompletionsPath) {
  var root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  var rel = chatCompletionsPath.trim();
  if (rel.startsWith('/')) rel = rel.substring(1);
  if (rel.isEmpty) rel = 'v1/chat/completions';
  final base = Uri.parse(root);
  final p = base.path;
  final normalized = (p.isEmpty || p.endsWith('/'))
      ? base
      : base.replace(path: '$p/');
  return normalized.resolve(rel);
}

/// LLM 消息格式：支持 role/content 和 name/tool_call_id
class LlmMessage {
  LlmMessage({
    required this.role,
    required this.content,
    this.name,
    this.toolCallId,
  });

  final String role;
  final String content;
  final String? name;
  final String? toolCallId;

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    if (name != null) 'name': name,
    if (toolCallId != null) 'tool_call_id': toolCallId,
  };

  Map<String, String> toSimpleMap() => {'role': role, 'content': content};
}

/// 工具定义，符合 OpenAI function calling 格式
class LlmTool {
  LlmTool({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  Map<String, dynamic> toJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

/// 工具调用
class LlmToolCall {
  LlmToolCall({required this.id, required this.name, required this.arguments});

  final String id;
  final String name;
  final String arguments;

  Map<String, dynamic> get parsedArgs => jsonDecode(arguments) as Map<String, dynamic>;
}

/// Chat 响应
class LlmChatResponse {
  LlmChatResponse({required this.content, this.toolCalls, this.finishReason});

  final String? content;
  final List<LlmToolCall>? toolCalls;
  final String? finishReason;

  bool get hasToolCalls => toolCalls != null && toolCalls!.isNotEmpty;
}

/// OpenAI 兼容 Chat Completions。
class LlmClient {
  LlmClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.chatCompletionsPath = 'v1/chat/completions',
    required http.Client httpClient,
  }) : _http = httpClient;

  final String baseUrl;
  final String apiKey;
  final String model;
  final String chatCompletionsPath;
  final http.Client _http;

  Uri get _chatUri => buildLlmChatCompletionsUri(baseUrl, chatCompletionsPath);

  /// 简单聊天（无 tools），向后兼容
  Future<String> chat(List<Map<String, String>> messages, {double temperature = 0.3}) async {
    final msgs = messages.map((m) => LlmMessage(role: m['role'] ?? 'user', content: m['content'] ?? ''));
    final resp = await chatFull(msgs.toList(), temperature: temperature);
    return resp.content ?? '';
  }

  /// 完整 chat 接口，支持 tools 和工具调用
  Future<LlmChatResponse> chatFull(
    List<LlmMessage> messages, {
    double temperature = 0.3,
    List<LlmTool>? tools,
  }) async {
    return HttpRetryPolicy.run(() async {
      NetworkTransportPolicy.requireHttpsApiBase(baseUrl, 'LLM Base URL');
      final bodyMap = <String, dynamic>{
        'model': model,
        'temperature': temperature,
        'messages': messages.map((m) => m.toJson()).toList(),
      };
      if (tools != null && tools.isNotEmpty) {
        bodyMap['tools'] = tools.map((t) => t.toJson()).toList();
      }

      final body = jsonEncode(bodyMap);
      final res = await _http.post(
        _chatUri,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      final text = utf8.decode(res.bodyBytes);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (HttpRetryPolicy.isRetriableHttpStatus(res.statusCode)) {
          throw TransientHttpStatusException(res.statusCode);
        }
        throw LlmException(res.statusCode, text);
      }

      final j = jsonDecode(text) as Map<String, dynamic>;
      return _parseResponse(j, text);
    });
  }

  LlmChatResponse _parseResponse(Map<String, dynamic> j, String raw) {
    // 处理多种 choices 位置
    var choices = j['choices'];
    if (choices is! List || choices.isEmpty) {
      final data = j['data'];
      if (data is Map) choices = data['choices'];
    }
    if (choices is! List || choices.isEmpty) {
      throw LlmException(200, '无 choices');
    }
    final msg = choices.first as Map;
    final message = msg['message'];
    final finishReason = msg['finish_reason']?.toString();

    String? content;
    List<LlmToolCall>? toolCalls;

    if (message is Map) {
      // 文本内容
      final c = message['content'];
      if (c != null && c is String) content = c;
      if (content == null) {
        final r = message['reasoning_content'];
        if (r != null) content = r.toString();
      }

      // 工具调用
      final tcList = message['tool_calls'];
      if (tcList is List && tcList.isNotEmpty) {
        toolCalls = tcList.map((tc) {
          final fn = tc['function'] as Map;
          return LlmToolCall(
            id: tc['id']?.toString() ?? '',
            name: fn['name']?.toString() ?? '',
            arguments: fn['arguments']?.toString() ?? '{}',
          );
        }).toList();
      }
    }

    return LlmChatResponse(content: content, toolCalls: toolCalls, finishReason: finishReason);
  }

  /// 发送带 tools 的简单请求，自动处理工具调用循环
  Future<String> chatWithToolLoop(
    List<LlmMessage> messages, {
    double temperature = 0.3,
    List<LlmTool>? tools,
    required Future<String?> Function(LlmToolCall tc) onToolCall,
    int maxIterations = 10,
  }) async {
    final msgs = List<LlmMessage>.from(messages);
    for (int i = 0; i < maxIterations; i++) {
      final resp = await chatFull(msgs, temperature: temperature, tools: tools);
      if (!resp.hasToolCalls) {
        return resp.content ?? '';
      }

      // 添加 assistant 消息（含 tool_calls）
      msgs.add(LlmMessage(role: 'assistant', content: resp.content ?? ''));

      // 执行工具调用
      for (final tc in resp.toolCalls!) {
        final result = await onToolCall(tc);
        msgs.add(LlmMessage(
          role: 'tool',
          content: result ?? '工具执行完成（无返回）',
          toolCallId: tc.id,
        ));
      }
    }
    return '已达到最大工具调用次数 ($maxIterations)';
  }

  void close() => _http.close();
}

class LlmException implements Exception {
  LlmException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  String get userMessage => '大模型接口错误（HTTP $statusCode）';

  @override
  String toString() => userMessage;
}
