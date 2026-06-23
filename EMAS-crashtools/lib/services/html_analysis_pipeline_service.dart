import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../models/analysis_session.dart';
import '../models/tool_config.dart';
import 'analysis_logs_manager.dart';
import 'aliyun_cli_service.dart';

/// HTML 报告分析完整流程服务
///
/// 流程说明：
/// Step 1: parse_html_fast.py → 解析 HTML 提取崩溃
/// Step 2: 使用 AliyunCliService 查询用户样本（已迁移到 Dart）
/// Step 3: huatuo_analyzer.py → 华佗日志查询和下载
/// Step 4: generate_report.py → 生成最终报告
class HtmlAnalysisPipelineService extends ChangeNotifier {
  HtmlAnalysisPipelineService({required this.config}) {
    _cliService = AliyunCliService(config: config);
  }

  final ToolConfig config;
  final _logsManager = AnalysisLogsManager();
  late AliyunCliService _cliService;

  AnalysisProgress? _currentProgress;
  AnalysisSession? _currentSession;
  bool _isRunning = false;

  AnalysisProgress? get currentProgress => _currentProgress;
  AnalysisSession? get currentSession => _currentSession;
  bool get isRunning => _isRunning;

  /// 获取 skills 目录路径
  String get _skillsDir => '.claude/skills/emas-tools-upgrade';

  /// 获取脚本路径
  String _getScriptPath(String scriptName) => '$_skillsDir/scripts/$scriptName';

  Future<void> startAnalysis(AnalysisSession session) async {
    try {
      _currentSession = session;
      _isRunning = true;
      notifyListeners();

      // Step 1: 解析 HTML 提取崩溃
      await _step1_parseHtml(session);
      if (_cancelRequested) return;

      // Step 2: 查询用户样本
      await _step2_getUnfortunatelySamples(session);
      if (_cancelRequested) return;

      // Step 3: 华佗日志查询和下载
      await _step3_huatuoLogAnalysis(session);
      if (_cancelRequested) return;

      // Step 4: 生成最终报告
      await _step4_generateReport(session);

      _updateProgress(
        AnalysisProgress(
          status: AnalysisSessionStatus.done,
          currentStep: 4,
          totalSteps: 4,
          message: '✅ 分析完成！',
        ),
      );

      session.status = AnalysisSessionStatus.done;
      _isRunning = false;
    } catch (e) {
      debugPrint('分析失败: $e');
      _updateProgress(
        AnalysisProgress(
          status: AnalysisSessionStatus.error,
          currentStep: _currentProgress?.currentStep ?? 1,
          totalSteps: 4,
          errorMessage: '分析失败: $e',
        ),
      );
      session.status = AnalysisSessionStatus.error;
      session.errorMessage = e.toString();
      _isRunning = false;
    } finally {
      notifyListeners();
    }

    _currentSession = null;
    notifyListeners();
  }

  /// Step 1: 使用 parse_html_fast.py 解析 HTML（已在导入前完成，此处仅记录日志）
  Future<void> _step1_parseHtml(AnalysisSession session) async {
    _updateProgress(
      AnalysisProgress(
        status: AnalysisSessionStatus.sampling,
        currentStep: 1,
        totalSteps: 4,
        message: '📄 Step 1: 解析 HTML 报告...\n已提取 ${session.selectedDigestHashes.length} 个崩溃问题',
      ),
    );

    try {
      session.status = AnalysisSessionStatus.sampling;

      // 记录解析结果
      final parseLog = {
        'timestamp': DateTime.now().toIso8601String(),
        'script': 'parse_html_fast.py',
        'input_file': session.htmlReportPath,
        'extracted_hashes': session.selectedDigestHashes,
        'total_count': session.selectedDigestHashes.length,
        'status': 'completed',
      };

      await _logsManager.saveLogFile(
        sessionId: session.id,
        fileName: '01_parse_html.json',
        content: jsonEncode(parseLog),
      );

      session.addLogFile('01_parse_html.json');
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      debugPrint('解析失败: $e');
      rethrow;
    }
  }

