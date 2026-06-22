import '../aliyun/emas_appmonitor_client.dart';

/// 单个时间段的 ANR 统计数据
class AnrPeriodStatistics {
  final String periodLabel;           // "本周" / "2024-06-01 ~ 2024-06-07"
  final int startTimeMs;
  final int endTimeMs;
  final int anrCount;                 // 错误次数
  final int affectedDevices;          // 影响设备数
  final double errorRate;             // 错误率（0-1 之间）
  final int affectedDeviceRate;       // 设备率（百分比）
  final DateTime createdAt;           // 数据获取时间

  AnrPeriodStatistics({
    required this.periodLabel,
    required this.startTimeMs,
    required this.endTimeMs,
    required this.anrCount,
    required this.affectedDevices,
    required this.errorRate,
    required this.affectedDeviceRate,
    required this.createdAt,
  });

  /// 从 GetIssues 原始数据转换
  /// 注意：errorRatePercent 和 deviceRatePercent 已是百分比形式（0-100），需转换为小数形式（0-1）
  factory AnrPeriodStatistics.fromGetIssuesItem(
    IssueListItem item, {
    required String periodLabel,
    required int startTimeMs,
    required int endTimeMs,
  }) {
    final rateValue = _parseDouble(item.errorRatePercent) ?? 0.0;
    // 如果 rateValue > 1，说明是百分比形式（0-100），需要除以 100
    final normalizedRate = rateValue > 1 ? rateValue / 100 : rateValue;

    return AnrPeriodStatistics(
      periodLabel: periodLabel,
      startTimeMs: startTimeMs,
      endTimeMs: endTimeMs,
      anrCount: item.errorCount ?? 0,
      affectedDevices: item.errorDeviceCount ?? 0,
      errorRate: normalizedRate,
      affectedDeviceRate: _parseDouble(item.deviceRatePercent)?.toInt() ?? 0,
      createdAt: DateTime.now(),
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

/// 趋势分析结果
class AnrTrendAnalysis {
  final AnrPeriodStatistics current;       // 当前周期
  final AnrPeriodStatistics? previous;     // 上一周期（可选）
  final AnrPeriodStatistics? baseline;     // 基准周期（可选）

  AnrTrendAnalysis({
    required this.current,
    this.previous,
    this.baseline,
  });

  /// 同比：与上一周期的百分比变化（当前 vs 上一周期）
  /// 返回百分比，如 +10.5 表示增长 10.5%，-5.2 表示下降 5.2%
  double? getYoYTrend(String metric) {
    if (previous == null) return null;

    switch (metric) {
      case 'count':
        return _calculateTrendPercent(current.anrCount.toDouble(), previous!.anrCount.toDouble());
      case 'devices':
        return _calculateTrendPercent(current.affectedDevices.toDouble(), previous!.affectedDevices.toDouble());
      case 'rate':
        return _calculateTrendPercent(current.errorRate, previous!.errorRate);
      default:
        return null;
    }
  }

  /// 环比：与基准周期的百分比变化（当前 vs 基准）
  double? getQoQTrend(String metric) {
    if (baseline == null) return null;

    switch (metric) {
      case 'count':
        return _calculateTrendPercent(current.anrCount.toDouble(), baseline!.anrCount.toDouble());
      case 'devices':
        return _calculateTrendPercent(current.affectedDevices.toDouble(), baseline!.affectedDevices.toDouble());
      case 'rate':
        return _calculateTrendPercent(current.errorRate, baseline!.errorRate);
      default:
        return null;
    }
  }

  /// 趋势方向
  TrendDirection getTrendDirection(String metric) {
    final trend = getYoYTrend(metric);
    if (trend == null) return TrendDirection.stable;

    // 对于错误率等"越低越好"的指标，需要反向判断
    if (metric == 'rate' || metric == 'errorDeviceRate') {
      return trend < -5
          ? TrendDirection.down  // 率下降是好的
          : trend > 5
              ? TrendDirection.up  // 率上升是坏的
              : TrendDirection.stable;
    }

    // 对于 count/devices 等"越低越好"的指标
    return trend < -5
        ? TrendDirection.down
        : trend > 5
            ? TrendDirection.up
            : TrendDirection.stable;
  }

  static double? _calculateTrendPercent(double current, double previous) {
    if (previous == 0) return null;
    return ((current - previous) / previous) * 100;
  }
}

enum TrendDirection {
  up,
  down,
  stable,
}

/// 用户界面选择的参数
class AnrAnalysisQuery {
  final int periodCount;              // 需要统计的周期数（如 3 周）
  final PeriodGranularity granularity;

  AnrAnalysisQuery({
    this.periodCount = 3,
    this.granularity = PeriodGranularity.week,
  });
}

enum PeriodGranularity {
  day,
  week,
  month,
  custom,
}

extension PeriodGranularityExt on PeriodGranularity {
  String get displayName {
    switch (this) {
      case PeriodGranularity.day:
        return '日';
      case PeriodGranularity.week:
        return '周';
      case PeriodGranularity.month:
        return '月';
      case PeriodGranularity.custom:
        return '自定义';
    }
  }

  /// 转换为 EMAS API 粒度单位
  String get emasGranularityUnit {
    switch (this) {
      case PeriodGranularity.day:
        return 'DAY';
      case PeriodGranularity.week:
        return 'DAY';  // 周由多个日聚合
      case PeriodGranularity.month:
        return 'DAY';  // 月由多个日聚合
      case PeriodGranularity.custom:
        return 'DAY';
    }
  }

  /// 返回一个周期包含的毫秒数
  int getPeriodDurationMs() {
    switch (this) {
      case PeriodGranularity.day:
        return 24 * 60 * 60 * 1000;
      case PeriodGranularity.week:
        return 7 * 24 * 60 * 60 * 1000;
      case PeriodGranularity.month:
        return 30 * 24 * 60 * 60 * 1000;
      case PeriodGranularity.custom:
        return 0;  // 自定义不定义
    }
  }
}
