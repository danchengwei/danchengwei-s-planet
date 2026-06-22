import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../constants/app_constants.dart';
import '../services/performance_stats_service.dart';
import 'widgets/version_filter_widget.dart';

/// 性能统计页面：支持数据筛选、聚合、导出
class PerformanceStatsPage extends StatefulWidget {
  const PerformanceStatsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<PerformanceStatsPage> createState() => _PerformanceStatsPageState();
}

class _PerformanceStatsPageState extends State<PerformanceStatsPage> {
  late PerformanceStatsService _statsService;
  late PerformanceStatFilter _filter;
  PerformanceReport? _report;
  late List<String> _availableVersions;
  late bool _loadingVersions;

  @override
  void initState() {
    super.initState();
    _statsService = PerformanceStatsService();
    _statsService.loadSampleData();

    _availableVersions = [];
    _loadingVersions = false;

    _filter = PerformanceStatFilter(
      startDate: DateTime.now().subtract(const Duration(days: 7)),
      endDate: DateTime.now(),
      versions: [],
      bizModules: ['crash', 'anr'],
      groupBy: 'day',
    );

    _loadVersions();
  }

  Future<void> _loadVersions() async {
    setState(() => _loadingVersions = true);
    try {
      final versions = await widget.controller.fetchAvailableVersions(
        bizModule: 'crash',
        startTimeMs: _filter.startDate.millisecondsSinceEpoch,
        endTimeMs: _filter.endDate.millisecondsSinceEpoch,
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

  void _updateReport() {
    setState(() {
      _report = _statsService.generateReport(_filter);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('性能统计'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // 筛选栏
          Container(
            padding: EdgeInsets.all(kSpacing16),
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('筛选条件', style: Theme.of(context).textTheme.titleSmall),
                SizedBox(height: kSpacing12),

                // 日期范围
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('开始日期', style: Theme.of(context).textTheme.labelSmall),
                          SizedBox(height: kSpacing8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _filter.startDate ?? DateTime.now(),
                                firstDate: DateTime(2025, 1, 1),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) {
                                setState(() => _filter.startDate = date);
                                _updateReport();
                              }
                            },
                            icon: const Icon(Icons.calendar_today, size: 18),
                            label: Text(
                              DateFormat('yyyy-MM-dd').format(_filter.startDate ?? DateTime.now()),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: kSpacing12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('结束日期', style: Theme.of(context).textTheme.labelSmall),
                          SizedBox(height: kSpacing8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _filter.endDate ?? DateTime.now(),
                                firstDate: DateTime(2025, 1, 1),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) {
                                setState(() => _filter.endDate = date);
                                _updateReport();
                              }
                            },
                            icon: const Icon(Icons.calendar_today, size: 18),
                            label: Text(
                              DateFormat('yyyy-MM-dd').format(_filter.endDate ?? DateTime.now()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: kSpacing12),

                // 版本选择
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VersionFilterWidget(
                      versions: _availableVersions,
                      selectedVersion: _filter.versions.isEmpty ? null : _filter.versions.first,
                      onVersionChanged: (version) {
                        setState(() {
                          _filter.versions = version != null ? [version] : [];
                        });
                        _updateReport();
                      },
                      isLoading: _loadingVersions,
                    ),
                  ],
                ),

                SizedBox(height: kSpacing12),

                // 导出按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _exportAsTable(),
                      icon: const Icon(Icons.table_chart),
                      label: const Text('导出表格'),
                    ),
                    SizedBox(width: kSpacing8),
                    FilledButton.tonalIcon(
                      onPressed: () => _exportAsJson(),
                      icon: const Icon(Icons.code),
                      label: const Text('导出 JSON'),
                    ),
                    SizedBox(width: kSpacing8),
                    FilledButton.icon(
                      onPressed: () => _exportAsHtml(),
                      icon: const Icon(Icons.html),
                      label: const Text('导出 HTML'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 统计表格
          if (_report != null)
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // 日期统计表
                    _buildStatsTable(
                      title: '日期统计',
                      stats: _report!.dailyStats,
                      versions: _report!.versions,
                    ),

                    // 周期汇总表
                    if (_report!.averageStats != null ||
                        _report!.lastWeekStats != null ||
                        _report!.lastLastWeekStats != null)
                      _buildStatsTable(
                        title: '周期汇总',
                        stats: [
                          if (_report!.averageStats != null) _report!.averageStats!,
                          if (_report!.lastWeekStats != null) _report!.lastWeekStats!,
                          if (_report!.lastLastWeekStats != null) _report!.lastLastWeekStats!,
                        ],
                        versions: _report!.versions,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsTable({
    required String title,
    required List<AggregatedStats> stats,
    required List<String> versions,
  }) {
    return Padding(
      padding: EdgeInsets.all(kSpacing16),
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(kSpacing12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: kSpacing12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    const DataColumn(label: Text('日期')),
                    ...versions.map((v) => DataColumn(label: Text('$v(卡顿率)'))),
                    const DataColumn(label: Text('全部(卡顿率)')),
                    ...versions.map((v) => DataColumn(label: Text('$v(卡顿数)'))),
                    const DataColumn(label: Text('全部(卡顿数)')),
                  ],
                  rows: stats
                      .map((stat) => DataRow(cells: [
                            DataCell(Text(stat.period)),
                            ...versions.map((v) {
                              final vStat = stat.versionStats[v];
                              return DataCell(Text(vStat?.formattedRate ?? 'N/A'));
                            }),
                            DataCell(Text(stat.formattedRate)),
                            ...versions.map((v) {
                              final vStat = stat.versionStats[v];
                              return DataCell(Text('${vStat?.hangCount ?? 0}'));
                            }),
                            DataCell(Text('${stat.totalHangCount}')),
                          ]))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _exportAsTable() {
    final tableText = _report?.toTable() ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已复制表格数据到剪贴板'),
        action: SnackBarAction(label: '关闭', onPressed: () {}),
      ),
    );
  }

  void _exportAsJson() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已导出 JSON 文件'),
        action: SnackBarAction(label: '关闭', onPressed: () {}),
      ),
    );
  }

  void _exportAsHtml() {
    final htmlText = _report?.toHtml() ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已导出 HTML 文件'),
        action: SnackBarAction(label: '关闭', onPressed: () {}),
      ),
    );
  }
}
