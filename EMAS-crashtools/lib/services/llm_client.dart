import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_retry_policy.dart';
import 'network_transport_policy.dart';

/// OpenAI 兼容 Chat Completions（默认路径 `v1/chat/completions`，智谱等为 `chat/completions`）。
class LlmClient {
  LlmClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.chatCompletionsPath = 'v1/chat/completions',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final String model;
  /// 相对 [baseUrl] 的路径，无前导 `/`，如 `v1/chat/completions`。
  final String chatCompletionsPath;
  final http.Client _http;

  Uri get _chatUri {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    var rel = chatCompletionsPath.trim();
    if (rel.startsWith('/')) rel = rel.substring(1);
    if (rel.isEmpty) rel = 'v1/chat/completions';
    final base = Uri.parse(root);
    return base.resolve(rel);
  }

  Future<String> chat(List<Map<String, String>> messages, {double temperature = 0.3}) async {
    return HttpRetryPolicy.run(() async {
      NetworkTransportPolicy.requireHttpsApiBase(baseUrl, 'LLM Base URL');
      final body = jsonEncode({
        'model': model,
        'temperature': temperature,
        'messages': messages,
      });
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
      final choices = j['choices'];
      if (choices is! List || choices.isEmpty) throw LlmException(res.statusCode, '无 choices');
      final msg = choices.first;
      if (msg is! Map) throw LlmException(res.statusCode, '响应格式异常');
      final content = msg['message'];
      if (content is Map) {
        final c = content['content'];
        if (c != null) return c.toString();
        // 智谱等 reasoning 模型可能仅填 reasoning_content
        final r = content['reasoning_content'];
        if (r != null) return r.toString();
      }
      return text;
    });
  }

  void close() => _http.close();
}

class LlmException implements Exception {
  LlmException(this.statusCode, this.body);
  final int statusCode;
  /// 原始响应（勿写入日志或界面全文）。
  final String body;

  /// 界面与列表展示用，不含完整响应体。
  String get userMessage => '大模型接口错误（HTTP $statusCode）';

  @override
  String toString() => userMessage;
}
