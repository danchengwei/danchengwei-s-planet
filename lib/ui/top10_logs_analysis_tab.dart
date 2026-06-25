import 'dart:io';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../aliyun/emas_appmonitor_client.dart';
import '../constants/app_constants.dart';
import '../services/huatuo_logger.dart';
import '../services/llm_analyzer.dart';
import 'widgets/version_filter_widget.dart';

/// Top10日志分析页面：展示ANR/Crash/Lag的Top10数据
/// Crash细分为Native和Java两种类型
class Top10LogsAnalysisTab extends StatefulWidget {
  const Top10LogsAnalysisTab({super.key, required this.controller, required this.onOpenSettings});

  final AppController controller;
  final VoidCallback onOpenSettings;

  @override
  State<Top10LogsAnalysisTab> createState() => _Top10LogsAnalysisTabState();
}

class _Top10LogsAnalysisTabState extends State<Top10LogsAnalysisTab> with SingleTickerProviderStateMixin {
  late String? _selectedVersion;
  late List<String> _availableVersions;
  late bool _loadingVersions;

  // Top10数据
  late List<IssueListItem> _top10Anr;
  late List<IssueListItem> _top10NativeCrash;
  late List<IssueListItem> _top10JavaCrash;
  late List<IssueListItem> _top10Lag;

  // 样本和华佗日志缓存
  late Map<String, ErrorSampleWithHuatuoLogs> _sampleCache;

  // 多选相关
  late Set<String> _selectedDigests;  // 选中的digestHash集合

  // Tab 控制器
  late TabController _tabController;

