import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/tool_config.dart';

/// LLM 分析服务 - 使用 GLM 模型进行根因分析
class LlmAnalyzer {
  LlmAnalyzer({required this.config});

  final ToolConfig config;

  /// 根据日志和堆栈生成根因分析
  Future<Map<String, dynamic>> generateRootCauseAnalysis({
    required String digestHash,
    required String crashTitle,
    required String stackInfo,
    required Map<String, dynamic> huatuoAnalysis,
    required Map<String, dynamic> userSample,
  }) async {
    try {
      // 构建分析提示
      final prompt = _buildAnalysisPrompt(
        crashTitle: crashTitle,
        stackInfo: stackInfo,
        huatuoAnalysis: huatuoAnalysis,
        userSample: userSample,
      );

      debugPrint('[LLM] 调用 API 进行根因分析...');
      final response = await callLlmApi(prompt);

      // 解析 LLM 响应
      final analysis = _parseRootCauseAnalysis(response);
      return analysis;
    } catch (e) {
      debugPrint('[LLM] 分析失败: $e');
      return _getDefaultAnalysis();
    }
  }

  /// 调用 GLM API
  Future<String> callLlmApi(String prompt) async {
    final url = Uri.parse(
      '${config.llmBaseUrl}/${config.llmChatCompletionsPath}',
    );

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.llmApiKey}',
    };

    final body = jsonEncode({
      'model': config.llmModel,
      'messages': [
        {
          'role': 'user',
          'content': prompt,
        }
      ],
      'temperature': 0.7,
      'max_tokens': 2000,
    });

    try {
      final response = await http.post(
        url,
        headers: headers,
        body: body,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List<dynamic>? ?? [];
        if (choices.isNotEmpty) {
          final message = choices.first as Map<String, dynamic>;
          final content = message['message']['content'] as String? ?? '';
          return content;
        }
      } else {
        debugPrint('[LLM] API 错误: ${response.statusCode}');
        debugPrint('[LLM] 响应: ${response.body.substring(0, 200)}');
      }
    } catch (e) {
      debugPrint('[LLM] HTTP 请求异常: $e');
    }

    throw Exception('LLM API 调用失败');
  }

  /// 构建分析提示词
  String _buildAnalysisPrompt({
    required String crashTitle,
    required String stackInfo,
    required Map<String, dynamic> huatuoAnalysis,
    required Map<String, dynamic> userSample,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('你是一个 Android 应用崩溃分析专家。');
    buffer.writeln('请根据以下信息进行根因分析，输出 JSON 格式的结果。');
    buffer.writeln('');

    // 崩溃基本信息
    buffer.writeln('【崩溃信息】');
    buffer.writeln('标题: $crashTitle');
    buffer.writeln('堆栈信息:');
    buffer.writeln(stackInfo.split('\n').take(20).join('\n'));
    buffer.writeln('');

    // 用户样本信息
    buffer.writeln('【用户设备信息】');
    buffer.writeln('用户 ID: ${userSample['user_id'] ?? ''}');
    buffer.writeln('设备型号: ${userSample['device_model'] ?? ''}');
    buffer.writeln('应用版本: ${userSample['app_version'] ?? ''}');
    buffer.writeln('系统版本: ${userSample['system_version'] ?? ''}');
    buffer.writeln('国家/地区: ${userSample['country'] ?? ''}/${userSample['province'] ?? ''}');
    buffer.writeln('');

    // 华佗日志分析
    buffer.writeln('【华佗日志分析】');
    buffer.writeln('总事件数: ${huatuoAnalysis['total_events'] ?? 0}');
    buffer.writeln('错误事件: ${(huatuoAnalysis['error_events'] as List?)?.length ?? 0}');
    buffer.writeln('警告事件: ${(huatuoAnalysis['warning_events'] as List?)?.length ?? 0}');

    final pageHistory = huatuoAnalysis['page_history'] as List? ?? [];
    if (pageHistory.isNotEmpty) {
      buffer.writeln('页面访问序列: ${pageHistory.map((p) => p['page']).join(' -> ')}');
    }

    final errorEvents = huatuoAnalysis['error_events'] as List? ?? [];
    if (errorEvents.isNotEmpty) {
      buffer.writeln('关键错误事件（最多 5 个）:');
      for (final evt in errorEvents.take(5)) {
        buffer.writeln('  - [${evt['date']}] ${evt['eventid']}: ${evt['message']}');
      }
    }

    final httpRequests = huatuoAnalysis['http_requests'] as List? ?? [];
    if (httpRequests.isNotEmpty) {
      buffer.writeln('HTTP 请求（最多 3 个）:');
      for (final req in httpRequests.take(3)) {
        buffer.writeln('  - ${req['logtype']}: ${req['url']}');
      }
    }

    buffer.writeln('');
    buffer.writeln('【分析要求】');
    buffer.writeln('请分析上述信息，输出以下 JSON 格式的结果:');
    buffer.writeln('{');
    buffer.writeln('  "summary": "崩溃原因摘要（一句话）",');
    buffer.writeln('  "possible_causes": [');
    buffer.writeln('    {');
    buffer.writeln('      "cause": "原因名称",');
    buffer.writeln('      "detail": "详细说明（2-3 句话）",');
    buffer.writeln('      "evidence": ["证据1", "证据2"]');
    buffer.writeln('    }');
    buffer.writeln('  ],');
    buffer.writeln('  "fix_suggestions": [');
    buffer.writeln('    {');
    buffer.writeln('      "suggestion": "修复建议",');
    buffer.writeln('      "priority": "high|medium|low",');
    buffer.writeln('      "implementation": "实现方式（简要说明）"');
    buffer.writeln('    }');
    buffer.writeln('  ]');
    buffer.writeln('}');
    buffer.writeln('');
    buffer.writeln('请只返回 JSON，不要包含其他文本。');

    return buffer.toString();
  }

  /// 解析 LLM 响应的根因分析结果
  Map<String, dynamic> _parseRootCauseAnalysis(String response) {
    try {
      // 查找 JSON 块
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch == null) {
        throw Exception('未找到 JSON 数据');
      }

      final jsonStr = jsonMatch.group(0)!;
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      return {
        'summary': data['summary'] ?? '分析进行中',
        'possible_causes': (data['possible_causes'] as List? ?? [])
            .map((c) => {
              'cause': c['cause'] ?? '',
              'detail': c['detail'] ?? '',
              'evidence': (c['evidence'] as List? ?? []).cast<String>(),
            })
            .toList(),
        'fix_suggestions': (data['fix_suggestions'] as List? ?? [])
            .map((s) => {
              'suggestion': s['suggestion'] ?? '',
              'priority': s['priority'] ?? 'medium',
              'implementation': s['implementation'] ?? '',
            })
            .toList(),
      };
    } catch (e) {
      debugPrint('[LLM] 解析响应失败: $e');
      return _getDefaultAnalysis();
    }
  }

  /// 获取默认的根因分析（当 LLM 调用失败时）
  Map<String, dynamic> _getDefaultAnalysis() {
    return {
      'summary': '应用在处理用户操作时发生了异常。',
      'possible_causes': [
        {
          'cause': '资源不足或内存压力',
          'detail': '设备在处理当前操作时可能面临内存或其他系统资源压力。',
          'evidence': ['日志中观察到多个错误事件', '页面加载较慢'],
        },
        {
          'cause': '第三方库或系统 API 兼容性问题',
          'detail': '使用的第三方库可能在特定 Android 版本或设备上存在兼容性问题。',
          'evidence': ['堆栈涉及第三方库', '特定设备型号的重现率较高'],
        },
      ],
      'fix_suggestions': [
        {
          'suggestion': '检查内存泄漏和资源释放',
          'priority': 'high',
          'implementation': '使用 Android Profiler 分析内存使用，确保在 Activity/Fragment 销毁时释放资源。',
        },
        {
          'suggestion': '更新依赖库版本',
          'priority': 'medium',
          'implementation': '更新相关的第三方库到最新稳定版本，检查更新日志中的已知问题修复。',
        },
      ],
    };
  }
}
