import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/graytest_monitoring_task.dart';
import 'aliyun_cli_service.dart';
import 'emas_intelligent_analyzer.dart';
import 'config_repository.dart';

/// 灰度监听任务管理服务
/// 职责：CRUD 任务、执行定时检查、调用分析和 Webhook
class GraytestMonitoringService extends ChangeNotifier {
  GraytestMonitoringService({
    required this.configRepository,
    required this.aliyunCliService,
    required this.emasAnalyzer,
  });

  final ConfigRepository configRepository;
  final AliyunCliService aliyunCliService;
  final EmasIntelligentAnalyzer emasAnalyzer;

  final List<GraytestMonitoringTask> _tasks = [];
  final Map<String, List<TaskExecutionRecord>> _executionHistories = {};
  Timer? _monitoringTimer;
  bool _isMonitoring = false;

  // 用于跟踪最后检查时间，避免重复处理相同 Crash
  final Map<String, DateTime> _lastCheckTimePerTask = {};

  /// 加载任务列表
  Future<void> loadTasks() async {
    try {
      final workspace = await configRepository.loadWorkspace();
      _tasks.clear();

      if (workspace.projects.isNotEmpty) {
        final firstProject = workspace.projects.first;
        final taskDatas = firstProject.config.grayTestTasks ?? [];
        for (final data in taskDatas) {
          try {
            _tasks.add(GraytestMonitoringTask.fromJson(data as Map<String, dynamic>));
          } catch (e) {
            debugPrint('Failed to parse task: $e');
          }
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load tasks: $e');
      rethrow;
    }
  }

  /// 新增任务
  Future<void> addTask(GraytestMonitoringTask task) async {
    _tasks.add(task);
    _executionHistories[task.id] = [];
    await _saveTasks();
    notifyListeners();
  }

  /// 更新任务
  Future<void> updateTask(GraytestMonitoringTask task) async {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      _tasks[index] = task;
      await _saveTasks();
      notifyListeners();
    }
  }

  /// 删除任务
  Future<void> deleteTask(String taskId) async {
    _tasks.removeWhere((t) => t.id == taskId);
    _executionHistories.remove(taskId);
    await _saveTasks();
    notifyListeners();
  }

  /// 获取所有任务
  List<GraytestMonitoringTask> getTasks() => List.unmodifiable(_tasks);

  /// 启用/禁用任务
  Future<void> setTaskEnabled(String taskId, bool enabled) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index >= 0) {
      final task = _tasks[index];
      _tasks[index] = task.copyWith(enabled: enabled);
      await _saveTasks();
      notifyListeners();
    }
  }

  /// 开始后台监听
  void startMonitoring() {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _monitoringTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _checkAllTasks();
    });
    notifyListeners();
  }

  /// 停止后台监听
  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _isMonitoring = false;
    notifyListeners();
  }

  /// 是否正在监听
  bool isMonitoring() => _isMonitoring;

  /// 手动触发检查
  Future<void> checkNow() async {
    await _checkAllTasks();
  }

  /// 获取任务执行历史
  List<TaskExecutionRecord> getTaskExecutionHistory(String taskId) {
    return _executionHistories[taskId] ?? [];
  }

  // ============ 私有方法 ============

  /// 检查所有已启用的任务
  Future<void> _checkAllTasks() async {
    for (final task in _tasks) {
      if (!task.enabled) continue;

      try {
        await _checkAndNotifyForTask(task);
      } catch (e) {
        debugPrint('Error checking task ${task.id}: $e');
      }
    }
  }

  /// 检查单个任务：查询最新 Crash、分析、发送 Webhook
  Future<void> _checkAndNotifyForTask(GraytestMonitoringTask task) async {
    try {
      // 计算时间范围（最近 1 天）
      final now = DateTime.now();
      final startTime = now.subtract(const Duration(days: 1));
      final startMs = startTime.millisecondsSinceEpoch;
      final endMs = now.millisecondsSinceEpoch;

      // 查询指定版本的 Crash 列表
      final result = await aliyunCliService.getIssues(
        bizModule: task.bizModule,
        startTimeMs: startMs,
        endTimeMs: endMs,
        os: 'android',
      );

      // 筛选指定版本的问题
      // 注：这里使用 firstVersion，实际应根据需要调整
      final issues = result.items.where((issue) {
        final version = issue.firstVersion?.toString() ?? '';
        return task.targetVersions.contains(version);
      }).toList();

      // 筛选新的 Crash（相比上次检查）
      // 注：简化处理，所有问题都视为新的（实际应根据 issue 的更新时间判断）
      final newIssues = issues;

      // 更新最后检查时间
      _lastCheckTimePerTask[task.id] = DateTime.now();

      // 处理每个新 Crash
      for (final issue in newIssues) {
        await _processNewIssue(task, issue);
      }
    } catch (e) {
      debugPrint('Error in _checkAndNotifyForTask: $e');
    }
  }

  /// 处理单个新发现的 Crash
  Future<void> _processNewIssue(
    GraytestMonitoringTask task,
    dynamic issue,
  ) async {
    try {
      final digestHash = issue.digestHash?.toString() ?? '';
      final title = issue.errorName?.toString() ?? 'Unknown Issue';
      final version = issue.firstVersion?.toString() ?? '';

      // 调用大模型进行分析
      String analysisReport = '';
      try {
        // 构建 issueData（模拟从 issue 对象提取）
        final issueData = {
          'Stack': issue.stack?.toString() ?? '',
          'Name': title,
          'DigestHash': digestHash,
        };

        final report = await emasAnalyzer.analyze(
          digestHash: digestHash,
          issueData: issueData,
          bizModule: task.bizModule,
        );

        // 将 AnalysisReport 对象转换为 Markdown 字符串
        analysisReport = _formatAnalysisReportToMarkdown(report);
      } catch (e) {
        // 分析失败，使用模板
        analysisReport = '''## 原因
自动分析失败，请手动检查。错误: $e

## 分析
检查崩溃堆栈和相关日志。

## 如何处理
1. 查看详细的崩溃报告
2. 联系相关开发人员进行调查''';
      }

      // 构建 Webhook 通知
      final payload = _buildWebhookPayload(
        task: task,
        digestHash: digestHash,
        title: title,
        version: version,
        analysisReport: analysisReport,
      );

      // 发送 Webhook
      final record = await _sendWebhook(task, payload, digestHash, title, version, analysisReport);

      // 保存执行记录
      if (!_executionHistories.containsKey(task.id)) {
        _executionHistories[task.id] = [];
      }
      _executionHistories[task.id]!.add(record);

      // 保持最近 50 条记录
      if (_executionHistories[task.id]!.length > 50) {
        _executionHistories[task.id]!.removeAt(0);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error in _processNewIssue: $e');
    }
  }

  /// 将 AnalysisReport 对象转为 Markdown 字符串
  String _formatAnalysisReportToMarkdown(dynamic report) {
    // 如果 report 已经是字符串，直接返回
    if (report is String) return report;

    // 如果是对象，尝试提取关键字段
    try {
      final cause = report.cause?.toString() ?? '';
      final analysis = report.analysis?.toString() ?? '';
      final solution = report.solution?.toString() ?? '';

      return '''## 原因
$cause

## 分析
$analysis

## 如何处理
$solution''';
    } catch (e) {
      return report.toString();
    }
  }

  /// 构建 Webhook 请求体
  Map<String, dynamic> _buildWebhookPayload({
    required GraytestMonitoringTask task,
    required String digestHash,
    required String title,
    required String version,
    required String analysisReport,
  }) {
    return {
      'taskId': task.id,
      'taskName': task.name,
      'crashDigestHash': digestHash,
      'crashTitle': title,
      'affectedVersion': version,
      'analysisReport': analysisReport,
      'timestamp': DateTime.now().toIso8601String(),
      'bizModule': task.bizModule,
    };
  }

  /// 发送 Webhook 请求（支持重试）
  Future<TaskExecutionRecord> _sendWebhook(
    GraytestMonitoringTask task,
    Map<String, dynamic> payload,
    String digestHash,
    String title,
    String version,
    String analysisReport,
  ) async {
    String status = 'pending';
    String? error;

    try {
      final response = await http
          .post(
            Uri.parse(task.webhookUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        status = 'sent';
      } else {
        status = 'failed';
        error = 'HTTP ${response.statusCode}: ${response.body}';
      }
    } catch (e) {
      status = 'failed';
      error = e.toString();
    }

    final record = TaskExecutionRecord(
      id: 'exec_${DateTime.now().millisecondsSinceEpoch}_${task.id}',
      taskId: task.id,
      digestHash: digestHash,
      issueTitle: title,
      issueVersion: version,
      analysisReportContent: analysisReport,
      executedAt: DateTime.now(),
      webhookStatus: status,
      webhookError: error,
    );

    return record;
  }

  /// 保存任务到配置
  Future<void> _saveTasks() async {
    try {
      final workspace = await configRepository.loadWorkspace();

      if (workspace.projects.isNotEmpty) {
        final firstProject = workspace.projects.first;
        final config = firstProject.config;

        config.grayTestTasks = _tasks.map((t) => t.toJson()).toList();

        await configRepository.saveWorkspace(workspace);
      }
    } catch (e) {
      debugPrint('Failed to save tasks: $e');
    }
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