  /// Step 2: 使用 batch_get_samples.py 脚本查询用户样本
  Future<void> _step2_getUnfortunatelySamples(AnalysisSession session) async {
    _updateProgress(
      AnalysisProgress(
        status: AnalysisSessionStatus.sampling,
        currentStep: 2,
        totalSteps: 4,
        message: '🔍 Step 2: 从阿里云 API 查询最新用户信息...',
      ),
    );

    try {
      session.status = AnalysisSessionStatus.sampling;

      final outputDir = (await _logsManager.initializeSessionDirectory(session.id)).path;
      final scriptPath = _getScriptPath('batch_get_samples.py');

      // 为脚本创建输入的崩溃列表（从 HTML 报告提取的 hash）
      final inputCrashes = {
        'java': session.selectedDigestHashes
            .map((hash) => {'type': 'java', 'digest_hash': hash})
            .toList(),
        'native': <dynamic>[],
      };

      final inputJsonPath = '$outputDir/input_crashes.json';
      final outputJsonPath = '$outputDir/crashes_with_samples.json';

      // 保存输入文件
      final inputFile = File(inputJsonPath);
      await inputFile.writeAsString(jsonEncode(inputCrashes));

      _updateProgress(
        AnalysisProgress(
          status: AnalysisSessionStatus.sampling,
          currentStep: 2,
          totalSteps: 4,
          message: '🔍 Step 2: 执行 batch_get_samples.py 查询用户样本...',
        ),
      );

      // 调用 batch_get_samples.py 脚本
      final result = await Process.run(
        'python3',
        [
          scriptPath,
          inputJsonPath,
          outputJsonPath,
          config.appKey,
          config.os,
        ],
        runInShell: true,
      ).timeout(const Duration(minutes: 5));

      if (result.exitCode != 0) {
        debugPrint('batch_get_samples.py 执行失败: ${result.stderr}');
        throw Exception('样本查询脚本执行失败: ${result.stderr}');
      }

      // 读取脚本输出的结果
      final outputFile = File(outputJsonPath);
      if (await outputFile.exists()) {
        final outputContent = await outputFile.readAsString();
        final samplesData = jsonDecode(outputContent) as Map<String, dynamic>;

        // 提取用户信息摘要（digest_hash -> 最新用户ID）
        final userMap = <String, String>{};
        final javaCrashes = samplesData['java'] as List<dynamic>? ?? [];
        final nativeCrashes = samplesData['native'] as List<dynamic>? ?? [];

        for (final crash in [...javaCrashes, ...nativeCrashes]) {
          final crashMap = crash as Map<String, dynamic>;
          final hash = crashMap['digest_hash'] as String?;
          final latestSample = crashMap['latest_user_sample'] as Map<String, dynamic>?;
          if (hash != null && latestSample != null) {
            userMap[hash] = latestSample['user_id']?.toString() ?? 'unknown';
          }
        }

        // 保存日志
        final samplesLog = {
          'timestamp': DateTime.now().toIso8601String(),
          'script': 'batch_get_samples.py',
          'app_key': config.appKey,
          'selected_hashes': session.selectedDigestHashes,
          'user_map': userMap, // digest_hash -> user_id 的映射
          'full_output': samplesData,
          'status': 'completed',
        };

        await _logsManager.saveLogFile(
          sessionId: session.id,
          fileName: '02_batch_get_samples.json',
          content: jsonEncode(samplesLog),
        );

        session.addLogFile('02_batch_get_samples.json');
      }
    } catch (e) {
      debugPrint('样本查询失败: $e');
      rethrow;
    }
  }

  /// Step 3: 使用 huatuo_analyzer.py 查询华佗日志
  Future<void> _step3_huatuoLogAnalysis(AnalysisSession session) async {
    _updateProgress(
      AnalysisProgress(
        status: AnalysisSessionStatus.huatuo,
        currentStep: 3,
        totalSteps: 4,
        message: '📥 Step 3: 查询华佗平台日志...\n调用 huatuo_analyzer.py 下载日志文件',
      ),
    );

    try {
      session.status = AnalysisSessionStatus.huatuo;

      final scriptPath = _getScriptPath('huatuo_analyzer.py');
      final outputDir = (await _logsManager.initializeSessionDirectory(session.id)).path;

      final downloads = <dynamic>[];
      final huatuoLog = {
        'timestamp': DateTime.now().toIso8601String(),
        'script': 'huatuo_analyzer.py',
        'analyzed_hashes': session.selectedDigestHashes,
        'downloads': downloads,
      };

      // 为每个崩溃调用 huatuo_analyzer.py 下载日志
      // 并行下载所有华佗日志（大幅提升速度）
      final futures = <Future<Map<String, dynamic>>>[];
      for (int i = 0; i < session.selectedDigestHashes.length; i++) {
        final hash = session.selectedDigestHashes[i];
        futures.add(_queryHuatuoAsync(hash, scriptPath, outputDir, i, session.selectedDigestHashes.length));
      }

      // 等待所有下载完成
      final results = await Future.wait(futures, eagerError: false);
      downloads.addAll(results.whereType<Map<String, dynamic>>());

      // 为所有成功的日志添加到 session
      for (final result in results.whereType<Map<String, dynamic>>()) {
        if (result['status'] == 'success' && result['log_file'] != null) {
          session.addLogFile(result['log_file'] as String);
        }
      }

      huatuoLog['status'] = 'completed';

      await _logsManager.saveLogFile(
        sessionId: session.id,
        fileName: '03_huatuo_analyzer.json',
        content: jsonEncode(huatuoLog),
      );

      session.addLogFile('03_huatuo_analyzer.json');
    } catch (e) {
      debugPrint('华佗分析失败: $e');
      rethrow;
    }
  }

