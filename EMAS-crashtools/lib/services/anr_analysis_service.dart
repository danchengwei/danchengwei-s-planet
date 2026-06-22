import 'package:intl/intl.dart';

import '../aliyun/emas_appmonitor_client.dart';
import '../models/anr_statistics.dart';
import '../models/tool_config.dart';
import 'aliyun_cli_service.dart';

/// ANR 时间段统计分析服务
/// 负责：生成周期边界、查询 EMAS API、聚合统计数据、计算趋势
class AnrAnalysisService {
  final AliyunCliService _cliService;
  final ToolConfig _config;

  AnrAnalysisService({
    required ToolConfig config,
  })  : _cliService = AliyunCliService(config: config),
        _config = config;

  /// 获取指定周期数的 ANR 统计数据
  ///
  /// [periodCount]: 需要统计的周期数（如 3 表示取最近 3 周）
  /// [granularity]: 周期粒度（日/周/月）
  /// [endTimeMs]: 时间范围的结束时间戳（毫秒）
  /// [bizModule]: 业务模块（crash/anr/lag/custom/memory_leak/memory_alloc 等），默认 anr
  /// [firstVersion]: 要筛选的首现版本（可选，为空表示不筛选），用于过滤问题列表
  /// [topN]: 返回前 N 条错误，默认 10
  /// [orderBy]: 排序字段，支持 ErrorRate/ErrorCount/ErrorDeviceCount/ErrorDeviceRate
  ///
  /// 返回：按时间正序排列的统计数据列表（最早的周期在前）
  /// 如果某个周期查询失败，该周期会被跳过但不会抛异常
  Future<List<AnrPeriodStatistics>> fetchAnrStatistics({
    required int periodCount,
    required PeriodGranularity granularity,
    required int endTimeMs,
    String bizModule = 'anr',
    String? firstVersion,
    int topN = 10,
    String orderBy = 'ErrorRate',
  }) async {
    // 无论选择的粒度是什么，都按天获取数据（这样 UI 可以显示每一天的详情）
    final dayPeriods = _generateDayPeriods(periodCount, granularity, endTimeMs);

    // 依次查询每个周期的 ANR 数据（失败则跳过该周期，不中断流程）
    final results = <AnrPeriodStatistics>[];
    for (final (startMs, endMs, label) in dayPeriods) {
      try {
        final stats = await _fetchSinglePeriodStats(
          startMs: startMs,
          endMs: endMs,
          periodLabel: label,
          bizModule: bizModule,
          firstVersion: firstVersion,
          topN: topN,
          orderBy: orderBy,
        );
        if (stats != null) {
          results.add(stats);
        }
      } catch (e) {
        // 单个周期失败时记录但继续下一个周期
        // 只在全部周期都失败时才在外层抛异常
      }
    }

    return results;
  }

  /// 生成天粒度周期（用于时间段分析）
  /// 无论选择了什么粒度，都返回每一天的时间范围，这样 UI 可以显示每天的详情
  List<(int, int, String)> _generateDayPeriods(
    int periodCount,
    PeriodGranularity granularity,
    int endTimeMs,
  ) {
    final result = <(int, int, String)>[];
    final endDate = DateTime.fromMillisecondsSinceEpoch(endTimeMs);

    // 根据粒度计算总天数
    int totalDays;
    switch (granularity) {
      case PeriodGranularity.day:
        totalDays = periodCount;
      case PeriodGranularity.week:
        totalDays = periodCount * 7;
      case PeriodGranularity.month:
        totalDays = periodCount * 30;
      case PeriodGranularity.custom:
        totalDays = periodCount;
    }

    // 对齐到今天的开始
    final todayStart = DateTime(endDate.year, endDate.month, endDate.day);

    // 从 totalDays 天前开始，逐天生成
    for (int i = totalDays - 1; i >= 0; i--) {
      final dayStart = todayStart.subtract(Duration(days: i));
      final dayEnd = dayStart.add(const Duration(days: 1, milliseconds: -1));

      // 生成日期标签（如"06-20"）
      final label = '${dayStart.month.toString().padLeft(2, '0')}-${dayStart.day.toString().padLeft(2, '0')}';

      result.add((
        dayStart.millisecondsSinceEpoch,
        dayEnd.millisecondsSinceEpoch,
        label,
      ));
    }

    return result;
  }

