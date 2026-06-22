import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/emas_apm_query_engine.dart';
import '../models/emas_issue_summary.dart';
import '../ui/theme_colors.dart';

/// EMAS 问题列表页面 (Top N 崩溃)
class EmasIssuesListPage extends StatefulWidget {
  const EmasIssuesListPage({
    super.key,
    required this.controller,
    required this.queryEngine,
    this.onSelectIssue,
  });

  final AppController controller;
  final EmasApmQueryEngine queryEngine;
  final Function(EmasIssueSummary)? onSelectIssue;

  @override
  State<EmasIssuesListPage> createState() => _EmasIssuesListPageState();
}

class _EmasIssuesListPageState extends State<EmasIssuesListPage> {
  List<EmasIssueSummary>? _issues;
  EmasQueryException? _error;
  bool _isLoading = false;

  late DateTime _startTime;
  late DateTime _endTime;
  String _selectedType = 'all'; // all / crash / anr / lag

  @override
  void initState() {
    super.initState();
    _endTime = DateTime.now();
    _startTime = _endTime.subtract(const Duration(days: 7));
    _loadIssues();
  }

  Future<void> _loadIssues() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final issues = await widget.queryEngine.getTopIssues(
        topN: 10,
        startTime: _startTime,
        endTime: _endTime,
        orderBy: 'ErrorRate',
      );

      if (!mounted) return;

      List<EmasIssueSummary> summaries = issues
          .map((json) => EmasIssueSummary.fromJson(json))
          .toList();

      // 按类型筛选
      if (_selectedType != 'all') {
        summaries = summaries.where((s) => s.type == _selectedType).toList();
      }

      setState(() {
        _issues = summaries;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is EmasQueryException ? e : EmasQueryException('Unknown error: $e');
        _isLoading = false;
      });
    }
  }

  void _onRefresh() => _loadIssues();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.lightGray,
      appBar: AppBar(
        title: const Text('EMAS 问题列表'),
        backgroundColor: Colors.white,
        elevation: 2,
      ),
      body: Column(
        children: [
          // 筛选栏
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '时间范围',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_startTime.toLocal().toString().split(' ')[0]} ~ ${_endTime.toLocal().toString().split(' ')[0]}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _onRefresh,
                  icon: _isLoading ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ) : const Icon(Icons.refresh),
                  label: const Text('刷新'),
                ),
              ],
            ),
          ),
          // 类型选择
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Wrap(
              spacing: 8,
              children: [
                _buildTypeChip('全部', 'all'),
                _buildTypeChip('Crash', 'crash'),
                _buildTypeChip('ANR', 'anr'),
                _buildTypeChip('Lag', 'lag'),
              ],
            ),
          ),
          const Divider(height: 1),
          // 问题列表或错误提示
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String label, String type) {
    final isSelected = _selectedType == type;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _selectedType = type);
        _loadIssues();
      },
      backgroundColor: Colors.transparent,
      selectedColor: ThemeColors.primaryGreen.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? ThemeColors.primaryGreen : ThemeColors.textGray,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      ),
      side: BorderSide(
        color: isSelected ? ThemeColors.primaryGreen : ThemeColors.borderGray,
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                '加载失败',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _error!.message,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _onRefresh,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_issues == null || _issues!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              '暂无问题数据',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _issues!.length,
      padding: const EdgeInsets.all(12),
      itemBuilder: (context, index) => _buildIssueCard(context, _issues![index]),
    );
  }

  Widget _buildIssueCard(BuildContext context, EmasIssueSummary issue) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: ThemeColors.borderGray),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        onTap: () => widget.onSelectIssue?.call(issue),
        title: Text(
          issue.name,
          style: Theme.of(context).textTheme.titleMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                _buildTag(issue.type),
                const SizedBox(width: 8),
                _buildTag('${issue.errorCount} errors'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '错误率: ${issue.errorRate}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '${issue.errorDeviceCount} 设备',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget _buildTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ThemeColors.primaryGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: ThemeColors.primaryGreen,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
