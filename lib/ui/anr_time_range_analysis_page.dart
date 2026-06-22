import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/anr_statistics.dart';
import '../constants/app_constants.dart';
import 'widgets/version_filter_widget.dart';

/// 时间段统计分析页面（支持 ANR、卡顿率等多个业务模块）
/// 支持：手动时间范围选择 + 快捷周期选择（最近 1/2/3 周）
class AnrTimeRangeAnalysisPage extends StatefulWidget {
  const AnrTimeRangeAnalysisPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<AnrTimeRangeAnalysisPage> createState() => _AnrTimeRangeAnalysisPageState();
}

class _AnrTimeRangeAnalysisPageState extends State<AnrTimeRangeAnalysisPage> {
  late DateTime? _startDate;
  late DateTime? _endDate;
  late int _quickWeekCount;
  late String? _selectedVersion;
  late String _selectedBizModule;  // 选择的业务模块
  late List<String> _availableVersions;  // 可用版本列表
  late bool _loadingVersions;

  @override
  void initState() {
    super.initState();
    // 默认：最近 3 周，业务模块为 ANR
    _quickWeekCount = 3;
    _startDate = null;
    _endDate = null;
    _selectedVersion = null;  // null 表示不筛选版本
    _selectedBizModule = 'anr';  // 默认 ANR
    _availableVersions = [];
    _loadingVersions = false;
    // 页面进入时自动加载版本列表（但不执行查询）
    Future.microtask(() => _initializeVersions());
  }

  /// 页面初始化时加载版本列表（仅加载版本，不触发查询）
  Future<void> _initializeVersions() async {
    final now = DateTime.now();
    final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final startDate = endDate.subtract(Duration(days: _quickWeekCount * 7));

    setState(() {
      _startDate = startDate;
      _endDate = endDate;
      _loadingVersions = true;
    });

    // 注意：这里不调用 setWorkspaceBizOverride()，避免触发不必要的 controller 更新
    // 版本列表只需要知道业务模块和时间范围，直接传参获取即可
    await _fetchAvailableVersions(startDate, endDate, _quickWeekCount);
  }


  /// 页面进入或切换业务模块时，只加载版本列表（不查询数据）
  Future<void> _loadVersionsForCurrentModule() async {
    final now = DateTime.now();
    final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final startDate = endDate.subtract(Duration(days: _quickWeekCount * 7));

    setState(() {
      _loadingVersions = true;
    });

    widget.controller.setWorkspaceBizOverride(_selectedBizModule);
    await _fetchAvailableVersions(startDate, endDate, _quickWeekCount);
  }

  /// 快捷选择周期后，重新加载该周期的版本列表（仍然不查询数据）
  Future<void> _selectQuickPeriod(int weekCount) async {
    final now = DateTime.now();
    final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final startDate = endDate.subtract(Duration(days: weekCount * 7));

    setState(() {
      _quickWeekCount = weekCount;
      _startDate = startDate;
      _endDate = endDate;
      _selectedVersion = null;  // 重置版本选择
      _loadingVersions = true;
    });

    // 不调用 setWorkspaceBizOverride()，避免触发不必要的 controller 更新
    await _fetchAvailableVersions(startDate, endDate, weekCount);
  }

  /// 业务模块切换时的回调
  Future<void> _changeBizModule(String module) async {
    final now = DateTime.now();
    final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final startDate = endDate.subtract(Duration(days: _quickWeekCount * 7));

    setState(() {
      _selectedBizModule = module;
      _selectedVersion = null;  // 切换模块时重置版本选择
      _loadingVersions = true;
    });

    // 不调用 setWorkspaceBizOverride()，避免触发不必要的 controller 更新
    // 业务模块切换只需要在用户点"开始统计"时才真正应用到 controller
    await _fetchAvailableVersions(startDate, endDate, _quickWeekCount);
  }

  /// 获取可用的版本列表
  /// 调用统一的版本获取方法，展示所有真实数据中的版本
  Future<void> _fetchAvailableVersions(DateTime startDate, DateTime endDate, int weekCount) async {
    try {
      final versions = await widget.controller.fetchAvailableVersions(
        bizModule: _selectedBizModule,
        startTimeMs: startDate.millisecondsSinceEpoch,
        endTimeMs: endDate.millisecondsSinceEpoch,
      );

      setState(() {
        _availableVersions = versions;
        _loadingVersions = false;
      });
    } catch (e) {
      setState(() {
        _availableVersions = [];
        _loadingVersions = false;
      });
    }
  }

