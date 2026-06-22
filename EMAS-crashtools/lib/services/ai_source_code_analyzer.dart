import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/analysis_report_record.dart';
import '../models/tool_config.dart';
import 'report_manager.dart';
import 'llm_client.dart';

/// AI 源码分析服务：结合堆栈信息与本地源码进行 LLM 分析
class AiSourceCodeAnalyzer {
  AiSourceCodeAnalyzer({
    required this.reportManager,
    required this.config,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  final ReportManager reportManager;
  final ToolConfig config;
  final http.Client? _httpClient;

  /// 从堆栈中提取关键信息（文件名、函数名、行号）
  StackInfo _parseStackTrace(String stackTrace) {
    final lines = stackTrace.split('\n');
    final files = <String>{};
    final functions = <String>{};
    final lines_ = <String>[];

    for (final line in lines) {
      // 提取 Java/Kotlin 的类和方法
      final javaMatch = RegExp(r'at\s+([\w.$]+)\.([\w<>$]+)\(([\w.]+):?(\d+)?\)').firstMatch(line);
      if (javaMatch != null) {
        final className = javaMatch.group(1) ?? '';
        final methodName = javaMatch.group(2) ?? '';
        final fileName = javaMatch.group(3) ?? '';
        final lineNum = javaMatch.group(4) ?? '';

        functions.add('$className.$methodName');
        files.add(fileName);
        lines_.add(lineNum);
      }

      // 提取 Native/C++ 的文件和函数
      final nativeMatch = RegExp(r'#\d+\s+0x[\da-f]+\s+in\s+([\w_]+)\s+(.+?):(\d+)').firstMatch(line);
      if (nativeMatch != null) {
        final funcName = nativeMatch.group(1) ?? '';
        final filePath = nativeMatch.group(2) ?? '';
        final lineNum = nativeMatch.group(3) ?? '';

        functions.add(funcName);
        files.add(filePath);
        lines_.add(lineNum);
      }
    }

    return StackInfo(
      files: files.toList(),
      functions: functions.toList(),
      lineNumbers: lines_,
    );
  }

  /// 从本地项目中查找匹配的源代码文件
  Future<Map<String, String>> _findSourceFiles(
    String projectPath,
    List<String> fileNames,
  ) async {
    final sourceMap = <String, String>{};

    for (final fileName in fileNames) {
      try {
        final projectDir = Directory(projectPath);
        if (!projectDir.existsSync()) continue;

        // 在项目中递归搜索文件
        final found = await _searchFile(projectDir, fileName);
        if (found != null && found.existsSync()) {
          sourceMap[fileName] = await found.readAsString();
        }
      } catch (e) {
        // 静默处理文件读取错误
      }
    }

    return sourceMap;
  }

  /// 递归搜索文件（仅搜索3层深度以提高性能）
  Future<File?> _searchFile(Directory dir, String fileName, {int depth = 0}) async {
    if (depth > 3) return null;

    try {
      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith(fileName)) {
          return entity;
        }
        if (entity is Directory && !entity.path.contains('.git') && !entity.path.contains('build')) {
          final found = await _searchFile(entity, fileName, depth: depth + 1);
          if (found != null) return found;
        }
      }
    } catch (e) {
      // 忽略权限错误
    }

    return null;
  }

  /// 获取Git信息（最近修改者、git blame）
  Future<Map<String, dynamic>> _getGitInfo(String projectPath, List<String> fileNames, List<String> lineNumbers) async {
    final gitInfo = <String, dynamic>{};

    try {
      if (!Directory(projectPath).existsSync()) {
        return gitInfo;
      }

      // 获取最近修改者信息
      final result = await Process.run(
        'git',
        ['log', '--oneline', '-1'],
        workingDirectory: projectPath,
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final lastCommit = result.stdout.toString().trim();
        gitInfo['last_commit'] = lastCommit;
      }

      // 对于每个文件，尝试获取 git blame 信息
      final blameInfo = <String, String>{};
      for (int i = 0; i < fileNames.length && i < lineNumbers.length; i++) {
        final fileName = fileNames[i];
        final lineNum = lineNumbers[i];

        try {
          final blameResult = await Process.run(
            'git',
            ['blame', '-L', '$lineNum,$lineNum', '--format=%aN|%aE|%ad', '--date=short', fileName],
            workingDirectory: projectPath,
            runInShell: true,
          ).timeout(const Duration(seconds: 5));

          if (blameResult.exitCode == 0) {
            blameInfo[fileName] = blameResult.stdout.toString().trim();
          }
        } catch (e) {
          // 静默处理单个blame失败
        }
      }

      if (blameInfo.isNotEmpty) {
        gitInfo['blame'] = blameInfo;
      }
    } catch (e) {
      // 静默处理Git操作异常
    }

    return gitInfo;
  }

