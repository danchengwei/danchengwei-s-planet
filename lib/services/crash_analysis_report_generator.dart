import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../aliyun/emas_appmonitor_client.dart';
import '../models/tool_config.dart';
import 'console_links.dart';
import 'llm_client.dart';
import 'outbound_http_client_for_config.dart';
import 'source_code_analyzer.dart';
import 'stack_parser.dart';

/// 单条报告入参：调用方把已抓到的 GetIssue 详情 + 列表侧摘要传进来，避免重复请求。
class ReportInput {
  ReportInput({
    required this.digestHash,
    required this.title,
    required this.issueDetailJson,
    this.listItem,
    this.listStack,
    this.startTimeMs,
    this.endTimeMs,
  });

  final String digestHash;
  final String title;
  final Map<String, dynamic> issueDetailJson;
  final IssueListItem? listItem;
  final String? listStack;
  final int? startTimeMs;
  final int? endTimeMs;
}

/// 单条报告生成进度回调（用于 UI 显示「正在分析 N/M」）。
typedef ReportProgressCallback = void Function(int done, int total);

/// 崩溃/卡顿/异常 智能分析报告生成器。
///
/// 参照 `.claude/skills/emas-intelligent-analysis2/index.ts` 的 [analyzeCrash]
/// 输出结构，生成完整 Markdown 分析报告：
///
/// 1. 卡片式基本信息（Hash/类型/次数/影响设备/错误率/首现版本/控制台链接）
/// 2. 📱 系统版本分布
/// 3. 📱 机型分布
/// 4. 🏷️ 品牌分布
/// 5. 📋 详细堆栈信息
/// 6. 📍 堆栈分析（类型/关键帧/应用代码位置/系统调用）
/// 7. 🔎 源码分析（含 Git blame 代码片段 + 贡献者统计）
/// 8. 💡 原因分析 + 🛠️ 修改建议 + 📝 代码示例（LLM 或内置模板）
///
/// 报告保存到 [getApplicationSupportDirectory]/emas_analysis_reports/ 下。
class CrashAnalysisReportGenerator {
  CrashAnalysisReportGenerator({required this.config});

  final ToolConfig config;

  static const String _reportSubdir = 'emas_analysis_reports';

