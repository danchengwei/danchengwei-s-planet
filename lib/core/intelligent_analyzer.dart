import 'dart:io';
import 'package:http/http.dart' as http;

/// 堆栈帧表示
class StackFrame {
  final String className;
  final String methodName;
  final String? fileName;
  final int? lineNumber;
  final bool isApplicationCode;

  StackFrame({
    required this.className,
    required this.methodName,
    this.fileName,
    this.lineNumber,
    this.isApplicationCode = false,
  });

  @override
  String toString() {
    final loc = fileName != null && lineNumber != null ? ' at $fileName:$lineNumber' : '';
    return '$className.$methodName$loc';
  }
}

/// 源码位置信息
class SourceLocation {
  final String filePath;
  final int startLine;
  final int endLine;
  final String codeSnippet;

  SourceLocation({
    required this.filePath,
    required this.startLine,
    required this.endLine,
    required this.codeSnippet,
  });
}

/// Git 责任信息
class GitBlameInfo {
  final String author;
  final String email;
  final DateTime commitTime;
  final String commitHash;
  final String commitMessage;

  GitBlameInfo({
    required this.author,
    required this.email,
    required this.commitTime,
    required this.commitHash,
    required this.commitMessage,
  });
}

/// 智能崩溃分析引擎
/// 集成: 堆栈解析 → 源码定位 → Git 查询 → LLM 分析
class IntelligentAnalyzer {
  final String projectPath;
  final String gitRepoPath;
  final String llmApiKey;
  final String llmModel;
  final String llmBaseUrl;
  final http.Client httpClient;

  IntelligentAnalyzer({
    required this.projectPath,
    required this.gitRepoPath,
    required this.llmApiKey,
    required this.llmModel,
    required this.llmBaseUrl,
    required this.httpClient,
  });

  /// 解析堆栈文本，提取应用代码帧
  List<StackFrame> parseStack(String stackText) {
    final lines = stackText.split('\n');
    final frames = <StackFrame>[];

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      // 简单的堆栈帧解析 (支持 Java/Kotlin/Android 格式)
      // 格式: at com.example.MyClass.methodName(SourceFile.java:123)
      final atMatch = RegExp(r'at\s+([\w.]+)\.([\w<>$]+)\((.*?):?(\d+)?\)').firstMatch(line);

      if (atMatch != null) {
        final className = atMatch.group(1) ?? '';
        final methodName = atMatch.group(2) ?? '';
        final fileName = atMatch.group(3);
        final lineNumStr = atMatch.group(4);
        final lineNum = lineNumStr != null ? int.tryParse(lineNumStr) : null;

        // 判断是否为应用代码 (不包含 android, java, com.google 等系统包)
        final isAppCode = !className.startsWith('android.') &&
            !className.startsWith('java.') &&
            !className.startsWith('kotlin.') &&
            !className.startsWith('com.google.') &&
            !className.startsWith('androidx.');

        frames.add(
          StackFrame(
            className: className,
            methodName: methodName,
            fileName: fileName,
            lineNumber: lineNum,
            isApplicationCode: isAppCode,
          ),
        );
      }
    }