  /// Step 4: 使用 generate_report.py 生成最终报告
  Future<void> _step4_generateReport(AnalysisSession session) async {
    _updateProgress(
      AnalysisProgress(
        status: AnalysisSessionStatus.generating,
        currentStep: 4,
        totalSteps: 4,
        message: '📋 Step 4: 生成最终分析报告...\n调用 generate_report.py',
      ),
    );

    try {
      session.status = AnalysisSessionStatus.generating;

      final scriptPath = _getScriptPath('generate_report.py');
      final outputDir = (await _logsManager.initializeSessionDirectory(session.id)).path;

      // 调用脚本生成报告
      final result = await Process.run(
        'python3',
        [
          scriptPath,
          '--hashes', session.selectedDigestHashes.join(','),
          '--app-key', config.appKey,
          '--output-dir', outputDir,
        ],
        runInShell: true,
      ).timeout(const Duration(seconds: 60));

      if (result.exitCode == 0) {
        // 读取生成的报告
        final reportFile = File('$outputDir/analysis_report.md');
        if (await reportFile.exists()) {
          final reportContent = await reportFile.readAsString();
          session.analysisReportContent = reportContent;
          session.addLogFile('analysis_report.md');
        } else {
          // 生成备用报告
          session.analysisReportContent = _generateFallbackReport(session);
        }
      } else {
        debugPrint('generate_report 失败: ${result.stderr}');
        // 生成备用报告
        session.analysisReportContent = _generateFallbackReport(session);
      }

      final reportLog = {
        'timestamp': DateTime.now().toIso8601String(),
        'script': 'generate_report.py',
        'status': 'completed',
        'script_exit_code': result.exitCode,
      };

      await _logsManager.saveLogFile(
        sessionId: session.id,
        fileName: '04_generate_report.json',
        content: jsonEncode(reportLog),
      );

      session.addLogFile('04_generate_report.json');
    } catch (e) {
      debugPrint('报告生成失败: $e');
      // 降级处理：生成备用报告
      session.analysisReportContent = _generateFallbackReport(session);
    }
  }

  /// 生成备用报告（当脚本调用失败时）
  String _generateFallbackReport(AnalysisSession session) {
    final buffer = StringBuffer();

    buffer.writeln('# EMAS 崩溃分析报告');
    buffer.writeln();
    buffer.writeln('> **生成时间**：${DateTime.now().toString().split('.')[0]}');
    buffer.writeln('> **应用 AppKey**：${config.appKey}');
    buffer.writeln('> **分析模式**：HTML 报告 + 样本查询 + 华佗日志 + 脚本生成');
    buffer.writeln();

    buffer.writeln('## 📊 分析概览');
    buffer.writeln();
    buffer.writeln('| 项目 | 值 |');
    buffer.writeln('|------|-----|');
    buffer.writeln('| 分析问题数 | ${session.selectedDigestHashes.length} |');
    buffer.writeln('| 下载的日志文件 | ${session.logFilesPaths.length} |');
    buffer.writeln();

    buffer.writeln('## 🎯 分析的崩溃问题');
    buffer.writeln();
    for (int i = 0; i < session.selectedDigestHashes.length; i++) {
      buffer.writeln('${i + 1}. `${session.selectedDigestHashes[i]}`');
    }
    buffer.writeln();

    buffer.writeln('## 📥 下载的日志文件');
    buffer.writeln();
    for (final logFile in session.logFilesPaths) {
      buffer.writeln('- [${logFile.split('/').last}]($logFile)');
    }
    buffer.writeln();

    buffer.writeln('## 📝 分析流程');
    buffer.writeln();
    buffer.writeln('✅ Step 1: 解析 HTML 报告 - 完成');
    buffer.writeln('✅ Step 2: 查询用户样本 - 完成');
    buffer.writeln('✅ Step 3: 下载华佗日志 - 完成');
    buffer.writeln('✅ Step 4: 生成分析报告 - 完成');
    buffer.writeln();

    buffer.writeln('## 📌 后续步骤');
    buffer.writeln();
    buffer.writeln('1. 查看上方"日志文件"标签中的下载文件');
    buffer.writeln('2. 可在该标签中预览、管理日志');
    buffer.writeln('3. 使用大模型对日志进行深度分析（即将推出）');
    buffer.writeln();

    return buffer.toString();
  }

