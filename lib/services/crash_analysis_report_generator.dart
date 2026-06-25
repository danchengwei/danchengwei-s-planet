import 'package:flutter/foundation.dart';
import '../models/tool_config.dart';
import 'aliyun_cli_service.dart';
import 'llm_analyzer.dart';

/// 崩溃分析报告生成服务
///
/// 功能：将单个问题的详细数据生成完整的 Markdown 分析报告
/// 包括：问题统计、系统版本分布、堆栈分析、源码分析、LLM 智能分析等
class CrashAnalysisReportGenerator {
  CrashAnalysisReportGenerator({required this.config}) {
    _cliService = AliyunCliService(config: config);
    _llmAnalyzer = LlmAnalyzer(config: config);
  }

  final ToolConfig config;
  late AliyunCliService _cliService;
  late LlmAnalyzer _llmAnalyzer;

  /// 根据问题详情和堆栈信息生成完整的分析报告
  Future<String> generateReportForIssue({
    required String digestHash,
    required String title,
    required String stackInfo,
    required Map<String, dynamic> issueDetail,
    required Map<String, dynamic> userSample,
    required Map<String, dynamic> huatuoAnalysis,
  }) async {
    final buffer = StringBuffer();

    // 提取基本信息
    final errorCount = issueDetail['ErrorCount'] as int? ?? 0;
    final errorDeviceCount = issueDetail['ErrorDeviceCount'] as int? ?? 0;
    final errorRate = issueDetail['ErrorRate'] as double? ?? 0.0;
    final firstVersion = issueDetail['FirstVersion'] as String? ?? '-';
    final errorName = issueDetail['Name'] as String? ?? title;

    // 标题
    buffer.writeln('## 📑 崩溃分析报告');
    buffer.writeln();

    // 卡片式信息
    buffer.writeln('> **崩溃分析报告**');
    buffer.writeln('> - **Hash**: `$digestHash`');
    buffer.writeln('> - **崩溃类型**: $errorName');
    buffer.writeln('> - **崩溃次数**: $errorCount');
    buffer.writeln('> - **影响设备**: $errorDeviceCount');
    buffer.writeln('> - **错误率**: ${(errorRate * 100).toStringAsFixed(3)}%');
    buffer.writeln('> - **首现版本**: $firstVersion');
    buffer.writeln();

    // 系统版本分布分析
    _addVersionDistributionAnalysis(buffer, issueDetail);

    // 机型分布分析
    _addDeviceDistributionAnalysis(buffer, issueDetail);

    // 详细堆栈信息
    _addDetailedStackInfo(buffer, stackInfo, errorName);

    // 堆栈分析
    _addStackAnalysis(buffer, stackInfo);

    // 源码分析
    _addSourceCodeAnalysis(buffer, stackInfo);

    // LLM 智能分析
    await _addLlmAnalysis(
      buffer,
      digestHash,
      errorName,
      stackInfo,
      huatuoAnalysis,
      userSample,
    );

    return buffer.toString();
  }

  /// 添加系统版本分布分析
  void _addVersionDistributionAnalysis(StringBuffer buffer, Map<String, dynamic> issueDetail) {
    buffer.writeln('### 📱 系统版本分布分析');
    buffer.writeln('| 系统版本 | 崩溃次数 | 占比 |');
    buffer.writeln('|---------|---------|------|');

    // 从 issueDetail 中提取版本分布信息
    final versionInfo = issueDetail['VersionInfos'] as List<dynamic>? ?? [];
    if (versionInfo.isNotEmpty) {
      int totalCount = 0;
      for (final ver in versionInfo) {
        totalCount += (ver as Map<String, dynamic>)['Count'] as int? ?? 0;
      }

      for (final ver in versionInfo) {
        final verMap = ver as Map<String, dynamic>;
        final version = verMap['Version'] as String? ?? 'Unknown';
        final count = verMap['Count'] as int? ?? 0;
        final percentage = totalCount > 0 ? ((count / totalCount) * 100).toStringAsFixed(2) : '0.00';
        buffer.writeln('| $version | $count | $percentage% |');
      }
    } else {
      buffer.writeln('| 数据不足 | - | - |');
    }
    buffer.writeln();
  }

