import 'dart:io';
import 'stack_parser.dart';
import 'distribution_analyzer.dart';
import 'git_analyzer.dart';
import 'llm_client.dart';
import 'package:http/http.dart' as http;

/// 完整的分析报告
class AnalysisReport {
  AnalysisReport({
    required this.digestHash,
    required this.issueType,
    required this.stackInfo,
    required this.distribution,
    required this.sourceCode,
    required this.contributors,
    required this.analysisText,
    required this.createdAt,
  });

  final String digestHash;
  final String issueType;
  final StructuredStackInfo stackInfo;
  final DistributionAnalysis distribution;
  final Map<String, String> sourceCode;      // 文件名 → 代码片段
  final Map<String, List<GitContributor>> contributors;  // 文件名 → 贡献者列表
  final String analysisText;                  // LLM 生成的分析
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'digestHash': digestHash,
        'issueType': issueType,
        'stackInfo': stackInfo.toJson(),
        'distribution': distribution.toJson(),
        'sourceCodeFiles': sourceCode.keys.toList(),
        'analysisText': analysisText,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// EMAS 智能分析器 - 统一入口
class EmasIntelligentAnalyzer {
  EmasIntelligentAnalyzer({
    required this.projectPath,
    required this.llmBaseUrl,
    required this.llmApiKey,
    required this.llmModel,
    required this.llmChatCompletionsPath,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final String projectPath;
  final String llmBaseUrl;
  final String llmApiKey;
  final String llmModel;
  final String llmChatCompletionsPath;
  final http.Client _httpClient;

  /// 完整分析流程
  /// Step 1: 解析堆栈 → Step 2: 查找源码 → Step 3: Git分析 → Step 4: 分布分析 → Step 5: LLM分析
  Future<AnalysisReport> analyze({
    required String digestHash,
    required Map<String, dynamic> issueData,
    required String bizModule,
  }) async {
    try {
      final stackTrace = issueData['Stack']?.toString() ?? '';
      final issueType = issueData['Name']?.toString() ?? 'Unknown';

      // Step 1: 解析堆栈
      final stackInfo = StackParser.parse(stackTrace);

      // 提取文件列表
      final fileNames = StackParser.extractFileNames(stackTrace);

      // Step 2: 查找本地源码
      final sourceCode = await _findSourceCode(fileNames);

      // Step 3: Git 分析（获取代码贡献者）
      final contributors = await _analyzeGit(fileNames);

      // Step 4: 分布分析
      final distribution = DistributionAnalyzer.analyze(issueData: issueData);

      // Step 5: LLM 分析
      final analysisText = await _callLlmAnalysis(
        stackInfo: stackInfo,
        sourceCode: sourceCode,
        distribution: distribution,
        bizModule: bizModule,
        issueType: issueType,
      );

      return AnalysisReport(
        digestHash: digestHash,
        issueType: issueType,
        stackInfo: stackInfo,
        distribution: distribution,
        sourceCode: sourceCode,
        contributors: contributors,
        analysisText: analysisText,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Step 2: 查找本地源码
  Future<Map<String, String>> _findSourceCode(List<String> fileNames) async {
    final sourceMap = <String, String>{};

    for (final fileName in fileNames) {
      try {
        final file = await _searchFile(projectPath, fileName);
        if (file != null && file.existsSync()) {
          final content = await file.readAsString();
          sourceMap[fileName] = content;
        }
      } catch (e) {
        // 跳过找不到的文件
      }
    }

    return sourceMap;
  }

  /// 递归搜索文件（最多 3 层深）
  Future<File?> _searchFile(String dirPath, String fileName, {int depth = 0}) async {
    if (depth > 3) return null;

    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return null;

      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith(fileName)) {
          return entity;
        }
        if (entity is Directory &&
            !entity.path.contains('.git') &&
            !entity.path.contains('build') &&
            !entity.path.contains('.dart_tool')) {
          final found = await _searchFile(entity.path, fileName, depth: depth + 1);
          if (found != null) return found;
        }
      }
    } catch (e) {
      // 忽略权限错误
    }

    return null;
  }

  /// Step 3: Git 分析
  Future<Map<String, List<GitContributor>>> _analyzeGit(List<String> fileNames) async {
    final result = <String, List<GitContributor>>{};
    final gitAnalyzer = GitAnalyzer(workingDirectory: projectPath);

    for (final fileName in fileNames.take(5)) {  // 最多分析 5 个文件
      try {
        final contributors = await gitAnalyzer.getFileContributors(fileName, limit: 3);
        if (contributors.isNotEmpty) {
          result[fileName] = contributors;
        }
      } catch (e) {
        // 跳过错误
      }
    }

    return result;
  }

  /// Step 5: LLM 分析
  Future<String> _callLlmAnalysis({
    required StructuredStackInfo stackInfo,
    required Map<String, String> sourceCode,
    required DistributionAnalysis distribution,
    required String bizModule,
    required String issueType,
  }) async {
    try {
      final llmClient = LlmClient(
        baseUrl: llmBaseUrl,
        apiKey: llmApiKey,
        model: llmModel,
        chatCompletionsPath: llmChatCompletionsPath,
        httpClient: _httpClient,
      );

      final systemPrompt = _buildSystemPrompt(bizModule);
      final userPrompt = _buildUserPrompt(
        stackInfo: stackInfo,
        sourceCode: sourceCode,
        distribution: distribution,
        issueType: issueType,
        bizModule: bizModule,
      );

      final response = await llmClient.chat(
        [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        temperature: 0.3,
      );

      return response;
    } catch (e) {
      return _generateDefaultAnalysis(stackInfo, distribution);
    }
  }

  /// 构建系统提示词
  String _buildSystemPrompt(String bizModule) {
    final crashType = bizModule == 'crash' ? '崩溃' : 'ANR';
    return '''你是资深移动端$crashType分析工程师，擅长 Android/iOS 原生与跨端栈。回答使用简体中文。

若用户消息中的【分析要求】说明堆栈主要为系统/框架、无法定位业务源文件，则禁止编造具体业务源文件路径；改为给出排查方向、配置与容错类修改思路。

请严格按下面 Markdown 结构输出（二级标题必须保留且字面一致，便于界面分块展示；小节内可用列表、代码块）：

## 原因
（现象、堆栈指向、可疑根因与置信度）

## 分析
（结合业务/系统栈的进一步解读、关联模块、排查优先级）

## 如何处理
（分步骤的修复方案；文件/类/方法级修改思路与示例或伪代码；配置与发布策略；最后简述如何验证已修复、日志与监控要点）''';
  }

  /// 构建用户提示词
  String _buildUserPrompt({
    required StructuredStackInfo stackInfo,
    required Map<String, String> sourceCode,
    required DistributionAnalysis distribution,
    required String issueType,
    required String bizModule,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('【问题信息】');
    buffer.writeln('- 类型: $issueType');
    buffer.writeln('- 崩溃类型: ${stackInfo.crashType}');
    buffer.writeln('- 异常名称: ${stackInfo.exceptionName ?? "未知"}');
    buffer.writeln('- 堆栈行数: ${stackInfo.lineCount}');
    buffer.writeln();

    // 堆栈跟踪
    buffer.writeln('【堆栈跟踪】');
    buffer.writeln('```');
    buffer.writeln(stackInfo.rawStack.substring(0, stackInfo.rawStack.length > 1000 ? 1000 : stackInfo.rawStack.length));
    if (stackInfo.rawStack.length > 1000) {
      buffer.writeln('...(已截断)');
    }
    buffer.writeln('```');
    buffer.writeln();

    // 应用代码位置
    if (stackInfo.applicationCodeLocation != null) {
      buffer.writeln('【应用代码位置】');
      final loc = stackInfo.applicationCodeLocation!;
      buffer.writeln('- 类: ${loc.className}');
      buffer.writeln('- 方法: ${loc.methodName}');
      buffer.writeln('- 文件: ${loc.fileName}');
      buffer.writeln('- 行号: ${loc.lineNumber}');
      buffer.writeln();
    }

    // Java 类
    if (stackInfo.javaClasses.isNotEmpty) {
      buffer.writeln('【涉及的 Java 类】');
      for (final cls in stackInfo.javaClasses.take(10)) {
        buffer.writeln('- $cls');
      }
      buffer.writeln();
    }

    // 源码片段
    if (sourceCode.isNotEmpty) {
      buffer.writeln('【源码分析】');
      sourceCode.forEach((fileName, content) {
        buffer.writeln('**文件**: $fileName');
        buffer.writeln('```java');
        buffer.writeln(content.substring(0, content.length > 500 ? 500 : content.length));
        if (content.length > 500) buffer.writeln('...(已截断)');
        buffer.writeln('```');
      });
      buffer.writeln();
    }

    // 分布分析
    if (distribution.totalCount > 0) {
      buffer.writeln('【分布分析】');
      buffer.writeln('- 总崩溃数: ${distribution.totalCount}');
      if (distribution.versions.isNotEmpty) {
        buffer.write('- 主要版本: ');
        buffer.write(distribution.versions.take(3).map((v) => '${v.version}(${v.count})').join(', '));
        buffer.writeln();
      }
      if (distribution.osVersions.isNotEmpty) {
        buffer.write('- 主要系统: ');
        buffer.write(distribution.osVersions.take(3).map((v) => '${v.osVersion}(${v.count})').join(', '));
        buffer.writeln();
      }
      buffer.writeln();
    }

    buffer.writeln('【分析要求】');
    buffer.writeln('根据上述信息，生成完整的$bizModule分析报告。');

    return buffer.toString();
  }

  /// 生成默认分析（LLM 调用失败时）
  String _generateDefaultAnalysis(
    StructuredStackInfo stackInfo,
    DistributionAnalysis distribution,
  ) {
    return '''## 原因
基于堆栈跟踪分析，该问题由 ${stackInfo.crashType == 'Java' ? 'Java 异常' : '系统级崩溃'}导致。
堆栈指向在 ${stackInfo.applicationCodeLocation?.className ?? '系统框架'} 的 ${stackInfo.applicationCodeLocation?.methodName ?? '方法'}中发生。

## 分析
1. **直接原因**：堆栈显示 ${stackInfo.exceptionName ?? '异常未明确标识'}
2. **影响范围**：共 ${distribution.totalCount} 次崩溃
3. **重点版本**：${distribution.versions.isNotEmpty ? distribution.versions.first.version : '需进一步分析'}

## 如何处理
### 修复步骤
1. 查看堆栈指向的具体方法（第 ${stackInfo.applicationCodeLocation?.lineNumber ?? '?'} 行）
2. 分析该方法的调用链和上下文
3. 根据异常类型采取相应措施

### 验证方案
- 在相同条件下复现问题
- 修改后重新测试
- 观察崩溃率变化''';
  }
}
