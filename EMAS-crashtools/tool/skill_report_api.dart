/// 统一的报告 Skills API 接口
/// 供龙虾等外部工具调用所有集成的分析能力
///
/// 调用示例：
/// ```
/// // 生成崩溃分析报告
/// final result = await skillGenerateCrashAnalysisReport(
///   projectId: 'proj_123',
///   issueId: 'issue_456',
///   crashStackTrace: '...',
///   appVersion: '1.0.0',
/// );
///
/// // 获取报告列表
/// final reports = await skillGetReportsList(
///   projectId: 'proj_123',
///   bizModule: 'crash',
/// );
/// ```

import 'dart:convert';

/// 生成崩溃分析报告
///
/// 参数：
/// - projectId: 项目 ID
/// - issueId: 问题 ID
/// - crashStackTrace: 崩溃堆栈
/// - appVersion: 应用版本
/// - additionalContext: 额外上下文信息（可选）
///
/// 返回：{success: bool, reportId: string?, reportBody: string?, error: string?}
Future<Map<String, dynamic>> skillGenerateCrashAnalysisReport({
  required String projectId,
  required String issueId,
  required String crashStackTrace,
  required String appVersion,
  Map<String, dynamic>? additionalContext,
}) async {
  // 实现：调用 LLM 生成分析报告
  // 存储到 ReportManager
  // 返回报告 ID 和内容
  return {
    'success': true,
    'reportId': 'r_${DateTime.now().microsecondsSinceEpoch}',
    'reportBody': '# 崩溃分析报告\n\n待实现',
  };
}

/// 生成 ANR 分析报告
Future<Map<String, dynamic>> skillGenerateAnrAnalysisReport({
  required String projectId,
  required String issueId,
  required String anrStackTrace,
  required String appVersion,
  String? threadName,
  Map<String, dynamic>? additionalContext,
}) async {
  return {
    'success': true,
    'reportId': 'r_${DateTime.now().microsecondsSinceEpoch}',
    'reportBody': '# ANR 分析报告\n\n待实现',
  };
}

/// 获取报告列表
///
/// 参数：
/// - projectId: 项目 ID
/// - bizModule: 业务模块（crash / anr / 等）可选
/// - limit: 返回条数限制，默认 20
/// - offset: 分页偏移，默认 0
///
/// 返回：{success: bool, reports: List<Map>?, totalCount: int?, error: string?}
Future<Map<String, dynamic>> skillGetReportsList({
  required String projectId,
  String? bizModule,
  int limit = 20,
  int offset = 0,
}) async {
  return {
    'success': true,
    'reports': [],
    'totalCount': 0,
  };
}

/// 获取单个报告详情
///
/// 参数：
/// - projectId: 项目 ID
/// - reportId: 报告 ID
///
/// 返回：{success: bool, report: Map?, error: string?}
Future<Map<String, dynamic>> skillGetReportDetail({
  required String projectId,
  required String reportId,
}) async {
  return {
    'success': false,
    'error': '报告不存在',
  };
}

/// 搜索报告
///
/// 参数：
/// - projectId: 项目 ID
/// - keyword: 搜索关键词
/// - limit: 返回条数限制
///
/// 返回：{success: bool, results: List<Map>?, error: string?}
Future<Map<String, dynamic>> skillSearchReports({
  required String projectId,
  required String keyword,
  int limit = 20,
}) async {
  return {
    'success': true,
    'results': [],
  };
}

/// 删除报告
///
/// 参数：
/// - projectId: 项目 ID
/// - reportId: 报告 ID
///
/// 返回：{success: bool, error: string?}
Future<Map<String, dynamic>> skillDeleteReport({
  required String projectId,
  required String reportId,
}) async {
  return {
    'success': true,
  };
}

/// 导出报告
///
/// 参数：
/// - projectId: 项目 ID
/// - reportIds: 报告 ID 列表
/// - format: 格式（json / md / html），默认 json
///
/// 返回：{success: bool, content: string?, format: string?, error: string?}
Future<Map<String, dynamic>> skillExportReports({
  required String projectId,
  required List<String> reportIds,
  String format = 'json',
}) async {
  return {
    'success': true,
    'format': format,
    'content': '{}',
  };
}

/// 批量分析问题并生成报告
///
/// 参数：
/// - projectId: 项目 ID
/// - issues: 问题列表 [{id, type, stackTrace, ...}]
/// - appVersion: 应用版本
///
/// 返回：{success: bool, reportIds: List<String>?, failedCount: int?, error: string?}
Future<Map<String, dynamic>> skillBatchAnalyzeAndGenerateReports({
  required String projectId,
  required List<Map<String, dynamic>> issues,
  required String appVersion,
}) async {
  return {
    'success': true,
    'reportIds': [],
    'failedCount': 0,
  };
}

/// 获取报告统计信息
///
/// 参数：
/// - projectId: 项目 ID
///
/// 返回：{success: bool, stats: Map?, error: string?}
Future<Map<String, dynamic>> skillGetReportsStats({
  required String projectId,
}) async {
  return {
    'success': true,
    'stats': {
      'totalCount': 0,
      'bizModuleCount': 0,
      'oldestReportDate': null,
      'newestReportDate': null,
    },
  };
}