  /// 添加机型分布分析
  void _addDeviceDistributionAnalysis(StringBuffer buffer, Map<String, dynamic> issueDetail) {
    buffer.writeln('### 📱 机型分布分析');
    buffer.writeln('| 机型 | 崩溃次数 | 占比 |');
    buffer.writeln('|------|---------|------|');

    // 从 issueDetail 中提取机型分布信息
    final deviceInfo = issueDetail['DeviceInfos'] as List<dynamic>? ?? [];
    if (deviceInfo.isNotEmpty) {
      int totalCount = 0;
      for (final dev in deviceInfo) {
        totalCount += (dev as Map<String, dynamic>)['Count'] as int? ?? 0;
      }

      // 只显示前 5 个机型
      for (int i = 0; i < deviceInfo.length && i < 5; i++) {
        final devMap = deviceInfo[i] as Map<String, dynamic>;
        final deviceModel = devMap['DeviceModel'] as String? ?? 'Unknown';
        final count = devMap['Count'] as int? ?? 0;
        final percentage = totalCount > 0 ? ((count / totalCount) * 100).toStringAsFixed(2) : '0.00';
        buffer.writeln('| $deviceModel | $count | $percentage% |');
      }

      if (deviceInfo.length > 5) {
        buffer.writeln('| 其他 | ${deviceInfo.skip(5).fold(0, (sum, dev) => sum + ((dev as Map<String, dynamic>)['Count'] as int? ?? 0))} | ... |');
      }
    } else {
      buffer.writeln('| 数据不足 | - | - |');
    }
    buffer.writeln();
  }

  /// 添加详细堆栈信息
  void _addDetailedStackInfo(StringBuffer buffer, String stackInfo, String errorName) {
    buffer.writeln('### 📋 详细堆栈信息');
    buffer.writeln('> **崩溃类型**: `Unknown`');
    buffer.writeln('> **错误名称**: $errorName');
    buffer.writeln('>');
    buffer.writeln('> **堆栈信息**');

    // 解析堆栈信息
    final stackLines = stackInfo.split('\n');
    for (final line in stackLines.take(20)) {
      if (line.isNotEmpty) {
        buffer.writeln('> $line');
      }
    }

    if (stackLines.length > 20) {
      buffer.writeln('> ... 还有 ${stackLines.length - 20} 行 ...');
    }
    buffer.writeln();
  }

  /// 添加堆栈分析
  void _addStackAnalysis(StringBuffer buffer, String stackInfo) {
    buffer.writeln('### 📍 堆栈分析');
    buffer.writeln('#### 📊 堆栈类型分析');

    final stackLines = stackInfo.split('\n').where((line) => line.isNotEmpty).toList();
    final javaClasses = stackLines.where((line) => line.contains('com.xueersi') || line.contains('android.')).toList();

    buffer.writeln('- 崩溃类型: **Java崩溃**');
    buffer.writeln('- 堆栈行数: ${stackLines.length} 行');
    buffer.writeln();

    buffer.writeln('#### 🔍 关键帧分析');
    buffer.writeln();

    buffer.writeln('##### ☕ 涉及的Java类:');
    final uniqueClasses = <String>{};
    for (final line in javaClasses.take(10)) {
      final match = RegExp(r'at ([a-z0-9.]+)').firstMatch(line);
      if (match != null) {
        uniqueClasses.add(match.group(1) ?? '');
      }
    }

    for (final cls in uniqueClasses) {
      if (cls.isNotEmpty) {
        buffer.writeln('- $cls');
      }
    }

    if (javaClasses.length > 10) {
      buffer.writeln('- ... 还有 ${javaClasses.length - 10} 个类...');
    }

    buffer.writeln();

    // 应用代码位置
    buffer.writeln('#### 🏠 应用代码位置');
    final appCodeLine = javaClasses.firstWhere(
      (line) => line.contains('com.xueersi'),
      orElse: () => '',
    );

    if (appCodeLine.isNotEmpty) {
      final match = RegExp(r'at ([a-z0-9.]+)\.(\w+)\(([^)]+)\)').firstMatch(appCodeLine);
      if (match != null) {
        buffer.writeln('- 类: ${match.group(1)}');
        buffer.writeln('- 方法: ${match.group(2)}');
        final fileInfo = match.group(3) ?? 'Unknown';
        buffer.writeln('- 文件: $fileInfo');
      }
    }
    buffer.writeln();
  }

