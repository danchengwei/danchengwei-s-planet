import '../core/baymax_report_parser.dart';
import '../models/emas_issue_summary.dart';

/// 统一报告类型
enum ReportType {
  emas,      // EMAS API 查询结果
  baymax,    // Baymax HTML 导入
  local,     // 本地分析报告
}

/// 报告元数据
class ReportMetadata {
  final String id;
  final String title;
  final DateTime createdAt;
  final String? sourceFile; // 来源文件路径
  final String tags; // 逗号分隔的标签
  final String? description;

  ReportMetadata({
    required this.id,
    required this.title,
    required this.createdAt,
    this.sourceFile,
    this.tags = '',
    this.description,
  });
}

/// 统一报告数据容器
class UnifiedReport {
  final ReportType type;
  final ReportMetadata metadata;
  final dynamic data; // BaymaxReportSummary | EmasReport | LocalAnalysisReport
  final DateTime? lastAccessedAt;

  UnifiedReport({
    required this.type,
    required this.metadata,
    required this.data,
    this.lastAccessedAt,
  });

  /// 获取报告的显示名称
  String get displayName {
    switch (type) {
      case ReportType.baymax:
        if (data is BaymaxReportSummary) {
          return 'Baymax-${metadata.createdAt.year}${metadata.createdAt.month}${metadata.createdAt.day}';
        }
      case ReportType.emas:
        return 'EMAS-${metadata.createdAt.year}${metadata.createdAt.month}${metadata.createdAt.day}';
      case ReportType.local:
        return metadata.title;
    }
    return metadata.title;
  }

  /// 获取项目数量（用于统计展示）
  int get itemCount {
    switch (type) {
      case ReportType.baymax:
        if (data is BaymaxReportSummary) {
          return (data as BaymaxReportSummary).totalCrashItems;
        }
      case ReportType.emas:
        if (data is List<EmasIssueSummary>) {
          return (data as List<EmasIssueSummary>).length;
        }
      case ReportType.local:
        return 0; // 待实现
    }
    return 0;
  }

  /// 获取主要指标
  String get summary {
    switch (type) {
      case ReportType.baymax:
        if (data is BaymaxReportSummary) {
          final report = data as BaymaxReportSummary;
          return 'Java: ${report.javaCrashes.length}, Native: ${report.nativeCrashes.length}';
        }
      case ReportType.emas:
        if (data is List<EmasIssueSummary>) {
          return '${(data as List<EmasIssueSummary>).length} 个问题';
        }
      case ReportType.local:
        return '本地分析';
    }
    return 'N/A';
  }
}

/// EMAS 报告数据结构（统一 API）
class EmasReport {
  final List<EmasIssueSummary> issues;
  final DateTime queryTime;
  final String? bizModule;
  final String? errorType; // 'crash', 'anr', 'lag', 'exception'

  EmasReport({
    required this.issues,
    required this.queryTime,
    this.bizModule,
    this.errorType,
  });

  int get totalIssues => issues.length;
  int get totalErrors => issues.fold(0, (sum, issue) => sum + issue.errorCount);
}

/// 报告导出配置
class ReportExportConfig {
  final String format; // 'md', 'json', 'csv', 'pdf'
  final bool includeStackTrace;
  final bool includeMetadata;
  final bool includeCharts;

  ReportExportConfig({
    required this.format,
    this.includeStackTrace = true,
    this.includeMetadata = true,
    this.includeCharts = false,
  });
}

/// 报告搜索过滤器
class ReportFilter {
  final String? keyword;
  final ReportType? typeFilter;
  final DateTimeRange? dateRange;
  final String? tagFilter;

  ReportFilter({
    this.keyword,
    this.typeFilter,
    this.dateRange,
    this.tagFilter,
  });

  /// 检查报告是否匹配过滤条件
  bool matches(UnifiedReport report) {
    // 关键字匹配
    if (keyword != null && keyword!.isNotEmpty) {
      final titleMatch = report.metadata.title.toLowerCase().contains(keyword!.toLowerCase());
      final descMatch = report.metadata.description?.toLowerCase().contains(keyword!.toLowerCase()) ?? false;
      if (!titleMatch && !descMatch) {
        return false;
      }
    }

    // 类型过滤
    if (typeFilter != null && report.type != typeFilter) {
      return false;
    }

    // 日期范围过滤
    if (dateRange != null) {
      if (report.metadata.createdAt.isBefore(dateRange!.start) ||
          report.metadata.createdAt.isAfter(dateRange!.end)) {
        return false;
      }
    }

    // 标签过滤
    if (tagFilter != null && tagFilter!.isNotEmpty) {
      if (!report.metadata.tags.contains(tagFilter!)) {
        return false;
      }
    }

    return true;
  }
}

/// 日期范围
class DateTimeRange {
  final DateTime start;
  final DateTime end;

  DateTimeRange({
    required this.start,
    required this.end,
  });

  bool contains(DateTime date) => date.isAfter(start) && date.isBefore(end);
}
