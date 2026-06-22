/// 性能统计服务：卡顿率、卡顿数等指标的数据聚合和导出
import 'dart:math';

/// 性能指标数据
class PerformanceMetric {
  PerformanceMetric({
    required this.date,
    required this.version,
    required this.hangRate, // 卡顿率（百分比）
    required this.hangCount, // 卡顿数
    this.bizModule = 'all',
  });

  final DateTime date;
  final String version;
  final double hangRate; // e.g., 0.1000
  final int hangCount; // e.g., 535
  final String bizModule;

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'version': version,
        'hangRate': hangRate,
        'hangCount': hangCount,
        'bizModule': bizModule,
      };

  factory PerformanceMetric.fromJson(Map<String, dynamic> json) {
    return PerformanceMetric(
      date: DateTime.parse(json['date']),
      version: json['version'],
      hangRate: (json['hangRate'] as num).toDouble(),
      hangCount: json['hangCount'] ?? 0,
      bizModule: json['bizModule'] ?? 'all',
    );
  }
}

/// 性能统计过滤条件
class PerformanceStatFilter {
  PerformanceStatFilter({
    this.startDate,
    this.endDate,
    this.versions = const [],
    this.bizModules = const ['crash', 'anr'],
    this.groupBy = 'day', // 'day', 'week', 'month'
  });

  DateTime? startDate;
  DateTime? endDate;
  List<String> versions; // e.g., ['10.16.03', '10.17.15']
  List<String> bizModules;
  String groupBy; // 按日期分组粒度
}

/// 聚合统计结果
class AggregatedStats {
  AggregatedStats({
    required this.period, // e.g., '2025-03-13', 'week', 'average'
    required this.versionStats, // Map<version, stat>
    required this.totalHangRate,
    required this.totalHangCount,
  });

  final String period;
  final Map<String, PerformanceStat> versionStats;
  final double totalHangRate;
  final int totalHangCount;

  String get formattedRate => '${(totalHangRate * 100).toStringAsFixed(4)}%';

  Map<String, dynamic> toJson() => {
        'period': period,
        'versionStats': versionStats.map((k, v) => MapEntry(k, v.toJson())),
        'totalHangRate': totalHangRate,
        'totalHangCount': totalHangCount,
      };
}

class PerformanceStat {
  PerformanceStat({
    required this.version,
    required this.hangRate,
    required this.hangCount,
    this.dayCount = 1,
  });

  final String version;
  final double hangRate;
  final int hangCount;
  final int dayCount; // 用于计算平均值

  String get formattedRate => '${(hangRate * 100).toStringAsFixed(4)}%';

  Map<String, dynamic> toJson() => {
        'version': version,
        'hangRate': hangRate,
        'hangCount': hangCount,
        'dayCount': dayCount,
      };
}

/// 性能统计服务
class PerformanceStatsService {
  PerformanceStatsService();

  final List<PerformanceMetric> _metrics = [];

  /// 添加指标数据
  void addMetric(PerformanceMetric metric) {
    _metrics.add(metric);
  }

  /// 添加多个指标
  void addMetrics(List<PerformanceMetric> metrics) {
    _metrics.addAll(metrics);
  }

  /// 加载示例数据（对应用户提供的表格）
  void loadSampleData() {
    final sampleData = [
      // 3月13日
      PerformanceMetric(date: DateTime(2025, 3, 13), version: '10.16.03', hangRate: 0.001000, hangCount: 535),
      PerformanceMetric(date: DateTime(2025, 3, 13), version: '10.17.15', hangRate: 0.000530, hangCount: 604),
      // 3月14日
      PerformanceMetric(date: DateTime(2025, 3, 14), version: '10.16.03', hangRate: 0.000900, hangCount: 821),
      PerformanceMetric(date: DateTime(2025, 3, 14), version: '10.17.15', hangRate: 0.000560, hangCount: 1130),
      // 3月15日
      PerformanceMetric(date: DateTime(2025, 3, 15), version: '10.16.03', hangRate: 0.000750, hangCount: 407),
      PerformanceMetric(date: DateTime(2025, 3, 15), version: '10.17.15', hangRate: 0.000430, hangCount: 572),
      // 3月16日
      PerformanceMetric(date: DateTime(2025, 3, 16), version: '10.16.03', hangRate: 0.000530, hangCount: 141),
      PerformanceMetric(date: DateTime(2025, 3, 16), version: '10.17.15', hangRate: 0.000350, hangCount: 274),
      // 3月17日
      PerformanceMetric(date: DateTime(2025, 3, 17), version: '10.16.03', hangRate: 0.000460, hangCount: 76),
      PerformanceMetric(date: DateTime(2025, 3, 17), version: '10.17.15', hangRate: 0.000270, hangCount: 133),
      // 3月18日
      PerformanceMetric(date: DateTime(2025, 3, 18), version: '10.16.03', hangRate: 0.000530, hangCount: 80),
      PerformanceMetric(date: DateTime(2025, 3, 18), version: '10.17.15', hangRate: 0.000310, hangCount: 149),
      // 3月19日
      PerformanceMetric(date: DateTime(2025, 3, 19), version: '10.16.03', hangRate: 0.000270, hangCount: 9),
      PerformanceMetric(date: DateTime(2025, 3, 19), version: '10.17.15', hangRate: 0.000160, hangCount: 19),
    ];
    addMetrics(sampleData);
  }

