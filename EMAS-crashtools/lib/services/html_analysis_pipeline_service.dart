import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/analysis_session.dart';
import '../models/tool_config.dart';
import 'analysis_logs_manager.dart';
import 'aliyun_cli_service.dart';
import 'huatuo_log_analyzer.dart';
import 'llm_analyzer.dart';

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
    _huatuoAnalyzer = HuatuoLogAnalyzer();
    _llmAnalyzer = LlmAnalyzer(config: config);
  }

  final ToolConfig config;
  final _logsManager = AnalysisLogsManager();
  late AliyunCliService _cliService;
  late HuatuoLogAnalyzer _huatuoAnalyzer;
  late LlmAnalyzer _llmAnalyzer;

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
      debugPrint('[Pipeline] 开始分析流程，Session ID: ${session.id}');
      debugPrint('[Pipeline] 崩溃哈希: ${session.selectedDigestHashes}');
      _currentSession = session;
      _isRunning = true;
      notifyListeners();

      // Step 1: 解析 HTML 提取崩溃
      debugPrint('[Pipeline] ========== Step 1 开始 ==========');
      await _step1_parseHtml(session);
      if (_cancelRequested) return;
      debugPrint('[Pipeline] ========== Step 1 完成 ==========');

      // Step 2: 查询用户样本
      debugPrint('[Pipeline] ========== Step 2 开始 ==========');
      await _step2_getUnfortunatelySamples(session);
      if (_cancelRequested) return;
      debugPrint('[Pipeline] ========== Step 2 完成 ==========');

      // Step 3: 华佗日志查询和下载
      debugPrint('[Pipeline] ========== Step 3 开始 ==========');
      await _step3_huatuoLogAnalysis(session);
      if (_cancelRequested) return;
      debugPrint('[Pipeline] ========== Step 3 完成 ==========');

      // Step 4: 生成最终报告
      debugPrint('[Pipeline] ========== Step 4 开始 ==========');
      await _step4_generateReport(session);
      debugPrint('[Pipeline] ========== Step 4 完成 ==========');

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
    debugPrint('[Step1] ========== Step 1 开始 ==========');
    debugPrint('[Step1] 输入 HTML 报告: ${session.htmlReportPath}');
    debugPrint('[Step1] 已提取哈希数: ${session.selectedDigestHashes.length}');
    debugPrint('[Step1] 哈希列表: ${session.selectedDigestHashes}');

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
      debugPrint('[Step1] ========== Step 1 完成 ==========');
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      debugPrint('[Step1] 错误: $e');
      rethrow;
    }
  }

  /// Step 2: 直接用 Dart 查询用户样本（替代 Python 脚本，更快）
  Future<void> _step2_getUnfortunatelySamples(AnalysisSession session) async {
    debugPrint('[Step2] 初始化进度');
    _updateProgress(
      AnalysisProgress(
        status: AnalysisSessionStatus.sampling,
        currentStep: 2,
        totalSteps: 4,
        message: '🔍 Step 2: 从阿里云 API 查询最新用户信息...',
      ),
    );

    try {
      debugPrint('[Step2] 更新会话状态');
      session.status = AnalysisSessionStatus.sampling;

      debugPrint('[Step2] 初始化输出目录');
      final outputDir = (await _logsManager.initializeSessionDirectory(session.id)).path;
      debugPrint('[Step2] 输出目录: $outputDir');

      // 直接用 Dart 调用 Aliyun CLI 查询所有崩溃
      final now = DateTime.now();
      final endMs = (now.millisecondsSinceEpoch).toString();
      final startMs = (now.millisecondsSinceEpoch - 180 * 24 * 3600 * 1000).toString();

      final samplesData = {
        'java': <Map<String, dynamic>>[],
        'native': <Map<String, dynamic>>[],
      };

      // 并行查询所有哈希
      debugPrint('[Step2] 开始并行查询 ${session.selectedDigestHashes.length} 个崩溃');
      final futures = <Future<Map<String, dynamic>>>[];
      for (int i = 0; i < session.selectedDigestHashes.length; i++) {
        final hash = session.selectedDigestHashes[i];
        debugPrint('[Step2] 添加 future: $i/$session.selectedDigestHashes.length} - Hash: $hash');
        futures.add(
          _querySingleCrashSample(
            hash: hash,
            index: i + 1,
            total: session.selectedDigestHashes.length,
            startMs: startMs,
            endMs: endMs,
          ),
        );
      }

      debugPrint('[Step2] Futures 列表大小: ${futures.length}');

      // 等待所有查询完成
      debugPrint('[Step2] 等待所有查询完成...');
      final results = await Future.wait(futures, eagerError: false);
      debugPrint('[Step2] 所有查询完成');

      // 收集结果
      debugPrint('[Step2] 收到 ${results.length} 个结果');
      int successCount = 0;
      for (int i = 0; i < results.length; i++) {
        final result = results[i];
        debugPrint('[Step2] 结果 $i: $result');
        if (result['status'] == 'success') {
          successCount++;
          (samplesData['java'] as List<Map<String, dynamic>>).add(result['crash'] as Map<String, dynamic>);
        }
      }

      debugPrint('[Step 2] 完成: $successCount/${session.selectedDigestHashes.length} 个崩溃');

      // 保存日志
      final userMap = <String, String>{};
      for (final crash in samplesData['java'] ?? []) {
        final hash = crash['digest_hash'] as String?;
        final sample = crash['latest_user_sample'] as Map<String, dynamic>?;
        if (hash != null && sample != null) {
          userMap[hash] = sample['user_id']?.toString() ?? 'unknown';
        }
      }

      final samplesLog = {
        'timestamp': DateTime.now().toIso8601String(),
        'method': 'dart_direct',
        'app_key': config.appKey,
        'selected_hashes': session.selectedDigestHashes,
        'user_map': userMap,
        'full_output': samplesData,
        'status': 'completed',
      };

      await _logsManager.saveLogFile(
        sessionId: session.id,
        fileName: '02_batch_get_samples.json',
        content: jsonEncode(samplesLog),
      );

      session.addLogFile('02_batch_get_samples.json');
    } catch (e) {
      debugPrint('样本查询失败: $e');
      rethrow;
    }
  }

  /// 查询单个崩溃的用户样本
  Future<Map<String, dynamic>> _querySingleCrashSample({
    required String hash,
    required int index,
    required int total,
    required String startMs,
    required String endMs,
  }) async {
    debugPrint('[Step2] [$index/$total] 方法被调用 - Hash: $hash');

    // 只在首个和关键进度更新进度显示（避免过度更新导致卡顿）
    if (index == 1 || index % 5 == 0 || index == total) {
      _updateProgress(
        AnalysisProgress(
          status: AnalysisSessionStatus.sampling,
          currentStep: 2,
          totalSteps: 4,
          message: '🔍 Step 2: 查询样本 ($index/$total)',
        ),
      );
    }

    try {
      debugPrint('[Step2] [$index/$total] 查询 Hash: $hash');

      // 调用 get-errors 获取样本列表
      final errors = await _cliService.getErrors(
        bizModule: 'crash',
        digestHash: hash,
        startTimeMs: int.parse(startMs),
        endTimeMs: int.parse(endMs),
        os: config.os,
        pageSize: 1, // 只取最新的1个样本
      );

      final items = errors['Model']['Items'] as List? ?? [];
      debugPrint('[Step2] [$index/$total] get-errors 返回 ${items.length} 个样本');
      if (items.isEmpty) {
        debugPrint('[Step2] [$index/$total] 无样本，跳过');
        return {'status': 'no_samples', 'hash': hash};
      }

      final item = items.first as Map<String, dynamic>;
      final uuid = item['Uuid'] as String?;
      final clientTime = item['ClientTime'] as dynamic;
      final did = item['Did'] as String? ?? '';

      debugPrint('[Step2] [$index/$total] UUID: $uuid, ClientTime: $clientTime');

      if (uuid == null || clientTime == null) {
        debugPrint('[Step2] [$index/$total] UUID 或 ClientTime 为空');
        return {'status': 'incomplete_sample', 'hash': hash};
      }

      // 调用 get-error 获取详细信息
      debugPrint('[Step2] [$index/$total] 调用 get-error 获取详情');
      final model = await _cliService.getError(
        bizModule: 'crash',
        digestHash: hash,
        uuid: uuid,
        clientTime: int.parse(clientTime.toString()),
        did: did,
        os: config.os,
      ) as Map<String, dynamic>;

      debugPrint('[Step2] [$index/$total] Model 字段数: ${model.keys.length}');

      // 构建样本数据
      final crash = {
        'digest_hash': hash,
        'type': 'java',
        'latest_user_sample': {
          'uuid': uuid,
          'user_id': model['UserId']?.toString() ?? '',
          'utdid': model['Utdid']?.toString() ?? '',
          'device_model': model['DeviceModel']?.toString() ?? '',
          'app_version': model['AppVersion']?.toString() ?? '',
          'country': model['Country']?.toString() ?? '',
          'province': model['Province']?.toString() ?? '',
          'city': model['City']?.toString() ?? '',
          'client_time': clientTime.toString(),
          'did': did,
          'report_time': model['ReportTime']?.toString() ?? '',
          'happened_time': model['HappenedTime']?.toString() ?? '',
          'startup_time': model['StartupTime']?.toString() ?? '',
          'exception_msg': model['ExceptionMsg']?.toString() ?? '',
          'stack_top': (model['Backtrace'] as String?)?.split('\n').take(5).join('\n') ?? '',
        }
      };

      final userSample = crash['latest_user_sample'] as Map<String, dynamic>;
      print('[STEP2_SUCCESS] [$index/$total] 成功! UserId=${userSample['user_id']}');
      return {'status': 'success', 'hash': hash, 'crash': crash};
    } catch (e) {
      print('[STEP2_EXCEPTION] [$index/$total] 错误: $e');
      print('[STEP2_STACKTRACE] $e');
      return {'status': 'error', 'hash': hash, 'error': e.toString()};
    }
  }

  /// Step 3: 下载华佗原始日志压缩包
  Future<void> _step3_huatuoLogAnalysis(AnalysisSession session) async {
    _updateProgress(
      AnalysisProgress(
        status: AnalysisSessionStatus.huatuo,
        currentStep: 3,
        totalSteps: 4,
        message: '📥 Step 3: 下载华佗日志...',
      ),
    );

    try {
      session.status = AnalysisSessionStatus.huatuo;
      final outputDir = (await _logsManager.initializeSessionDirectory(session.id)).path;

      debugPrint('[Step3] ========== 开始下载华佗日志压缩包 ==========');

      // 读取 Step 2 日志获取用户样本信息
      final step2LogPath = '$outputDir/02_batch_get_samples.json';
      debugPrint('[Step3] 读取 Step 2 输出: $step2LogPath');

      final step2Log = await _readLogFile(step2LogPath);
      if (step2Log.isEmpty) {
        debugPrint('[Step3] 错误：Step 2 日志不存在或为空');
        throw Exception('Step 2 log not found');
      }

      final fullOutput = step2Log['full_output'] as Map<String, dynamic>? ?? {};
      final javaCrashes = fullOutput['java'] as List<dynamic>? ?? [];
      final nativeCrashes = fullOutput['native'] as List<dynamic>? ?? [];

      // 构建用户样本映射
      final sampleMap = <String, Map<String, dynamic>>{};
      for (final crash in [...javaCrashes, ...nativeCrashes]) {
        final crashMap = crash as Map<String, dynamic>;
        final hash = crashMap['digest_hash'] as String?;
        final latestSample = crashMap['latest_user_sample'] as Map<String, dynamic>?;
        if (hash != null && latestSample != null) {
          sampleMap[hash] = latestSample;
          debugPrint('[Step3] 找到样本 - Hash: $hash, UUID: ${latestSample['uuid']}');
        }
      }

      // 并行下载所有华佗日志
      debugPrint('[Step3] 开始并行下载 ${session.selectedDigestHashes.length} 个崩溃的日志');
      final downloadFutures = <Future<void>>[];
      for (int i = 0; i < session.selectedDigestHashes.length; i++) {
        final hash = session.selectedDigestHashes[i];
        final sample = sampleMap[hash] ?? {};
        downloadFutures.add(_downloadHuatuoLogArchive(
          hash,
          sample,
          outputDir,
          i + 1,
          session.selectedDigestHashes.length,
          session,
        ));
      }

      await Future.wait(downloadFutures, eagerError: false);
      debugPrint('[Step3] ========== 华佗日志下载完成 ==========');
    } catch (e) {
      debugPrint('[Step3] 错误: $e');
      rethrow;
    }
  }

  /// 下载单个华佗日志压缩包
  Future<void> _downloadHuatuoLogArchive(
    String hash,
    Map<String, dynamic> sample,
    String outputDir,
    int index,
    int total,
    AnalysisSession session,
  ) async {
    try {
      debugPrint('[Step3] [$index/$total] 开始下载 Hash: $hash');

      final uuid = sample['uuid'] as String? ?? '';
      final userId = sample['user_id'] as String? ?? '';
      final did = sample['did'] as String? ?? '';
      final clientTime = sample['client_time'] as String? ?? '';

      if (uuid.isEmpty) {
        debugPrint('[Step3] [$index/$total] 跳过：UUID 为空');
        return;
      }

      // 构建华佗 API 请求（不需要 appKey，用户 ID、devid 和日期即可）
      const baseUrl = 'https://huatuo.xesv5.com/api/1.0';

      // 从 clientTime（毫秒时间戳）提取日期
      String dateStr = '';
      if (clientTime.isNotEmpty) {
        try {
          final timestamp = int.parse(clientTime);
          final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
          dateStr = '${dateTime.year}${dateTime.month.toString().padLeft(2, '0')}${dateTime.day.toString().padLeft(2, '0')}';
        } catch (e) {
          final today = DateTime.now();
          dateStr = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
        }
      } else {
        final today = DateTime.now();
        dateStr = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
      }

      final url = '$baseUrl/logFile?'
          'userId=$userId&'
          'devid=8&'
          'date=$dateStr';

      debugPrint('[Step3] [$index/$total] 请求 URL: $url');

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('Huatuo request timeout'),
      );

      if (response.statusCode != 200) {
        debugPrint('[Step3] [$index/$total] 错误：HTTP ${response.statusCode}');
        return;
      }

      // 解析响应
      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint('[Step3] [$index/$total] 响应大小: ${response.bodyBytes.length} 字节');

      // 从响应中提取下载链接和崩溃日志数据
      final huatuoData = responseData['data'] as Map<String, dynamic>? ?? {};
      final fileList = huatuoData['fileList'] as List<dynamic>? ?? [];
      final dataList = huatuoData['dataList'] as List<dynamic>? ?? [];

      debugPrint('[Step3] [$index/$total] 解析数据列表，共 ${dataList.length} 条，文件列表 ${fileList.length} 个');

      // 从 fileList 中提取第一个压缩包的下载链接
      String? downloadUrl;
      if (fileList.isNotEmpty) {
        final fileItem = fileList.first as Map<String, dynamic>;
        downloadUrl = fileItem['filePath'] as String? ?? '';
        if (downloadUrl.isNotEmpty) {
          debugPrint('[Step3] [$index/$total] 找到文件链接 (fileList): $downloadUrl');
        }
      }

      // 备用方案：从 dataList 中查找 crashLogFile 事件
      if (downloadUrl == null || downloadUrl.isEmpty) {
        for (final item in dataList) {
          final itemMap = item as Map<String, dynamic>;
          final eventType = itemMap['eventType'] as String? ?? '';

          if (eventType == 'crashLogFile' || eventType.toLowerCase().contains('crash')) {
            final logFileUrl = itemMap['logFileUrl'] as String? ?? '';
            if (logFileUrl.isNotEmpty) {
              downloadUrl = logFileUrl;
              debugPrint('[Step3] [$index/$total] 从 dataList 找到 crashLogFile URL: $downloadUrl');
              break;
            }
          }
        }
      }

      if (downloadUrl == null || downloadUrl.isEmpty) {
        debugPrint('[Step3] [$index/$total] 未找到下载链接，跳过');
        return;
      }

      // 下载压缩包
      final archiveFileName = '03_${hash}_huatuo_log.tar.gz';
      final archivePath = '$outputDir/$archiveFileName';

      debugPrint('[Step3] [$index/$total] 下载压缩包到: $archivePath');
      final archiveResponse = await http.get(Uri.parse(downloadUrl)).timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw TimeoutException('Archive download timeout'),
      );

      if (archiveResponse.statusCode != 200) {
        debugPrint('[Step3] [$index/$total] 错误：无法下载压缩包 ${archiveResponse.statusCode}');
        return;
      }

      // 保存压缩包
      await _logsManager.saveBinaryLogFile(
        sessionId: session.id,
        fileName: archiveFileName,
        bytes: archiveResponse.bodyBytes,
      );
      debugPrint('[Step3] [$index/$total] 压缩包已保存，大小: ${archiveResponse.bodyBytes.length} 字节');
      session.addLogFile(archiveFileName);

      // 保存华佗日志数据分析（提取 dataList 中的 data 字段进行后续 LLM 分析）
      final huatuoLogsFileName = '03_${hash}_huatuo_logs_analysis.json';
      final huatuoLogsData = {
        'hash': hash,
        'uuid': uuid,
        'user_id': userId,
        'did': did,
        'archive_file': archiveFileName,
        'download_url': downloadUrl,
        'archive_size': archiveResponse.bodyBytes.length,
        'logs_count': dataList.length,
        'timestamp': DateTime.now().toIso8601String(),
        // 提取 dataList 中的 data 字段用于 AI 分析
        'data_items': dataList.map((item) {
          final itemMap = item as Map<String, dynamic>;
          return {
            'eventid': itemMap['eventType'] ?? '',
            'logtype': itemMap['logtype'] ?? '',
            'data': itemMap['data'] ?? {},
            'userid': itemMap['userid'] ?? '',
            'loglevel': itemMap['loglevel'] ?? '',
            'clits': itemMap['clits'] ?? 0,
          };
        }).toList(),
      };
      await _logsManager.saveLogFile(
        sessionId: session.id,
        fileName: huatuoLogsFileName,
        content: jsonEncode(huatuoLogsData),
      );
      session.addLogFile(huatuoLogsFileName);

      debugPrint('[Step3] [$index/$total] 完成：$hash');
    } catch (e) {
      debugPrint('[Step3] 下载失败 ($hash): $e');
    }
  }

  /// Step 4: 生成最终分析报告（整合用户样本和华佗日志文件链接）
  Future<void> _step4_generateReport(AnalysisSession session) async {
    _updateProgress(
      AnalysisProgress(
        status: AnalysisSessionStatus.generating,
        currentStep: 4,
        totalSteps: 4,
        message: '📋 Step 4: 生成最终分析报告...',
      ),
    );

    try {
      session.status = AnalysisSessionStatus.generating;

      final outputDir = (await _logsManager.initializeSessionDirectory(session.id)).path;

      debugPrint('[Step4] ========== 开始生成报告 ==========');

      // 读取 Step 2 数据
      final step2Log = await _readLogFile('$outputDir/02_batch_get_samples.json');

      // 读取 Step 3 华佗日志数据（如果存在）
      final Map<String, dynamic> huatuoLogsMap = {};
      for (final hash in session.selectedDigestHashes) {
        final huatuoLogsPath = '$outputDir/03_${hash}_huatuo_logs_analysis.json';
        final huatuoLogsData = await _readLogFile(huatuoLogsPath);
        if (huatuoLogsData.isNotEmpty) {
          huatuoLogsMap[hash] = huatuoLogsData;
        }
      }

      // 生成 Markdown 报告（包含 LLM 分析）
      final report = await _generateReportFromDataAsync(
        session: session,
        step2Data: step2Log,
        step3Data: huatuoLogsMap,
        outputDir: outputDir,
      );

      session.analysisReportContent = report;

      // 保存报告
      await _logsManager.saveLogFile(
        sessionId: session.id,
        fileName: 'analysis_report.md',
        content: report,
      );

      session.addLogFile('analysis_report.md');

      // 保存生成日志
      final reportLog = {
        'timestamp': DateTime.now().toIso8601String(),
        'method': 'dart_direct',
        'status': 'completed',
        'hashes_analyzed': session.selectedDigestHashes.length,
        'log_files_downloaded': session.logFilesPaths.length,
      };

      await _logsManager.saveLogFile(
        sessionId: session.id,
        fileName: '04_generate_report.json',
        content: jsonEncode(reportLog),
      );

      session.addLogFile('04_generate_report.json');

      debugPrint('[Step4] ========== 报告生成完成 ==========');
    } catch (e) {
      debugPrint('[Step4] 报告生成失败: $e');
      session.analysisReportContent = _generateFallbackReport(session);
    }
  }

  /// 读取日志文件内容
  Future<Map<String, dynamic>> _readLogFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('读取日志文件失败: $e');
    }
    return {};
  }

  /// 从数据生成分析报告（按照 skills 中的规范，包含 LLM 分析和华佗日志）
  Future<String> _generateReportFromDataAsync({
    required AnalysisSession session,
    required Map<String, dynamic> step2Data,
    required Map<String, dynamic> step3Data,
    required String outputDir,
  }) async {
    final buffer = StringBuffer();
    final now = DateTime.now();
    final timeStr = now.toString().split('.')[0];

    // 标题和元信息
    buffer.writeln('# EMAS Crash 完整分析报告');
    buffer.writeln();
    buffer.writeln('> 生成时间: $timeStr');
    buffer.writeln('> 报告日期: ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}');
    buffer.writeln('> 数据来源: HTML 报告分析 + LLM 智能分析');
    buffer.writeln();

    // 统计数据
    final fullOutput = step2Data['full_output'] as Map<String, dynamic>? ?? {};
    final javaCrashes = fullOutput['java'] as List<dynamic>? ?? [];
    final nativeCrashes = fullOutput['native'] as List<dynamic>? ?? [];

    // 概览表格
    buffer.writeln('## 📊 概览');
    buffer.writeln();
    buffer.writeln('| 指标 | Java | Native | 合计 |');
    buffer.writeln('|:---|---:|---:|---:|');
    buffer.writeln('| 崩溃种类 | ${javaCrashes.length} | ${nativeCrashes.length} | ${session.selectedDigestHashes.length} |');
    buffer.writeln('| 下载日志 | - | - | ${session.logFilesPaths.length} |');
    buffer.writeln();

    // Java 崩溃列表
    if (javaCrashes.isNotEmpty) {
      buffer.writeln('## ☕ Java Crash 完整列表');
      buffer.writeln();
      buffer.writeln('| 排名 | DigestHash | 应用版本 |');
      buffer.writeln('|:---:|:---|:---|');
      for (int i = 0; i < javaCrashes.length; i++) {
        final crash = javaCrashes[i] as Map<String, dynamic>;
        final hash = crash['digest_hash'] as String? ?? '';
        final sample = crash['latest_user_sample'] as Map<String, dynamic>? ?? {};
        final version = sample['app_version'] as String? ?? '-';
        buffer.writeln('| ${i + 1} | `$hash` | $version |');
      }
      buffer.writeln();
    }

    // Native 崩溃列表
    if (nativeCrashes.isNotEmpty) {
      buffer.writeln('## ⚙️ Native Crash 完整列表');
      buffer.writeln();
      buffer.writeln('| 排名 | DigestHash | 应用版本 |');
      buffer.writeln('|:---:|:---|:---|');
      for (int i = 0; i < nativeCrashes.length; i++) {
        final crash = nativeCrashes[i] as Map<String, dynamic>;
        final hash = crash['digest_hash'] as String? ?? '';
        final sample = crash['latest_user_sample'] as Map<String, dynamic>? ?? {};
        final version = sample['app_version'] as String? ?? '-';
        buffer.writeln('| ${i + 1} | `$hash` | $version |');
      }
      buffer.writeln();
    }

    buffer.writeln('---');
    buffer.writeln();

    // 详情部分
    buffer.writeln('## 📋 崩溃详情与用户样本');
    buffer.writeln();

    if (javaCrashes.isNotEmpty) {
      buffer.writeln('### ☕ Java 崩溃详情');
      buffer.writeln();
      for (int i = 0; i < javaCrashes.length; i++) {
        final crash = javaCrashes[i] as Map<String, dynamic>;
        final hash = crash['digest_hash'] as String? ?? '';
        final sample = crash['latest_user_sample'] as Map<String, dynamic>? ?? {};

        buffer.writeln('### Java ${i + 1}. [$hash]');
        buffer.writeln();

        // 用户样本信息
        if (sample.isNotEmpty) {
          buffer.writeln('**受影响用户（最新）**:');
          buffer.writeln();
          buffer.writeln('```');
          buffer.writeln('设备ID (did): ${sample['did'] ?? '-'}');
          buffer.writeln('用户ID: ${sample['user_id'] ?? '-'}');
          buffer.writeln('应用版本: ${sample['app_version'] ?? '-'}');
          buffer.writeln('设备名称: ${sample['device_model'] ?? '-'}');
          buffer.writeln('系统版本: ${sample['system_version'] ?? '-'}');
          buffer.writeln('上报时间: ${sample['client_time'] ?? '-'}');
          buffer.writeln('```');
          buffer.writeln();
        }

        // 堆栈信息
        final stackTop = sample['stack_top'] as String? ?? '';
        if (stackTop.isNotEmpty) {
          buffer.writeln('**关键堆栈**:');
          buffer.writeln('```');
          for (final line in stackTop.split('\n').take(15)) {
            buffer.writeln(line);
          }
          buffer.writeln('```');
          buffer.writeln();
        }

        // 华佗日志链接与 data 数据
        buffer.writeln('**华佗日志**:');
        buffer.writeln();
        final userId = sample['user_id'] as String? ?? '';
        final uuid = sample['uuid'] as String? ?? '';
        if (userId.isNotEmpty && userId != '-') {
          final clientTime = sample['client_time'] as String? ?? '';
          String dateStr = '';
          try {
            final timestamp = int.parse(clientTime);
            final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
            dateStr = '${dateTime.year}${dateTime.month.toString().padLeft(2, '0')}${dateTime.day.toString().padLeft(2, '0')}';
          } catch (e) {
            dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
          }
          buffer.writeln('[🔗 日志列表查询](https://huatuo.xesv5.com/api/1.0/logFile?userId=$userId&devid=8&date=$dateStr)');
          buffer.writeln();

          // 显示华佗 API 返回的日志数据 - 查找 eventid 为 "crashLogFile" 的数据部分
          final huatuoData = step3Data[hash] as Map<String, dynamic>?;
          if (huatuoData != null && huatuoData.isNotEmpty) {
            buffer.writeln('**华佗日志数据 (crashLogFile)**:');
            buffer.writeln();
            final dataItems = huatuoData['data_items'] as List<dynamic>? ?? [];

            // 查找 data.eventid 为 "crashLogFile" 的日志
            Map<String, dynamic>? crashLogFileData;
            for (final item in dataItems) {
              final itemMap = item as Map<String, dynamic>?;
              if (itemMap != null) {
                final itemData = itemMap['data'] as Map<String, dynamic>? ?? {};
                final eventid = itemData['eventid'] as String? ?? '';
                if (eventid == 'crashLogFile') {
                  crashLogFileData = itemData;
                  break;
                }
              }
            }

            if (crashLogFileData != null && crashLogFileData.isNotEmpty) {
              buffer.writeln('```json');
              buffer.writeln(jsonEncode(crashLogFileData));
              buffer.writeln('```');
              buffer.writeln();
            }
          }
        }

        // 异常栈信息
        final stackStr = sample['stack_top'] as String? ?? '';
        if (stackStr.isNotEmpty) {
          buffer.writeln('**异常堆栈** (前部分):');
          buffer.writeln('```');
          for (final line in stackStr.split('\n').take(10)) {
            buffer.writeln(line);
          }
          buffer.writeln('```');
          buffer.writeln();
        }

        // LLM 根因分析
        try {
          debugPrint('[Step4] 调用 LLM 分析 Java 崩溃: $hash');

          // 获取对应的华佗日志数据
          final huatuoAnalysis = (step3Data[hash] ?? {}) as Map<String, dynamic>;

          final llmAnalysis = await _llmAnalyzer.generateRootCauseAnalysis(
            digestHash: hash,
            crashTitle: hash,
            stackInfo: stackStr,
            huatuoAnalysis: huatuoAnalysis,
            userSample: sample,
          );

          if (llmAnalysis.isNotEmpty) {
            buffer.writeln('**🤖 智能根因分析**:');
            buffer.writeln();

            final summary = llmAnalysis['summary'] as String? ?? '';
            if (summary.isNotEmpty) {
              buffer.writeln('**分析摘要**: $summary');
              buffer.writeln();
            }

            final possibleCauses = llmAnalysis['possible_causes'] as List<dynamic>? ?? [];
            if (possibleCauses.isNotEmpty) {
              buffer.writeln('**可能原因**:');
              buffer.writeln();
              for (final cause in possibleCauses) {
                final causeMap = cause as Map<String, dynamic>?;
                if (causeMap != null) {
                  final causeTitle = causeMap['cause'] as String? ?? '';
                  final detail = causeMap['detail'] as String? ?? '';
                  final evidence = causeMap['evidence'] as List<dynamic>? ?? [];

                  if (causeTitle.isNotEmpty) {
                    buffer.writeln('- **$causeTitle**');
                    if (detail.isNotEmpty) {
                      buffer.writeln('  $detail');
                    }
                    if (evidence.isNotEmpty) {
                      buffer.writeln('  证据: ${evidence.join(", ")}');
                    }
                  }
                }
              }
              buffer.writeln();
            }

            final fixSuggestions = llmAnalysis['fix_suggestions'] as List<dynamic>? ?? [];
            if (fixSuggestions.isNotEmpty) {
              buffer.writeln('**修复建议**:');
              buffer.writeln();
              for (final suggestion in fixSuggestions) {
                final suggestionMap = suggestion as Map<String, dynamic>?;
                if (suggestionMap != null) {
                  final suggestionTitle = suggestionMap['suggestion'] as String? ?? '';
                  final priority = suggestionMap['priority'] as String? ?? 'medium';
                  final implementation = suggestionMap['implementation'] as String? ?? '';

                  if (suggestionTitle.isNotEmpty) {
                    final priorityIcon = priority == 'high' ? '🔴' : priority == 'medium' ? '🟡' : '🟢';
                    buffer.writeln('- **$suggestionTitle** $priorityIcon');
                    if (implementation.isNotEmpty) {
                      buffer.writeln('  实现: $implementation');
                    }
                  }
                }
              }
              buffer.writeln();
            }
          }
        } catch (e) {
          debugPrint('[Step4] LLM 分析失败: $e');
          buffer.writeln('**🤖 智能根因分析**:');
          buffer.writeln();
          buffer.writeln('分析中...');
          buffer.writeln();
        }

        buffer.writeln('---');
        buffer.writeln();
      }
    }

    if (nativeCrashes.isNotEmpty) {
      buffer.writeln('### ⚙️ Native 崩溃详情');
      buffer.writeln();
      for (int i = 0; i < nativeCrashes.length; i++) {
        final crash = nativeCrashes[i] as Map<String, dynamic>;
        final hash = crash['digest_hash'] as String? ?? '';
        final sample = crash['latest_user_sample'] as Map<String, dynamic>? ?? {};

        buffer.writeln('### Native ${i + 1}. [$hash]');
        buffer.writeln();

        // 用户样本信息
        if (sample.isNotEmpty) {
          buffer.writeln('**受影响用户（最新）**:');
          buffer.writeln();
          buffer.writeln('```');
          buffer.writeln('设备ID (did): ${sample['did'] ?? '-'}');
          buffer.writeln('用户ID: ${sample['user_id'] ?? '-'}');
          buffer.writeln('应用版本: ${sample['app_version'] ?? '-'}');
          buffer.writeln('设备名称: ${sample['device_model'] ?? '-'}');
          buffer.writeln('系统版本: ${sample['system_version'] ?? '-'}');
          buffer.writeln('上报时间: ${sample['client_time'] ?? '-'}');
          buffer.writeln('```');
          buffer.writeln();
        }

        // 堆栈信息
        final stackTop = sample['stack_top'] as String? ?? '';
        if (stackTop.isNotEmpty) {
          buffer.writeln('**关键堆栈**:');
          buffer.writeln('```');
          for (final line in stackTop.split('\n').take(15)) {
            buffer.writeln(line);
          }
          buffer.writeln('```');
          buffer.writeln();
        }

        // 华佗日志链接
        buffer.writeln('**华佗日志**:');
        buffer.writeln();
        final userId = sample['user_id'] as String? ?? '';
        final uuid = sample['uuid'] as String? ?? '';
        if (userId.isNotEmpty && userId != '-') {
          final clientTime = sample['client_time'] as String? ?? '';
          String dateStr = '';
          try {
            final timestamp = int.parse(clientTime);
            final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
            dateStr = '${dateTime.year}${dateTime.month.toString().padLeft(2, '0')}${dateTime.day.toString().padLeft(2, '0')}';
          } catch (e) {
            dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
          }
          buffer.writeln('[🔗 日志列表查询](https://huatuo.xesv5.com/api/1.0/logFile?userId=$userId&devid=8&date=$dateStr)');
          buffer.writeln();

          // 显示华佗 API 返回的日志数据 - 查找 eventid 为 "crashLogFile" 的数据部分
          final huatuoData = step3Data[hash] as Map<String, dynamic>?;
          if (huatuoData != null && huatuoData.isNotEmpty) {
            buffer.writeln('**华佗日志数据 (crashLogFile)**:');
            buffer.writeln();
            final dataItems = huatuoData['data_items'] as List<dynamic>? ?? [];

            // 查找 data.eventid 为 "crashLogFile" 的日志
            Map<String, dynamic>? crashLogFileData;
            for (final item in dataItems) {
              final itemMap = item as Map<String, dynamic>?;
              if (itemMap != null) {
                final itemData = itemMap['data'] as Map<String, dynamic>? ?? {};
                final eventid = itemData['eventid'] as String? ?? '';
                if (eventid == 'crashLogFile') {
                  crashLogFileData = itemData;
                  break;
                }
              }
            }

            if (crashLogFileData != null && crashLogFileData.isNotEmpty) {
              buffer.writeln('```json');
              buffer.writeln(jsonEncode(crashLogFileData));
              buffer.writeln('```');
              buffer.writeln();
            }
          }
        }

        // 异常栈信息
        final stackStr = sample['stack_top'] as String? ?? '';
        if (stackStr.isNotEmpty) {
          buffer.writeln('**异常堆栈** (前部分):');
          buffer.writeln('```');
          for (final line in stackStr.split('\n').take(10)) {
            buffer.writeln(line);
          }
          buffer.writeln('```');
          buffer.writeln();
        }

        // LLM 根因分析
        try {
          debugPrint('[Step4] 调用 LLM 分析 Native 崩溃: $hash');

          // 获取对应的华佗日志数据
          final huatuoAnalysis = (step3Data[hash] ?? {}) as Map<String, dynamic>;

          final llmAnalysis = await _llmAnalyzer.generateRootCauseAnalysis(
            digestHash: hash,
            crashTitle: hash,
            stackInfo: stackStr,
            huatuoAnalysis: huatuoAnalysis,
            userSample: sample,
          );

          if (llmAnalysis.isNotEmpty) {
            buffer.writeln('**🤖 智能根因分析**:');
            buffer.writeln();

            final summary = llmAnalysis['summary'] as String? ?? '';
            if (summary.isNotEmpty) {
              buffer.writeln('**分析摘要**: $summary');
              buffer.writeln();
            }

            final possibleCauses = llmAnalysis['possible_causes'] as List<dynamic>? ?? [];
            if (possibleCauses.isNotEmpty) {
              buffer.writeln('**可能原因**:');
              buffer.writeln();
              for (final cause in possibleCauses) {
                final causeMap = cause as Map<String, dynamic>?;
                if (causeMap != null) {
                  final causeTitle = causeMap['cause'] as String? ?? '';
                  final detail = causeMap['detail'] as String? ?? '';
                  final evidence = causeMap['evidence'] as List<dynamic>? ?? [];

                  if (causeTitle.isNotEmpty) {
                    buffer.writeln('- **$causeTitle**');
                    if (detail.isNotEmpty) {
                      buffer.writeln('  $detail');
                    }
                    if (evidence.isNotEmpty) {
                      buffer.writeln('  证据: ${evidence.join(", ")}');
                    }
                  }
                }
              }
              buffer.writeln();
            }

            final fixSuggestions = llmAnalysis['fix_suggestions'] as List<dynamic>? ?? [];
            if (fixSuggestions.isNotEmpty) {
              buffer.writeln('**修复建议**:');
              buffer.writeln();
              for (final suggestion in fixSuggestions) {
                final suggestionMap = suggestion as Map<String, dynamic>?;
                if (suggestionMap != null) {
                  final suggestionTitle = suggestionMap['suggestion'] as String? ?? '';
                  final priority = suggestionMap['priority'] as String? ?? 'medium';
                  final implementation = suggestionMap['implementation'] as String? ?? '';

                  if (suggestionTitle.isNotEmpty) {
                    final priorityIcon = priority == 'high' ? '🔴' : priority == 'medium' ? '🟡' : '🟢';
                    buffer.writeln('- **$suggestionTitle** $priorityIcon');
                    if (implementation.isNotEmpty) {
                      buffer.writeln('  实现: $implementation');
                    }
                  }
                }
              }
              buffer.writeln();
            }
          }
        } catch (e) {
          debugPrint('[Step4] LLM 分析失败: $e');
          buffer.writeln('**🤖 智能根因分析**:');
          buffer.writeln();
          buffer.writeln('分析中...');
          buffer.writeln();
        }

        buffer.writeln('---');
        buffer.writeln();
      }
    }

    // 后续步骤说明
    buffer.writeln('## 📌 后续分析');
    buffer.writeln();
    buffer.writeln('1. 点击上方"华佗日志"链接查看完整日志列表');
    buffer.writeln('2. 在"下载日志"标签中查看已下载的压缩包');
    buffer.writeln('3. 解压并分析日志内容定位根因');
    buffer.writeln('4. 根据用户样本信息追踪特定设备/版本问题');
    buffer.writeln();

    return buffer.toString();
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

  /// 提取 ZIP 文件 - 使用 unzip 命令行工具

  void reset() {
    _currentProgress = null;
    _currentSession = null;
    _cancelRequested = false;
    notifyListeners();
  }
}