  /// 生成单条报告（Markdown 字符串 + 元信息）。
  ///
  /// - [bizModule] 用于控制台链接拼接。
  /// - [projectPath] 为空时跳过源码分析（Git blame 同样跳过）。
  /// - [useLlm] 为 true 且配置了 LLM 时，调用大模型生成原因分析/修改建议/代码示例。
  Future<GeneratedReport> generateForIssue({
    required ReportInput input,
    required String bizModule,
    String? projectPath,
    bool useLlm = false,
  }) async {
    final projectRoot = projectPath ?? config.localProjectPath;
    final detail = input.issueDetailJson;
    final model = detail['Model'] is Map
        ? Map<String, dynamic>.from(detail['Model'] as Map)
        : detail;

    final hash = (model['DigestHash']?.toString() ?? input.digestHash).trim();
    final errorName = (model['Name']?.toString() ?? input.listItem?.errorName ?? input.title).trim();
    final errorType = (model['Type']?.toString() ?? input.listItem?.errorType ?? 'Unknown').trim();
    final errorCount = _readInt(model['ErrorCount'] ?? input.listItem?.errorCount) ?? 0;
    final errorDeviceCount = _readInt(model['ErrorDeviceCount'] ?? input.listItem?.errorDeviceCount) ?? 0;
    final errorRate = _readRate(model['ErrorRate'] ?? model['CrashRate'] ?? input.listItem?.errorRatePercent);
    final firstVersion = (model['FirstVersion']?.toString() ?? input.listItem?.firstVersion ?? '-').trim();
    final firstTime = model['FirstTime']?.toString();
    final latestTime = model['LatestTime']?.toString();
    final errorVersionCount = _readInt(model['ErrorVersionCount']);

    final stackText = _extractStack(detail) ?? input.listStack ?? input.listItem?.stack ?? '';

    final buffer = StringBuffer();
    final bizLabel = _bizLabel(bizModule);
    final sectionTitle = '$bizLabel分析报告 #${input.digestHash.hashCode.abs() % 1000}';
    final stackHead = _stackHeadLine(stackText);

    buffer.writeln('## 📑 $sectionTitle');
    buffer.writeln();
    buffer.writeln('> **$bizLabel分析报告**');
    buffer.writeln('> - **Hash**: `$hash`');
    buffer.writeln('> - **$bizLabel类型**: $stackHead');
    buffer.writeln('> - **$bizLabel次数**: $errorCount');
    buffer.writeln('> - **影响设备**: $errorDeviceCount');
    buffer.writeln('> - **错误率**: ${errorRate != null ? '${errorRate.toStringAsFixed(3)}%' : '-'}');
    buffer.writeln('> - **首现版本**: ${firstVersion.isEmpty ? '-' : firstVersion}');
    if (errorVersionCount != null) {
      buffer.writeln('> - **影响版本数**: $errorVersionCount');
    }
    if (firstTime != null && firstTime.isNotEmpty) buffer.writeln('> - **首次时间**: $firstTime');
    if (latestTime != null && latestTime.isNotEmpty) buffer.writeln('> - **最近时间**: $latestTime');
    buffer.writeln('> - **阿里云控制台**: [点击跳转](${_consoleLink(bizModule, hash)})');
    buffer.writeln();

    final osDist = _readDistributionList(model['OsDistribution'] ?? model['SystemVersionDistribution']);
    final deviceDist = _readDistributionList(model['DeviceDistribution'] ?? model['DeviceModelDistribution']);
    final brandDist = _readDistributionList(model['BrandDistribution']);

    _writeOsDistribution(buffer, osDist, errorCount, bizLabel);
    _writeDeviceDistribution(buffer, deviceDist, errorCount, bizLabel);
    _writeBrandDistribution(buffer, brandDist, errorCount, bizLabel);

    buffer.writeln('### 📋 详细堆栈信息');
    buffer.writeln('> **Hash**: `$hash`');
    buffer.writeln('> **$bizLabel类型**: `${errorType.isEmpty ? 'Unknown' : errorType}`');
    if (stackHead.isNotEmpty && stackHead != errorType) {
      final short = stackHead.length > 200 ? '${stackHead.substring(0, 200)}…' : stackHead;
      buffer.writeln('> **错误名称**: $short');
    }
    final reason = (model['Reason']?.toString() ?? '').trim();
    if (reason.isNotEmpty) {
      final short = reason.length > 200 ? '${reason.substring(0, 200)}…' : reason;
      buffer.writeln('> **错误原因**: $short');
    }
    buffer.writeln('>');
    buffer.writeln('> **堆栈信息**');
    if (stackText.trim().isEmpty) {
      buffer.writeln('> （无）');
    } else {
      for (final line in stackText.split('\n')) {
        buffer.writeln('> $line');
      }
    }
    buffer.writeln();

    _writeStackAnalysis(buffer, stackText, errorType);

    SourceCodeLookup? sourceLookup;
    if (projectRoot.trim().isNotEmpty) {
      sourceLookup = await _writeSourceAnalysis(buffer, stackText, projectRoot);
    } else {
      buffer.writeln('### 🔎 源码分析');
      buffer.writeln('- ⚠️ 未配置本地项目路径（ToolConfig.localProjectPath），跳过源码定位与 Git blame。');
      buffer.writeln();
    }

    final fix = await _resolveFix(
      errorType: errorType,
      stackText: stackText,
      osDist: osDist,
      deviceDist: deviceDist,
      brandDist: brandDist,
      sourceLookup: sourceLookup,
      useLlm: useLlm,
      bizLabel: bizLabel,
    );
    buffer.writeln('### 💡 原因分析');
    buffer.writeln(fix.reason.trim().isEmpty ? '需要根据具体堆栈信息分析。' : fix.reason.trim());
    buffer.writeln();
    buffer.writeln('### 🛠️ 修改建议');
    buffer.writeln(fix.suggestion.trim().isEmpty
        ? '- 1. 查看堆栈定位具体代码\n- 2. 检查相关对象状态\n- 3. 添加空检查和异常处理\n- 4. 分析场景和条件'
        : fix.suggestion.split('\n').map((l) => l.trim().isEmpty ? l : '- $l').join('\n'));
    buffer.writeln();
    buffer.writeln('### 📝 代码示例');
    buffer.writeln('```java');
    buffer.writeln();
    buffer.writeln(fix.codeExample.trim().isEmpty ? '// 请参考上方修改建议自行补全示例' : fix.codeExample.trim());
    buffer.writeln();
    buffer.writeln('```');
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();

    final fileName = _buildFileName('issue');
    return GeneratedReport(
      digestHash: hash,
      fileName: fileName,
      markdown: buffer.toString(),
      bizModule: bizModule,
      title: errorName.isEmpty ? errorType : errorName,
      generatedAt: DateTime.now(),
    );
  }