  /// 根据过滤条件获取统计数据
  List<AggregatedStats> getFilteredStats(PerformanceStatFilter filter) {
    // 1. 过滤指标
    var filtered = _metrics.where((m) {
      // 日期范围
      if (filter.startDate != null && m.date.isBefore(filter.startDate!)) return false;
      if (filter.endDate != null && m.date.isAfter(filter.endDate!)) return false;

      // 版本
      if (filter.versions.isNotEmpty && !filter.versions.contains(m.version)) return false;

      // 业务模块
      if (filter.bizModules.isNotEmpty && !filter.bizModules.contains(m.bizModule)) return false;

      return true;
    }).toList();

    if (filtered.isEmpty) return [];

    // 2. 按日期分组
    final grouped = <String, List<PerformanceMetric>>{};
    for (final metric in filtered) {
      final key = _getGroupKey(metric.date, filter.groupBy);
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(metric);
    }

    // 3. 计算聚合统计
    final results = <AggregatedStats>[];
    for (final entry in grouped.entries) {
      final versionStats = <String, PerformanceStat>{};
      double totalRate = 0;
      int totalCount = 0;
      int versionCount = 0;

      // 按版本聚合
      final byVersion = <String, List<PerformanceMetric>>{};
      for (final metric in entry.value) {
        byVersion.putIfAbsent(metric.version, () => []);
        byVersion[metric.version]!.add(metric);
      }

      for (final versionEntry in byVersion.entries) {
        final metrics = versionEntry.value;
        final avgRate = metrics.fold(0.0, (sum, m) => sum + m.hangRate) / metrics.length;
        final totalHangCount = metrics.fold(0, (sum, m) => sum + m.hangCount);

        versionStats[versionEntry.key] = PerformanceStat(
          version: versionEntry.key,
          hangRate: avgRate,
          hangCount: totalHangCount,
          dayCount: metrics.length,
        );

        totalRate += avgRate;
        totalCount += totalHangCount;
        versionCount++;
      }

      results.add(AggregatedStats(
        period: entry.key,
        versionStats: versionStats,
        totalHangRate: totalRate / versionCount,
        totalHangCount: totalCount,
      ));
    }

    // 按日期排序
    results.sort((a, b) => a.period.compareTo(b.period));
    return results;
  }

  /// 获取日均统计
  AggregatedStats? getAverageStats(PerformanceStatFilter filter) {
    final allStats = getFilteredStats(filter);
    if (allStats.isEmpty) return null;

    final allVersionStats = <String, List<PerformanceStat>>{};

    for (final stat in allStats) {
      for (final entry in stat.versionStats.entries) {
        allVersionStats.putIfAbsent(entry.key, () => []);
        allVersionStats[entry.key]!.add(entry.value);
      }
    }

    final versionStats = <String, PerformanceStat>{};
    double totalRate = 0;
    int totalCount = 0;

    for (final entry in allVersionStats.entries) {
      final stats = entry.value;
      final avgRate = stats.fold(0.0, (sum, s) => sum + s.hangRate) / stats.length;
      final totalHangCount = stats.fold(0, (sum, s) => sum + s.hangCount);

      versionStats[entry.key] = PerformanceStat(
        version: entry.key,
        hangRate: avgRate,
        hangCount: totalHangCount,
        dayCount: stats.length,
      );

      totalRate += avgRate;
      totalCount += totalHangCount;
    }

    return AggregatedStats(
      period: 'average',
      versionStats: versionStats,
      totalHangRate: totalRate / versionStats.length,
      totalHangCount: totalCount,
    );
  }