  /// 生成周期边界（按时间粒度）
  ///
  /// 返回格式：List<(startMs, endMs, periodLabel)>
  /// 例如周粒度、3 周期、endTime=本周四：
  ///   [
  ///     (3周前周一, 3周前周日, "3周前"),
  ///     (2周前周一, 2周前周日, "2周前"),
  ///     (1周前周一, 本周一, "上周"),
  ///   ]
  List<(int, int, String)> _generatePeriodBoundaries({
    required int count,
    required PeriodGranularity granularity,
    required int endTimeMs,
  }) {
    final result = <(int, int, String)>[];
    final endDate = DateTime.fromMillisecondsSinceEpoch(endTimeMs);

    switch (granularity) {
      case PeriodGranularity.day:
        _generateDailyPeriods(count, endDate, result);
      case PeriodGranularity.week:
        _generateWeeklyPeriods(count, endDate, result);
      case PeriodGranularity.month:
        _generateMonthlyPeriods(count, endDate, result);
      case PeriodGranularity.custom:
        // 自定义暂不实现
        break;
    }

    return result;
  }

  /// 生成日粒度周期
  void _generateDailyPeriods(
    int count,
    DateTime endDate,
    List<(int, int, String)> result,
  ) {
    // 对齐到今天的开始
    final todayStart = DateTime(endDate.year, endDate.month, endDate.day);

    for (int i = count - 1; i >= 0; i--) {
      final dayStart = todayStart.subtract(Duration(days: i));
      final dayEnd = dayStart.add(const Duration(days: 1, milliseconds: -1));

      final label = i == 0 ? '今天' : '${count - i} 天前';

      result.add((
        dayStart.millisecondsSinceEpoch,
        dayEnd.millisecondsSinceEpoch,
        label,
      ));
    }
  }

  /// 生成周粒度周期
  /// 周定义：周一至周日
  void _generateWeeklyPeriods(
    int count,
    DateTime endDate,
    List<(int, int, String)> result,
  ) {
    // 对齐到当前周的周日晚 23:59:59
    final currentWeekEnd = _getWeekEnd(endDate);

    for (int i = count - 1; i >= 0; i--) {
      final weekEnd = currentWeekEnd.subtract(Duration(days: 7 * i));
      final weekStart = weekEnd.subtract(const Duration(days: 6));

      // 生成标签
      String label;
      if (i == 0) {
        label = '本周';
      } else if (i == 1) {
        label = '上周';
      } else {
        label = '${count - i} 周前';
      }

      result.add((
        weekStart.millisecondsSinceEpoch,
        weekEnd.millisecondsSinceEpoch,
        label,
      ));
    }
  }

  /// 生成月粒度周期
  void _generateMonthlyPeriods(
    int count,
    DateTime endDate,
    List<(int, int, String)> result,
  ) {
    // 对齐到当前月的最后一天
    var currentDate = DateTime(endDate.year, endDate.month, endDate.day);

    for (int i = count - 1; i >= 0; i--) {
      final month = currentDate.month - i;
      final year = currentDate.year + (month - 1) ~/ 12;
      final adjustedMonth = ((month - 1) % 12) + 1;

      final monthStart = DateTime(year, adjustedMonth, 1);
      final monthEnd = DateTime(year, adjustedMonth + 1, 0, 23, 59, 59, 999);

      final label = i == 0 ? '本月' : DateFormat('yyyy-MM').format(monthStart);

      result.add((
        monthStart.millisecondsSinceEpoch,
        monthEnd.millisecondsSinceEpoch,
        label,
      ));
    }
  }

  /// 获取周末（周日，时间为该天的最后一秒）
  DateTime _getWeekEnd(DateTime date) {
    // 计算从周一开始有多少天
    final daysFromMonday = date.weekday - 1;
    // 周日是本周的最后一天，距离周一 6 天
    final daysToSunday = 6 - daysFromMonday;

    final weekEnd = date.add(Duration(days: daysToSunday));
    return DateTime(weekEnd.year, weekEnd.month, weekEnd.day, 23, 59, 59, 999);
  }

