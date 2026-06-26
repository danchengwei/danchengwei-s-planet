/// Agent 工具执行器。
///
/// 实现 Agent 可调用的所有工具（获取 issue 详情、搜索源码、Git blame 等）。

import '../models/tool_config.dart';
import 'ai_source_code_analyzer.dart';
import 'stack_parser.dart';

/// 工具执行错误
class ToolExecutionException implements Exception {
  ToolExecutionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Agent 工具执行器
class AgentToolExecutor {
  AgentToolExecutor({
    required this.config,
    required this.emasClient,
    required this.sourceCodeAnalyzer,
  }) : _stackParser = StackParser();

  final ToolConfig config;
  final dynamic emasClient;
  final AiSourceCodeAnalyzer sourceCodeAnalyzer;
  final StackParser _stackParser;

  /// 执行工具
  Future<String> executeTool(String toolName, Map<String, dynamic> params) async {
    try {
      switch (toolName) {
        case 'get_issue_details':
          return await _getIssueDetails(params);
        case 'get_issue_stack_samples':
          return await _getIssueStackSamples(params);
        case 'search_source_code':
          return await _searchSourceCode(params);
        case 'get_git_blame':
          return await _getGitBlame(params);
        case 'search_gitlab_issues':
          return await _searchGitlabIssues(params);
        case 'get_package_versions':
          return await _getPackageVersions(params);
        case 'analyze_stack_trace':
          return await _analyzeStackTrace(params);
        case 'search_similar_crashes':
          return await _searchSimilarCrashes(params);
        default:
          throw ToolExecutionException('未知工具: $toolName');
      }
    } catch (e) {
      throw ToolExecutionException('工具执行失败 [$toolName]: $e');
    }
  }

  /// 获取 EMAS issue 详情
  Future<String> _getIssueDetails(Map<String, dynamic> params) async {
    final digestHash = params['digestHash'] as String?;
    final appKey = params['appKey'] as String?;

    if (digestHash == null || digestHash.isEmpty) {
      throw ToolExecutionException('缺少必需参数: digestHash');
    }

    // 调用 EMAS 客户端
    final result = await emasClient.getIssue(
      digestHash: digestHash,
      appKey: appKey ?? config.appKey,
    );

    if (result == null) {
      return '未找到该 issue (digestHash=$digestHash)';
    }

    // 整理返回结果
    final sb = StringBuffer();
    sb.writeln('**Issue 详情**\n');

    final data = result;
    if (data is Map) {
      sb.writeln('- **错误类型**: ${data['ErrorType'] ?? 'N/A'}');
      sb.writeln('- **错误名**: ${data['ErrorName'] ?? 'N/A'}');
      sb.writeln('- **影响设备**: ${data['AffectedDeviceCount'] ?? 0}');
      sb.writeln('- **错误率**: ${data['ErrorRate'] ?? 'N/A'}');
      sb.writeln('- **首现版本**: ${data['FirstVersion'] ?? 'N/A'}');

      // 版本分布
      if (data['VersionDistribution'] is List) {
        sb.writeln('\n**版本分布**:');
        for (final v in (data['VersionDistribution'] as List).take(5)) {
          sb.writeln('  - ${v['Version']}: ${v['Count']} 次');
        }
      }

      // 机型分布
      if (data['DeviceDistribution'] is List) {
        sb.writeln('\n**机型分布**:');
        for (final d in (data['DeviceDistribution'] as List).take(5)) {
          sb.writeln('  - ${d['Model']}: ${d['Count']} 次');
        }
      }
    }

    return sb.toString();
  }

  /// 获取 issue 的样本堆栈
  Future<String> _getIssueStackSamples(Map<String, dynamic> params) async {
    final digestHash = params['digestHash'] as String?;
    final limit = (params['limit'] as num?)?.toInt() ?? 5;

    if (digestHash == null || digestHash.isEmpty) {
      throw ToolExecutionException('缺少必需参数: digestHash');
    }

    // 获取错误样本
    final errors = await emasClient.getErrors(
      digestHash: digestHash,
      appKey: config.appKey,
      limit: limit,
    );

    if (errors.isEmpty) {
      return '未找到该 issue 的错误样本';
    }

    final sb = StringBuffer();
    sb.writeln('**$limit 个样本堆栈**\n');

    for (int i = 0; i < errors.length; i++) {
      final err = errors[i];
      sb.writeln('### 样本 ${i + 1}\n');

      if (err is Map) {
        sb.writeln('**设备**: ${err['DeviceModel'] ?? 'N/A'}');
        sb.writeln('**系统版本**: ${err['OsVersion'] ?? 'N/A'}');
        sb.writeln('**应用版本**: ${err['AppVersion'] ?? 'N/A'}');

        final stackTrace = err['StackTrace'] ?? err['Stack'] ?? '';
        if (stackTrace.isNotEmpty) {
          sb.writeln('\n**堆栈**:\n```\n$stackTrace\n```\n');
        }
      }
    }

    return sb.toString();
  }