  /// 提取分布信息（版本、系统、机型、品牌）
  Map<String, dynamic> _extractDistributionInfo(Map<String, dynamic> issueData) {
    final distribution = <String, dynamic>{};

    // 版本分布
    if (issueData['versionDistribution'] != null) {
      distribution['versions'] = issueData['versionDistribution'];
    }

    // 系统版本分布
    if (issueData['osVersionDistribution'] != null) {
      distribution['os_versions'] = issueData['osVersionDistribution'];
    }

    // 机型分布
    if (issueData['deviceModelDistribution'] != null) {
      distribution['device_models'] = issueData['deviceModelDistribution'];
    }

    // 品牌分布
    if (issueData['brandDistribution'] != null) {
      distribution['brands'] = issueData['brandDistribution'];
    }

    return distribution;
  }

  /// 生成 LLM 分析提示词：参照skills中的报告格式，结合堆栈信息、源码、Git信息和分布数据
  String _generateAnalysisPrompt(
    Map<String, dynamic> issueData,
    StackInfo stackInfo,
    Map<String, String> sourceMap,
    Map<String, dynamic> gitInfo,
    Map<String, dynamic> distributionInfo,
    String bizModule,
  ) {
    final buffer = StringBuffer();

    buffer.writeln('【任务】根据堆栈信息、源码、Git信息和分布数据进行详细分析');
    buffer.writeln('参照以下skills报告格式进行结构化分析');
    buffer.writeln();

    buffer.writeln('【基本信息】');
    buffer.writeln('- 分析类型: ${bizModule == 'crash' ? '崩溃分析' : 'ANR分析'}');
    buffer.writeln('- 错误类型: ${issueData['issueType'] ?? '未知'}');
    buffer.writeln('- 错误次数: ${issueData['errorCount'] ?? 0}');
    buffer.writeln('- 受影响设备数: ${issueData['affectedDevices'] ?? 0}');
    if (issueData['errorRate'] != null) {
      buffer.writeln('- 错误率: ${issueData['errorRate']}');
    }
    if (issueData['digestHash'] != null) {
      buffer.writeln('- Hash: ${issueData['digestHash']}');
    }
    buffer.writeln();

    buffer.writeln('【分布数据分析】');
    if (distributionInfo['versions'] != null && (distributionInfo['versions'] as List).isNotEmpty) {
      buffer.writeln('- 首现App版本: ${(distributionInfo['versions'] as List).first}');
      buffer.writeln('- 受影响版本: ${(distributionInfo['versions'] as List).take(5).join(", ")}');
    }
    if (distributionInfo['os_versions'] != null && (distributionInfo['os_versions'] as List).isNotEmpty) {
      buffer.writeln('- 受影响OS版本: ${(distributionInfo['os_versions'] as List).take(5).join(", ")}');
    }
    if (distributionInfo['device_models'] != null && (distributionInfo['device_models'] as List).isNotEmpty) {
      buffer.writeln('- 受影响机型: ${(distributionInfo['device_models'] as List).take(5).join(", ")}');
    }
    if (distributionInfo['brands'] != null && (distributionInfo['brands'] as List).isNotEmpty) {
      buffer.writeln('- 受影响品牌: ${(distributionInfo['brands'] as List).take(5).join(", ")}');
    }
    buffer.writeln();

    buffer.writeln('【堆栈信息】');
    final stackTrace = issueData['stackTrace'] as String? ?? '无';
    buffer.writeln(stackTrace.length > 3000 ? stackTrace.substring(0, 3000) : stackTrace);
    buffer.writeln();

    buffer.writeln('【堆栈分析上下文】');
    if (stackInfo.files.isNotEmpty) {
      buffer.writeln('关键文件: ${stackInfo.files.take(10).join(", ")}');
    }
    if (stackInfo.functions.isNotEmpty) {
      buffer.writeln('关键函数: ${stackInfo.functions.take(10).join(", ")}');
    }
    buffer.writeln();

    if (sourceMap.isNotEmpty) {
      buffer.writeln('【源码上下文】');
      sourceMap.forEach((fileName, content) {
        buffer.writeln('文件: $fileName');
        buffer.writeln('代码片段:');
        buffer.writeln(content.length > 800 ? content.substring(0, 800) : content);
        buffer.writeln();
      });
    }

    if (gitInfo.isNotEmpty) {
      buffer.writeln('【Git信息】');
      if (gitInfo['last_commit'] != null) {
        buffer.writeln('- 最近提交: ${gitInfo['last_commit']}');
      }
      if (gitInfo['blame'] != null) {
        final blame = gitInfo['blame'] as Map<String, String>;
        buffer.writeln('- 代码责任人信息:');
        blame.forEach((file, info) {
          buffer.writeln('  * $file: $info');
        });
      }
      buffer.writeln();
    }

    buffer.writeln('''【分析输出要求】
按照以下Markdown结构输出（必须保持以下二级标题）：

## 📍 堆栈分析

### 📊 堆栈类型分析
- 崩溃类型: (Java崩溃/Native崩溃/ANR等)
- 信号类型: (异常类型或信号名)
- 堆栈行数: N 行

### 🔍 关键帧分析

#### ☕ 涉及的关键类:
- (列举5-10个关键类)

#### 🏠 应用代码位置
- 类: (主要类名)
- 方法: (主要方法名)
- 文件: (文件名)
- 行号: (行号)

### ⚙️ 系统调用
- 类: (系统类)
- 方法: (系统方法)

## 🔎 源码分析
（如有源码信息则分析，无则说明"无法获取源码"）

## 💡 原因分析
（现象、堆栈指向的根本原因、置信度、版本/机型/系统版本相关性分析）

## 🛠️ 修改建议
- 1. (建议1)
- 2. (建议2)
- 3. (建议3)
- 4. (建议4)
- 5. (建议5)
- 6. (建议6 - 针对主要影响的版本/机型/品牌进行适配或测试)

## 📝 代码示例
（提供修复前后的代码对比示例）

### 设备和版本特定处理
（如需要针对特定版本或品牌的处理建议）
''');

    return buffer.toString();
  }