  /// 获取单个周期的 ANR 统计数据
  ///
  /// EMAS API 的 get-issues 返回**各个问题**的统计（按错误率排序），而不是周期聚合。
  /// 为了获取周期的总体数据（总错误数、总设备数等），需要聚合所有问题数据。
  /// 支持通过 firstVersion 筛选特定版本的问题。
  ///
  /// 查询策略：分页查询所有问题（而不是只查 topN），然后按条件筛选。
  Future<AnrPeriodStatistics?> _fetchSinglePeriodStats({
    required int startMs,
    required int endMs,
    required String periodLabel,
    required String bizModule,
    String? firstVersion,
    required int topN,
    required String orderBy,
  }) async {
    try {
      final appKeyInt = int.tryParse(_config.appKey.trim());
      if (appKeyInt == null) {
        throw Exception('Invalid appKey: ${_config.appKey}');
      }

      // 分页查询所有问题（通过 CLI 调用 API）
      final allItems = <IssueListItem>[];
      int pageIndex = 1;
      const pageSize = 500;
      bool hasMorePages = true;
      int totalPages = 0;

      print('[ANR分析] 开始查询问题列表，时间范围: $startMs - $endMs, 业务模块: $bizModule, 版本: $firstVersion');

      while (hasMorePages) {
        print('[ANR分析] 查询第 $pageIndex 页...');
        final result = await _cliService.getIssues(
          bizModule: bizModule,
          os: _config.os.trim(),
          startTimeMs: startMs,
          endTimeMs: endMs,
          pageIndex: pageIndex,
          pageSize: pageSize,
          orderBy: orderBy,
          firstVersion: firstVersion,
        );

        print('[ANR分析] 第 $pageIndex 页返回 ${result.items.length} 条问题');
        allItems.addAll(result.items);

        // 判断是否还有下一页
        totalPages = result.pages ?? 1;
        print('[ANR分析] 总页数: $totalPages, 当前页: $pageIndex');
        hasMorePages = pageIndex < totalPages;
        pageIndex++;
      }

      print('[ANR分析] CLI 查询完成，总问题数: ${allItems.length}');

      // 如果 API 没有返回数据，返回零值统计
      if (allItems.isEmpty) {
        return AnrPeriodStatistics(
          periodLabel: periodLabel,
          startTimeMs: startMs,
          endTimeMs: endMs,
          anrCount: 0,
          affectedDevices: 0,
          errorRate: 0.0,
          affectedDeviceRate: 0,
          createdAt: DateTime.now(),
        );
      }

      // 聚合所有问题的数据（API 已通过 Filter 参数过滤）
      int totalErrorCount = 0;
      int totalErrorDeviceCount = 0;
      double totalErrorRate = 0.0;
      int totalDeviceRate = 0;

      for (final item in allItems) {
        totalErrorCount += item.errorCount ?? 0;
        totalErrorDeviceCount += item.errorDeviceCount ?? 0;
        totalErrorRate += _parseDouble(item.errorRatePercent) ?? 0.0;
        totalDeviceRate += (_parseDouble(item.deviceRatePercent)?.toInt() ?? 0);
      }

      // 错误率和设备率取平均
      if (allItems.isNotEmpty) {
        totalErrorRate = totalErrorRate / allItems.length;
        totalDeviceRate = totalDeviceRate ~/ allItems.length;
      }

      return AnrPeriodStatistics(
        periodLabel: periodLabel,
        startTimeMs: startMs,
        endTimeMs: endMs,
        anrCount: totalErrorCount,
        affectedDevices: totalErrorDeviceCount,
        errorRate: totalErrorRate,
        affectedDeviceRate: totalDeviceRate,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      rethrow;
    }
  }

  /// 计算趋势分析
  /// 输入：多个时间段的统计数据（时间正序）
  /// 返回：包含当前、上一周期、基准周期的趋势对象
  AnrTrendAnalysis? calculateTrend(List<AnrPeriodStatistics> stats) {
    if (stats.isEmpty) return null;

    final current = stats.last;
    final previous = stats.length >= 2 ? stats[stats.length - 2] : null;
    final baseline = stats.length >= 3 ? stats[0] : null;

    return AnrTrendAnalysis(
      current: current,
      previous: previous,
      baseline: baseline,
    );
  }

  /// 数值解析助手
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