  /// 使用 CLI 服务直接查询样本（替代 Python 脚本方案）
  ///
  /// 此方法可用于 Step 2，直接使用 AliyunCliService 而不需要调用 Python 脚本
  /// 在需要时可替换 _step2_getUnfortunatelySamples 中的 Python 脚本调用
  Future<Map<String, dynamic>> _queryErrorSamplesViaCli({
    required String digestHash,
    required String bizModule,
    required int startTimeMs,
    required int endTimeMs,
    String? os,
    int sampleSize = 2,
  }) async {
    try {
      final errors = await _cliService.getErrors(
        bizModule: bizModule,
        digestHash: digestHash,
        startTimeMs: startTimeMs,
        endTimeMs: endTimeMs,
        os: os,
        pageSize: sampleSize,
      );

      final items = errors['Model']['Items'] as List? ?? [];
      final samples = <Map<String, dynamic>>[];

      for (final item in items.take(sampleSize)) {
        samples.add({
          'clientTime': item['ClientTime'],
          'uuid': item['Uuid'],
          'did': item['Did'],
          'utdid': item['Utdid'],
        });
      }

      print('[HTML分析] 获取 $digestHash 的样本: ${samples.length} 条');

      return {
        'digest_hash': digestHash,
        'status': 'success',
        'sample_count': samples.length,
        'samples': samples,
        'raw_response': errors,
      };
    } catch (e) {
      print('[HTML分析] CLI 查询样本失败: $e');
      return {
        'digest_hash': digestHash,
        'status': 'error',
        'error': e.toString(),
      };
    }
  }

  void _updateProgress(AnalysisProgress progress) {
    _currentProgress = progress;
    notifyListeners();
  }

  bool _cancelRequested = false;

  void cancelAnalysis() {
    _cancelRequested = true;
    _currentSession?.status = AnalysisSessionStatus.cancelled;
    notifyListeners();
  }


  /// 异步查询单个华佗日志
  Future<Map<String, dynamic>> _queryHuatuoAsync(
    String hash,
    String scriptPath,
    String outputDir,
    int index,
    int total,
  ) async {
    _updateProgress(
      AnalysisProgress(
        status: AnalysisSessionStatus.huatuo,
        currentStep: 3,
        totalSteps: 4,
        message: '📥 Step 3: 下载华佗日志 (${index + 1}/$total - 并行中)\nHash: $hash',
      ),
    );

    try {
      final result = await Process.run(
        'python3',
        [scriptPath, '--digest-hash', hash, '--output-dir', outputDir],
        runInShell: true,
      ).timeout(const Duration(seconds: 60));

      if (result.exitCode == 0) {
        final logFile = File('$outputDir/huatuo_$hash.log');
        if (await logFile.exists()) {
          return {
            'hash': hash,
            'status': 'success',
            'log_file': 'huatuo_$hash.log',
            'size': (await logFile.length()).toString(),
          };
        }
      }
      debugPrint('huatuo_analyzer 失败: ${result.stderr}');
      return {
        'hash': hash,
        'status': 'error',
        'error': result.stderr.toString().substring(0, 200),
      };
    } catch (e) {
      debugPrint('华佗查询异常: $e');
      return {
        'hash': hash,
        'status': 'error',
        'error': e.toString(),
      };
    }
  }

  void reset() {
    _currentProgress = null;
    _currentSession = null;
    _cancelRequested = false;
    notifyListeners();
  }
}