  /// 顺序执行多条 [inputs] 的报告，合成**一份**合并 Markdown（分析概览 + 统计表 + 详细分析）。
  ///
  /// [onProgress] 用于 UI 显示「正在生成 1/N」；失败条会写入占位小节并继续。
  Future<GeneratedReport> generateForBatch({
    required List<ReportInput> inputs,
    required String bizModule,
    String? projectPath,
    ReportProgressCallback? onProgress,
  }) async {
    if (inputs.isEmpty) {
      throw ArgumentError('inputs 不能为空');
    }
    final overview = StringBuffer();
    final start = inputs.first.startTimeMs;
    final end = inputs.first.endTimeMs;
    overview.writeln('# EMAS 智能分析报告');
    overview.writeln();
    overview.writeln('## 📋 分析概览');
    overview.writeln('| 项目 | 内容 |');
    overview.writeln('|------|------|');
    overview.writeln('| 分析类型 | ${_bizLabel(bizModule)} |');
    overview.writeln('| 时间范围 | ${_formatRange(start, end)} |');
    overview.writeln('| 分析数量 | ${inputs.length} 条 |');
    final proj = (projectPath?.trim().isNotEmpty ?? false)
        ? projectPath!.trim()
        : (config.localProjectPath.trim().isEmpty ? '-' : config.localProjectPath.trim());
    overview.writeln('| 项目路径 | $proj |');
    overview.writeln();
    overview.writeln('## 📊 ${_bizLabel(bizModule)}统计');
    overview.writeln('| ${_bizLabel(bizModule)}类型 | ${_bizLabel(bizModule)}次数 | 影响设备 | 错误率 | 首现版本 |');
    overview.writeln('|------|---------|---------|---------|---------|');

    for (var i = 0; i < inputs.length; i++) {
      final it = inputs[i];
      final m = it.issueDetailJson['Model'] is Map
          ? Map<String, dynamic>.from(it.issueDetailJson['Model'] as Map)
          : it.issueDetailJson;
      final hash = (m['DigestHash']?.toString() ?? it.digestHash).trim();
      final type = (m['Type']?.toString() ?? it.listItem?.errorType ?? '-').trim();
      final ec = _readInt(m['ErrorCount'] ?? it.listItem?.errorCount) ?? 0;
      final ed = _readInt(m['ErrorDeviceCount'] ?? it.listItem?.errorDeviceCount) ?? 0;
      final er = _readRate(m['ErrorRate'] ?? m['CrashRate'] ?? it.listItem?.errorRatePercent);
      final fv = (m['FirstVersion']?.toString() ?? it.listItem?.firstVersion ?? '-').trim();
      final stackText = _extractStack(it.issueDetailJson) ?? it.listStack ?? it.listItem?.stack ?? '';
      final head = _stackHeadLine(stackText);
      final cellText = head.isEmpty ? (type.isEmpty ? hash : type) : head;
      overview.writeln('| $cellText | $ec | $ed | ${er != null ? '${er.toStringAsFixed(3)}%' : '-'} | ${fv.isEmpty ? '-' : fv} |');
    }
    overview.writeln();
    overview.writeln('## 📝 详细分析');
    overview.writeln();

    for (var i = 0; i < inputs.length; i++) {
      final it = inputs[i];
      try {
        final r = await generateForIssue(
          input: it,
          bizModule: bizModule,
          projectPath: projectPath,
        );
        overview.writeln(r.markdown);
      } catch (e) {
        overview.writeln('### 📑 ${_bizLabel(bizModule)}分析报告 #${i + 1}（失败）');
        overview.writeln('> - **Hash**: `${it.digestHash}`');
        overview.writeln('> - **错误**: $e');
        overview.writeln();
      }
      onProgress?.call(i + 1, inputs.length);
    }

    final fileName = _buildFileName('batch');
    return GeneratedReport(
      digestHash: 'batch-${inputs.length}',
      fileName: fileName,
      markdown: overview.toString(),
      bizModule: bizModule,
      title: '${_bizLabel(bizModule)}批量分析（${inputs.length} 条）',
      generatedAt: DateTime.now(),
    );
  }

  /// 把生成的报告落盘到 `getApplicationSupportDirectory()/emas_analysis_reports/`。
  ///
  /// 返回保存后的绝对路径。
  Future<String> saveReport(GeneratedReport report) async {
    final dir = await _reportDir();
    final path = p.join(dir.path, report.fileName);
    await File(path).writeAsString(report.markdown, flush: true);
    return path;
  }

  /// 把 [dir] 下所有 `*.md` 报告按修改时间倒序返回（用于「打开最近一份」等场景）。
  Future<List<FileSystemEntity>> listSavedReports() async {
    final dir = await _reportDir();
    if (!await dir.exists()) return const [];
    final files = await dir.list().where((e) => e is File && e.path.endsWith('.md')).toList();
    files.sort((a, b) {
      final am = File(a.path).statSync().modified;
      final bm = File(b.path).statSync().modified;
      return bm.compareTo(am);
    });
    return files;
  }

  /// 报告保存目录。
  Future<Directory> _reportDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, _reportSubdir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // -------- 私有：分布、堆栈、源码、模板 --------

  void _writeOsDistribution(StringBuffer buffer, List<_DistEntry> osDist, int errorCount, String bizLabel) {
    buffer.writeln('### 📱 系统版本分布分析');
    buffer.writeln('| 系统版本 | $bizLabel次数 | 占比 |');
    buffer.writeln('|---------|---------|------|');
    if (osDist.isNotEmpty) {
      final total = osDist.fold<int>(0, (s, e) => s + (e.count ?? 0));
      final sorted = [...osDist]..sort((a, b) => (b.count ?? 0).compareTo(a.count ?? 0));
      for (final e in sorted) {
        final pct = total > 0 ? ((e.count ?? 0) / total * 100).toStringAsFixed(2) : '0.00';
        buffer.writeln('| ${e.name.isEmpty ? 'Unknown' : e.name} | ${e.count ?? 0} | $pct% |');
      }
    } else {
      buffer.writeln('| 暂无数据 | - | - |');
    }
    buffer.writeln();
  }

  void _writeDeviceDistribution(StringBuffer buffer, List<_DistEntry> list, int errorCount, String bizLabel) {
    buffer.writeln('### 📱 机型分布分析');
    buffer.writeln('| 机型 | $bizLabel次数 | 占比 |');
    buffer.writeln('|------|---------|------|');
    if (list.isNotEmpty) {
      final total = list.fold<int>(0, (s, e) => s + (e.count ?? 0));
      final sorted = [...list]..sort((a, b) => (b.count ?? 0).compareTo(a.count ?? 0));
      final top = sorted.take(5).toList();
      int others = 0;
      for (var i = 5; i < sorted.length; i++) {
        others += sorted[i].count ?? 0;
      }
      for (final e in top) {
        final pct = total > 0 ? ((e.count ?? 0) / total * 100).toStringAsFixed(2) : '0.00';
        buffer.writeln('| ${e.name.isEmpty ? 'Unknown' : e.name} | ${e.count ?? 0} | $pct% |');
      }
      if (others > 0) {
        final pct = total > 0 ? (others / total * 100).toStringAsFixed(2) : '0.00';
        buffer.writeln('| 其他 | $others | $pct% |');
      }
    } else {
      buffer.writeln('| 暂无数据 | - | - |');
    }
    buffer.writeln();
  }

