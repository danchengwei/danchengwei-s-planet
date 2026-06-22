import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/analysis_report_record.dart';
import 'analysis_report_storage.dart';

/// 报告管理服务：统一的 CRUD 和查询 API
class ReportManager extends ChangeNotifier {
  Map<String, List<AnalysisReportRecord>> _byProject = {};

  Map<String, List<AnalysisReportRecord>> get byProject => _byProject;

  /// 加载所有报告
  Future<void> loadReports() async {
    _byProject = await AnalysisReportStorage.load();
    notifyListeners();
  }

  /// 保存所有报告
  Future<void> saveReports() async {
    await AnalysisReportStorage.save(_byProject);
  }

  /// 添加报告
  Future<void> addReport(AnalysisReportRecord report) async {
    _byProject.putIfAbsent(report.projectId, () => []);
    _byProject[report.projectId]!.insert(0, report);
    await saveReports();
    notifyListeners();
  }

  /// 删除报告
  Future<void> deleteReport(String projectId, String reportId) async {
    _byProject[projectId]?.removeWhere((r) => r.id == reportId);
    await saveReports();
    notifyListeners();
  }

  /// 删除项目的所有报告
  Future<void> deleteProjectReports(String projectId) async {
    _byProject.remove(projectId);
    await saveReports();
    notifyListeners();
  }

  /// 获取项目的所有报告
  List<AnalysisReportRecord> getProjectReports(String projectId) {
    return _byProject[projectId] ?? [];
  }

  /// 按业务模块筛选报告
  List<AnalysisReportRecord> getReportsByBizModule(String projectId, String bizModule) {
    return getProjectReports(projectId).where((r) => r.bizModule == bizModule).toList();
  }

  /// 按关键字搜索报告
  List<AnalysisReportRecord> searchReports(String projectId, String keyword) {
    final lower = keyword.toLowerCase();
    return getProjectReports(projectId)
        .where((r) => r.title.toLowerCase().contains(lower) || r.reportBody.toLowerCase().contains(lower))
        .toList();
  }

  /// 按时间范围筛选
  List<AnalysisReportRecord> getReportsByDateRange(
    String projectId,
    DateTime startDate,
    DateTime endDate,
  ) {
    final startMs = startDate.millisecondsSinceEpoch;
    final endMs = endDate.add(const Duration(days: 1)).millisecondsSinceEpoch;
    return getProjectReports(projectId).where((r) => r.createdAtMs >= startMs && r.createdAtMs < endMs).toList();
  }

  /// 获取所有项目的所有报告（按创建时间倒序）
  List<AnalysisReportRecord> getAllReports() {
    final all = <AnalysisReportRecord>[];
    for (final list in _byProject.values) {
      all.addAll(list);
    }
    all.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return all;
  }

  /// 按业务模块分组统计
  Map<String, int> getReportCountByBizModule(String projectId) {
    final counts = <String, int>{};
    for (final report in getProjectReports(projectId)) {
      counts[report.bizModule] = (counts[report.bizModule] ?? 0) + 1;
    }
    return counts;
  }

  /// 获取最近 N 条报告
  List<AnalysisReportRecord> getRecentReports(String projectId, {int limit = 10}) {
    return getProjectReports(projectId).take(limit).toList();
  }

  /// 导出为 JSON（用于分享或备份）
  String exportAsJson(String projectId) {
    final reports = getProjectReports(projectId);
    final jsonList = reports.map((r) => r.toJson()).toList();
    return '''
{
  "projectId": "$projectId",
  "exportedAt": "${DateTime.now().toIso8601String()}",
  "reportCount": ${reports.length},
  "reports": ${jsonList.map((j) => _formatJson(j)).join(',\n')}
}
''';
  }

  String _formatJson(Map<String, dynamic> map) {
    // 简单的 JSON 格式化
    return map.toString();
  }

  /// 获取报告统计信息
  ReportStats getStats(String projectId) {
    final reports = getProjectReports(projectId);
    if (reports.isEmpty) {
      return ReportStats(
        totalCount: 0,
        bizModuleCount: 0,
        oldestReportDate: null,
        newestReportDate: null,
      );
    }

    final bizModules = reports.map((r) => r.bizModule).toSet().length;
    final oldest = reports.last.createdAtMs;
    final newest = reports.first.createdAtMs;

    return ReportStats(
      totalCount: reports.length,
      bizModuleCount: bizModules,
      oldestReportDate: DateTime.fromMillisecondsSinceEpoch(oldest),
      newestReportDate: DateTime.fromMillisecondsSinceEpoch(newest),
    );
  }
}

class ReportStats {
  const ReportStats({
    required this.totalCount,
    required this.bizModuleCount,
    required this.oldestReportDate,
    required this.newestReportDate,
  });

  final int totalCount;
  final int bizModuleCount;
  final DateTime? oldestReportDate;
  final DateTime? newestReportDate;

  String get summaryText {
    if (totalCount == 0) return '无报告';
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final oldest = oldestReportDate != null ? df.format(oldestReportDate!) : 'N/A';
    final newest = newestReportDate != null ? df.format(newestReportDate!) : 'N/A';
    return '共 $totalCount 条报告（$bizModuleCount 类），最早：$oldest，最新：$newest';
  }
}