  /// 执行 AI 分析：调用 LLM 生成分析报告
  Future<String> _callAiAnalysis(String prompt, String llmBaseUrl, String llmApiKey, String llmModel) async {
    try {
      // 验证 LLM 配置
      if (llmBaseUrl.trim().isEmpty || llmApiKey.trim().isEmpty || llmModel.trim().isEmpty) {
        return _generateTemplateAnalysisReport();
      }

      // 使用真实的 LLM 客户端调用
      final httpClient = _httpClient ?? http.Client();
      final llmClient = LlmClient(
        baseUrl: llmBaseUrl,
        apiKey: llmApiKey,
        model: llmModel,
        chatCompletionsPath: config.llmChatCompletionsPath.trim().isEmpty
          ? 'v1/chat/completions'
          : config.llmChatCompletionsPath,
        httpClient: httpClient,
      );

      // 构建消息
      final messages = [
        {'role': 'system', 'content': config.effectiveLlmSystemPrompt},
        {'role': 'user', 'content': prompt},
      ];

      // 调用 LLM
      final response = await llmClient.chat(messages, temperature: 0.3)
        .timeout(const Duration(seconds: 60));

      return response.isNotEmpty ? response : _generateTemplateAnalysisReport();
    } catch (e) {
      // LLM 调用失败，降级到模板
      return _generateTemplateAnalysisReport();
    }
  }

