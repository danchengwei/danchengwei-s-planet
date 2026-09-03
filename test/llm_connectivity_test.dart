import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../lib/services/llm_client.dart';
import '../lib/services/create_outbound_client_io.dart' show createOutboundHttpClient;
import '../lib/services/workspace_cipher.dart';

void main() {
  test('LLM 连通性检测（从本机加密工作区读取配置）', () async {
    // 读取本机加密工作区
    final home = Platform.environment['HOME'] ?? '/Users/${Platform.environment['USER']}';
    final wsPath = p.join(
      home, 'Library', 'Application Support',
      'com.crashtools.crashEmasTool', 'crash-tools-workspace.json',
    );

    final wsFile = File(wsPath);
    if (!await wsFile.exists()) {
      fail('工作区文件不存在: $wsPath');
    }

    final sealed = await wsFile.readAsString();
    if (!WorkspaceCipher.looksEncrypted(sealed)) {
      fail('工作区未加密或格式异常');
    }

    final jsonText = await WorkspaceCipher.openUtf8(sealed);
    final ws = jsonDecode(jsonText) as Map<String, dynamic>;

    // 找到当前活跃项目
    final projects = ws['projects'] as List<dynamic>? ?? [];
    final activeId = ws['activeProjectId']?.toString() ?? '';
    Map<String, dynamic>? config;
    for (final p in projects) {
      if (p is Map && p['id']?.toString() == activeId) {
        config = (p['config'] as Map?)?.cast<String, dynamic>();
        break;
      }
    }
    config ??= (projects.isNotEmpty && projects.first is Map)
        ? (projects.first['config'] as Map?)?.cast<String, dynamic>()
        : null;

    if (config == null) {
      fail('工作区中未找到项目配置');
    }

    final baseUrl = config['llmBaseUrl']?.toString().trim() ?? '';
    final apiKey = config['llmApiKey']?.toString().trim() ?? '';
    final model = config['llmModel']?.toString().trim() ?? '';
    final chatPath = config['llmChatCompletionsPath']?.toString().trim() ?? '';
    final projectName = activeId;

    print('=== LLM 连通性测试 ===');
    print('项目: $projectName');
    print('Base URL: $baseUrl');
    print('Model: ${model.isNotEmpty ? model : "(未配置)"}');
    print('API Key: ${apiKey.isNotEmpty ? "${apiKey.substring(0, 8)}..." : "(未配置)"}');
    print('');

    if (baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
      fail('LLM 配置不完整（需要 Base URL / API Key / Model）');
    }

    final httpClient = createOutboundHttpClient();
    final client = LlmClient(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      chatCompletionsPath: chatPath.isEmpty ? 'chat/completions' : chatPath,
      httpClient: httpClient,
    );

    try {
      final response = await client.chat(
        [{'role': 'user', 'content': '只回复OK两个字，不要其他内容'}],
        temperature: 0,
      );
      print('PASS: LLM 连接正常');
      print('Response: $response');
    } on LlmException catch (e) {
      print('FAIL: HTTP ${e.statusCode}');
      print('Body (前300字符): ${e.body.length > 300 ? e.body.substring(0, 300) : e.body}');
      fail('LLM 请求失败: ${e.userMessage}');
    } catch (e) {
      print('FAIL: ${e.toString()}');
      fail('LLM 请求异常: $e');
    } finally {
      client.close();
    }
  });
}