  /// 搜索源码
  Future<String> _searchSourceCode(Map<String, dynamic> params) async {
    final query = params['query'] as String?;

    if (query == null || query.isEmpty) {
      throw ToolExecutionException('缺少必需参数: query');
    }

    if (config.localProjectPath.isEmpty) {
      return '未配置项目本地路径，无法搜索源码';
    }

    try {
      final sb = StringBuffer();
      sb.writeln('**源码搜索** (查询: $query)\n');
      sb.writeln('(源码搜索功能正在开发中，暂时返回占位结果)');

      return sb.toString();
    } catch (e) {
      return '源码搜索失败: $e';
    }
  }

  /// 获取 Git Blame
  Future<String> _getGitBlame(Map<String, dynamic> params) async {
    final filePath = params['filePath'] as String?;
    final lineNumber = params['lineNumber'] as int?;

    if (filePath == null || lineNumber == null) {
      throw ToolExecutionException('缺少必需参数: filePath, lineNumber');
    }

    if (config.localProjectPath.isEmpty) {
      return '未配置项目本地路径，无法获取 Git Blame';
    }

    try {
      // 这里可以调用 git blame 命令
      // 目前简单返回提示
      return '**Git Blame 信息**\n\n文件: $filePath\n行号: $lineNumber\n\n'
          '(需要本地 Git 仓库支持，当前仅提供占位)';
    } catch (e) {
      return 'Git Blame 获取失败: $e';
    }
  }

  /// 搜索 Git 提交历史和代码
  Future<String> _searchGitlabIssues(Map<String, dynamic> params) async {
    final query = params['query'] as String?;

    if (query == null || query.isEmpty) {
      throw ToolExecutionException('缺少必需参数: query');
    }

    if (config.localProjectPath.isEmpty) {
      return '未配置项目路径，无法搜索 Git 历史';
    }

    try {
      final sb = StringBuffer();
      sb.writeln('**Git 历史搜索** (查询: $query)\n');

      // 搜索包含该关键词的提交信息
      sb.writeln('**相关提交** (使用: git log --grep="$query"):');
      sb.writeln('(需要调用本地 git 命令来搜索提交历史)');

      return sb.toString();
    } catch (e) {
      return 'Git 搜索失败: $e';
    }
  }

  /// 获取包版本信息
  Future<String> _getPackageVersions(Map<String, dynamic> params) async {
    final packageNames = params['packageNames'] as List?;

    if (packageNames == null || packageNames.isEmpty) {
      throw ToolExecutionException('缺少必需参数: packageNames');
    }

    if (config.localProjectPath.isEmpty) {
      return '未配置项目本地路径，无法获取依赖版本';
    }

    try {
      // 读取 pubspec.yaml 或 build.gradle 等
      final sb = StringBuffer();
      sb.writeln('**依赖版本信息**\n');

      for (final pkg in packageNames) {
        sb.writeln('- $pkg: (查询中...)');
      }

      return sb.toString();
    } catch (e) {
      return '依赖版本获取失败: $e';
    }
  }

  /// 分析堆栈轨迹
  Future<String> _analyzeStackTrace(Map<String, dynamic> params) async {
    final stackTrace = params['stackTrace'] as String?;

    if (stackTrace == null || stackTrace.isEmpty) {
      throw ToolExecutionException('缺少必需参数: stackTrace');
    }

    try {
      final sb = StringBuffer();
      sb.writeln('**堆栈分析**\n');

      final lines = stackTrace.split('\n');
      sb.writeln('**总行数**: ${lines.length}\n');

      // 提取关键信息
      final keyFrames = lines
          .where((line) => line.trim().isNotEmpty)
          .take(10)
          .toList();

      if (keyFrames.isNotEmpty) {
        sb.writeln('**关键帧** (前 10):');
        for (int i = 0; i < keyFrames.length; i++) {
          sb.writeln('  ${i + 1}. ${keyFrames[i]}');
        }
      }

      return sb.toString();
    } catch (e) {
      return '堆栈分析失败: $e';
    }
  }

  /// 搜索类似崩溃
  Future<String> _searchSimilarCrashes(Map<String, dynamic> params) async {
    final errorType = params['errorType'] as String?;
    final errorMessage = params['errorMessage'] as String?;
    final methodName = params['methodName'] as String?;

    if (errorType == null || errorType.isEmpty) {
      throw ToolExecutionException('缺少必需参数: errorType');
    }

    try {
      final sb = StringBuffer();
      sb.writeln('**相似崩溃搜索**\n');
      sb.writeln('- **错误类型**: $errorType');
      if (errorMessage != null) {
        sb.writeln('- **错误信息**: $errorMessage');
      }
      if (methodName != null) {
        sb.writeln('- **方法**: $methodName');
      }
      sb.writeln('\n(搜索相似崩溃中...)');

      return sb.toString();
    } catch (e) {
      return '相似崩溃搜索失败: $e';
    }
  }
}