  /// 加载自定义时间范围数据
  Future<void> _loadCustomData() async {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择开始和结束日期')),
      );
      return;
    }

    // 同步更新 controller 的时间范围（关键：必须在查询前同步）
    widget.controller.setTimeRange(_startDate!, _endDate!);

    // 计算两个日期之间相差多少周
    final diffDays = _endDate!.difference(_startDate!).inDays;
    final weekCount = (diffDays / 7).ceil().clamp(1, 52);

    // 设置业务模块
    widget.controller.setWorkspaceBizOverride(_selectedBizModule);

    // 应用版本筛选（如果选中了版本）
    if (_selectedVersion != null && _selectedVersion!.isNotEmpty) {
      widget.controller.setAnrAnalysisVersionFilter(_selectedVersion!);
    } else {
      widget.controller.setAnrAnalysisVersionFilter('');
    }

    // 执行查询
    await widget.controller.fetchAnrTimeRangeStatistics(
      periodCount: weekCount,
      granularity: PeriodGranularity.week,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // 标题
              Text(
                'ANR 时间段统计分析',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.35,
                ),
              ),
              const SizedBox(height: 20),

              // 查询条件卡片
              Card(
                elevation: 0,
                color: cs.surfaceContainerHighest.withValues(alpha: kOpacityMedium),
                shape: RoundedRectangleBorder(
                  borderRadius: AppBorderRadius.lg,
                  side: BorderSide(color: cs.outlineVariant.withValues(alpha: kOpacityLight)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '业务模块',
                        style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('ANR'),
                            selected: _selectedBizModule == 'anr',
                            onSelected: (_) => _changeBizModule('anr'),
                          ),
                          FilterChip(
                            label: const Text('卡顿率'),
                            selected: _selectedBizModule == 'lag',
                            onSelected: (_) => _changeBizModule('lag'),
                          ),
                          FilterChip(
                            label: const Text('崩溃'),
                            selected: _selectedBizModule == 'crash',
                            onSelected: (_) => _changeBizModule('crash'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Divider(color: cs.outlineVariant.withValues(alpha: kOpacityLight), height: 1),
                      const SizedBox(height: 14),
                      Text(
                        '快捷选择',
                        style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('最近 1 周'),
                            selected: _quickWeekCount == 1,
                            onSelected: (_) => _selectQuickPeriod(1),
                          ),
                          FilterChip(
                            label: const Text('最近 2 周'),
                            selected: _quickWeekCount == 2,
                            onSelected: (_) => _selectQuickPeriod(2),
                          ),
                          FilterChip(
                            label: const Text('最近 3 周'),
                            selected: _quickWeekCount == 3,
                            onSelected: (_) => _selectQuickPeriod(3),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Divider(color: cs.outlineVariant.withValues(alpha: kOpacityLight), height: 1),
                      const SizedBox(height: 14),
                      Text(
                        '版本筛选',
                        style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      _buildVersionFilterField(context, cs, textTheme),
                      const SizedBox(height: 14),
                      Divider(color: cs.outlineVariant.withValues(alpha: kOpacityLight), height: 1),
                      const SizedBox(height: 14),
                      Text(
                        '时间范围',
                        style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      _buildCustomDateRangePicker(context, cs, textTheme),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: widget.controller.loadingAnrStats
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: cs.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.play_arrow, size: 18),
                          label: Text(widget.controller.loadingAnrStats ? '统计中…' : '开始统计'),
                          onPressed: widget.controller.loadingAnrStats ? null : _loadCustomData,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 统计数据展示
              _buildStatisticsSection(context, cs, textTheme),
              const SizedBox(height: 24),

              // 趋势分析
              _buildTrendAnalysisSection(context, cs, textTheme),
            ],
          ),
          ),
        );
      },
    );
  }

  /// 自定义时间范围选择器
  Widget _buildCustomDateRangePicker(BuildContext context, ColorScheme cs, TextTheme textTheme) {
    final fmt = (DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 日期选择按钮行
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(
                  _startDate != null ? fmt(_startDate!) : '开始日期',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _startDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _startDate = picked);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(
                  _endDate != null ? fmt(_endDate!) : '结束日期',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _endDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _endDate = picked);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 按周分组的统计数据表格
  Widget _buildWeeklyStatisticsTable(
    BuildContext context,
    List<AnrPeriodStatistics> stats,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    // 按周分组统计
    final weeklyGroups = _groupStatisticsByWeek(stats);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...weeklyGroups.map((weekData) {
            return _buildWeekTable(context, weekData, cs, textTheme);
          }),
        ],
      ),
    );
  }

  /// 按周分组统计数据（按日期自动分组成周）
  List<_WeeklyDataGroup> _groupStatisticsByWeek(List<AnrPeriodStatistics> stats) {
    if (stats.isEmpty) return [];

    final result = <_WeeklyDataGroup>[];
    var currentWeek = <AnrPeriodStatistics>[];
    var currentWeekLabel = '';

    for (var i = 0; i < stats.length; i++) {
      final stat = stats[i];
      // 从时间戳计算周号（周一-周日），生成周标签
      final date = DateTime.fromMillisecondsSinceEpoch(stat.startTimeMs);
      final weekLabel = _getWeekLabel(date);

      if (currentWeekLabel.isEmpty) {
        currentWeekLabel = weekLabel;
      }

      if (weekLabel == currentWeekLabel) {
        currentWeek.add(stat);
      } else {
        if (currentWeek.isNotEmpty) {
          result.add(_WeeklyDataGroup(
            weekLabel: currentWeekLabel,
            dailyStats: currentWeek,
          ));
        }
        currentWeek = [stat];
        currentWeekLabel = weekLabel;
      }
    }

    // 添加最后一周
    if (currentWeek.isNotEmpty) {
      result.add(_WeeklyDataGroup(
        weekLabel: currentWeekLabel,
        dailyStats: currentWeek,
      ));
    }

    return result;
  }

  /// 根据日期生成周标签（如"本周"、"上周"等）
  String _getWeekLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentWeekEnd = _getWeekEnd(today);
    final currentWeekStart = currentWeekEnd.subtract(const Duration(days: 6));

    // 判断日期属于哪一周
    if (date.isAfter(currentWeekStart) && date.isBefore(currentWeekEnd.add(const Duration(days: 1)))) {
      return '本周';
    }

    final lastWeekEnd = currentWeekStart.subtract(const Duration(days: 1));
    final lastWeekStart = lastWeekEnd.subtract(const Duration(days: 6));
    if (date.isAfter(lastWeekStart) && date.isBefore(lastWeekEnd.add(const Duration(days: 1)))) {
      return '上周';
    }

    // 计算周数差（倒推）
    final weeksAgo = ((today.difference(date).inDays) / 7).ceil();
    return '${weeksAgo}周前';
  }

  /// 获取周末（周日，时间为该天的开始）
  DateTime _getWeekEnd(DateTime date) {
    final daysFromMonday = date.weekday - 1;
    final daysToSunday = 6 - daysFromMonday;
    final weekEnd = date.add(Duration(days: daysToSunday));
    return DateTime(weekEnd.year, weekEnd.month, weekEnd.day);
  }

  /// 构建周表格
  Widget _buildWeekTable(
    BuildContext context,
    _WeeklyDataGroup weekData,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final weekTotal = weekData.calculateWeeklyTotal();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.lg,
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: kOpacityLight)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 周标题
            Text(
              weekData.weekLabel,
              style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            // 表格
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 12,
                horizontalMargin: 8,
                dataRowHeight: 36,
                headingRowHeight: 40,
                columns: [
                  DataColumn(label: Text('日期', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text('版本', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text('次数', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text('设备数', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text('错误率', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
                ],
                rows: [
                  ...weekData.dailyStats.map((stat) {
                    final date = DateTime.fromMillisecondsSinceEpoch(stat.startTimeMs);
                    final dateStr = '${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
                    final versionStr = _selectedVersion?.isNotEmpty == true ? _selectedVersion! : '全部';

                    return DataRow(cells: [
                      DataCell(Text(dateStr, style: textTheme.bodySmall)),
                      DataCell(Text(versionStr, style: textTheme.bodySmall)),
                      DataCell(Text('${stat.anrCount}', style: textTheme.bodySmall)),
                      DataCell(Text('${stat.affectedDevices}', style: textTheme.bodySmall)),
                      DataCell(Text('${(stat.errorRate * 100).toStringAsFixed(2)}%', style: textTheme.bodySmall)),
                    ]);
                  }),
                  // 周汇总行
                  DataRow(
                    color: MaterialStateProperty.all(cs.surfaceContainerHighest.withValues(alpha: 0.5)),
                    cells: [
                      DataCell(Text('周汇总', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
                      DataCell(Text('', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
                      DataCell(Text('${weekTotal['count']}', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
                      DataCell(Text('${weekTotal['devices']}', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
                      DataCell(Text('${(weekTotal['rate'] * 100).toStringAsFixed(2)}%', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 版本筛选下拉框
  Widget _buildVersionFilterField(BuildContext context, ColorScheme cs, TextTheme textTheme) {
    if (_loadingVersions) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '加载版本中...',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return VersionFilterWidget(
      versions: _availableVersions,
      selectedVersion: _selectedVersion,
      onVersionChanged: (version) {
        setState(() => _selectedVersion = version);
      },
      isLoading: _loadingVersions,
    );
  }

  Widget _buildStatisticsSection(BuildContext context, ColorScheme cs, TextTheme textTheme) {
    if (widget.controller.loadingAnrStats) {
      return Center(
        child: Column(
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: 12),
            Text(
              '正在查询 ANR 数据…',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (widget.controller.anrStatsError != null) {
      return Material(
        color: cs.errorContainer.withValues(alpha: kOpacityHeavy),
        borderRadius: AppBorderRadius.md,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: cs.onErrorContainer, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '查询失败',
                      style: textTheme.titleSmall?.copyWith(color: cs.onErrorContainer),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.controller.anrStatsError!,
                style: textTheme.bodySmall?.copyWith(color: cs.onErrorContainer),
              ),
            ],
          ),
        ),
      );
    }

    final stats = widget.controller.anrStatistics;
    if (stats.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.info_outline, color: cs.onSurfaceVariant, size: 40),
              const SizedBox(height: 12),
              Text(
                '暂无数据',
                style: textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                '所选时间段内无 ANR 数据',
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '统计数据',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        _buildWeeklyStatisticsTable(context, stats, cs, textTheme),
      ],
    );
  }

  Widget _buildTrendAnalysisSection(BuildContext context, ColorScheme cs, TextTheme textTheme) {
    final trend = widget.controller.anrTrendAnalysis;
    if (trend == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '趋势分析',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: AppBorderRadius.lg,
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: kOpacityLight)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '与上一周期对比',
                  style: textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                _TrendRow(
                  label: 'ANR 错误次数',
                  trend: trend.getYoYTrend('count'),
                  direction: trend.getTrendDirection('count'),
                ),
                const SizedBox(height: 10),
                _TrendRow(
                  label: '影响设备数',
                  trend: trend.getYoYTrend('devices'),
                  direction: trend.getTrendDirection('devices'),
                ),
                const SizedBox(height: 10),
                _TrendRow(
                  label: '错误率',
                  trend: trend.getYoYTrend('rate'),
                  direction: trend.getTrendDirection('rate'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// ANR 统计数据卡片
class _AnrStatCard extends StatelessWidget {
  const _AnrStatCard({required this.stat});

  final AnrPeriodStatistics stat;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.lg,
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: kOpacityLight)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stat.periodLabel,
              style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatItem(
                  label: 'ANR 次数',
                  value: '${stat.anrCount}',
                  color: cs.primary,
                ),
                _StatItem(
                  label: '影响设备',
                  value: '${stat.affectedDevices}',
                  color: cs.secondary,
                ),
                _StatItem(
                  label: '错误率',
                  value: '${(stat.errorRate * 100).toStringAsFixed(2)}%',
                  color: cs.tertiary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个统计项
class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 周数据分组模型
class _WeeklyDataGroup {
  final String weekLabel;
  final List<AnrPeriodStatistics> dailyStats;

  _WeeklyDataGroup({
    required this.weekLabel,
    required this.dailyStats,
  });

  /// 计算周汇总（周错误率 = 周总次数 / 周总设备数）
  Map<String, dynamic> calculateWeeklyTotal() {
    int totalCount = 0;
    int totalDevices = 0;

    for (final stat in dailyStats) {
      totalCount += stat.anrCount;
      totalDevices += stat.affectedDevices;
    }

    // 周错误率：总次数 / 总设备数；如果无数据则为 0
    final weekRate = totalDevices > 0 ? totalCount.toDouble() / totalDevices : 0.0;

    return {
      'count': totalCount,
      'devices': totalDevices,
      'rate': weekRate,
    };
  }
}

/// 趋势行
class _TrendRow extends StatelessWidget {
  const _TrendRow({
    required this.label,
    required this.trend,
    required this.direction,
  });

  final String label;
  final double? trend;
  final TrendDirection direction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Color trendColor;
    String trendText;
    IconData trendIcon;

    if (trend == null) {
      trendColor = cs.onSurfaceVariant;
      trendText = '暂无数据';
      trendIcon = Icons.remove;
    } else {
      trendText = '${trend! > 0 ? '+' : ''}${trend!.toStringAsFixed(1)}%';

      switch (direction) {
        case TrendDirection.up:
          trendColor = cs.error;
          trendIcon = Icons.trending_up;
        case TrendDirection.down:
          trendColor = Colors.green;
          trendIcon = Icons.trending_down;
        case TrendDirection.stable:
          trendColor = cs.onSurfaceVariant;
          trendIcon = Icons.trending_flat;
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        Row(
          children: [
            Icon(trendIcon, color: trendColor, size: 18),
            const SizedBox(width: 6),
            Text(
              trendText,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: trendColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