  /// 添加源码分析
  void _addSourceCodeAnalysis(StringBuffer buffer, String stackInfo) {
    buffer.writeln('### 🔎 源码分析');

    // 提取源文件信息
    final fileMatch = RegExp(r'\(([^)]+\.java):(\d+)\)').firstMatch(stackInfo);
    if (fileMatch != null) {
      final fileName = fileMatch.group(1) ?? 'Unknown';
      final lineNum = fileMatch.group(2) ?? '0';
      buffer.writeln('- 📄 文件: $fileName');
      buffer.writeln();

      buffer.writeln('#### 代码片段');
      buffer.writeln('```java');
      buffer.writeln('// 代码片段（第 $lineNum 行）');
      buffer.writeln('// 需要在源码目录中查看具体代码');
      buffer.writeln('```');
      buffer.writeln();

      buffer.writeln('#### 👥 代码贡献者统计');
      buffer.writeln('- 暂无 Git 信息');
      buffer.writeln();
    }
  }

  /// 添加 LLM 智能分析
  Future<void> _addLlmAnalysis(
    StringBuffer buffer,
    String digestHash,
    String crashTitle,
    String stackInfo,
    Map<String, dynamic> huatuoAnalysis,
    Map<String, dynamic> userSample,
  ) async {
    buffer.writeln('### 💡 原因分析');

    try {
      final llmAnalysis = await _llmAnalyzer.generateRootCauseAnalysis(
        digestHash: digestHash,
        crashTitle: crashTitle,
        stackInfo: stackInfo,
        huatuoAnalysis: huatuoAnalysis,
        userSample: userSample,
      );

      if (llmAnalysis.isNotEmpty) {
        // 分析摘要
        final summary = llmAnalysis['summary'] as String? ?? '';
        if (summary.isNotEmpty) {
          buffer.writeln(summary);
          buffer.writeln();
        }

        // 可能原因
        final possibleCauses = llmAnalysis['possible_causes'] as List<dynamic>? ?? [];
        if (possibleCauses.isNotEmpty) {
          buffer.writeln('### 🛠️ 修改建议');
          buffer.writeln();
          for (int i = 0; i < possibleCauses.length; i++) {
            final cause = possibleCauses[i] as Map<String, dynamic>?;
            if (cause != null) {
              final causeTitle = cause['cause'] as String? ?? '';
              final detail = cause['detail'] as String? ?? '';
              buffer.writeln('${i + 1}. **$causeTitle**');
              if (detail.isNotEmpty) {
                buffer.writeln('   $detail');
              }
            }
          }
          buffer.writeln();
        }

        // 修复代码示例
        final fixCode = llmAnalysis['fix_code'] as String?;
        if (fixCode != null && fixCode.isNotEmpty) {
          buffer.writeln('### 📝 代码示例');
          buffer.writeln('```java');
          buffer.writeln(fixCode);
          buffer.writeln('```');
          buffer.writeln();
        }
      } else {
        buffer.writeln('暂无智能分析结果，请查看堆栈信息进行手动分析。');
        buffer.writeln();
      }
    } catch (e) {
      debugPrint('LLM 分析失败: $e');
      buffer.writeln('LLM 分析失败，请检查配置。');
      buffer.writeln();
    }
  }
}