  void _writeBrandDistribution(StringBuffer buffer, List<_DistEntry> list, int errorCount, String bizLabel) {
    buffer.writeln('### 🏷️ 品牌分布分析');
    buffer.writeln('| 品牌 | $bizLabel次数 | 占比 |');
    buffer.writeln('|------|---------|------|');
    if (list.isNotEmpty) {
      final total = list.fold<int>(0, (s, e) => s + (e.count ?? 0));
      final sorted = [...list]..sort((a, b) => (b.count ?? 0).compareTo(a.count ?? 0));
      for (final e in sorted) {
        final pct = total > 0 ? ((e.count ?? 0) / total * 100).toStringAsFixed(2) : '0.00';
        buffer.writeln('| ${e.name.isEmpty ? 'Unknown' : e.name} | ${e.count ?? 0} | $pct% |');
      }
    } else {
      buffer.writeln('| 暂无数据 | - | - |');
    }
    buffer.writeln();
  }

  void _writeFallbackDistribution(StringBuffer buffer, int errorCount, String bizLabel) {
    buffer.writeln('| 暂无数据 | - | - |');
  }

  void _writeStackAnalysis(StringBuffer buffer, String stackText, String errorType) {
    buffer.writeln('### 📍 堆栈分析');
    final parsed = stackText.trim().isEmpty
        ? null
        : StackParser.parse(stackText);
    final lineCount = stackText.split('\n').where((l) => l.trim().isNotEmpty).length;
    final isNative = errorType.toUpperCase().contains('SIG') ||
        errorType.toUpperCase().contains('SEGV') ||
        errorType.toUpperCase().contains('TRAP') ||
        errorType.toUpperCase().contains('ABRT');
    final isJava = errorType.contains('Exception') || stackText.contains('.java:');

    buffer.writeln('#### 📊 堆栈类型分析');
    final crashTypeLabel = isNative
        ? '**Native 崩溃**'
        : isJava
            ? '**Java 崩溃**'
            : '**未知类型**';
    buffer.writeln('- 崩溃类型: $crashTypeLabel');
    buffer.writeln('- 信号类型: ${errorType.isEmpty ? '未知' : errorType}');
    buffer.writeln('- 堆栈行数: $lineCount 行');
    if (parsed != null && parsed.exceptionName != null && parsed.exceptionName!.isNotEmpty) {
      buffer.writeln('- 异常名称: `${parsed.exceptionName}`');
    }
    buffer.writeln();

    if (parsed != null) {
      if (parsed.javaClasses.isNotEmpty) {
        buffer.writeln('#### 🔍 关键帧分析');
        buffer.writeln();
        buffer.writeln('##### ☕ 涉及的Java类:');
        final shown = parsed.javaClasses.take(10).toList();
        for (final c in shown) {
          buffer.writeln('- $c');
        }
        if (parsed.javaClasses.length > 10) {
          buffer.writeln('- ... 还有 ${parsed.javaClasses.length - 10} 个类...');
        }
        buffer.writeln();
      }
      if (parsed.nativeLibraries.isNotEmpty) {
        buffer.writeln('##### 📦 涉及的 Native 库:');
        for (final lib in parsed.nativeLibraries) {
          buffer.writeln('- ${lib.name}');
        }
        buffer.writeln();
      }
      final app = parsed.applicationCodeLocation;
      if (app != null) {
        buffer.writeln('#### 🏠 应用代码位置');
        buffer.writeln('- 类: ${app.className}');
        buffer.writeln('- 方法: ${app.methodName}');
        buffer.writeln('- 文件: ${app.fileName.isEmpty ? '-' : app.fileName}');
        buffer.writeln('- 行号: ${app.lineNumber}');
        buffer.writeln();
      }
      if (parsed.systemCallChain.isNotEmpty) {
        buffer.writeln('#### ⚙️ 系统调用');
        for (final s in parsed.systemCallChain.take(3)) {
          buffer.writeln('- 类: ${s.className}');
          buffer.writeln('- 方法: ${s.methodName}');
        }
        buffer.writeln();
      }
    } else {
      buffer.writeln('> （无可解析的堆栈内容）');
      buffer.writeln();
    }
  }