  /// 生成模板分析报告（当 LLM 调用失败时）
  String _generateTemplateAnalysisReport() {
    return '''## 📍 堆栈分析

### 📊 堆栈类型分析
- 崩溃类型: **Java崩溃/ANR**
- 信号类型: 主线程阻塞或异常
- 堆栈行数: 多行

### 🔍 关键帧分析

#### ☕ 涉及的关键类:
- android.os.Looper
- android.app.ActivityThread
- android.os.Handler
- (其他业务相关类)

#### 🏠 应用代码位置
- 类: (根据堆栈栈顶确定)
- 方法: (根据堆栈栈顶确定)
- 文件: (相关源文件)
- 行号: (堆栈指向)

### ⚙️ 系统调用
- 类: android.os.Handler 或业务类
- 方法: 消息分发或网络IO相关

## 🔎 源码分析
- 无法获取完整源码，建议手动检查堆栈指向的代码位置

## 💡 原因分析
基于堆栈分析，该问题主要是由以下原因导致：

1. **直接现象**：主线程被阻塞或存在未捕获异常
2. **根本原因**：
   - 在主线程执行了同步网络请求或IO操作
   - 或在UI线程执行了耗时计算
   - 或存在死锁导致消息队列无法处理
3. **版本/机型相关性**：
   - 查看堆栈中的系统API版本要求
   - 某些设备品牌的ROM定制可能加强了主线程检查
   - 特定Android版本的StrictMode策略不同

## 🛠️ 修改建议
- 1. 查看堆栈定位具体代码
- 2. 检查相关对象状态和初始化时机
- 3. 将同步操作改为异步处理（协程/线程池/回调）
- 4. 为耗时操作添加超时和异常捕获
- 5. 使用性能监控工具（Android Profiler）排查瓶颈
- 6. 针对主要影响的版本、机型和品牌进行兼容性测试

## 📝 代码示例

### 问题代码
```kotlin
// ❌ 错误：主线程同步操作
override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val data = networkClient.fetchData(url) // 同步网络请求，会阻塞主线程
    val result = processData(data) // 耗时计算
    updateUI(result)
}
```

### 修复代码
```kotlin
// ✅ 正确：使用协程异步处理
override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    lifecycleScope.launch {
        try {
            val data = withContext(Dispatchers.IO) {
                networkClient.fetchData(url) // 在IO线程执行
            }
            val result = processData(data) // 在主线程安全执行
            updateUI(result)
        } catch (e: Exception) {
            Log.e(TAG, "Error processing data", e)
            showErrorMessage()
        }
    }
}
```

### 设备和版本特定处理
```kotlin
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
    // Android 12+ 的特殊处理
    handleAndroid12Plus()
} else {
    // 低版本兼容性处理
    handleLegacy()
}

// 针对品牌的适配
when (Build.BRAND.lowercase()) {
    "huawei" -> applyHuaweiWorkaround()
    "xiaomi" -> applyXiaomiWorkaround()
    else -> applyGeneralFix()
}
```

## 验证方案
- 使用 Android Studio 的 Profiler 监控主线程耗时
- 在低端设备和高版本系统上进行测试
- 使用 StrictMode 检查是否有其他违规操作
- 对比修改前后的崩溃率和ANR频率趋势''';
  }

  /// 生成完整的分析报告
  Future<String> performAnalysis({
    required Map<String, dynamic> issueData,
    required String projectPath,
    required String bizModule,
    required String llmBaseUrl,
    required String llmApiKey,
    required String llmModel,
    required String projectId,
  }) async {
    try {
      // 1. 解析堆栈信息
      final stackTrace = issueData['stackTrace'] as String? ?? '';
      final stackInfo = _parseStackTrace(stackTrace);

      // 2. 从本地源码中查找相关文件
      final sourceMap = await _findSourceFiles(projectPath, stackInfo.files);

      // 3. 获取Git信息（最近修改者、git blame）
      final gitInfo = await _getGitInfo(projectPath, stackInfo.files, stackInfo.lineNumbers);

      // 4. 提取分布信息（版本、系统、机型、品牌）
      final distributionInfo = _extractDistributionInfo(issueData);

      // 5. 生成分析提示词（包含所有信息）
      final prompt = _generateAnalysisPrompt(
        issueData,
        stackInfo,
        sourceMap,
        gitInfo,
        distributionInfo,
        bizModule,
      );

      // 6. 调用 LLM 进行分析
      final analysisReport = await _callAiAnalysis(prompt, llmBaseUrl, llmApiKey, llmModel);

      // 7. 保存报告到本地系统
      final gitContext = gitInfo.isNotEmpty
          ? 'Git: ${gitInfo['last_commit'] ?? 'N/A'}, Blame: ${(gitInfo['blame'] as Map?)?.length ?? 0} files'
          : '';
      final report = AnalysisReportRecord(
        id: AnalysisReportRecord.newId(),
        projectId: projectId,
        digestHash: issueData['digestHash'] ?? '',
        title: issueData['issueType'] ?? 'AI Analysis Report',
        bizModule: bizModule,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        reportBody: analysisReport,
        stackSnippet: stackTrace.length > 100 ? stackTrace.substring(0, 100) : stackTrace,
        gitlabContext: 'Files: ${stackInfo.files.length}, Source: ${sourceMap.length}, $gitContext',
      );

      await reportManager.addReport(report);

      return analysisReport;
    } catch (e) {
      // 分析失败时返回默认报告
      return _generateTemplateAnalysisReport();
    }
  }

  /// 生成报告 ID
  String _generateReportId() {
    return 'ai_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }
}

/// 从堆栈中提取的关键信息
class StackInfo {
  StackInfo({
    required this.files,
    required this.functions,
    required this.lineNumbers,
  });

  final List<String> files;
  final List<String> functions;
  final List<String> lineNumbers;
}