  /// 获取周统计
  AggregatedStats? getWeekStats(PerformanceStatFilter filter, {int weeksAgo = 0}) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1 + weeksAgo * 7));
    final weekEnd = weekStart.add(const Duration(days: 7));

    final weekFilter = PerformanceStatFilter(
      startDate: weekStart,
      endDate: weekEnd,
      versions: filter.versions,
      bizModules: filter.bizModules,
    );

    return getAverageStats(weekFilter);
  }

  /// 导出为表格格式
  String exportAsTable(List<AggregatedStats> stats, List<String> versions) {
    final buffer = StringBuffer();

    // 表头
    buffer.writeln('日期\t${versions.map((v) => '$v(卡顿率)').join('\t')}\t全部(卡顿率)\t${versions.map((v) => '$v(卡顿数)').join('\t')}\t全部(卡顿数)');

    // 数据行
    for (final stat in stats) {
      buffer.write('${stat.period}');

      // 卡顿率
      for (final version in versions) {
        final vStat = stat.versionStats[version];
        buffer.write('\t${vStat?.formattedRate ?? 'N/A'}');
      }
      buffer.write('\t${stat.formattedRate}');

      // 卡顿数
      for (final version in versions) {
        final vStat = stat.versionStats[version];
        buffer.write('\t${vStat?.hangCount ?? 0}');
      }
      buffer.write('\t${stat.totalHangCount}');

      buffer.writeln();
    }

    return buffer.toString();
  }

  /// 导出为 JSON 格式
  String exportAsJson(List<AggregatedStats> stats) {
    return stats.map((s) => s.toJson()).toList().toString();
  }

  String _getGroupKey(DateTime date, String groupBy) {
    switch (groupBy) {
      case 'week':
        final weekStart = date.subtract(Duration(days: date.weekday - 1));
        return '${weekStart.year}-W${(date.day ~/ 7) + 1}';
      case 'month':
        return '${date.year}-${date.month.toString().padLeft(2, '0')}';
      case 'day':
      default:
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }

  /// 生成完整的统计报告
  PerformanceReport generateReport(PerformanceStatFilter filter) {
    final dailyStats = getFilteredStats(filter);
    final averageStats = getAverageStats(filter);
    final lastWeekStats = getWeekStats(filter, weeksAgo: 0);
    final lastLastWeekStats = getWeekStats(filter, weeksAgo: 1);

    final versions = _metrics.map((m) => m.version).toSet().toList()..sort();

    return PerformanceReport(
      filter: filter,
      dailyStats: dailyStats,
      averageStats: averageStats,
      lastWeekStats: lastWeekStats,
      lastLastWeekStats: lastLastWeekStats,
      versions: versions,
    );
  }
}

/// 性能统计报告
class PerformanceReport {
  PerformanceReport({
    required this.filter,
    required this.dailyStats,
    required this.averageStats,
    required this.lastWeekStats,
    required this.lastLastWeekStats,
    required this.versions,
  });

  final PerformanceStatFilter filter;
  final List<AggregatedStats> dailyStats;
  final AggregatedStats? averageStats;
  final AggregatedStats? lastWeekStats;
  final AggregatedStats? lastLastWeekStats;
  final List<String> versions;

  /// 导出为表格格式
  String toTable() {
    final service = PerformanceStatsService();
    final buffer = StringBuffer();

    // 日期统计表
    buffer.writeln('=== 日期统计 ===');
    buffer.writeln(service.exportAsTable(dailyStats, versions));

    // 周期汇总表
    buffer.writeln('\n=== 周期汇总 ===');
    final summaryStats = <AggregatedStats>[];
    if (averageStats != null) summaryStats.add(averageStats!);
    if (lastWeekStats != null) summaryStats.add(lastWeekStats!);
    if (lastLastWeekStats != null) summaryStats.add(lastLastWeekStats!);

    buffer.writeln(service.exportAsTable(summaryStats, versions));

    return buffer.toString();
  }

  /// 生成 HTML 表格
  String toHtml() {
    final buffer = StringBuffer();
    buffer.writeln('<table border="1" cellpadding="10">');

    // 表头
    buffer.write('<tr><th>日期</th>');
    for (final version in versions) {
      buffer.write('<th>$version(卡顿率)</th>');
    }
    buffer.write('<th>全部(卡顿率)</th>');
    for (final version in versions) {
      buffer.write('<th>$version(卡顿数)</th>');
    }
    buffer.writeln('<th>全部(卡顿数)</th></tr>');

    // 数据行
    for (final stat in dailyStats) {
      buffer.write('<tr><td>${stat.period}</td>');

      for (final version in versions) {
        final vStat = stat.versionStats[version];
        buffer.write('<td>${vStat?.formattedRate ?? 'N/A'}</td>');
      }
      buffer.write('<td>${stat.formattedRate}</td>');

      for (final version in versions) {
        final vStat = stat.versionStats[version];
        buffer.write('<td>${vStat?.hangCount ?? 0}</td>');
      }
      buffer.writeln('<td>${stat.totalHangCount}</td></tr>');
    }

    buffer.writeln('</table>');
    return buffer.toString();
  }
}
