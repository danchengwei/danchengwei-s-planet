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
    this.samples,
  });

  final String digestHash;
  final String title;
  final Map<String, dynamic> issueDetailJson;
  final IssueListItem? listItem;
  final String? listStack;
  final int? startTimeMs;
  final int? endTimeMs;

  /// 可选：从 get-error 获取到的样本详情列表（含 OsVersion/Brand/DeviceModel/AppVersion 等维度）。
  /// 若提供，报告将基于样本统计系统版本/机型/品牌/应用版本分布。
  final List<Map<String, dynamic>>? samples;
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
    final errorName = _firstNonEmpty([
      model['Name'],
      model['ErrorName'],
      model['Title'],
      input.listItem?.errorName,
      input.title,
    ]);
    final errorType = _firstNonEmpty([
      model['Type'],
      model['ErrorType'],
      model['CrashType'],
      input.listItem?.errorType,
      'Unknown',
    ]);
    final errorCount = _readInt(_firstNonNull([
      model['ErrorCount'],
      model['Count'],
      model['TotalCount'],
      model['CrashCount'],
      input.listItem?.errorCount,
    ])) ?? 0;
    final errorDeviceCount = _readInt(_firstNonNull([
      model['ErrorDeviceCount'],
      model['DeviceCount'],
      model['AffectedDeviceCount'],
      model['TotalDeviceCount'],
      input.listItem?.errorDeviceCount,
    ])) ?? 0;
    final errorRate = _readRate(_firstNonNull([
      model['ErrorRate'],
      model['CrashRate'],
      model['Rate'],
      model['IssueCrashRate'],
      input.listItem?.errorRatePercent,
    ]));
    final deviceRate = _readRate(_firstNonNull([
      model['ErrorDeviceRate'],
      model['DeviceRate'],
      model['AffectedDeviceRate'],
      model['IssueDeviceRate'],
      input.listItem?.deviceRatePercent,
    ]));
    final firstVersion = _firstNonEmpty([
      model['FirstVersion'],
      model['FirstSeenVersion'],
      model['FirstAppVersion'],
      input.listItem?.firstVersion,
      '-',
    ]);
    final firstTime = _firstNonEmpty([
      model['FirstTime'],
      model['FirstEventTime'],
      model['FirstSeenTime'],
    ]);
    final latestTime = _firstNonEmpty([
      model['LatestTime'],
      model['LastTime'],
      model['LatestEventTime'],
      model['LastSeenTime'],
      model['EventTime'],
    ]);
    final errorVersionCount = _readInt(_firstNonNull([
      model['ErrorVersionCount'],
      model['VersionCount'],
      model['AffectedVersionCount'],
    ]));
    final issueStatus = _firstNonEmpty([
      model['Status'],
      model['IssueStatus'],
      model['HandleStatus'],
      input.listItem?.issueStatus,
    ]);
    final reason = _firstNonEmpty([
      model['Reason'],
      model['ErrorReason'],
      model['CrashReason'],
    ]);

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
    if (deviceRate != null) {
      buffer.writeln('> - **设备影响率**: ${deviceRate.toStringAsFixed(3)}%');
    }
    buffer.writeln('> - **首现版本**: ${firstVersion.isEmpty ? '-' : firstVersion}');
    if (errorVersionCount != null) {
      buffer.writeln('> - **影响版本数**: $errorVersionCount');
    }
    if (firstTime.isNotEmpty) buffer.writeln('> - **首次时间**: $firstTime');
    if (latestTime.isNotEmpty) buffer.writeln('> - **最近时间**: $latestTime');
    if (issueStatus.isNotEmpty) buffer.writeln('> - **状态**: $issueStatus');
    buffer.writeln('> - **阿里云控制台**: [点击跳转](${_consoleLink(bizModule, hash)})');
    buffer.writeln();

    // EMAS get-issue 返回分布字段（OsDistribution/DeviceDistribution/BrandDistribution/VersionDistribution）；
    // 直接从 model 中读取，兼容多种键名。
    print('[ReportGenerator] model keys: ${model.keys.toList()}');
    final osDist = _readDistributionList(
        model['OsDistribution'] ?? model['SystemVersionDistribution'] ?? model['OsVersionDistribution']);
    final deviceDist = _readDistributionList(
        model['DeviceDistribution'] ?? model['DeviceModelDistribution']);
    final brandDist = _readDistributionList(model['BrandDistribution']);
    final versionDist = _readDistributionList(
        model['VersionDistribution'] ?? model['AppVersionDistribution']);

    _writeOsDistribution(buffer, osDist, errorCount, bizLabel);
    _writeDeviceDistribution(buffer, deviceDist, errorCount, bizLabel);
    _writeBrandDistribution(buffer, brandDist, errorCount, bizLabel);
    _writeVersionDistribution(buffer, versionDist, errorCount, bizLabel);

    buffer.writeln('### 📋 详细堆栈信息');
    buffer.writeln('> **Hash**: `$hash`');
    buffer.writeln('> **$bizLabel类型**: `${errorType.isEmpty ? 'Unknown' : errorType}`');
    if (errorName.isNotEmpty && errorName != errorType && errorName != stackHead) {
      final short = errorName.length > 200 ? '${errorName.substring(0, 200)}…' : errorName;
      buffer.writeln('> **错误名称**: $short');
    } else if (stackHead.isNotEmpty && stackHead != errorType) {
      final short = stackHead.length > 200 ? '${stackHead.substring(0, 200)}…' : stackHead;
      buffer.writeln('> **错误名称**: $short');
    }
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
      buffer.writeln('#### 基于堆栈的推断');
      final parsed = StackParser.parse(stackText);
      if (parsed.applicationCodeLocation != null) {
        final loc = parsed.applicationCodeLocation!;
        buffer.writeln('- 崩溃最上层的业务帧：**${loc.className}.${loc.methodName}**');
        buffer.writeln('- 源文件（来自堆栈）：`${loc.fileName}`${loc.lineNumber > 0 ? '，行号：${loc.lineNumber}' : ''}');
        buffer.writeln('- 建议：在本地仓库中搜索 `${loc.className}` 或 `${loc.fileName}`，定位到对应实现后重点检查该方法的生命周期回调、异步完成时机、对象初始化顺序。');
      } else {
        buffer.writeln('- 堆栈中未识别到明确的业务代码帧，可能以系统/框架/so 调用为主。');
      }
      if (parsed.javaClasses.isNotEmpty) {
        buffer.writeln('- 涉及的 Java/Kotlin 类：${parsed.javaClasses.take(5).join(' / ')}');
      }
      if (parsed.nativeLibraries.isNotEmpty) {
        buffer.writeln('- 涉及的 Native 库：${parsed.nativeLibraries.map((l) => l.name).take(5).join(' / ')}');
      }
      buffer.writeln('- 为提升下次分析的准确度，建议：');
      buffer.writeln('  1. 在「设置」中配置本地项目路径；');
      buffer.writeln('  2. 确保仓库分支与崩溃版本对应；');
      buffer.writeln('  3. 对 Native 崩溃，提前准备 mapping / symbols 文件。');
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
    if (fix.references.trim().isNotEmpty) {
      buffer.writeln('### 🔗 参考链接');
      buffer.writeln(fix.references.trim());
      buffer.writeln();
    }
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
      final type = _firstNonEmpty([
        m['Type'],
        m['ErrorType'],
        m['CrashType'],
        it.listItem?.errorType,
        '-',
      ]);
      final ec = _readInt(_firstNonNull([
        m['ErrorCount'],
        m['Count'],
        m['TotalCount'],
        m['CrashCount'],
        it.listItem?.errorCount,
      ])) ?? 0;
      final ed = _readInt(_firstNonNull([
        m['ErrorDeviceCount'],
        m['DeviceCount'],
        m['AffectedDeviceCount'],
        m['TotalDeviceCount'],
        it.listItem?.errorDeviceCount,
      ])) ?? 0;
      final er = _readRate(_firstNonNull([
        m['ErrorRate'],
        m['CrashRate'],
        m['Rate'],
        m['IssueCrashRate'],
        it.listItem?.errorRatePercent,
      ]));
      final fv = _firstNonEmpty([
        m['FirstVersion'],
        m['FirstSeenVersion'],
        m['FirstAppVersion'],
        it.listItem?.firstVersion,
        '-',
      ]);
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

  void _writeVersionDistribution(StringBuffer buffer, List<_DistEntry> list, int errorCount, String bizLabel) {
    buffer.writeln('### 📦 应用版本分布分析');
    buffer.writeln('| 版本 | $bizLabel次数 | 占比 |');
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
4. **如果提供了源码片段**，请紧密围绕片段内容分析，指出具体行可能的问题；**如果没有提供源码片段**，请基于堆栈和异常类型给出更深入的系统级/框架级推断、排查清单、日志埋点建议以及可搜索的关键字。
5. **分析必须具体、深入、有层次感**，禁止泛泛而谈（如只说「检查空指针」而不说明在哪检查、为什么）。
6. **修改建议必须分步骤、可落地**，包含：修复思路、具体文件/类/方法级改动点、测试与回归策略、线上监控要点。
7. **代码示例必须贴近实际堆栈**：尽量复用堆栈中出现的类名/方法名/变量名，不要给出与当前崩溃无关的通用示例。
8. **必须提供参考链接**：在【参考链接】中列出 2-5 个相关的中文技术文章/官方文档 URL，标题 + 链接。链接必须是真实可访问地址（优先官方文档、阿里云开发者社区、掘金、CSDN、GitHub 仓库），禁止用示例占位符；若不确定具体 URL，可给出对应主题的掘金/阿里云搜索链接或官方文档根地址。

**输出格式要求**：
直接输出以下四个部分，不要额外的标题或说明，不要输出超出这四部分的内容：

【原因分析】
- 按可能性从高到低列出 2-4 个根因假设，每个假设说明：置信度（高/中/低）、直接证据（堆栈哪一行/哪个类/哪个.so/哪个版本）、推断逻辑。
- 若提供了分布数据，说明是否有明显的系统版本/机型/品牌/应用版本聚集特征，并解释其含义。
- 若没有源码，说明为了确认根因还需要补充哪些信息（日志点、复现步骤、符号表、mapping 等）。

【修改建议】
- 分步骤给出修复方案（Step 1 / Step 2 / Step 3）。
- 每个步骤说明：改动位置（类/方法/资源文件）、改动内容、预期效果。
- 最后给出验证方案（如何复现、如何测试、如何灰度观察）和线上监控要点。

【代码示例】
- 给出可直接参考的 Java/Kotlin 代码片段（native 崩溃可用伪代码或 C++ 防护模式）。
- 代码必须围绕堆栈中实际出现的类/方法/变量，不要编造未出现的名称。
- 在关键行用注释说明「为什么这里要这样改」。

【参考链接】
- 列出 2-5 个相关的中文技术文章/官方文档 URL，标题 + 链接。例如：
  - Android 后台启动 Service 限制与适配 - https://developer.android.com/...
  - NullPointerException 排查最佳实践 - https://juejin.cn/...''';

    final hasSource = sourceLookup != null && sourceLookup.sourceFile != null;
    final userPrompt = '''【$bizLabel信息】
错误类型: $errorType
堆栈:
$stackText

${distBuf.toString().trim()}

${sourceBuf.toString().trim()}

${hasSource ? '' : '【补充说明】未提供本地源码，也未命中 Git blame。请基于堆栈和异常类型做尽可能深入的推断：给出系统级/框架级根因假设、排查清单、日志埋点建议、可搜索的关键字，并在【参考链接】中列出 2-5 个权威中文技术博客或官方文档地址，帮助开发者在无源码的情况下继续排查。'}

请基于以上信息，生成原因分析、修改建议、代码示例和参考链接。严格按照系统提示中的输出格式。''';

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
    final references = grabSection('参考链接');

    final codeExample = _extractFirstCodeBlock(codeSection ?? '');

    if (reason == null && suggestion == null) return null;

    return _FixContent(
      reason: reason ?? '由大模型生成。',
      suggestion: suggestion ?? '由大模型生成修复建议。',
      codeExample: codeExample.isEmpty ? '// 请参考上方修改建议自行补全示例' : codeExample,
      references: references ?? '',
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

  static String _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      if (c == null) continue;
      final s = c.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static dynamic _firstNonNull(List<dynamic> candidates) {
    for (final c in candidates) {
      if (c != null) return c;
    }
    return null;
  }

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
      final name = (m['OsVersion'] ??
              m['SystemVersion'] ??
              m['Device'] ??
              m['DeviceModel'] ??
              m['Brand'] ??
              m['AppVersion'] ??
              m['Name'] ??
              m['Version'] ??
              m['Value'] ??
              '')
          .toString();
      final count = _readInt(m['Count'] ?? m['ErrorCount'] ?? m['Number']);
      if (name.isNotEmpty) {
        out.add(_DistEntry(name: name, count: count));
      }
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
  _FixContent({
    required this.reason,
    required this.suggestion,
    required this.codeExample,
    this.references = '',
  });
  final String reason;
  final String suggestion;
  final String codeExample;
  final String references;
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
        suggestion: 'Step 1：定位堆栈中最后一个业务自定义 View 或 Activity/Fragment，检查其 onDraw / dispatchDraw 是否使用了已回收 Bitmap、空 Path 或未初始化 Paint。\n'
            'Step 2：在自定义 View 的绘制入口增加 try-catch 兜底，避免单个 View 绘错拖垮整个渲染线程。\n'
            'Step 3：检查动画复杂度与图片加载策略，避免在主线程解码大图、频繁创建 Bitmap；对动图/复杂动画启用硬件加速或降级策略。\n'
            'Step 4：针对崩溃聚集的系统版本/机型（如华为、小米特定型号）做兼容性测试，必要时关闭硬件加速或降级渲染路径。\n'
            'Step 5：上线后观察该 digest 的崩溃率与影响设备数是否下降，并监控 GPU 内存占用。',
        codeExample: '@Override\n'
            'protected void onDraw(Canvas canvas) {\n'
            '    // 兜底：绘制异常不应导致整个 Surface 崩溃\n'
            '    try {\n'
            '        super.onDraw(canvas);\n'
            '        if (bitmap != null && !bitmap.isRecycled()) {\n'
            '            canvas.drawBitmap(bitmap, 0, 0, paint);\n'
            '        }\n'
            '        if (path != null && !path.isEmpty()) {\n'
            '            canvas.drawPath(path, paint);\n'
            '        }\n'
            '    } catch (Exception e) {\n'
            '        Log.e(TAG, "onDraw error in " + getClass().getSimpleName(), e);\n'
            '        // 可选：上报自定义异常，便于后续定位具体 View\n'
            '    }\n'
            '}',
        references: '- Android 硬件加速与自定义 View 绘制最佳实践 - https://developer.android.com/develop/ui/views/custom-objects/custom-drawing\n'
            '- libhwui.so 崩溃排查思路 - https://juejin.cn/search?query=libhwui.so%20%E5%B4%A9%E6%BA%83\n'
            '- Android Bitmap 回收与内存抖动 - https://developer.android.com/topic/performance/graphics/manage-memory',
      );
    }
    if (t.contains('nullpointerexception')) {
      final loc = _extractTopAppFrame(stackText);
      return _FixContent(
        reason: '空指针异常：代码在 `${loc.className}.${loc.methodName}` 附近访问了 null 引用，而引用目标尚未初始化或已被置空。\n\n'
            '常见原因（按置信度排序）：\n'
            '- 高：异步回调/生命周期回调中使用了已被销毁的 Activity/Fragment/View\n'
            '- 高：方法返回 null 时未做防御性判断（如 findViewById、getIntent().getExtras()）\n'
            '- 中：多线程场景下对象被其它线程释放\n'
            '- 中：特定系统版本/机型下初始化时序不一致'
            '${distAnalysis.isEmpty ? '' : '\n\n分布特征：$distAnalysis'}',
        suggestion: 'Step 1：在 `${loc.className}.${loc.methodName}` 的入口处，对堆栈指向的行号附近的每个对象引用做 null 检查；优先检查来自异步回调、Intent、Bundle、findViewById 的返回值。\n'
            'Step 2：若崩溃发生在生命周期方法（onCreate/onStart/onResume/onDestroy），使用 `isAdded()` / `isFinishing()` / `getActivity() != null` 等状态保护。\n'
            'Step 3：对可能为 null 的字段采用懒加载或默认值兜底；Kotlin 项目优先使用 `?.let { }` / `?: return` / Elvis 操作符。\n'
            'Step 4：补充日志埋点：在关键分支打印对象 hashCode 与生命周期状态，便于线上复现。\n'
            'Step 5：在灰度环境验证后全量，持续观察该 digest 的次数与影响设备数。',
        codeExample: '// 在 ${loc.className}.${loc.methodName} 入口增加防御\n'
            'public void ${loc.methodName}(Bundle args) {\n'
            '    // 1. 对生命周期/异步来源的对象先判空\n'
            '    if (args == null || !isAdded() || getActivity() == null || getActivity().isFinishing()) {\n'
            '        Log.w(TAG, "skip ${loc.methodName}: invalid state");\n'
            '        return;\n'
            '    }\n'
            '    // 2. 对方法返回值做防御\n'
            '    String value = args.getString("key");\n'
            '    if (TextUtils.isEmpty(value)) {\n'
            '        value = ""; // 或上报异常\n'
            '    }\n'
            '    // 3. 真正使用 value\n'
            '    doSomething(value);\n'
            '}',
        references: '- NullPointerException 排查最佳实践 - https://developer.android.com/reference/java/lang/NullPointerException\n'
            '- Android 生命周期与空指针防护 - https://juejin.cn/search?query=Android%20%E7%94%9F%E5%91%BD%E5%91%A8%E6%9C%9F%20%E7%A9%BA%E6%8C%87%E9%92%88\n'
            '- Kotlin 空安全机制 - https://kotlinlang.org/docs/null-safety.html',
      );
    }
    if (t.contains('illegalstateexception') && s.contains('start service')) {
      return _FixContent(
        reason: 'Android 8.0（API 26）及以上对后台启动 Service 做了限制；应用在非前台状态调用 `Context.startService(Intent)` 会抛出 IllegalStateException。'
            '${distAnalysis.isEmpty ? '' : '\n\n分布特征：$distAnalysis'}',
        suggestion: 'Step 1：定位所有调用 `startService` 的代码，将其替换为 `ContextCompat.startForegroundService(context, intent)`，并在 Service.onCreate() 中 5 秒内调用 `startForeground(id, notification)`。\n'
            'Step 2：若任务可延迟执行，使用 WorkManager/JobScheduler 替代 Service，避免受后台启动限制。\n'
            'Step 3：在启动 Service 前判断应用是否在前台（如 ProcessLifecycleOwner/ActivityLifecycleCallbacks），后台场景走 WorkManager 分支。\n'
            'Step 4：对通知渠道、notification 布局做兼容性测试；缺少通知渠道会导致 startForeground 失败。\n'
            'Step 5：灰度验证 targetSdkVersion >= 26 的设备，重点观察后台任务是否被系统回收。',
        codeExample: 'public static void safeStartService(Context context, Intent intent) {\n'
            '    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {\n'
            '        // Android 8+ 必须走前台 Service，并在 Service 内 5s 调用 startForeground\n'
            '        ContextCompat.startForegroundService(context, intent);\n'
            '    } else {\n'
            '        context.startService(intent);\n'
            '    }\n'
            '}\n'
            '\n'
            '// Service 内必须立即提升为前台\n'
            '@Override\n'
            'public void onCreate() {\n'
            '    super.onCreate();\n'
            '    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {\n'
            '        NotificationChannel channel = new NotificationChannel(\n'
            '                "sync", "后台同步", NotificationManager.IMPORTANCE_LOW);\n'
            '        ((NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE))\n'
            '                .createNotificationChannel(channel);\n'
            '        Notification notification = new NotificationCompat.Builder(this, "sync")\n'
            '                .setContentTitle("正在同步")\n'
            '                .setSmallIcon(R.drawable.ic_sync)\n'
            '                .build();\n'
            '        startForeground(1, notification);\n'
            '    }\n'
            '}',
        references: '- Android 后台启动 Service 限制 - https://developer.android.com/about/versions/oreo/background-location-limits\n'
            '- startForegroundService 适配实践 - https://juejin.cn/search?query=Android%20startForegroundService%20%E9%80%82%E9%85%8D\n'
            '- WorkManager 官方文档 - https://developer.android.com/topic/libraries/architecture/workmanager',
      );
    }
    if (t.contains(r'resources$notfoundexception') || t.contains('notfoundexception')) {
      return _FixContent(
        reason: 'Resources.NotFoundException：运行时通过 `Resources.getXxx(id)` 或 `getIdentifier()` 获取了不存在的资源 ID，常见原因包括：R 文件与打包产物不一致、动态加载插件资源失败、多语言/多分辨率目录缺少对应资源、混淆后资源名被裁剪。'
            '${distAnalysis.isEmpty ? '' : '\n\n分布特征：$distAnalysis'}',
        suggestion: 'Step 1：检查堆栈中使用的资源 ID 对应的 R.xxx.yyy，确认该资源在 `res/` 各配置目录下均存在；对矢量图/动画资源检查 minSdk 兼容性。\n'
            'Step 2：若使用插件化/热修复，确认资源加载路径与 AssetManager 注入时机正确，插件资源未按需加载时 fallback 到宿主默认资源。\n'
            'Step 3：对 `getIdentifier()` 等动态资源访问增加 0 值检查与默认值兜底。\n'
            'Step 4：检查 `shrinkResources` / `resguard` 配置，必要时在 keep.xml 中保留被反射/动态使用的资源。\n'
            'Step 5：在主要崩溃机型/系统版本上回归测试资源加载路径。',
        codeExample: '// 对动态资源访问增加兜底\n'
            'int resId = getResources().getIdentifier("dynamic_name", "string", getPackageName());\n'
            'if (resId == 0) {\n'
            '    // 0 表示资源未找到，使用默认资源并上报\n'
            '    resId = R.string.default_text;\n'
            '    reportMissingResource("dynamic_name");\n'
            '}\n'
            'textView.setText(resId);\n'
            '\n'
            '// 插件资源加载时增加保护\n'
            'public Drawable loadPluginDrawable(String packageName, int resId) {\n'
            '    try {\n'
            '        return pluginResources.getDrawable(resId, null);\n'
            '    } catch (Resources.NotFoundException e) {\n'
            '        Log.e(TAG, "plugin resource not found: " + packageName + "/" + resId);\n'
            '        return ContextCompat.getDrawable(this, R.drawable.placeholder);\n'
            '    }\n'
            '}',
        references: '- Android Resources.NotFoundException 排查 - https://developer.android.com/reference/android/content/res/Resources.NotFoundException\n'
            '- shrinkResources 与 keep 资源 - https://developer.android.com/studio/build/shrink-code\n'
            '- 插件化资源加载原理 - https://juejin.cn/search?query=Android%20%E6%8F%92%E4%BB%B6%E5%8C%96%20%E8%B5%84%E6%BA%90%E5%8A%A0%E8%BD%BD',
      );
    }
    if (t.contains('sigtrap') || t.contains('sigsegv') || t.contains('sigabrt')) {
      return _FixContent(
        reason: 'Native 层崩溃（信号：${errorType.isEmpty ? 'SIGSEGV/SIGABRT/SIGTRAP' : errorType}）：崩溃发生在 native 代码，常见责任方包括 WebView、图形渲染库（libhwui/libGLES）、第三方 so（如音视频、地图、支付 SDK）、JNI 调用不当或内存越界。'
            '${distAnalysis.isEmpty ? '' : '\n\n分布特征：$distAnalysis'}',
        suggestion: 'Step 1：确认崩溃帧所在的 `.so` 文件名与偏移，判断是系统库还是业务引入的第三方库；若是业务 so，准备对应版本的 symbols 文件还原行号。\n'
            'Step 2：若堆栈中出现 `libwebviewchromium.so` / `libwebcore.so`，升级 WebView 内核到 Google Play / 系统最新版，或评估腾讯 X5 / 华为 Petal 等替代方案。\n'
            'Step 3：检查 JNI 层指针生命周期、数组越界、多线程访问；对 C/C++ 层新增边界检查与信号捕获（如 xCrash、Breakpad）。\n'
            'Step 4：针对分布中聚集的机型/系统版本，在对应真机或云测平台复现；若是特定 ROM 行为差异，增加版本/机型灰度开关。\n'
            'Step 5：灰度期间监控 native 崩溃率、影响设备数、so 库版本分布，确认修复有效后再全量。',
        codeExample: '// WebView 错误兜底与回收保护\n'
            'webView.setWebViewClient(new WebViewClient() {\n'
            '    @Override\n'
            '    public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {\n'
            '        super.onReceivedError(view, request, error);\n'
            '        Log.e(TAG, "WebView error: " + request.getUrl() + " desc=" + error.getDescription());\n'
            '        // 可在此处降级到 H5 或重试\n'
            '    }\n'
            '});\n'
            '\n'
            '// 销毁时彻底释放，减少 native 层 dangling pointer\n'
            'public void destroyWebView(WebView webView) {\n'
            '    if (webView == null) return;\n'
            '    webView.stopLoading();\n'
            '    webView.loadDataWithBaseURL(null, "", "text/html", "utf-8", null);\n'
            '    webView.clearHistory();\n'
            '    ((ViewGroup) webView.getParent()).removeView(webView);\n'
            '    webView.destroy();\n'
            '}',
        references: '- Android Native Crash 分析入门 - https://juejin.cn/search?query=Android%20Native%20Crash%20%E5%88%86%E6%9E%90\n'
            '- Android WebView 崩溃与适配 - https://developer.android.com/develop/ui/views/layout/webapps/webview\n'
            '- xCrash Native 崩溃捕获 - https://github.com/iqiyi/xCrash',
      );
    }
    final loc = _extractTopAppFrame(stackText);
    return _FixContent(
      reason: '当前崩溃类型 `${errorType.isEmpty ? '未知' : errorType}` 未命中内置模板，需要结合完整堆栈进一步分析。'
          '${loc.className.isNotEmpty ? '堆栈最上层业务帧疑似为 `${loc.className}.${loc.methodName}`，建议优先从这里入手。' : '堆栈中未识别出明确业务帧，建议先确认是系统框架还是第三方 SDK 导致。'}'
          '${distAnalysis.isEmpty ? '' : '\n\n分布特征：$distAnalysis'}',
      suggestion: 'Step 1：在本地仓库中搜索 `${loc.className}` / `${loc.methodName}` / `${loc.fileName}`，定位到具体实现；若未配置本地项目路径，可在 EMAS 控制台查看原始堆栈与符号化后的行号。\n'
          'Step 2：结合错误类型与堆栈上下文，判断是生命周期、异步回调、资源加载、JNI 调用还是第三方 SDK 问题。\n'
          'Step 3：在关键路径增加防御性代码（判空、try-catch、状态检查、默认值兜底）并补充日志埋点。\n'
          'Step 4：在分布聚集的系统版本/机型/品牌上做针对性复现；若是特定 ROM 问题，考虑灰度开关或降级策略。\n'
          'Step 5：修复后通过灰度发布验证崩溃率下降，并持续监控至少一个完整发布周期。',
      codeExample: '// 通用防御性模板：在 ${loc.className}.${loc.methodName} 关键路径增加保护\n'
          'public void ${loc.methodName.isEmpty ? 'suspectedMethod' : loc.methodName}() {\n'
          '    // 1. 前置状态检查\n'
          '    if (!isValidState()) {\n'
          '        Log.w(TAG, "skip due to invalid state");\n'
          '        return;\n'
          '    }\n'
          '    try {\n'
          '        // 2. 实际业务逻辑\n'
          '        doBusiness();\n'
          '    } catch (Exception e) {\n'
          '        // 3. 兜底：记录异常并优雅降级，避免崩溃\n'
          '        Log.e(TAG, "business error in ${loc.methodName}", e);\n'
          '        fallback();\n'
          '    }\n'
          '}',
      references: '- EMAS 崩溃分析最佳实践 - https://help.aliyun.com/zh/emas/user-guide/crash-analysis\n'
          '- Android 异常捕获与降级策略 - https://developer.android.com/reference/java/lang/Thread.UncaughtExceptionHandler\n'
          '- 掘金 Android 崩溃治理专栏 - https://juejin.cn/search?query=Android%20%E5%B4%A9%E6%BA%83%E6%B2%BB%E7%90%86',
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

/// 从堆栈中提取最上层疑似业务代码帧，用于内置模板生成更贴切的示例。
({String className, String methodName, String fileName}) _extractTopAppFrame(String stackText) {
  final parsed = StackParser.parse(stackText);
  final app = parsed.applicationCodeLocation;
  if (app != null) {
    return (className: app.className, methodName: app.methodName, fileName: app.fileName);
  }
  if (parsed.javaClasses.isNotEmpty) {
    final cls = parsed.javaClasses.first;
    final lines = stackText.split('\n');
    String method = '';
    for (final line in lines) {
      if (line.contains(cls) && line.contains('.')) {
        final parts = line.split('.');
        if (parts.length >= 2) {
          method = parts.last.split('(').first.trim();
        }
        break;
      }
    }
    return (className: cls, methodName: method, fileName: '');
  }
  return (className: '', methodName: '', fileName: '');
}