  Future<SourceCodeLookup?> _writeSourceAnalysis(StringBuffer buffer, String stackText, String projectRoot) async {
    final frame = SourceCodeAnalyzer.parseAppFrame(stackText);
    if (frame.className == null) {
      buffer.writeln('### 🔎 源码分析');
      buffer.writeln('- ⚠️ 堆栈中未定位到业务类（可能均为系统/框架调用）。');
      buffer.writeln();
      return null;
    }
    final analyzer = SourceCodeAnalyzer(projectPath: projectRoot);
    final lookup = await analyzer.readSnippet(className: frame.className, line: frame.line);
    buffer.writeln('### 🔎 源码分析');
    if (frame.file != null && frame.file!.isNotEmpty) {
      buffer.writeln('- 📋 堆栈文件: `${frame.file}`');
    }
    if (frame.method != null && frame.method!.isNotEmpty) {
      buffer.writeln('- 🔧 定位方法: `${frame.className}.${frame.method}()`');
    }
    if (lookup.sourceFile == null) {
      buffer.writeln('- 📄 源文件: 未找到');
      buffer.writeln('- 💡 可能原因：第三方库 / 业务包路径未配置 / 类名混淆。');
      buffer.writeln();
      return lookup;
    }
    if (lookup.isGitIgnored) {
      buffer.writeln('- 📄 文件: `${lookup.sourceFile}`');
      buffer.writeln('- ⚠️ 该文件被 `.gitignore` 忽略，跳过 git blame。');
      buffer.writeln();
      return lookup;
    }
    if (lookup.submodule.isNotEmpty) {
      buffer.writeln('- 📦 子模块: `${lookup.submodule}`（在子模块内执行 git blame）');
    }
    buffer.writeln('- 📄 文件: `${lookup.sourceFile}`');
    if (frame.line > 0) {
      buffer.writeln('- 📍 崩溃行: ${frame.line}');
    }
    buffer.writeln();
    if (lookup.snippet.isEmpty) {
      buffer.writeln('- ⚠️ 代码片段为空。');
      buffer.writeln();
      return lookup;
    }
    buffer.writeln('#### 代码片段');
    buffer.writeln('```java');
    for (final line in lookup.snippet) {
      final marker = line.lineNumber == lookup.centerLine ? '>>> ' : '    ';
      final meta = _blameMetaSuffix(line);
      buffer.writeln('$marker${line.lineNumber}: ${line.content}$meta');
    }
    buffer.writeln('```');
    if (lookup.authorStats.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('#### 👥 代码贡献者统计');
      final sorted = lookup.authorStats.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sorted) {
        buffer.writeln('- ${e.key}: ${e.value} 行');
      }
    }
    final commits = <String, _CommitMeta>{};
    for (final line in lookup.snippet) {
      if (line.commit.isEmpty || line.commit == '-') continue;
      commits[line.commit] = _CommitMeta(
        hash: line.commit,
        author: line.author,
        time: line.authorTimeText,
        summary: line.commitSummary,
      );
    }
    if (commits.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('#### 📝 涉及提交（按 commit 聚合）');
      for (final c in commits.values) {
        final line = '- `$c.hash` | $c.author'
            '${c.time.isEmpty ? '' : ' | $c.time'}'
            '${c.summary.isEmpty ? '' : ' | ${c.summary}'}';
        buffer.writeln(line);
      }
    }
    buffer.writeln();
    return lookup;
  }

  /// 在代码片段每行末尾追加「作者 · 时间 · commit 前 7 位」标识（最右注释区）。
  String _blameMetaSuffix(SourceCodeBlameLine line) {
    if (line.author == '-' || line.author.isEmpty) return '';
    final short = line.commit.length >= 7 ? line.commit.substring(0, 7) : line.commit;
    final t = line.authorTimeText.isEmpty ? '' : ' · ${line.authorTimeText}';
    return '  // ${line.author}$t · $short';
  }

  Future<_FixContent> _resolveFix({
    required String errorType,
    required String stackText,
    required List<_DistEntry> osDist,
    required List<_DistEntry> deviceDist,
    required List<_DistEntry> brandDist,
    required SourceCodeLookup? sourceLookup,
    required bool useLlm,
    required String bizLabel,
  }) async {
    if (useLlm && config.llmBaseUrl.trim().isNotEmpty && config.llmApiKey.trim().isNotEmpty && config.llmModel.trim().isNotEmpty) {
      try {
        final fromLlm = await _generateFixWithLlm(
          errorType: errorType,
          stackText: stackText,
          osDist: osDist,
          deviceDist: deviceDist,
          brandDist: brandDist,
          sourceLookup: sourceLookup,
          bizLabel: bizLabel,
        );
        if (fromLlm != null) return fromLlm;
      } catch (_) {
        // LLM 失败，回退到内置模板
      }
    }
    return _BuiltinFixTemplate.build(
      errorType: errorType,
      stackText: stackText,
      osDist: osDist,
      deviceDist: deviceDist,
      brandDist: brandDist,
    );
  }

  Future<_FixContent?> _generateFixWithLlm({
    required String errorType,
    required String stackText,
    required List<_DistEntry> osDist,
    required List<_DistEntry> deviceDist,
    required List<_DistEntry> brandDist,
    required SourceCodeLookup? sourceLookup,
    required String bizLabel,
  }) async {
    final client = newLlmClient();

    final distBuf = StringBuffer();
    if (osDist.isNotEmpty) {
      distBuf.writeln('【系统版本分布 Top5】');
      final sorted = [...osDist]..sort((a, b) => (b.count ?? 0).compareTo(a.count ?? 0));
      for (final e in sorted.take(5)) {
        distBuf.writeln('- ${e.name.isEmpty ? 'Unknown' : e.name}: ${e.count ?? 0}次');
      }
    }
    if (deviceDist.isNotEmpty) {
      distBuf.writeln('【机型分布 Top5】');
      final sorted = [...deviceDist]..sort((a, b) => (b.count ?? 0).compareTo(a.count ?? 0));
      for (final e in sorted.take(5)) {
        distBuf.writeln('- ${e.name.isEmpty ? 'Unknown' : e.name}: ${e.count ?? 0}次');
      }
    }
    if (brandDist.isNotEmpty) {
      distBuf.writeln('【品牌分布】');
      final sorted = [...brandDist]..sort((a, b) => (b.count ?? 0).compareTo(a.count ?? 0));
      for (final e in sorted) {
        distBuf.writeln('- ${e.name.isEmpty ? 'Unknown' : e.name}: ${e.count ?? 0}次');
      }
    }

    final sourceBuf = StringBuffer();
    if (sourceLookup != null && sourceLookup.sourceFile != null) {
      sourceBuf.writeln('【源码定位】');
      sourceBuf.writeln('文件: ${sourceLookup.sourceFile}');
      if (sourceLookup.submodule.isNotEmpty) {
        sourceBuf.writeln('子模块: ${sourceLookup.submodule}');
      }
      if (sourceLookup.snippet.isNotEmpty) {
        sourceBuf.writeln('代码片段（带 >>> 的是崩溃行）:');
        sourceBuf.writeln('```java');
        for (final line in sourceLookup.snippet) {
          final marker = line.lineNumber == sourceLookup.centerLine ? '>>> ' : '    ';
          sourceBuf.writeln('$marker${line.lineNumber}: ${line.content}');
        }
        sourceBuf.writeln('```');
      }
      if (sourceLookup.authorStats.isNotEmpty) {
        sourceBuf.writeln('代码贡献者:');
        final sorted = sourceLookup.authorStats.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        for (final e in sorted) {
          sourceBuf.writeln('- ${e.key}: ${e.value}行');
        }
      }
    }

    final systemPrompt = '''你是资深移动端崩溃分析工程师，擅长 Android/iOS 原生与跨端栈。回答使用简体中文。

**核心要求**：
1. **只基于提供的事实分析，严禁编造**。不确定的地方标注「待确认」。
2. **对于 native/so 崩溃**（堆栈是 libxxx.so、#xx pc 格式），从信号类型、.so 库作用、触发场景角度分析，不要强行对应业务代码。
3. **对于 Java/Kotlin 异常**，结合堆栈中的类名/方法名和源码片段分析，不要编造未出现的类。
4. **如果提供了源码片段**，请紧密围绕片段内容分析，指出具体行可能的问题。

**输出格式要求**：
直接输出三个部分，不要额外的标题或说明：

【原因分析】
（分析崩溃原因，结合堆栈指向、分布特征、源码定位等信息，给出 2-3 个最可能的原因，按可能性排序）

【修改建议】
（分点给出可操作的修复建议，每条建议具体、可落地）

【代码示例】
（用 Java 代码展示修复方案，如果是 native 崩溃则给出伪代码或防护模式）''';

    final userPrompt = '''【${bizLabel}信息】
错误类型: $errorType
堆栈:
$stackText

${distBuf.toString().trim()}

${sourceBuf.toString().trim()}

请基于以上信息，生成原因分析、修改建议和代码示例。严格按照系统提示中的输出格式。''';

    final reply = await client.chat([
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ]);

    return _parseLlmFixOutput(reply);
  }

  _FixContent? _parseLlmFixOutput(String text) {
    String? grabSection(String marker) {
      final re = RegExp('【${RegExp.escape(marker)}】\\s*\\n', multiLine: true);
      final m = re.firstMatch(text);
      if (m == null) return null;
      final rest = text.substring(m.end);
      final next = RegExp(r'【[^】]+】\s*\n', multiLine: true).firstMatch(rest);
      final end = next?.start ?? rest.length;
      final body = rest.substring(0, end).trim();
      return body.isEmpty ? null : body;
    }

    final reason = grabSection('原因分析');
    final suggestion = grabSection('修改建议');
    final codeSection = grabSection('代码示例');

    final codeExample = _extractFirstCodeBlock(codeSection ?? '');

    if (reason == null && suggestion == null) return null;

    return _FixContent(
      reason: reason ?? '由大模型生成。',
      suggestion: suggestion ?? '由大模型生成修复建议。',
      codeExample: codeExample.isEmpty ? '// 请参考上方修改建议自行补全示例' : codeExample,
    );
  }

  String _extractFirstCodeBlock(String md) {
    final m = RegExp(r'```[a-zA-Z]*\n([\s\S]*?)```').firstMatch(md);
    if (m == null) {
      final cleaned = md.trim();
      if (cleaned.isEmpty) return '';
      return cleaned;
    }
    return (m.group(1) ?? '').trim();
  }

  // -------- 工具方法 --------

  static int? _readInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  /// 错误率可能以小数（0.39）也可能以百分号字符串（0.39%）返回，统一成「百分数数值」。
  static double? _readRate(dynamic v) {
    if (v == null) return null;
    if (v is num) {
      final d = v.toDouble();
      // 接口语义：若 ≤ 1 当作小数；>1 当作已经是百分数（如 0.39 vs 0.39%）。
      return d <= 1 ? d * 100 : d;
    }
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final cleaned = s.endsWith('%') ? s.substring(0, s.length - 1).trim() : s;
    final d = double.tryParse(cleaned);
    if (d == null) return null;
    return d <= 1 ? d * 100 : d;
  }

  static List<_DistEntry> _readDistributionList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <_DistEntry>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final name = (m['OsVersion'] ?? m['SystemVersion'] ?? m['Device'] ?? m['DeviceModel'] ?? m['Brand'] ?? m['Name'] ?? m['Version'] ?? m['Value'] ?? '').toString();
      final count = _readInt(m['Count'] ?? m['ErrorCount'] ?? m['Number']);
      out.add(_DistEntry(name: name, count: count));
    }
    return out;
  }

  static String? _extractStack(Map<String, dynamic> detail) {
    String walk(dynamic x) {
      if (x is Map) {
        final st = x['Stack'] ?? x['stack'] ?? x['StackTrace'];
        if (st != null && st.toString().trim().isNotEmpty) return st.toString();
        for (final v in x.values) {
          final r = walk(v);
          if (r.isNotEmpty) return r;
        }
      } else if (x is List) {
        for (final e in x) {
          final r = walk(e);
          if (r.isNotEmpty) return r;
        }
      }
      return '';
    }
    final s = walk(detail);
    return s.isEmpty ? null : s;
  }

  /// 堆栈前几行（去掉空行、合并换行），供卡片标题里的"类型"字段用，与 skill 样例一致。
  static String _stackHeadLine(String stack, {int maxLines = 3}) {
    final lines = stack
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .take(maxLines)
        .toList();
    return lines.join(' / ');
  }

  String _consoleLink(String bizModule, String digest) {
    // 复用项目里已有的控制台 URL 构造器，自动读取 consoleBaseUrl / consoleIssueUrlTemplate；
    // 用户没配模板时会得到一个可控的占位（consoleLinkForIssue 返回 null）。
    final link = consoleLinkForIssue(config, digest, bizModuleForConsole: bizModule);
    return link ?? 'https://emas.console.aliyun.com/apm/${config.appKey}/';
  }

  String _bizLabel(String bizModule) => switch (bizModule.trim().toLowerCase()) {
        'crash' => '崩溃',
        'lag' => '卡顿',
        'anr' => 'ANR',
        'exception' => '异常',
        'custom' => '自定义异常',
        'network' => '网络错误',
        'pageload' => '页面加载',
        'startup' => '启动性能',
        'memory_leak' => '内存泄漏',
        'memory_alloc' => '内存分配',
        _ => bizModule,
      };

  String _buildFileName(String kind) {
    final ts = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    return '${ts}_emas_${kind}_report.md';
  }

  String _formatRange(int? start, int? end) {
    if (start == null || end == null) return '-';
    String fmt(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    return '${fmt(start)} 至 ${fmt(end)}';
  }

  /// 暴露 LLM 调用工具，便于批量场景下复用。
  LlmClient newLlmClient() {
    return LlmClient(
      baseUrl: config.llmBaseUrl.trim(),
      apiKey: config.llmApiKey.trim(),
      model: config.llmModel.trim(),
      chatCompletionsPath: config.effectiveLlmChatPath,
      httpClient: newOutboundHttpClient(),
    );
  }
}

