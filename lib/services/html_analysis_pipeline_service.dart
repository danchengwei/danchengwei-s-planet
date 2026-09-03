import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/analysis_session.dart';
import '../models/tool_config.dart';
import 'analysis_logs_manager.dart';
import 'aliyun_cli_service.dart';
import 'archive_manager.dart';
import 'crash_analysis_agent_service.dart';
import 'huatuo_log_analyzer.dart';

/// 用户主动取消分析时抛出。
class AnalysisCancelledException implements Exception {
  @override
  String toString() => '分析已被用户取消';
}

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
    _crashAnalysisAgent = CrashAnalysisAgentService(config: config);
  }

  final ToolConfig config;
  final _logsManager = AnalysisLogsManager();
  late AliyunCliService _cliService;
  late HuatuoLogAnalyzer _huatuoAnalyzer;
  late CrashAnalysisAgentService _crashAnalysisAgent;

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

      // 初始化进度为 0%
      _updateProgress(
        AnalysisProgress(
          status: AnalysisSessionStatus.sampling,
          currentStep: 0,
          totalSteps: 4,
          message: '🚀 准备开始分析...',
        ),
      );
      notifyListeners();

      // Step 1: 解析 HTML 提取崩溃
      debugPrint('[Pipeline] ========== Step 1 开始 ==========');
      await _step1_parseHtml(session);
      _checkCancelled();
      debugPrint('[Pipeline] ========== Step 1 完成 ==========');

      // Step 2: 查询用户样本
      debugPrint('[Pipeline] ========== Step 2 开始 ==========');
      await _step2_getUnfortunatelySamples(session);
      _checkCancelled();
      debugPrint('[Pipeline] ========== Step 2 完成 ==========');

      // Step 3: 华佗日志查询和下载
      debugPrint('[Pipeline] ========== Step 3 开始 ==========');
      await _step3_huatuoLogAnalysis(session);
      _checkCancelled();
      debugPrint('[Pipeline] ========== Step 3 完成 ==========');

      // Step 4: 生成最终报告
      debugPrint('[Pipeline] ========== Step 4 开始 ==========');
      await _step4_generateReport(session);
      _checkCancelled();
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
    } on AnalysisCancelledException {
      debugPrint('[Pipeline] 用户取消分析');
      _updateProgress(
        AnalysisProgress(
          status: AnalysisSessionStatus.cancelled,
          currentStep: _currentProgress?.currentStep ?? 1,
          totalSteps: 4,
          message: '⏹️ 分析已取消',
        ),
      );
      session.status = AnalysisSessionStatus.cancelled;
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

      // 调用 get-errors 获取样本列表（取最新多个，供后续逐个查找华佗日志）
      final errors = await _cliService.getErrors(
        bizModule: 'crash',
        digestHash: hash,
        startTimeMs: int.parse(startMs),
        endTimeMs: int.parse(endMs),
        os: config.os,
        pageSize: 4, // 取最新 4 个样本作为候选
      );

      final items = errors['Model']['Items'] as List? ?? [];
      debugPrint('[Step2] [$index/$total] get-errors 返回 ${items.length} 个样本');
      if (items.isEmpty) {
        debugPrint('[Step2] [$index/$total] 无样本，跳过');
        return {'status': 'no_samples', 'hash': hash};
      }

      // 逐个样本调用 get-error 获取详情，组装候选样本列表
      final candidateSamples = <Map<String, dynamic>>[];
      final samples = <Map<String, dynamic>>[];
      for (final rawItem in items) {
        final item = rawItem as Map<String, dynamic>;
        final uuid = item['Uuid'] as String?;
        final clientTime = item['ClientTime'] as dynamic;
        final did = item['Did'] as String? ?? '';

        if (uuid == null || clientTime == null) {
          debugPrint('[Step2] [$index/$total] UUID 或 ClientTime 为空，跳过该样本');
          continue;
        }

        // 调用 get-error 获取详细信息
        Map<String, dynamic> model;
        try {
          model = await _cliService.getError(
            bizModule: 'crash',
            digestHash: hash,
            uuid: uuid,
            clientTime: int.parse(clientTime.toString()),
            did: did,
            os: config.os,
          ) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('[Step2] [$index/$total] get-error 失败 (uuid=$uuid): $e');
          continue;
        }

        final userSample = {
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
          // 完整堆栈（不截断），供报告展示与 Agent 分析
          'stack_top': (model['Backtrace'] as String?) ?? '',
          'backtrace_full': (model['Backtrace'] as String?) ?? '',
        };

        candidateSamples.add(userSample);
        samples.add({
          'uuid': uuid,
          'user_id': model['UserId']?.toString() ?? '',
          'did': did,
          'app_version': model['AppVersion']?.toString() ?? '',
          'device_model': model['DeviceModel']?.toString() ?? '',
          'os_version': model['OsVersion']?.toString() ?? '',
          'client_time': clientTime.toString(),
        });
      }

      if (candidateSamples.isEmpty) {
        debugPrint('[Step2] [$index/$total] 无有效样本，跳过');
        return {'status': 'incomplete_sample', 'hash': hash};
      }

      debugPrint('[Step2] [$index/$total] 获取到 ${candidateSamples.length} 个候选样本');

      // 调用 get-issue 获取崩溃统计数据（错误次数、影响设备等）
      Map<String, dynamic> issueStats = {};
      try {
        debugPrint('[Step2] [$index/$total] 调用 get-issue 获取统计数据');
        final issueResult = await _cliService.getIssue(
          bizModule: 'crash',
          digestHash: hash,
          startTimeMs: int.parse(startMs),
          endTimeMs: int.parse(endMs),
          os: config.os,
        );
        issueStats = issueResult is Map ? Map<String, dynamic>.from(issueResult) : {};
        debugPrint('[Step2] [$index/$total] get-issue 成功，字段数: ${issueStats.keys.length}');
      } catch (e) {
        debugPrint('[Step2] [$index/$total] get-issue 失败: $e');
      }

      final errorCount = _readInt(_firstNonNull([
        issueStats['ErrorCount'],
        issueStats['Count'],
        issueStats['TotalCount'],
        issueStats['CrashCount'],
      ]));
      final errorDeviceCount = _readInt(_firstNonNull([
        issueStats['ErrorDeviceCount'],
        issueStats['DeviceCount'],
        issueStats['AffectedDeviceCount'],
        issueStats['TotalDeviceCount'],
      ]));
      final errorRate = _readDouble(_firstNonNull([
        issueStats['ErrorRate'],
        issueStats['CrashRate'],
        issueStats['Rate'],
        issueStats['IssueCrashRate'],
      ]));
      final deviceRate = _readDouble(_firstNonNull([
        issueStats['ErrorDeviceRate'],
        issueStats['DeviceRate'],
        issueStats['AffectedDeviceRate'],
        issueStats['IssueDeviceRate'],
      ]));
      final firstVersion = _firstNonEmpty([
        issueStats['FirstVersion'],
        issueStats['FirstSeenVersion'],
        issueStats['FirstAppVersion'],
      ]);
      final firstTime = _firstNonEmpty([
        issueStats['FirstTime'],
        issueStats['FirstEventTime'],
        issueStats['FirstSeenTime'],
      ]);
      final latestTime = _firstNonEmpty([
        issueStats['LatestTime'],
        issueStats['LastTime'],
        issueStats['LatestEventTime'],
        issueStats['LastSeenTime'],
        issueStats['EventTime'],
      ]);
      final errorVersionCount = _readInt(_firstNonNull([
        issueStats['ErrorVersionCount'],
        issueStats['VersionCount'],
        issueStats['AffectedVersionCount'],
      ]));
      final name = _firstNonEmpty([
        issueStats['Name'],
        issueStats['ErrorName'],
        issueStats['Title'],
      ]);
      final type = _firstNonEmpty([
        issueStats['Type'],
        issueStats['ErrorType'],
        issueStats['CrashType'],
        'java',
      ]);
      final status = _firstNonEmpty([
        issueStats['Status'],
        issueStats['IssueStatus'],
        issueStats['HandleStatus'],
      ]);
      final reason = _firstNonEmpty([
        issueStats['Reason'],
        issueStats['ErrorReason'],
        issueStats['CrashReason'],
      ]);

      final osDist = issueStats['OsDistribution'] ?? issueStats['SystemVersionDistribution'] ?? [];
      final deviceDist = issueStats['DeviceDistribution'] ?? issueStats['DeviceModelDistribution'] ?? [];
      final brandDist = issueStats['BrandDistribution'] ?? [];

      // 构建样本数据
      final crash = {
        'digest_hash': hash,
        'type': type,
        'title': name,
        'error_count': errorCount ?? 0,
        'affected_devices': errorDeviceCount ?? 0,
        'error_rate': errorRate ?? 0.0,
        'device_rate': deviceRate ?? 0.0,
        'version': firstVersion,
        'first_time': firstTime,
        'latest_time': latestTime,
        'version_count': errorVersionCount,
        'status': status,
        'reason': reason,
        'os_distribution': osDist,
        'device_distribution': deviceDist,
        'brand_distribution': brandDist,
        'full_issue_data': issueStats,
        'latest_user_sample': candidateSamples.first,
        'candidate_samples': candidateSamples,
        'samples': samples,
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

      // 构建用户候选样本映射（hash → 候选样本列表）
      final sampleMap = <String, List<Map<String, dynamic>>>{};
      for (final crash in [...javaCrashes, ...nativeCrashes]) {
        final crashMap = crash as Map<String, dynamic>;
        final hash = crashMap['digest_hash'] as String?;
        final candidateSamples = crashMap['candidate_samples'] as List<dynamic>? ?? [];
        if (hash != null && candidateSamples.isNotEmpty) {
          sampleMap[hash] = candidateSamples
              .map((s) => s as Map<String, dynamic>)
              .toList();
          debugPrint('[Step3] 找到候选样本 - Hash: $hash, 数量: ${candidateSamples.length}');
        }
      }

      // 并行下载所有华佗日志
      debugPrint('[Step3] 开始并行下载 ${session.selectedDigestHashes.length} 个崩溃的日志');
      final downloadFutures = <Future<void>>[];
      for (int i = 0; i < session.selectedDigestHashes.length; i++) {
        final hash = session.selectedDigestHashes[i];
        final samples = sampleMap[hash] ?? [];
        downloadFutures.add(_downloadHuatuoLogArchive(
          hash,
          samples,
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
  ///
  /// 依次遍历候选样本（最多 4 个），逐个查询华佗日志，
  /// 找到第一个含 crashLogFile 事件且能拿到下载链接的样本即下载并停止。
  Future<void> _downloadHuatuoLogArchive(
    String hash,
    List<Map<String, dynamic>> samples,
    String outputDir,
    int index,
    int total,
    AnalysisSession session,
  ) async {
    try {
      debugPrint('[Step3] [$index/$total] 开始下载 Hash: $hash，候选样本 ${samples.length} 个');

      if (samples.isEmpty) {
        debugPrint('[Step3] [$index/$total] 跳过：无候选样本');
        return;
      }

      const baseUrl = 'https://huatuo.xesv5.com/api/1.0';

      // 逐个尝试候选样本
      for (int s = 0; s < samples.length; s++) {
        _checkCancelled();
        final sample = samples[s];
        final uuid = sample['uuid'] as String? ?? '';
        final userId = sample['user_id'] as String? ?? '';
        final did = sample['did'] as String? ?? '';
        final clientTime = sample['client_time'] as String? ?? '';

        debugPrint('[Step3] [$index/$total] 尝试候选样本 ${s + 1}/${samples.length} - UUID: $uuid, UserId: $userId');

        if (userId.isEmpty && uuid.isEmpty) {
          debugPrint('[Step3] [$index/$total] 候选 ${s + 1} 无 userId/uuid，跳过');
          continue;
        }

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

        // 华佗接口限流时会返回 data:null，对同一候选样本重试若干次。
        List<dynamic> dataList = const [];
        bool gotResponse = false;
        for (int attempt = 1; attempt <= 3; attempt++) {
          final http.Response response;
          try {
            response = await http.get(Uri.parse(url)).timeout(
              const Duration(seconds: 30),
              onTimeout: () => throw TimeoutException('Huatuo request timeout'),
            );
          } catch (e) {
            debugPrint('[Step3] [$index/$total] 候选 ${s + 1} 第 $attempt 次请求失败: $e');
            await Future.delayed(Duration(milliseconds: 400 * attempt));
            continue;
          }

          if (response.statusCode != 200) {
            debugPrint('[Step3] [$index/$total] 候选 ${s + 1} HTTP ${response.statusCode}');
            await Future.delayed(Duration(milliseconds: 400 * attempt));
            continue;
          }

          Map<String, dynamic>? responseData;
          try {
            responseData = jsonDecode(response.body) as Map<String, dynamic>;
          } catch (e) {
            debugPrint('[Step3] [$index/$total] 候选 ${s + 1} 响应解析失败: $e');
            break;
          }

          final huatuoData = responseData['data'];
          if (huatuoData == null) {
            // 限流/暂态空响应，重试
            debugPrint('[Step3] [$index/$total] 候选 ${s + 1} 第 $attempt 次返回 data:null（限流），重试...');
            await Future.delayed(Duration(milliseconds: 500 * attempt));
            continue;
          }

          final dataMap = huatuoData as Map<String, dynamic>? ?? {};
          dataList = dataMap['dataList'] as List<dynamic>? ?? [];
          gotResponse = true;
          break;
        }

        if (!gotResponse) {
          debugPrint('[Step3] [$index/$total] 候选 ${s + 1} 多次请求无有效数据，尝试下一个');
          continue;
        }

        debugPrint('[Step3] [$index/$total] 候选 ${s + 1} dataList 共 ${dataList.length} 条');

        // 按命中条件：在 dataList 中查找 eventid 为 crashLogFile 的事件，且能拿到下载路径
        String? downloadUrl;
        for (final item in dataList) {
          final itemMap = item as Map<String, dynamic>;
          final innerData = itemMap['data'] as Map<String, dynamic>? ?? {};
          final eventid = innerData['eventid'] as String? ?? '';

          if (eventid != 'crashLogFile' && !eventid.toLowerCase().contains('crash')) {
            continue;
          }

          // 下载路径：真实结构在 data.logFileUrl（嵌套在 data 对象内）
          final logFileUrl = innerData['logFileUrl'] as String? ??
              itemMap['logFileUrl'] as String? ??
              innerData['filePath'] as String? ??
              innerData['fileUrl'] as String? ??
              innerData['url'] as String? ??
              '';

          downloadUrl = logFileUrl;
          if (downloadUrl.isNotEmpty) {
            debugPrint('[Step3] [$index/$total] 候选 ${s + 1} 命中 crashLogFile: $downloadUrl');
            break;
          }
        }

        if (downloadUrl == null || downloadUrl.isEmpty) {
          debugPrint('[Step3] [$index/$total] 候选 ${s + 1} 无 crashLogFile 下载链接，尝试下一个');
          continue;
        }

        // 命中：下载压缩包。扩展名按真实下载链接判断（华佗日志多为 .zip）。
        // 归档名取下载链接里的原始压缩包名（如 23475914_1788354226074_zipLog），
        // 便于在日志列表中与实际下载文件保持一致。
        final lowerUrl = downloadUrl.toLowerCase();
        final archiveExt = lowerUrl.contains('.tar.gz') || lowerUrl.contains('.tgz')
            ? 'tar.gz'
            : 'zip';
        final urlBaseName = downloadUrl.split('?').first.split('/').last;
        final archiveBaseName = urlBaseName
            .replaceAll(RegExp(r'\.(tar\.gz|tgz|zip)$', caseSensitive: false), '')
            .trim();
        final archiveFileName = '03_${hash}_huatuo_log.$archiveExt';
        final archivePath = '$outputDir/$archiveFileName';

        debugPrint('[Step3] [$index/$total] 下载压缩包到: $archivePath (格式: $archiveExt)');
        final archiveResponse = await http.get(Uri.parse(downloadUrl)).timeout(
          const Duration(minutes: 2),
          onTimeout: () => throw TimeoutException('Archive download timeout'),
        );

        if (archiveResponse.statusCode != 200) {
          debugPrint('[Step3] [$index/$total] 候选 ${s + 1} 压缩包下载失败 ${archiveResponse.statusCode}，尝试下一个');
          continue;
        }

        // 保存压缩包
        await _logsManager.saveBinaryLogFile(
          sessionId: session.id,
          fileName: archiveFileName,
          bytes: archiveResponse.bodyBytes,
        );
        debugPrint('[Step3] [$index/$total] 压缩包已保存，大小: ${archiveResponse.bodyBytes.length} 字节');

        // 全量解压：保留包内所有日志文件（tombstone + 按日期日志等）。
        // 目录名含原始压缩包名（如 03_23475914_1788354226074_zipLog_logs），
        // 使日志列表展示与实际下载文件一致。
        final dirLabel = archiveBaseName.isNotEmpty ? archiveBaseName : hash;
        final extractDir = '$outputDir/03_${dirLabel}_logs';
        final extractOk = await ArchiveManager.extractArchive(archivePath, extractDir);

        // 删除压缩包（内容已解压保留）
        try {
          await File(archivePath).delete();
          debugPrint('[Step3] [$index/$total] 已删除压缩包');
        } catch (e) {
          debugPrint('[Step3] [$index/$total] 删除压缩包失败: $e');
        }

        if (!extractOk) {
          debugPrint('[Step3] [$index/$total] 解压失败，尝试下一个候选');
          try {
            await Directory(extractDir).delete(recursive: true);
          } catch (_) {}
          continue;
        }

        // 定位 tombstone 文件名（分析时使用；目录内其他日志文件全部保留）
        final tombstoneFileName = await _findTombstoneFileName(extractDir);
        if (tombstoneFileName == null) {
          debugPrint('[Step3] [$index/$total] 解压成功但未找到 tombstone 文件，尝试下一个候选');
          try {
            await Directory(extractDir).delete(recursive: true);
          } catch (_) {}
          continue;
        }

        debugPrint('[Step3] [$index/$total] 解压完成，tombstone 文件: $tombstoneFileName');

        // 保存华佗 API 数据（用于 Step 4 生成报告时使用）
        final huatuoLogsFileName = '03_${hash}_huatuo_logs_analysis.json';
        final huatuoLogsData = {
          'hash': hash,
          'uuid': uuid,
          'user_id': userId,
          'did': did,
          'extract_dir': extractDir,
          'tombstone_file': tombstoneFileName,
          'query_url': url,
          'download_url': downloadUrl,
          'archive_size': archiveResponse.bodyBytes.length,
          'logs_count': dataList.length,
          'timestamp': DateTime.now().toIso8601String(),
          // 保留 API 的 dataList 用于报告和 LLM 分析
          'data_items': dataList.map((item) {
            final itemMap = item as Map<String, dynamic>;
            final innerData = itemMap['data'] as Map<String, dynamic>? ?? {};
            return {
              'eventid': innerData['eventid'] ?? '',
              'logtype': itemMap['logtype'] ?? '',
              'data': innerData,
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

        // 添加 tombstone 文件路径到会话
        session.addLogFile('$extractDir/$tombstoneFileName');

        debugPrint('[Step3] [$index/$total] 完成：$hash（命中候选 ${s + 1}）');
        return;
      }

      debugPrint('[Step3] [$index/$total] 所有候选样本均无 crashLogFile 日志，放弃下载：$hash');
    } catch (e) {
      debugPrint('[Step3] 下载失败 ($hash): $e');
    }
  }

  /// 在已全量解压的目录中递归查找 tombstone 文件，返回其文件名（不含路径）。
  /// 目录内其余日志文件全部保留。
  Future<String?> _findTombstoneFileName(String extractDir) async {
    try {
      final dir = Directory(extractDir);
      if (!await dir.exists()) return null;
      final entities = dir.listSync(recursive: true, followLinks: false);
      for (final e in entities) {
        if (e is File) {
          final name = e.path.split('/').last;
          if (name.toLowerCase().contains('tombstone')) {
            return name;
          }
        }
      }
    } catch (e) {
      debugPrint('[Step3] 查找 tombstone 失败: $e');
    }
    return null;
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

      // 删除 Step 3 的 JSON 分析数据文件（只保留解压后的原始日志目录）
      for (final hash in session.selectedDigestHashes) {
        final huatuoJsonPath = '$outputDir/03_${hash}_huatuo_logs_analysis.json';
        try {
          final jsonFile = File(huatuoJsonPath);
          if (await jsonFile.exists()) {
            await jsonFile.delete();
            debugPrint('[Step4] 已删除 JSON 文件: $huatuoJsonPath');
          }
        } catch (e) {
          debugPrint('[Step4] 删除 JSON 文件失败 ($huatuoJsonPath): $e');
        }
      }

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

    int javaErrorCount = 0;
    int javaDeviceCount = 0;
    int nativeErrorCount = 0;
    int nativeDeviceCount = 0;
    for (final c in javaCrashes) {
      final m = c as Map<String, dynamic>;
      javaErrorCount += (m['error_count'] as int? ?? 0);
      javaDeviceCount += (m['affected_devices'] as int? ?? 0);
    }
    for (final c in nativeCrashes) {
      final m = c as Map<String, dynamic>;
      nativeErrorCount += (m['error_count'] as int? ?? 0);
      nativeDeviceCount += (m['affected_devices'] as int? ?? 0);
    }

    // 概览表格
    buffer.writeln('## 📊 概览');
    buffer.writeln();
    buffer.writeln('| 指标 | Java | Native | 合计 |');
    buffer.writeln('|:---|---:|---:|---:|');
    buffer.writeln('| 崩溃种类 | ${javaCrashes.length} | ${nativeCrashes.length} | ${session.selectedDigestHashes.length} |');
    buffer.writeln('| 影响设备 | $javaDeviceCount | $nativeDeviceCount | ${javaDeviceCount + nativeDeviceCount} |');
    buffer.writeln('| 错误次数 | $javaErrorCount | $nativeErrorCount | ${javaErrorCount + nativeErrorCount} |');
    buffer.writeln();

    // Java 崩溃列表
    if (javaCrashes.isNotEmpty) {
      buffer.writeln('## ☕ Java Crash 完整列表');
      buffer.writeln();
      buffer.writeln('| 排名 | DigestHash | 影响设备 | 错误次数 | 崩溃率 | 版本 |');
      buffer.writeln('|:---:|:---|---:|---:|:---|:---|');
      for (int i = 0; i < javaCrashes.length; i++) {
        final crash = javaCrashes[i] as Map<String, dynamic>;
        final hash = crash['digest_hash'] as String? ?? '';
        final deviceCount = crash['affected_devices'] as int? ?? 0;
        final errorCount = crash['error_count'] as int? ?? 0;
        final errorRate = crash['error_rate'] as num? ?? 0.0;
        final version = crash['version'] as String? ?? '-';
        final rateStr = errorRate > 0
            ? (errorRate < 1 ? '${errorRate.toStringAsFixed(4)}%' : '$errorRate%')
            : '-';
        buffer.writeln('| ${i + 1} | `$hash` | $deviceCount | $errorCount | $rateStr | $version |');
      }
      buffer.writeln();
    }

    // Native 崩溃列表
    if (nativeCrashes.isNotEmpty) {
      buffer.writeln('## ⚙️ Native Crash 完整列表');
      buffer.writeln();
      buffer.writeln('| 排名 | DigestHash | 影响设备 | 错误次数 | 崩溃率 | 版本 |');
      buffer.writeln('|:---:|:---|---:|---:|:---|:---|');
      for (int i = 0; i < nativeCrashes.length; i++) {
        final crash = nativeCrashes[i] as Map<String, dynamic>;
        final hash = crash['digest_hash'] as String? ?? '';
        final deviceCount = crash['affected_devices'] as int? ?? 0;
        final errorCount = crash['error_count'] as int? ?? 0;
        final errorRate = crash['error_rate'] as num? ?? 0.0;
        final version = crash['version'] as String? ?? '-';
        final rateStr = errorRate > 0
            ? (errorRate < 1 ? '${errorRate.toStringAsFixed(4)}%' : '$errorRate%')
            : '-';
        buffer.writeln('| ${i + 1} | `$hash` | $deviceCount | $errorCount | $rateStr | $version |');
      }
      buffer.writeln();
    }

    buffer.writeln('---');
    buffer.writeln();

    // 并行预计算所有 crash 的 Agent 分析（最多 3 并发），后续详情段直接读取结果。
    final allCrashes = <Map<String, dynamic>>[
      ...javaCrashes.whereType<Map<String, dynamic>>(),
      ...nativeCrashes.whereType<Map<String, dynamic>>(),
    ];
    final agentAnalysisMap = await _runAgentAnalysesInParallel(allCrashes, outputDir, step3Data);

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
        final title = crash['title'] as String? ?? '';
        final errorCount = crash['error_count'] as int? ?? 0;
        final deviceCount = crash['affected_devices'] as int? ?? 0;
        final errorRate = crash['error_rate'] as num? ?? 0.0;
        final version = crash['version'] as String? ?? '';
        final crashExtractDir = _extractDirForHash(step3Data, hash, outputDir);

        buffer.writeln('### Java ${i + 1}. [$hash]');
        buffer.writeln();

        if (title.isNotEmpty) {
          buffer.writeln('**错误名称**: $title');
          buffer.writeln();
        }
        buffer.writeln('- **错误次数**: $errorCount');
        buffer.writeln('- **影响设备**: $deviceCount');
        if (errorRate > 0) {
          final rateStr = errorRate < 1 ? '${errorRate.toStringAsFixed(4)}%' : '$errorRate%';
          buffer.writeln('- **崩溃率**: $rateStr');
        }
        if (version.isNotEmpty && version != '-') {
          buffer.writeln('- **首现版本**: $version');
        }
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

        // 堆栈信息（完整，不省略）
        final stackTop = (sample['backtrace_full'] ?? sample['stack_top']) as String? ?? '';
        if (stackTop.isNotEmpty) {
          buffer.writeln('**完整崩溃堆栈**:');
          buffer.writeln('```');
          buffer.writeln(stackTop.trim());
          buffer.writeln('```');
          buffer.writeln();
        }

        // tombstone 关键数据（完整展示崩溃主日志）
        final tombstoneText = await _readTombstoneContent(crashExtractDir);
        if (tombstoneText.trim().isNotEmpty) {
          final keySections = _extractTombstoneForReport(tombstoneText);
          if (keySections.trim().isNotEmpty) {
            buffer.writeln('**📄 tombstone 崩溃主日志（关键数据）**:');
            buffer.writeln('```');
            buffer.writeln(keySections);
            buffer.writeln('```');
            buffer.writeln();
          }
        }

        // 分布分析
        final osDist = _readDistributionList(crash['os_distribution']);
        final deviceDist = _readDistributionList(crash['device_distribution']);
        final brandDist = _readDistributionList(crash['brand_distribution']);

        if (osDist.isNotEmpty || deviceDist.isNotEmpty || brandDist.isNotEmpty) {
          buffer.writeln('**分布分析**:');
          buffer.writeln();

          if (osDist.isNotEmpty) {
            buffer.writeln('*系统版本分布:*');
            buffer.writeln();
            buffer.writeln('| 系统版本 | 次数 | 占比 |');
            buffer.writeln('|:---|---:|---:|');
            for (final e in osDist.take(5)) {
              final name = (e['OsVersion'] ?? e['SystemVersion'] ?? e['Name'] ?? e['Value'] ?? '').toString();
              final count = _readInt(e['Count'] ?? e['ErrorCount']) ?? 0;
              final pct = errorCount > 0 ? ((count / errorCount) * 100).toStringAsFixed(1) : '0';
              buffer.writeln('| $name | $count | ${pct}% |');
            }
            buffer.writeln();
          }

          if (brandDist.isNotEmpty) {
            buffer.writeln('*品牌分布:*');
            buffer.writeln();
            buffer.writeln('| 品牌 | 次数 | 占比 |');
            buffer.writeln('|:---|---:|---:|');
            for (final e in brandDist.take(5)) {
              final name = (e['Brand'] ?? e['Name'] ?? e['Value'] ?? '').toString();
              final count = _readInt(e['Count'] ?? e['ErrorCount']) ?? 0;
              final pct = errorCount > 0 ? ((count / errorCount) * 100).toStringAsFixed(1) : '0';
              buffer.writeln('| $name | $count | ${pct}% |');
            }
            buffer.writeln();
          }

          if (deviceDist.isNotEmpty) {
            buffer.writeln('*机型分布:*');
            buffer.writeln();
            buffer.writeln('| 机型 | 次数 | 占比 |');
            buffer.writeln('|:---|---:|---:|');
            for (final e in deviceDist.take(5)) {
              final name = (e['Device'] ?? e['DeviceModel'] ?? e['Name'] ?? e['Value'] ?? '').toString();
              final count = _readInt(e['Count'] ?? e['ErrorCount']) ?? 0;
              final pct = errorCount > 0 ? ((count / errorCount) * 100).toStringAsFixed(1) : '0';
              buffer.writeln('| $name | $count | ${pct}% |');
            }
            buffer.writeln();
          }
        }

        // 华佗日志：链接与数据均来自实际命中并下载成功的那次请求（step3 JSON）。
        final huatuoData = step3Data[hash] as Map<String, dynamic>?;
        if (huatuoData != null && huatuoData.isNotEmpty) {
          final hitQueryUrl = (huatuoData['query_url'] as String? ?? '').trim();
          final hitDownloadUrl = (huatuoData['download_url'] as String? ?? '').trim();
          final hitUserId = (huatuoData['user_id'] as String? ?? '').trim();
          buffer.writeln('**华佗日志**（命中用户: $hitUserId）:');
          buffer.writeln();
          if (hitQueryUrl.isNotEmpty) {
            buffer.writeln('- [🔗 日志列表查询（实际命中请求）]($hitQueryUrl)');
          }
          if (hitDownloadUrl.isNotEmpty) {
            buffer.writeln('- [⬇️ 崩溃日志压缩包]($hitDownloadUrl)');
          }
          buffer.writeln();

          // 展示实际命中响应里的 crashLogFile 数据
          final dataItems = huatuoData['data_items'] as List<dynamic>? ?? [];
          Map<String, dynamic>? crashLogFileData;
          for (final item in dataItems) {
            final itemMap = item as Map<String, dynamic>?;
            if (itemMap != null) {
              final itemData = itemMap['data'] as Map<String, dynamic>? ?? {};
              final eventid = (itemData['eventid'] as String? ?? '');
              if (eventid == 'crashLogFile') {
                crashLogFileData = itemData;
                break;
              }
            }
          }

          if (crashLogFileData != null && crashLogFileData.isNotEmpty) {
            buffer.writeln('**华佗日志数据 (crashLogFile)**:');
            buffer.writeln();
            const pretty = JsonEncoder.withIndent('  ');
            buffer.writeln('```json');
            buffer.writeln(pretty.convert(crashLogFileData));
            buffer.writeln('```');
            buffer.writeln();
          }
        }

        // Agent 根因分析（已并行预计算）
        final llmAnalysis = agentAnalysisMap[hash];
        if (llmAnalysis != null && llmAnalysis.isNotEmpty) {
          _writeAgentAnalysis(buffer, llmAnalysis);
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
        final title = crash['title'] as String? ?? '';
        final errorCount = crash['error_count'] as int? ?? 0;
        final deviceCount = crash['affected_devices'] as int? ?? 0;
        final errorRate = crash['error_rate'] as num? ?? 0.0;
        final version = crash['version'] as String? ?? '';
        final crashExtractDir = _extractDirForHash(step3Data, hash, outputDir);

        buffer.writeln('### Native ${i + 1}. [$hash]');
        buffer.writeln();

        if (title.isNotEmpty) {
          buffer.writeln('**错误名称**: $title');
          buffer.writeln();
        }
        buffer.writeln('- **错误次数**: $errorCount');
        buffer.writeln('- **影响设备**: $deviceCount');
        if (errorRate > 0) {
          final rateStr = errorRate < 1 ? '${errorRate.toStringAsFixed(4)}%' : '$errorRate%';
          buffer.writeln('- **崩溃率**: $rateStr');
        }
        if (version.isNotEmpty && version != '-') {
          buffer.writeln('- **首现版本**: $version');
        }
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

        // 堆栈信息（完整，不省略）
        final stackTop = (sample['backtrace_full'] ?? sample['stack_top']) as String? ?? '';
        if (stackTop.isNotEmpty) {
          buffer.writeln('**完整崩溃堆栈**:');
          buffer.writeln('```');
          buffer.writeln(stackTop.trim());
          buffer.writeln('```');
          buffer.writeln();
        }

        // tombstone 关键数据（完整展示崩溃主日志）
        final tombstoneTextNative = await _readTombstoneContent(crashExtractDir);
        if (tombstoneTextNative.trim().isNotEmpty) {
          final keySections = _extractTombstoneForReport(tombstoneTextNative);
          if (keySections.trim().isNotEmpty) {
            buffer.writeln('**📄 tombstone 崩溃主日志（关键数据）**:');
            buffer.writeln('```');
            buffer.writeln(keySections);
            buffer.writeln('```');
            buffer.writeln();
          }
        }

        // 分布分析
        final osDistNative = _readDistributionList(crash['os_distribution']);
        final deviceDistNative = _readDistributionList(crash['device_distribution']);
        final brandDistNative = _readDistributionList(crash['brand_distribution']);
        final errorCountNative = crash['error_count'] as int? ?? 0;

        if (osDistNative.isNotEmpty || deviceDistNative.isNotEmpty || brandDistNative.isNotEmpty) {
          buffer.writeln('**分布分析**:');
          buffer.writeln();

          if (osDistNative.isNotEmpty) {
            buffer.writeln('*系统版本分布:*');
            buffer.writeln();
            buffer.writeln('| 系统版本 | 次数 | 占比 |');
            buffer.writeln('|:---|---:|---:|');
            for (final e in osDistNative.take(5)) {
              final name = (e['OsVersion'] ?? e['SystemVersion'] ?? e['Name'] ?? e['Value'] ?? '').toString();
              final count = _readInt(e['Count'] ?? e['ErrorCount']) ?? 0;
              final pct = errorCountNative > 0 ? ((count / errorCountNative) * 100).toStringAsFixed(1) : '0';
              buffer.writeln('| $name | $count | ${pct}% |');
            }
            buffer.writeln();
          }

          if (brandDistNative.isNotEmpty) {
            buffer.writeln('*品牌分布:*');
            buffer.writeln();
            buffer.writeln('| 品牌 | 次数 | 占比 |');
            buffer.writeln('|:---|---:|---:|');
            for (final e in brandDistNative.take(5)) {
              final name = (e['Brand'] ?? e['Name'] ?? e['Value'] ?? '').toString();
              final count = _readInt(e['Count'] ?? e['ErrorCount']) ?? 0;
              final pct = errorCountNative > 0 ? ((count / errorCountNative) * 100).toStringAsFixed(1) : '0';
              buffer.writeln('| $name | $count | ${pct}% |');
            }
            buffer.writeln();
          }

          if (deviceDistNative.isNotEmpty) {
            buffer.writeln('*机型分布:*');
            buffer.writeln();
            buffer.writeln('| 机型 | 次数 | 占比 |');
            buffer.writeln('|:---|---:|---:|');
            for (final e in deviceDistNative.take(5)) {
              final name = (e['Device'] ?? e['DeviceModel'] ?? e['Name'] ?? e['Value'] ?? '').toString();
              final count = _readInt(e['Count'] ?? e['ErrorCount']) ?? 0;
              final pct = errorCountNative > 0 ? ((count / errorCountNative) * 100).toStringAsFixed(1) : '0';
              buffer.writeln('| $name | $count | ${pct}% |');
            }
            buffer.writeln();
          }
        }

        // 华佗日志：链接与数据均来自实际命中并下载成功的那次请求（step3 JSON）。
        final huatuoData = step3Data[hash] as Map<String, dynamic>?;
        if (huatuoData != null && huatuoData.isNotEmpty) {
          final hitQueryUrl = (huatuoData['query_url'] as String? ?? '').trim();
          final hitDownloadUrl = (huatuoData['download_url'] as String? ?? '').trim();
          final hitUserId = (huatuoData['user_id'] as String? ?? '').trim();
          buffer.writeln('**华佗日志**（命中用户: $hitUserId）:');
          buffer.writeln();
          if (hitQueryUrl.isNotEmpty) {
            buffer.writeln('- [🔗 日志列表查询（实际命中请求）]($hitQueryUrl)');
          }
          if (hitDownloadUrl.isNotEmpty) {
            buffer.writeln('- [⬇️ 崩溃日志压缩包]($hitDownloadUrl)');
          }
          buffer.writeln();

          // 展示实际命中响应里的 crashLogFile 数据
          final dataItems = huatuoData['data_items'] as List<dynamic>? ?? [];
          Map<String, dynamic>? crashLogFileData;
          for (final item in dataItems) {
            final itemMap = item as Map<String, dynamic>?;
            if (itemMap != null) {
              final itemData = itemMap['data'] as Map<String, dynamic>? ?? {};
              final eventid = (itemData['eventid'] as String? ?? '');
              if (eventid == 'crashLogFile') {
                crashLogFileData = itemData;
                break;
              }
            }
          }

          if (crashLogFileData != null && crashLogFileData.isNotEmpty) {
            buffer.writeln('**华佗日志数据 (crashLogFile)**:');
            buffer.writeln();
            const pretty = JsonEncoder.withIndent('  ');
            buffer.writeln('```json');
            buffer.writeln(pretty.convert(crashLogFileData));
            buffer.writeln('```');
            buffer.writeln();
          }
        }

        // Agent 根因分析（已并行预计算）
        final llmAnalysis = agentAnalysisMap[hash];
        if (llmAnalysis != null && llmAnalysis.isNotEmpty) {
          _writeAgentAnalysis(buffer, llmAnalysis);
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

  /// 从解压后的目录中提取关键日志信息
  Future<Map<String, dynamic>> _extractKeyLogsFromDecompressed(
    String extractDir,
    String hash,
  ) async {
    try {
      final dir = Directory(extractDir);
      if (!await dir.exists()) {
        debugPrint('[extractKeyLogs] 解压目录不存在: $extractDir');
        return {};
      }

      final List<String> extractedFiles = [];
      final Map<String, String> fileContents = {};

      // 递归查找所有日志文件
      final files = dir.listSync(recursive: true, followLinks: false);

      for (final entity in files) {
        if (entity is File) {
          final fileName = entity.path.split('/').last;
          final relativePath = entity.path.replaceFirst('$extractDir/', '');

          // 筛选关键日志文件：.log, .txt, .json 等
          if (_isKeyLogFile(fileName)) {
            extractedFiles.add(relativePath);

            try {
              // 读取文件内容，限制大小防止过大
              final bytes = await entity.readAsBytes();
              if (bytes.length > 10 * 1024 * 1024) {
                // 如果文件过大，只读取前 100KB
                fileContents[relativePath] =
                    '${String.fromCharCodes(bytes.sublist(0, 100 * 1024))}\n...[truncated]';
              } else {
                fileContents[relativePath] = String.fromCharCodes(bytes);
              }
            } catch (e) {
              debugPrint('[extractKeyLogs] 读取文件失败 $relativePath: $e');
              fileContents[relativePath] = '[Error reading file: $e]';
            }
          }
        }
      }

      final result = {
        'extracted_files': extractedFiles,
        'file_contents': fileContents,
      };

      debugPrint('[extractKeyLogs] 提取了 ${extractedFiles.length} 个关键日志文件');
      return result;
    } catch (e) {
      debugPrint('[extractKeyLogs] 提取关键日志失败: $e');
      return {};
    }
  }

  /// 判断是否是关键日志文件
  bool _isKeyLogFile(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.log') ||
        lower.endsWith('.txt') ||
        lower.endsWith('.json') ||
        lower.endsWith('.out') ||
        lower.contains('crash') ||
        lower.contains('error') ||
        lower.contains('exception') ||
        lower.contains('stack');
  }

  /// 从解压目录读取 tombstone 文件内容。
  /// 解析某个 hash 对应的日志解压目录。
  ///
  /// 优先用 Step 3 落盘 JSON 里记录的 extract_dir（目录名含原始压缩包名），
  /// 回退到旧的 03_<hash>_logs 命名。
  String _extractDirForHash(Map<String, dynamic> step3Data, String hash, String outputDir) {
    final entry = step3Data[hash];
    if (entry is Map<String, dynamic>) {
      final d = entry['extract_dir']?.toString() ?? '';
      if (d.isNotEmpty) return d;
    }
    return '$outputDir/03_${hash}_logs';
  }

  Future<String> _readTombstoneContent(String extractDir) async {
    final dir = Directory(extractDir);
    if (!await dir.exists()) return '';
    try {
      final entities = dir.listSync(recursive: true, followLinks: false);
      // 只读 tombstone 文件（目录里还包含按日期分割的大日志文件，避免误读）
      for (final entity in entities) {
        if (entity is File &&
            entity.path.split('/').last.toLowerCase().contains('tombstone')) {
          final bytes = await entity.readAsBytes();
          return String.fromCharCodes(bytes);
        }
      }
    } catch (e) {
      debugPrint('[Step4] 读取 tombstone 内容失败: $e');
    }
    return '';
  }

  /// 从完整 tombstone 中提取报告展示用的关键数据。
  ///
  /// 保留：头部标识（Build fingerprint / pid / tid / signal）、完整异常堆栈
  /// （java stacktrace / Caused by / backtrace）、以及崩溃时间点附近的 logcat
  /// 关键行（error/fatal/exception/页面切换/Activity 生命周期），过滤重复埋点噪音。
  String _extractTombstoneForReport(String tombstone, {int maxChars = 12000}) {
    final lines = tombstone.split('\n');
    final out = <String>[];
    var inStack = false;
    var stackLines = 0;

    for (final line in lines) {
      final t = line.trim();
      final lower = t.toLowerCase();

      final isHeader = lower.startsWith('build fingerprint') ||
          lower.startsWith('pid:') ||
          lower.startsWith('signal') ||
          lower.startsWith('abort message') ||
          lower.startsWith('name:');

      final isStackStart = lower.contains('stacktrace') ||
          lower.contains('caused by') ||
          lower.contains('backtrace:') ||
          lower.contains('fatal exception');

      if (isHeader || isStackStart) {
        inStack = true;
        stackLines = 0;
        out.add(line);
        continue;
      }

      if (inStack) {
        final isStackLine = t.startsWith('at ') ||
            line.startsWith('\t') ||
            line.startsWith('    ') ||
            t.startsWith('#') ||
            t.startsWith('Caused by');
        if (isStackLine || (t.isNotEmpty && stackLines < 80)) {
          out.add(line);
          stackLines++;
          continue;
        }
        inStack = false;
      }

      if (t.isEmpty) continue;

      // logcat：过滤重复埋点噪音，保留崩溃相关与用户操作时间线
      final isNoise = lower.contains('@basebury') ||
          lower.contains('realinnelbasebury') ||
          lower.contains('buryentity');
      final isMeaningful = lower.contains('error') ||
          lower.contains('fatal') ||
          lower.contains('exception') ||
          lower.contains('crash') ||
          lower.contains('onactivity') ||
          lower.contains('onfragment') ||
          lower.contains('activity') ||
          lower.contains('fragment') ||
          lower.contains('page') ||
          (t.startsWith('---------') && lower.contains('log'));
      if (isNoise && !isMeaningful) continue;
      if (isMeaningful) out.add(line);
    }

    var result = out.join('\n');
    if (result.length > maxChars) {
      result = '${result.substring(0, maxChars)}\n...[已截断，原文共 ${tombstone.length} 字符]';
    }
    return result;
  }

  /// 并行预计算所有 crash 的 Agent 分析，最多 [maxConcurrency] 个同时进行。
  /// 返回 hash → 分析结果 map；单个失败不影响其他 crash。
  Future<Map<String, Map<String, dynamic>>> _runAgentAnalysesInParallel(
    List<Map<String, dynamic>> crashes,
    String outputDir,
    Map<String, dynamic> step3Data, {
    int maxConcurrency = 3,
  }) async {
    final result = <String, Map<String, dynamic>>{};
    if (crashes.isEmpty) return result;

    // 去重（同一 hash 可能在 java/native 列表里重复）
    final unique = <String, Map<String, dynamic>>{};
    for (final c in crashes) {
      final hash = c['digest_hash'] as String? ?? '';
      if (hash.isNotEmpty && !unique.containsKey(hash)) {
        unique[hash] = c;
      }
    }

    final entries = unique.entries.toList();
    int cursor = 0;

    Future<void> worker() async {
      while (true) {
        _checkCancelled();
        final int idx = cursor;
        cursor++;
        if (idx >= entries.length) return;

        final entry = entries[idx];
        final hash = entry.key;
        final crash = entry.value;
        final sample = (crash['latest_user_sample'] as Map<String, dynamic>?) ?? {};
        final stackStr =
            ((sample['backtrace_full'] ?? sample['stack_top']) as String?) ?? '';
        final extractDir = _extractDirForHash(step3Data, hash, outputDir);
        try {
          debugPrint('[Step4] 并行分析 crash: $hash');
          _updateProgress(AnalysisProgress(
            status: AnalysisSessionStatus.generating,
            currentStep: 4,
            totalSteps: 4,
            message: '📋 Step 4: 智能分析中... (${idx + 1}/${entries.length})',
          ));
          final analysis = await _analyzeWithAgent(
            hash: hash,
            stackStr: stackStr,
            sample: sample,
            extractDir: extractDir,
          );
          result[hash] = analysis;
        } on AnalysisCancelledException {
          rethrow;
        } catch (e) {
          debugPrint('[Step4] 并行分析失败 ($hash): $e');
          result[hash] = {
            'summary': '智能分析失败：$e',
            'error': '$e',
            'possible_causes': <dynamic>[],
            'fix_suggestions': <dynamic>[],
          };
        }
      }
    }

    final workers = List.generate(
      entries.length < maxConcurrency ? entries.length : maxConcurrency,
      (_) => worker(),
    );
    await Future.wait(workers);

    return result;
  }

  /// 使用崩溃分析 Agent 生成根因分析，返回报告消费的 map 结构。
  Future<Map<String, dynamic>> _analyzeWithAgent({
    required String hash,
    required String stackStr,
    required Map<String, dynamic> sample,
    required String extractDir,
  }) async {
    try {
      final tombstoneContent = await _readTombstoneContent(extractDir);

      final result = await _crashAnalysisAgent.analyze(
        digestHash: hash,
        stackInfo: stackStr,
        tombstoneContent: tombstoneContent,
        userSample: sample,
        // 报告生成阶段不做源码检索（源码分析作为独立功能，由用户手动触发）。
        enableSourceAnalysis: false,
      );

      return {
        'summary': result.summary,
        'error': result.isError ? result.error : null,
        'root_cause': result.rootCause,
        'investigation': result.investigation,
        'source_analysis': result.sourceAnalysis,
        'conclusion': result.conclusion,
        'tool_trace': result.toolTrace,
        'possible_causes': result.possibleCauses
            .map((c) => {
                  'cause': c.cause,
                  'detail': c.detail,
                  'evidence': c.evidence,
                })
            .toList(),
        'fix_suggestions': result.fixSuggestions
            .map((s) => {
                  'suggestion': s.suggestion,
                  'priority': s.priority,
                  'implementation': s.implementation,
                  'file': s.file ?? '',
                  'code_diff': s.codeDiff ?? '',
                })
            .toList(),
      };
    } catch (e) {
      // 不再回退到写死模板，直接返回真实错误，避免误导。
      debugPrint('[Step4] Agent 分析异常: $e');
      return {
        'summary': '智能分析调用异常：$e',
        'error': '$e',
        'possible_causes': <dynamic>[],
        'fix_suggestions': <dynamic>[],
      };
    }
  }

  /// 将 Agent 分析结果完整写入报告（根因、可能原因+证据、修复建议+代码改动）。
  void _writeAgentAnalysis(StringBuffer buffer, Map<String, dynamic> llmAnalysis) {
    buffer.writeln('**🤖 智能根因分析**:');
    buffer.writeln();

    final isError = llmAnalysis['error'] != null;

    final summary = (llmAnalysis['summary'] as String? ?? '').trim();
    if (summary.isNotEmpty) {
      buffer.writeln('**分析摘要**: $summary');
      buffer.writeln();
    }

    final rootCause = (llmAnalysis['root_cause'] as String? ?? '').trim();
    if (rootCause.isNotEmpty) {
      buffer.writeln('**根本原因分析**:');
      buffer.writeln();
      buffer.writeln(rootCause);
      buffer.writeln();
    }

    if (!isError) {
      // 排查过程
      final investigation = (llmAnalysis['investigation'] as String? ?? '').trim();
      if (investigation.isNotEmpty) {
        buffer.writeln('**🔍 排查过程**:');
        buffer.writeln();
        buffer.writeln(investigation);
        buffer.writeln();
      }

      // 源码分析
      final sourceAnalysis = (llmAnalysis['source_analysis'] as String? ?? '').trim();
      if (sourceAnalysis.isNotEmpty) {
        buffer.writeln('**📂 结合源码分析**:');
        buffer.writeln();
        buffer.writeln(sourceAnalysis);
        buffer.writeln();
      }

      // 源码检索轨迹（模型实际 grep/read 了哪些文件）
      final toolTrace = (llmAnalysis['tool_trace'] as String? ?? '').trim();
      if (toolTrace.isNotEmpty) {
        buffer.writeln('<details><summary>源码检索轨迹</summary>');
        buffer.writeln();
        buffer.writeln('```');
        buffer.writeln(toolTrace);
        buffer.writeln('```');
        buffer.writeln();
        buffer.writeln('</details>');
        buffer.writeln();
      }

      final possibleCauses = llmAnalysis['possible_causes'] as List<dynamic>? ?? [];
      if (possibleCauses.isNotEmpty) {
        buffer.writeln('**可能原因**:');
        buffer.writeln();
        for (final cause in possibleCauses) {
          final causeMap = cause as Map<String, dynamic>?;
          if (causeMap == null) continue;
          final causeTitle = (causeMap['cause'] as String? ?? '').trim();
          final detail = (causeMap['detail'] as String? ?? '').trim();
          final evidence = causeMap['evidence'] as List<dynamic>? ?? [];

          if (causeTitle.isNotEmpty) {
            buffer.writeln('- **$causeTitle**');
            if (detail.isNotEmpty) {
              buffer.writeln('  $detail');
            }
            if (evidence.isNotEmpty) {
              buffer.writeln();
              buffer.writeln('  **证据**:');
              for (final ev in evidence) {
                final evStr = ev.toString().trim();
                if (evStr.isNotEmpty) {
                  buffer.writeln('  - $evStr');
                }
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
          final m = suggestion as Map<String, dynamic>?;
          if (m == null) continue;
          final title = (m['suggestion'] as String? ?? '').trim();
          final priority = (m['priority'] as String? ?? 'medium').trim();
          final implementation = (m['implementation'] as String? ?? '').trim();
          final file = (m['file'] as String? ?? '').trim();
          final codeDiff = (m['code_diff'] as String? ?? '').trim();

          if (title.isEmpty) continue;
          final priorityIcon = priority == 'high'
              ? '🔴'
              : priority == 'medium'
                  ? '🟡'
                  : '🟢';
          buffer.writeln('- **$title** $priorityIcon');
          if (file.isNotEmpty) {
            buffer.writeln('  涉及文件: `$file`');
          }
          if (implementation.isNotEmpty) {
            buffer.writeln('  实现建议: $implementation');
          }
          if (codeDiff.isNotEmpty) {
            buffer.writeln();
            buffer.writeln('  ```diff');
            for (final line in codeDiff.split('\n')) {
              buffer.writeln('  $line');
            }
            buffer.writeln('  ```');
          }
        }
        buffer.writeln();
      }

      // 最终结论
      final conclusion = (llmAnalysis['conclusion'] as String? ?? '').trim();
      if (conclusion.isNotEmpty) {
        buffer.writeln('**✅ 结论**:');
        buffer.writeln();
        buffer.writeln(conclusion);
        buffer.writeln();
      }
    }
  }

  void _updateProgress(AnalysisProgress progress) {
    _currentProgress = progress;
    notifyListeners();
  }

  bool _cancelRequested = false;

  /// 用户取消时抛出，用于中断各步骤内部的长耗时循环。
  void _checkCancelled() {
    if (_cancelRequested) {
      throw AnalysisCancelledException();
    }
  }

  void cancelAnalysis() {
    _cancelRequested = true;
    _currentSession?.status = AnalysisSessionStatus.cancelled;
    _updateProgress(AnalysisProgress(
      status: AnalysisSessionStatus.cancelled,
      currentStep: _currentProgress?.currentStep ?? 1,
      totalSteps: 4,
      message: '⏹️ 正在取消…',
    ));
  }

  /// 提取 ZIP 文件 - 使用 unzip 命令行工具

  void reset() {
    _currentProgress = null;
    _currentSession = null;
    _cancelRequested = false;
    notifyListeners();
  }

  static int? _readInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static double? _readDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

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

  static List<Map<String, dynamic>> _readDistributionList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) {
        out.add(Map<String, dynamic>.from(e));
      }
    }
    return out;
  }

  static String _formatRate(num? rate) {
    if (rate == null || rate == 0) return '-';
    if (rate is double) {
      return rate < 1 ? '${(rate * 100).toStringAsFixed(4)}%' : '${rate.toStringAsFixed(3)}%';
    }
    return '$rate%';
  }
}