  late bool _loadingData;
  late String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedVersion = null;
    _availableVersions = [];
    _loadingVersions = false;
    _top10Anr = [];
    _top10NativeCrash = [];
    _top10JavaCrash = [];
    _top10Lag = [];
    _sampleCache = {};
    _selectedDigests = {};
    _loadingData = false;
    _errorMessage = null;

    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // 当tab变化时刷新UI
    });

    // 初始化加载版本列表
    Future.microtask(() => _initializeVersions());
    // 初始化加载数据
    Future.microtask(() => _loadTop10Data());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 初始化版本列表
  Future<void> _initializeVersions() async {
    setState(() => _loadingVersions = true);

    try {
      final now = DateTime.now();
      final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final startDate = endDate.subtract(const Duration(days: 7));

      // 调用controller获取版本列表
      final versions = await _fetchVersions(startDate, endDate);

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

  /// 获取版本列表
  Future<List<String>> _fetchVersions(DateTime startDate, DateTime endDate) async {
    try {
      final result = await widget.controller.cliService.getIssues(
        bizModule: 'crash',
        os: widget.controller.config.os.trim(),
        startTimeMs: startDate.millisecondsSinceEpoch,
        endTimeMs: endDate.millisecondsSinceEpoch,
        pageIndex: 1,
        pageSize: 500,
      );

      // 提取版本列表（最多3页，1500条）
      final versions = <String>{'全部'}.toList();
      for (final item in result.items) {
        if (item.firstVersion != null && item.firstVersion!.isNotEmpty) {
          versions.add(item.firstVersion!);
        }
      }

      // 去重、排序并仅保留xx.xx.xx格式
      final filtered = versions
          .toSet()
          .where((v) => v == '全部' || RegExp(r'^\d+\.\d+\.\d+$').hasMatch(v))
          .toList();
      filtered.sort((a, b) {
        if (a == '全部') return -1;
        if (b == '全部') return 1;
        return b.compareTo(a);
      });

      return filtered;
    } catch (e) {
      return ['全部'];
    }
  }

  /// 加载Top10数据
  Future<void> _loadTop10Data() async {
    setState(() {
      _loadingData = true;
      _errorMessage = null;
    });

    try {
      final now = DateTime.now();
      final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final startDate = endDate.subtract(const Duration(days: 7));

      final startMs = startDate.millisecondsSinceEpoch;
      final endMs = endDate.millisecondsSinceEpoch;

      // 构建版本筛选条件
      Map<String, dynamic>? versionFilter;
      if (_selectedVersion != null && _selectedVersion != '全部') {
        versionFilter = {
          'Key': 'appVersion',
          'Operator': '=',
          'Values': [_selectedVersion!],
        };
      }

      // 并行获取所有类型的Top10数据
      final results = await Future.wait([
        _fetchTop10(bizModule: 'anr', startMs: startMs, endMs: endMs, filter: versionFilter),
        _fetchTop10(
          bizModule: 'crash',
          startMs: startMs,
          endMs: endMs,
          filter: versionFilter,
          crashType: 'MOTU_ANDROID_NATIVE_CRASH',
        ),
        _fetchTop10(
          bizModule: 'crash',
          startMs: startMs,
          endMs: endMs,
          filter: versionFilter,
          crashType: 'MOTU_ANDROID_CRASH',
        ),
        _fetchTop10(bizModule: 'lag', startMs: startMs, endMs: endMs, filter: versionFilter),
      ]);

      setState(() {
        _top10Anr = results[0];
        _top10NativeCrash = results[1];
        _top10JavaCrash = results[2];
        _top10Lag = results[3];
        _loadingData = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '加载数据失败：${e.toString()}';
        _loadingData = false;
      });
    }
  }

  /// 获取单个类型的Top10数据
  Future<List<IssueListItem>> _fetchTop10({
    required String bizModule,
    required int startMs,
    required int endMs,
    Map<String, dynamic>? filter,
    String? crashType,
  }) async {
    try {
      // 如果指定了crashType，添加到filter中
      Map<String, dynamic>? finalFilter = filter;
      if (crashType != null) {
        final crashTypeFilter = {
          'Key': 'crashType',
          'Operator': '=',
          'Values': [crashType],
        };

        if (filter != null) {
          // 组合两个filter
          finalFilter = {
            'Operator': 'and',
            'SubFilters': [filter, crashTypeFilter],
          };
        } else {
          finalFilter = crashTypeFilter;
        }
      }

      final result = await widget.controller.cliService.getIssues(
        bizModule: bizModule,
        os: widget.controller.config.os.trim(),
        startTimeMs: startMs,
        endTimeMs: endMs,
        pageIndex: 1,
        pageSize: 10, // 只获取前10条
        orderBy: 'ErrorCount',
        orderType: 'DESC',
        filter: finalFilter,
      );

      return result.items.take(10).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          // 标题
          SliverPadding(
            padding: EdgeInsets.fromLTRB(kSpacing24, kSpacing20, kSpacing24, kSpacing8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Top10 日志分析',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          // 版本筛选
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: kSpacing24),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '应用版本',
                    style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: kSpacing8),
                  VersionFilterWidget(
                    versions: _availableVersions,
                    selectedVersion: _selectedVersion,
                    onVersionChanged: (version) {
                      setState(() => _selectedVersion = version);
                      _loadTop10Data();
                    },
                    isLoading: _loadingVersions,
                  ),
                  SizedBox(height: kSpacing16),
                ],
              ),
            ),
          ),
          // Tab Bar
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: kSpacing24),
            sliver: SliverToBoxAdapter(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: cs.outline)),
                ),
                child: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'ANR'),
                    Tab(text: 'Native Crash'),
                    Tab(text: 'Java Crash'),
                    Tab(text: 'Lag'),
                  ],
                  labelColor: cs.primary,
                  unselectedLabelColor: cs.onSurfaceVariant,
                  indicatorColor: cs.primary,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: kSpacing16)),
          // 错误提示
          if (_errorMessage != null)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: kSpacing24),
              sliver: SliverToBoxAdapter(
                child: Card(
                  color: cs.errorContainer,
                  child: Padding(
                    padding: EdgeInsets.all(kSpacing16),
                    child: Text(
                      _errorMessage!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer),
                    ),
                  ),
                ),
              ),
            ),
          // 数据加载中
          if (_loadingData)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(cs.primary)),
                    SizedBox(height: kSpacing16),
                    Text('加载数据中...', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
          // 内容
          if (!_loadingData && _errorMessage == null)
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.of(context).size.height - 400,
                child: IndexedStack(
                  index: _tabController.index,
                  children: [
                    _buildTop10List(context, 'ANR', _top10Anr, theme, cs),
                    _buildTop10List(context, 'Native Crash', _top10NativeCrash, theme, cs),
                    _buildTop10List(context, 'Java Crash', _top10JavaCrash, theme, cs),
                    _buildTop10List(context, 'Lag', _top10Lag, theme, cs),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建Top10列表
  Widget _buildTop10List(
    BuildContext context,
    String title,
    List<IssueListItem> items,
    ThemeData theme,
    ColorScheme cs,
  ) {
    return CustomScrollView(
      slivers: [
        // 多选操作栏
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: kSpacing24),
          sliver: SliverToBoxAdapter(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _selectedDigests.isEmpty
                          ? null
                          : () {
                              setState(() => _selectedDigests.clear());
                            },
                      icon: const Icon(Icons.deselect),
                      label: const Text('取消选中'),
                    ),
                    SizedBox(width: kSpacing8),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          final allDigests = <String>{};
                          for (final item in items) {
                            if (item.digestHash != null) {
                              allDigests.add(item.digestHash!);
                            }
                          }
                          _selectedDigests = allDigests;
                        });
                      },
                      icon: const Icon(Icons.select_all),
                      label: const Text('全选'),
                    ),
                    Text(
                      '(已选 ${_selectedDigests.length})',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _selectedDigests.isEmpty
                      ? null
                      : () => _performBatchAnalysis(),
                  icon: const Icon(Icons.analytics),
                  label: const Text('获取日志分析'),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: kSpacing12)),
        // 列表内容
        if (items.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Text(
                '暂无数据',
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: kSpacing24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = items[index];
                  final (primary, secondary) = item.displayTitles();
                  final isSelected = item.digestHash != null && _selectedDigests.contains(item.digestHash);

                  return Column(
                    children: [
                      if (index > 0) Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
                      Material(
                        color: isSelected ? cs.primaryContainer.withValues(alpha: 0.3) : Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            if (item.digestHash != null) {
                              setState(() {
                                if (_selectedDigests.contains(item.digestHash)) {
                                  _selectedDigests.remove(item.digestHash);
                                } else {
                                  _selectedDigests.add(item.digestHash!);
                                }
                              });
                            }
                          },
                          onLongPress: () => _showSampleDetail(context, item),
                          child: Padding(
                            padding: EdgeInsets.all(kSpacing12),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: isSelected,
                                  onChanged: (value) {
                                    if (item.digestHash != null) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedDigests.add(item.digestHash!);
                                        } else {
                                          _selectedDigests.remove(item.digestHash);
                                        }
                                      });
                                    }
                                  },
                                ),
                                SizedBox(width: kSpacing8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // 排名 + 标题
                                      Row(
                                        children: [
                                          Container(
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: cs.primaryContainer,
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              '${index + 1}',
                                              style: theme.textTheme.labelSmall?.copyWith(
                                                color: cs.primary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: kSpacing8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  primary,
                                                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                if (secondary != null)
                                                  Text(
                                                    secondary,
                                                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: kSpacing8),
                                      // 统计数据
                                      Row(
                                        children: [
                                          _buildStatMetric('次数', '${item.errorCount ?? 0}', theme, cs),
                                          SizedBox(width: kSpacing16),
                                          _buildStatMetric('设备数', '${item.errorDeviceCount ?? 0}', theme, cs),
                                          SizedBox(width: kSpacing16),
                                          _buildStatMetric(
                                            '错误率',
                                            '${((item.errorRatePercent ?? 0) * 100).toStringAsFixed(2)}%',
                                            theme,
                                            cs,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: kSpacing24)),
      ],
    );
  }

  /// 执行批量分析
  Future<void> _performBatchAnalysis() async {
    if (_selectedDigests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择要分析的问题')),
      );
      return;
    }

    final now = DateTime.now();
    final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final startDate = endDate.subtract(const Duration(days: 7));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('批量获取日志'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: FutureBuilder<List<ErrorSampleWithHuatuoLogs>>(
            future: _fetchBatchSamples(
              startMs: startDate.millisecondsSinceEpoch,
              endMs: endDate.millisecondsSinceEpoch,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在获取日志...'),
                    ],
                  ),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text('获取失败: ${snapshot.error}'),
                );
              }

              final samples = snapshot.data ?? [];
              final theme = Theme.of(context);
              final cs = theme.colorScheme;

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '已获取 ${samples.length} 个样本',
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: kSpacing12),
                    ...samples.map((sample) {
                      final llmAnalysis = sample.llmAnalysis;
                      final hasSummary = (llmAnalysis?['summary'] as String?)?.isNotEmpty ?? false;

                      return Padding(
                        padding: EdgeInsets.only(bottom: kSpacing12),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: hasSummary ? cs.primary : cs.outline,
                              width: hasSummary ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: EdgeInsets.all(kSpacing8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '用户: ${sample.userId}',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                '时间: ${sample.errorTime}',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                '日志: ${sample.huatuoLogs.length} 条',
                                style: theme.textTheme.bodySmall,
                              ),
                              if (hasSummary) ...[
                                SizedBox(height: kSpacing8),
                                Text(
                                  '📊 分析摘要:',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: cs.primary,
                                  ),
                                ),
                                Text(
                                  llmAnalysis!['summary'] as String,
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ] else if (llmAnalysis != null)
                                Text(
                                  '❌ 分析失败',
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 批量获取样本
  Future<List<ErrorSampleWithHuatuoLogs>> _fetchBatchSamples({
    required int startMs,
    required int endMs,
  }) async {
    final results = <ErrorSampleWithHuatuoLogs>[];
    final llmAnalyzer = LlmAnalyzer(config: widget.controller.config);

    for (final digestHash in _selectedDigests) {
      try {
        final sample = await _fetchLatestSampleWithHuatuoLogs(
          bizModule: 'crash',
          digestHash: digestHash,
          startMs: startMs,
          endMs: endMs,
        );
        if (sample != null) {
          // 调用 LLM 进行根因分析
          Map<String, dynamic>? llmAnalysis;
          try {
            final stackStr = sample.rawErrorDetail['stacktrace'] as String? ?? '';
            final huatuoLogsMap = <String, dynamic>{
              'logs': sample.huatuoLogs.map((log) => log.toJson()).toList(),
            };

            llmAnalysis = await llmAnalyzer.generateRootCauseAnalysis(
              digestHash: digestHash,
              crashTitle: digestHash,
              stackInfo: stackStr,
              huatuoAnalysis: huatuoLogsMap,
              userSample: sample.rawErrorDetail,
            );
          } catch (e) {
            debugPrint('LLM 分析失败: $e');
            llmAnalysis = null;
          }

          results.add(ErrorSampleWithHuatuoLogs(
            digestHash: sample.digestHash,
            userId: sample.userId,
            errorTime: sample.errorTime,
            osVersion: sample.osVersion,
            deviceModel: sample.deviceModel,
            huatuoLogs: sample.huatuoLogs,
            rawErrorDetail: sample.rawErrorDetail,
            llmAnalysis: llmAnalysis,
          ));
        }
      } catch (e) {
        print('获取 $digestHash 样本失败: $e');
      }
    }

    return results;
  }

  /// 显示样本详情对话框
  Future<void> _showSampleDetail(BuildContext context, IssueListItem item) async {
    final now = DateTime.now();
    final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final startDate = endDate.subtract(const Duration(days: 7));

    if (item.digestHash == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('最新崩溃样本'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: FutureBuilder<ErrorSampleWithHuatuoLogs?>(
            future: _fetchLatestSampleWithHuatuoLogs(
              bizModule: 'crash',
              digestHash: item.digestHash!,
              startMs: startDate.millisecondsSinceEpoch,
              endMs: endDate.millisecondsSinceEpoch,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError || snapshot.data == null) {
                return Center(
                  child: Text('获取失败: ${snapshot.error ?? "未知错误"}'),
                );
              }

              final sample = snapshot.data!;
              final theme = Theme.of(context);
              final cs = theme.colorScheme;

              return StatefulBuilder(
                builder: (context, setState) {
                  Map<String, dynamic>? llmAnalysis = sample.llmAnalysis;
                  bool isAnalyzing = false;

                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildDetailField('用户 ID', sample.userId, theme, cs),
                        _buildDetailField('错误时间', sample.errorTime, theme, cs),
                        _buildDetailField('设备型号', sample.deviceModel, theme, cs),
                        _buildDetailField('系统版本', sample.osVersion, theme, cs),
                        SizedBox(height: kSpacing16),
                        Text(
                          '华佗日志 (${sample.huatuoLogs.length} 条)',
                          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: kSpacing8),
                        if (sample.huatuoLogs.isEmpty)
                          Text(
                            '暂无日志',
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          )
                        else
                          Container(
                            constraints: const BoxConstraints(maxHeight: 200),
                            decoration: BoxDecoration(
                              border: Border.all(color: cs.outline),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: sample.huatuoLogs.map((log) {
                                  return Padding(
                                    padding: EdgeInsets.all(kSpacing8),
                                    child: Text(
                                      '[${log.timestamp}] ${log.level}: ${log.message}',
                                      style: theme.textTheme.bodySmall,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        SizedBox(height: kSpacing16),
                        if (llmAnalysis != null && (llmAnalysis['summary'] as String?)?.isNotEmpty == true) ...[
                          Text(
                            '📊 智能分析',
                            style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: kSpacing8),
                          Container(
                            padding: EdgeInsets.all(kSpacing12),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer.withValues(alpha: 0.1),
                              border: Border.all(color: cs.primary),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '分析摘要',
                                  style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  llmAnalysis['summary'] as String,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 构建详情字段
  Widget _buildDetailField(String label, String value, ThemeData theme, ColorScheme cs) {
    return Padding(
      padding: EdgeInsets.only(bottom: kSpacing12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// 构建统计指标
  Widget _buildStatMetric(String label, String value, ThemeData theme, ColorScheme cs) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// 获取单个问题的最新样本及华佗日志
  Future<ErrorSampleWithHuatuoLogs?> _fetchLatestSampleWithHuatuoLogs({
    required String bizModule,
    required String digestHash,
    required int startMs,
    required int endMs,
  }) async {
    try {
      // 先检查缓存
      if (_sampleCache.containsKey(digestHash)) {
        return _sampleCache[digestHash];
      }

      // 1. 获取样本列表，取最新的第一个
      final errorsResult = await widget.controller.cliService.getErrors(
        bizModule: bizModule,
        digestHash: digestHash,
        startTimeMs: startMs,
        endTimeMs: endMs,
        pageIndex: 1,
        pageSize: 1,
        orderBy: 'ClientTime',
      );

      final model = errorsResult['Model'];
      if (model == null || model['Items'] == null || (model['Items'] as List).isEmpty) {
        return null;
      }

      final firstError = model['Items'][0];
      final clientTime = firstError['ClientTime'];
      final uuid = firstError['Uuid'];
      final did = firstError['Did'];

      // 2. 获取完整的样本信息
      final errorDetail = await widget.controller.cliService.getError(
        bizModule: bizModule,
        digestHash: digestHash,
        clientTime: clientTime,
        uuid: uuid,
        did: did,
      );

      // 3. 提取用户和时间信息
      final userId = errorDetail['UserId']?.toString() ?? '未知用户';
      final errorTime = errorDetail['ClientTime']?.toString() ?? '';
      final osVersion = errorDetail['OsVersion']?.toString() ?? '';
      final deviceModel = errorDetail['DeviceModel']?.toString() ?? '';

      // 4. 查询华佗日志
      List<HuatuoLogEntry> huatuoLogs = [];
      try {
        final huatuo = HuatuoLogger(
          user: userId,
          dae: widget.controller.config.appKey,
        );

        // 以错误时间为中心，查询前后5分钟的日志
        if (errorTime.isNotEmpty) {
          try {
            final errorDateTime = DateTime.parse(errorTime);
            huatuoLogs = await huatuo.queryByIssue(
              crashTime: errorDateTime,
              timeWindow: const Duration(minutes: 5),
            );
          } catch (e) {
            // 华佗查询失败，继续
            print('华佗日志查询失败: $e');
          }
        }
      } catch (e) {
        print('华佗日志查询异常: $e');
      }

      final result = ErrorSampleWithHuatuoLogs(
        digestHash: digestHash,
        userId: userId,
        errorTime: errorTime,
        osVersion: osVersion,
        deviceModel: deviceModel,
        huatuoLogs: huatuoLogs,
        rawErrorDetail: errorDetail,
      );

      // 缓存结果
      _sampleCache[digestHash] = result;
      return result;
    } catch (e) {
      print('获取样本失败: $e');
      return null;
    }
  }
}

/// 错误样本 + 华佗日志数据结构
class ErrorSampleWithHuatuoLogs {
  final String digestHash;
  final String userId;
  final String errorTime;
  final String osVersion;
  final String deviceModel;
  final List<HuatuoLogEntry> huatuoLogs;
  final Map<String, dynamic> rawErrorDetail;
  final Map<String, dynamic>? llmAnalysis;

  ErrorSampleWithHuatuoLogs({
    required this.digestHash,
    required this.userId,
    required this.errorTime,
    required this.osVersion,
    required this.deviceModel,
    required this.huatuoLogs,
    required this.rawErrorDetail,
    this.llmAnalysis,
  });
}