class GeneratedReport {
  GeneratedReport({
    required this.digestHash,
    required this.fileName,
    required this.markdown,
    required this.bizModule,
    required this.title,
    required this.generatedAt,
  });

  final String digestHash;
  final String fileName;
  final String markdown;
  final String bizModule;
  final String title;
  final DateTime generatedAt;
}

class _DistEntry {
  _DistEntry({required this.name, required this.count});
  final String name;
  final int? count;
}

class _CommitMeta {
  _CommitMeta({required this.hash, required this.author, required this.time, required this.summary});
  final String hash;
  final String author;
  final String time;
  final String summary;
}
class _FixContent {
  _FixContent({required this.reason, required this.suggestion, required this.codeExample});
  final String reason;
  final String suggestion;
  final String codeExample;
}

/// 内置模板（无 LLM 时的兜底；结合分布数据生成更具体的分析）。
class _BuiltinFixTemplate {
  static _FixContent build({
    required String errorType,
    required String stackText,
    required List<_DistEntry> osDist,
    required List<_DistEntry> deviceDist,
    required List<_DistEntry> brandDist,
  }) {
    final t = errorType.toLowerCase();
    final s = stackText.toLowerCase();

    final distAnalysis = _buildDistributionAnalysis(osDist, deviceDist, brandDist);

    if (s.contains('libhwui.so') || t.contains('hwui')) {
      return _FixContent(
        reason: '崩溃位置：libhwui.so（Android 硬件渲染引擎）\n'
            '崩溃类型：Native 崩溃 / 渲染崩溃 / 绘图崩溃\n\n'
            '常见原因：\n'
            '- 自定义 View 绘图逻辑异常（onDraw 写错）\n'
            '- 动画过度 / 内存抖动导致渲染器挂掉\n'
            '- Android 系统版本 bug（尤其是 8.0/9.0/10.0）\n'
            '- GPU 驱动异常 / 设备兼容性问题\n'
            '- 大量图片、画布、纹理未释放'
            '${distAnalysis.isEmpty ? '' : '\n\n分布特征：$distAnalysis'}',
        suggestion: '1. 检查自定义 View 的 onDraw 方法，确保没有空指针和异常\n'
            '2. 减少动画复杂度，避免过度绘制\n'
            '3. 及时释放 Canvas、Bitmap 等资源\n'
            '4. 对不同 Android 版本进行兼容性测试\n'
            '5. 考虑使用硬件加速的替代方案\n'
            '6. 检查是否有内存泄漏导致的内存抖动\n'
            '7. 针对主要影响设备和品牌进行专门测试\n'
            '8. 如果主要集中在特定设备上，考虑添加设备特定的适配代码',
        codeExample: '@Override\n'
            'protected void onDraw(Canvas canvas) {\n'
            '    try {\n'
            '        if (bitmap != null && !bitmap.isRecycled()) {\n'
            '            canvas.drawBitmap(bitmap, 0, 0, paint);\n'
            '        }\n'
            '        if (path != null && !path.isEmpty()) {\n'
            '            canvas.drawPath(path, paint);\n'
            '        }\n'
            '    } catch (Exception e) {\n'
            '        Log.e(TAG, "onDraw error", e);\n'
            '    }\n'
            '}',
      );
    }
    if (t.contains('nullpointerexception')) {
      return _FixContent(
        reason: '空指针异常：访问了 null 对象或未初始化的变量。\n\n'
            '常见原因：\n'
            '- 访问了 null 对象的方法或属性\n'
            '- 未初始化的变量\n'
            '- 方法返回了 null 但没有检查\n'
            '- 异步操作导致对象被提前释放'
            '${distAnalysis.isEmpty ? '' : '\n\n分布特征：$distAnalysis'}',
        suggestion: '1. 在访问对象前添加 null 检查\n'
            '2. 确保变量在使用前已初始化\n'
            '3. 检查方法返回值是否为 null\n'
            '4. 注意异步操作中的对象生命周期\n'
            '5. 使用 Optional 类或空安全操作符\n'
            '6. 添加异常捕获机制\n'
            '7. 针对主要影响设备和版本进行测试',
        codeExample: 'String planId = obj != null ? obj.getPlanId() : null;\n'
            'if (planId != null) {\n'
            '    use(planId);\n'
            '} else {\n'
            '    Log.w(TAG, "planId is null, fallback");\n'
            '    fallback();\n'
            '}',
      );
    }
    if (t.contains('illegalstateexception') && s.contains('start service')) {
      return _FixContent(
        reason: 'Android 12+ 不允许在后台启动 Service，应用在后台时尝试 startService 会崩溃。'
            '${distAnalysis.isEmpty ? '' : '\n\n分布特征：$distAnalysis'}',
        suggestion: '方案1: 使用 WorkManager 替代后台 Service\n'
            '方案2: 使用 startForegroundService() + startForeground()\n'
            '方案3: 在 onDestroy() 中判断应用是否在后台',
        codeExample: 'if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {\n'
            '    context.startForegroundService(intent);\n'
            '} else {\n'
            '    context.startService(intent);\n'
            '}\n'
            '\n'
            '// WorkManager 替代方案\n'
            'WorkManager.getInstance(context).enqueue(\n'
            '    new OneTimeWorkRequest.Builder(MyWorker.class).build());',
      );
    }
    if (t.contains(r'resources$notfoundexception') || t.contains('notfoundexception')) {
      return _FixContent(
        reason: '资源未找到：资源 ID 不存在或资源名称拼写错误。'
            '${distAnalysis.isEmpty ? '' : '\n\n分布特征：$distAnalysis'}',
        suggestion: '1. 检查资源名/ID 是否正确\n'
            '2. 多语言/多分辨率目录下确认资源齐备\n'
            '3. 必要时使用 getIdentifier() 兜底',
        codeExample: 'int resId = getResources().getIdentifier("xxx", "string", getPackageName());\n'
            'view.setText(resId != 0 ? resId : R.string.default_text);',
      );
    }
    if (t.contains('sigtrap') || t.contains('sigsegv') || t.contains('sigabrt')) {
      return _FixContent(
        reason: 'Native 层崩溃：WebView/图形渲染/第三方 native 库常见。'
            '${distAnalysis.isEmpty ? '' : '\n\n分布特征：$distAnalysis'}',
        suggestion: '1. 更新 WebView 到最新版本\n'
            '2. 捕获并上报 native 异常（xCrash 等）\n'
            '3. 评估替换为 X5 WebView\n'
            '4. 检查 JNI 调用',
        codeExample: 'WebView.setWebViewClient(new WebViewClient() {\n'
            '    @Override\n'
            '    public void onReceivedError(WebView view, WebResourceError error) {\n'
            '        Log.e("WebView", "Error: " + error.getDescription());\n'
            '    }\n'
            '});',
      );
    }
    return _FixContent(
      reason: '需要根据具体堆栈信息进一步分析。'
          '${distAnalysis.isEmpty ? '' : '\n\n分布特征：$distAnalysis'}',
      suggestion: '1. 查看堆栈定位具体代码\n'
          '2. 检查相关对象状态\n'
          '3. 添加空检查和异常处理\n'
          '4. 分析崩溃发生的场景和条件\n'
          '5. 检查相关依赖库版本\n'
          '6. 针对主要影响设备、品牌和版本进行测试',
      codeExample: 'try {\n'
          '    // 可能出现问题的代码\n'
          '} catch (Exception e) {\n'
          '    Log.e(TAG, "Error", e);\n'
          '}',
    );
  }

