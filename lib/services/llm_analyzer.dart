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
      // 检查 LLM 配置是否完整
      if (config.llmBaseUrl.trim().isEmpty ||
          config.llmApiKey.trim().isEmpty ||
          config.llmModel.trim().isEmpty) {
        debugPrint('[LLM] LLM 未配置，使用默认分析');
        return _getDefaultAnalysis();
      }

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

    buffer.writeln('你是一个 Android 应用崩溃分析专家。请根据以下完整的崩溃信息和实时日志数据进行深入的根因分析。');
    buffer.writeln('');

    // 1. 崩溃堆栈信息
    buffer.writeln('## 1. 崩溃堆栈');
    buffer.writeln(stackInfo);
    buffer.writeln('');

    // 2. 设备和应用信息
    buffer.writeln('## 2. 设备和应用信息');
    buffer.writeln('- 用户 ID: ${userSample['user_id'] ?? ''}');
    buffer.writeln('- 设备型号: ${userSample['device_model'] ?? ''}');
    buffer.writeln('- 应用版本: ${userSample['app_version'] ?? ''}');
    buffer.writeln('- 系统版本: ${userSample['system_version'] ?? ''}');
    buffer.writeln('- 启动时间: ${userSample['startup_time'] ?? ''}');
    buffer.writeln('');

    // 3. API 原始日志数据（来自华佗 API）
    buffer.writeln('## 3. API 原始日志数据（华佗平台）');
    final dataItems = huatuoAnalysis['data_items'] as List<dynamic>? ?? [];
    if (dataItems.isNotEmpty) {
      for (int i = 0; i < dataItems.take(20).length; i++) {
        final item = dataItems[i] as Map<String, dynamic>?;
        if (item != null) {
          buffer.writeln('日志 ${i + 1}: ${jsonEncode(item)}');
        }
      }
    } else {
      buffer.writeln('无 API 日志数据');
    }
    buffer.writeln('');

    // 4. 解压后的日志文件内容（关键日志）
    buffer.writeln('## 4. 解压后的关键日志文件');
    final extractedLogs = huatuoAnalysis['extracted_logs'] as Map<String, dynamic>? ?? {};
    final extractedFiles = extractedLogs['extracted_files'] as List<dynamic>? ?? [];
    final fileContents = extractedLogs['file_contents'] as Map<String, dynamic>? ?? {};

    if (extractedFiles.isNotEmpty) {
      buffer.writeln('提取的文件列表 (${extractedFiles.length} 个):');
      for (final fileName in extractedFiles) {
        buffer.writeln('- $fileName');
      }
      buffer.writeln('');

      buffer.writeln('关键日志内容:');
      for (final fileName in extractedFiles.take(10)) {
        final content = fileContents[fileName] as String?;
        if (content != null && content.isNotEmpty) {
          buffer.writeln('');
          buffer.writeln('### 文件: $fileName');
          buffer.writeln('```');
          // 限制每个文件显示的内容长度
          final displayContent = content.length > 2000 ? '${content.substring(0, 2000)}\n...[已截断]' : content;
          buffer.writeln(displayContent);
          buffer.writeln('```');
        }
      }
    } else {
      buffer.writeln('无解压后的日志文件');
    }
    buffer.writeln('');

    // 5. 分析指导
    buffer.writeln('## 5. 分析要求');
    buffer.writeln('基于崩溃堆栈、API 日志数据和解压后的日志文件，请进行以下分析:');
    buffer.writeln('1. 根据 Exception 类型和堆栈追踪确定直接崩溃原因');
    buffer.writeln('2. 从 API 日志和解压后的日志文件中寻找触发崩溃的操作序列');
    buffer.writeln('3. 对比两种日志来源，找出不一致的地方或关键事件');
    buffer.writeln('4. 分析是否存在内存/资源泄漏或兼容性问题');
    buffer.writeln('5. 评估问题严重性和影响范围');
    buffer.writeln('6. 提供具体的修复方案和代码级建议');
    buffer.writeln('');

    buffer.writeln('## 6. 输出格式（必须是有效 JSON）');
    buffer.writeln('{');
    buffer.writeln('  "summary": "用一句话总结崩溃原因（要具体，不要宽泛）",');
    buffer.writeln('  "possible_causes": [');
    buffer.writeln('    {');
    buffer.writeln('      "cause": "直接崩溃原因",');
    buffer.writeln('      "detail": "详细解释这个原因如何导致崩溃（3-5 句话，基于堆栈和日志）",');
    buffer.writeln('      "evidence": ["日志中的关键证据1", "堆栈中的关键信息2", "设备特征3"]');
    buffer.writeln('    },');
    buffer.writeln('    {');
    buffer.writeln('      "cause": "根本原因或触发因素",');
    buffer.writeln('      "detail": "为什么会出现这种情况，与用户操作或应用状态的关系",');
    buffer.writeln('      "evidence": ["关键日志数据", "操作序列"]');
    buffer.writeln('    }');
    buffer.writeln('  ],');
    buffer.writeln('  "fix_suggestions": [');
    buffer.writeln('    {');
    buffer.writeln('      "suggestion": "具体的修复方案",');
    buffer.writeln('      "priority": "high|medium|low",');
    buffer.writeln('      "implementation": "代码级或架构级的实现建议（包括具体的类/方法）"');
    buffer.writeln('    }');
    buffer.writeln('  ]');
    buffer.writeln('}');
    buffer.writeln('');
    buffer.writeln('重要：只返回 JSON 对象，不要返回其他文本。');

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