/// 获取所有可用的 Skills
///
/// 返回：{skills: List<Map>} 每个 skill 包含 name, description, params, returns
Future<Map<String, dynamic>> skillGetAvailableSkills() async {
  return {
    'skills': [
      {
        'name': 'skillGenerateCrashAnalysisReport',
        'description': '生成崩溃分析报告',
        'category': 'analysis',
        'params': {
          'projectId': 'string（项目 ID）',
          'issueId': 'string（问题 ID）',
          'crashStackTrace': 'string（崩溃堆栈）',
          'appVersion': 'string（应用版本）',
          'additionalContext': 'object（可选）',
        },
        'returns': '{success: bool, reportId: string?, reportBody: string?, error: string?}',
      },
      {
        'name': 'skillGenerateAnrAnalysisReport',
        'description': '生成 ANR 分析报告',
        'category': 'analysis',
        'params': {
          'projectId': 'string',
          'issueId': 'string',
          'anrStackTrace': 'string',
          'appVersion': 'string',
          'threadName': 'string（可选）',
          'additionalContext': 'object（可选）',
        },
        'returns': '{success: bool, reportId: string?, reportBody: string?, error: string?}',
      },
      {
        'name': 'skillGetReportsList',
        'description': '获取报告列表',
        'category': 'query',
        'params': {
          'projectId': 'string',
          'bizModule': 'string（可选）',
          'limit': 'int',
          'offset': 'int',
        },
        'returns': '{success: bool, reports: List?, totalCount: int?, error: string?}',
      },
      {
        'name': 'skillGetReportDetail',
        'description': '获取报告详情',
        'category': 'query',
        'params': {
          'projectId': 'string',
          'reportId': 'string',
        },
        'returns': '{success: bool, report: Map?, error: string?}',
      },
      {
        'name': 'skillSearchReports',
        'description': '搜索报告',
        'category': 'query',
        'params': {
          'projectId': 'string',
          'keyword': 'string',
          'limit': 'int',
        },
        'returns': '{success: bool, results: List?, error: string?}',
      },
      {
        'name': 'skillDeleteReport',
        'description': '删除报告',
        'category': 'manage',
        'params': {
          'projectId': 'string',
          'reportId': 'string',
        },
        'returns': '{success: bool, error: string?}',
      },
      {
        'name': 'skillExportReports',
        'description': '导出报告',
        'category': 'manage',
        'params': {
          'projectId': 'string',
          'reportIds': 'List<string>',
          'format': 'string（json / md / html）',
        },
        'returns': '{success: bool, content: string?, format: string?, error: string?}',
      },
      {
        'name': 'skillBatchAnalyzeAndGenerateReports',
        'description': '批量分析问题并生成报告',
        'category': 'analysis',
        'params': {
          'projectId': 'string',
          'issues': 'List<Map>',
          'appVersion': 'string',
        },
        'returns': '{success: bool, reportIds: List?, failedCount: int?, error: string?}',
      },
      {
        'name': 'skillGetReportsStats',
        'description': '获取报告统计信息',
        'category': 'query',
        'params': {
          'projectId': 'string',
        },
        'returns': '{success: bool, stats: Map?, error: string?}',
      },
    ],
  };
}

/// 通用的 skill 调用路由器
///
/// 使用方式：
/// ```
/// final result = await skillInvoke(
///   'skillGenerateCrashAnalysisReport',
///   {
///     'projectId': 'proj_123',
///     'issueId': 'issue_456',
///     'crashStackTrace': '...',
///     'appVersion': '1.0.0',
///   },
/// );
/// ```
Future<Map<String, dynamic>> skillInvoke(String skillName, Map<String, dynamic> params) async {
  switch (skillName) {
    case 'skillGenerateCrashAnalysisReport':
      return skillGenerateCrashAnalysisReport(
        projectId: params['projectId'] ?? '',
        issueId: params['issueId'] ?? '',
        crashStackTrace: params['crashStackTrace'] ?? '',
        appVersion: params['appVersion'] ?? '',
        additionalContext: params['additionalContext'],
      );

    case 'skillGenerateAnrAnalysisReport':
      return skillGenerateAnrAnalysisReport(
        projectId: params['projectId'] ?? '',
        issueId: params['issueId'] ?? '',
        anrStackTrace: params['anrStackTrace'] ?? '',
        appVersion: params['appVersion'] ?? '',
        threadName: params['threadName'],
        additionalContext: params['additionalContext'],
      );

    case 'skillGetReportsList':
      return skillGetReportsList(
        projectId: params['projectId'] ?? '',
        bizModule: params['bizModule'],
        limit: params['limit'] ?? 20,
        offset: params['offset'] ?? 0,
      );

    case 'skillGetReportDetail':
      return skillGetReportDetail(
        projectId: params['projectId'] ?? '',
        reportId: params['reportId'] ?? '',
      );

    case 'skillSearchReports':
      return skillSearchReports(
        projectId: params['projectId'] ?? '',
        keyword: params['keyword'] ?? '',
        limit: params['limit'] ?? 20,
      );

    case 'skillDeleteReport':
      return skillDeleteReport(
        projectId: params['projectId'] ?? '',
        reportId: params['reportId'] ?? '',
      );

    case 'skillExportReports':
      return skillExportReports(
        projectId: params['projectId'] ?? '',
        reportIds: List<String>.from(params['reportIds'] ?? []),
        format: params['format'] ?? 'json',
      );

    case 'skillBatchAnalyzeAndGenerateReports':
      return skillBatchAnalyzeAndGenerateReports(
        projectId: params['projectId'] ?? '',
        issues: List<Map<String, dynamic>>.from(params['issues'] ?? []),
        appVersion: params['appVersion'] ?? '',
      );

    case 'skillGetReportsStats':
      return skillGetReportsStats(
        projectId: params['projectId'] ?? '',
      );

    case 'skillGetAvailableSkills':
      return skillGetAvailableSkills();

    default:
      return {
        'success': false,
        'error': 'Unknown skill: $skillName',
      };
  }
}