    return frames;
  }

  /// 在项目源码中定位文件
  Future<SourceLocation?> findSourceCode(String className, String methodName) async {
    try {
      // 将类名转换为文件路径
      // com.example.MyClass → com/example/MyClass.kt 或 com/example/MyClass.java
      final pathParts = className.split('.');
      final fileName = pathParts.last;

      // 在项目中搜索源码文件
      final result = await Process.run('find', [
        projectPath,
        '-name',
        '$fileName.kt',
        '-o',
        '-name',
        '$fileName.java',
      ]);

      if (result.exitCode != 0) {
        return null;
      }

      final files = result.stdout.toString().trim().split('\n').where((f) => f.isNotEmpty).toList();

      if (files.isEmpty) {
        return null;
      }

      // 读取第一个找到的文件
      final filePath = files.first;
      final content = await File(filePath).readAsString();
      final lines = content.split('\n');

      // 简单搜索方法
      int? methodLineNum;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('fun $methodName') || lines[i].contains('void $methodName')) {
          methodLineNum = i + 1;
          break;
        }
      }

      if (methodLineNum == null) {
        return null;
      }

      // 提取代码片段 (前后 5 行)
      final startLine = (methodLineNum - 5).clamp(0, lines.length - 1);
      final endLine = (methodLineNum + 10).clamp(0, lines.length - 1);
      final codeSnippet = lines.sublist(startLine, endLine).join('\n');

      return SourceLocation(
        filePath: filePath,
        startLine: startLine + 1,
        endLine: endLine + 1,
        codeSnippet: codeSnippet,
      );
    } catch (e) {
      return null;
    }
  }

  /// 查询 Git Blame 信息
  Future<GitBlameInfo?> getGitBlame(String filePath, int lineNumber) async {
    try {
      final result = await Process.run('git', [
        '-C',
        gitRepoPath,
        'blame',
        '-L',
        '$lineNumber,$lineNumber',
        '--line-porcelain',
        filePath,
      ]);

      if (result.exitCode != 0) {
        return null;
      }

      final output = result.stdout.toString();
      final lines = output.split('\n');

      String? hash, author, email, time;
      for (final line in lines) {
        if (line.startsWith('commit ')) {
          hash = line.substring(7);
        } else if (line.startsWith('author ')) {
          author = line.substring(7);
        } else if (line.startsWith('author-mail ')) {
          email = line.substring(13).replaceAll('<', '').replaceAll('>', '');
        } else if (line.startsWith('author-time ')) {
          time = line.substring(12);
        }
      }

      if (hash == null || author == null) {
        return null;
      }

      final timestamp = int.tryParse(time ?? '0') ?? 0;
      final commitTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);

      return GitBlameInfo(
        author: author,
        email: email ?? 'unknown',
        commitTime: commitTime,
        commitHash: hash,
        commitMessage: 'N/A', // 可通过另一个 git 查询获取
      );
    } catch (e) {
      return null;
    }
  }

  /// 调用 LLM 生成分析报告
  Future<String> generateAnalysisReport({
    required String issueType,
    required String stackTrace,
    required String sourceCode,
    required String? gitInfo,
  }) async {
    final prompt = '''
分析以下移动应用崩溃信息，并提供根因分析和修复建议。

崩溃类型: $issueType

堆栈信息:
$stackTrace

相关源码:
$sourceCode

${gitInfo != null ? 'Git 信息: $gitInfo' : ''}

请提供:
1. 根本原因分析 (为什么会崩溃)
2. 影响范围 (哪些用户/场景受影响)
3. 修复建议 (具体修改方案)
4. 预防措施 (如何避免类似问题)

回答要简洁，最多 500 字。
''';

    try {
      final response = await httpClient.post(
        Uri.parse('$llmBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $llmApiKey',
          'Content-Type': 'application/json',
        },
        body: _buildRequestBody(prompt),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return 'LLM 分析失败 (${response.statusCode})';
      }

      // 简单的 JSON 解析 (实际应使用 jsonDecode)
      final content = _extractContentFromResponse(response.body);
      return content;
    } catch (e) {
      return 'LLM 分析异常: $e';
    }
  }

  /// 构建 LLM 请求体
  String _buildRequestBody(String prompt) {
    // 适配 GLM-4.7-Flash API 格式
    return '''{
  "model": "$llmModel",
  "messages": [{
    "role": "user",
    "content": "${prompt.replaceAll('"', '\\"').replaceAll('\n', '\\n')}"
  }],
  "temperature": 0.7,
  "max_tokens": 500
}''';
  }

  /// 从响应体提取内容
  String _extractContentFromResponse(String body) {
    try {
      // 简单的字符串搜索 (实际应使用 jsonDecode)
      final start = body.indexOf('"content"');
      if (start == -1) return '无法解析响应';

      final contentStart = body.indexOf(':', start) + 1;
      final contentEnd = body.indexOf('"', contentStart + 2);

      if (contentStart == -1 || contentEnd == -1) return '无法解析响应';

      return body.substring(contentStart + 2, contentEnd);
    } catch (e) {
      return '解析响应失败: $e';
    }
  }
}