  static String _buildDistributionAnalysis(
    List<_DistEntry> osDist,
    List<_DistEntry> deviceDist,
    List<_DistEntry> brandDist,
  ) {
    final parts = <String>[];

    if (osDist.isNotEmpty) {
      final sorted = [...osDist]..sort((a, b) => (b.count ?? 0).compareTo(a.count ?? 0));
      final top = sorted.first;
      final total = osDist.fold<int>(0, (s, e) => s + (e.count ?? 0));
      if (total > 0 && (top.count ?? 0) / total > 0.6) {
        parts.add('主要集中在 ${top.name.isEmpty ? 'Unknown' : top.name} 系统版本');
      } else if (sorted.length > 3) {
        parts.add('影响多个系统版本（${sorted.length}个）');
      }
    }

    if (brandDist.isNotEmpty) {
      final sorted = [...brandDist]..sort((a, b) => (b.count ?? 0).compareTo(a.count ?? 0));
      final top = sorted.first;
      final total = brandDist.fold<int>(0, (s, e) => s + (e.count ?? 0));
      if (total > 0 && (top.count ?? 0) / total > 0.5) {
        parts.add('主要集中在 ${top.name.isEmpty ? 'Unknown' : top.name} 品牌');
      }
    }

    if (deviceDist.isNotEmpty) {
      final sorted = [...deviceDist]..sort((a, b) => (b.count ?? 0).compareTo(a.count ?? 0));
      final top = sorted.first;
      final total = deviceDist.fold<int>(0, (s, e) => s + (e.count ?? 0));
      if (total > 0 && (top.count ?? 0) / total > 0.5) {
        parts.add('主要集中在 ${top.name.isEmpty ? 'Unknown' : top.name} 机型');
      }
    }

    return parts.join('；');
  }
}
