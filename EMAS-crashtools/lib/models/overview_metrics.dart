import '../aliyun/emas_appmonitor_client.dart';

/// 实时概览：多 Biz 下 GetIssues 的聚合规模（与控制台「实时大盘」图表口径可能不同，见 UI 脚注）。
class OverviewMetricsSnapshot {
  const OverviewMetricsSnapshot({
    required this.rangeStartMs,
    required this.rangeEndMs,
    required this.byBizTotal,
    this.crashPreviewItems = const [],
    this.todayCrashTotal,
    this.perBizError = const {},
    this.todayError,
  });

  final int rangeStartMs;
  final int rangeEndMs;
  /// crash / anr / startup / exception
  final Map<String, int> byBizTotal;
  final List<IssueListItem> crashPreviewItems;
  final int? todayCrashTotal;
  final Map<String, String> perBizError;
  final String? todayError;
}
