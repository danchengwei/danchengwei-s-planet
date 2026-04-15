import 'package:flutter_test/flutter_test.dart';

import 'package:crash_emas_tool/services/llm_client.dart';

void main() {
  group('buildLlmChatCompletionsUri', () {
    test('智谱：v4 无尾斜杠 + chat/completions 须保留 v4 段', () {
      final u = buildLlmChatCompletionsUri(
        'https://open.bigmodel.cn/api/paas/v4',
        'chat/completions',
      );
      expect(
        u.toString(),
        'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      );
    });

    test('OpenAI 风格：根域名 + v1/chat/completions', () {
      final u = buildLlmChatCompletionsUri(
        'https://api.openai.com',
        'v1/chat/completions',
      );
      expect(u.toString(), 'https://api.openai.com/v1/chat/completions');
    });

    test('base 已有尾斜杠时不再重复', () {
      final u = buildLlmChatCompletionsUri(
        'https://open.bigmodel.cn/api/paas/v4/',
        'chat/completions',
      );
      expect(
        u.toString(),
        'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      );
    });
  });
}
