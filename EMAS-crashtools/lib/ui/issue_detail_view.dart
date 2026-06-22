import 'package:flutter/material.dart';

import '../core/emas_apm_query_engine.dart';
import '../models/emas_issue_summary.dart';
import '../ui/theme_colors.dart';

/// EMAS 问题详情页面 (5 个标签页)
class IssueDetailView extends StatefulWidget {
  const IssueDetailView({
    super.key,
    required this.issue,
    required this.queryEngine,
  });

  final EmasIssueSummary issue;
  final EmasApmQueryEngine queryEngine;

  @override
  State<IssueDetailView> createState() => _IssueDetailViewState();
}

class _IssueDetailViewState extends State<IssueDetailView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  Map<String, dynamic>? _issueDetails;
  List<Map<String, dynamic>>? _samples;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadIssueDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadIssueDetails() async {
    try {
      // 获取问题详情目录
      final issueDir = await widget.queryEngine.digIssue(
        digestHash: widget.issue.digestHash,
        bizModule: widget.issue.bizModule,
        startTime: DateTime.now().subtract(const Duration(days: 7)),
        endTime: DateTime.now(),
        sampleSize: 5,
      );

      if (!mounted) return;

      // 读取详情数据
      final details = await widget.queryEngine.readIssueDetails(issueDir);

      if (!mounted) return;

      // 解析样本列表
      final errorsList = details['errors'] as Map<String, dynamic>? ?? {};
      final itemsList = errorsList['Items'] as List<dynamic>? ?? [];
      final samples = itemsList.cast<Map<String, dynamic>>();

      setState(() {
        _issueDetails = details;
        _samples = samples;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.lightGray,
      appBar: AppBar(
        title: Text(widget.issue.name),
        backgroundColor: Colors.white,
        elevation: 2,
        bottom: _buildTabBar(),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorContent()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(),
                    _buildStackTab(),
                    _buildDistributionTab(),
                    _buildSamplesTab(),
                    _buildAnalysisTab(),
                  ],
                ),
    );
  }

  PreferredSizeWidget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      tabs: const [
        Tab(text: '概览'),
        Tab(text: '堆栈'),
        Tab(text: '分布'),
        Tab(text: '样本'),
        Tab(text: '分析'),
      ],
      indicatorColor: ThemeColors.primaryGreen,
      labelColor: ThemeColors.primaryGreen,
      unselectedLabelColor: ThemeColors.textGray,
    );
  }

  Widget _buildErrorContent() {
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
              _error ?? 'Unknown error',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() => _isLoading = true);
                _loadIssueDetails();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 基本信息卡片
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: ThemeColors.borderGray),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('基本信息', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                _buildInfoRow('问题名称', widget.issue.name),
                _buildInfoRow('问题类型', widget.issue.type),
                _buildInfoRow('业务模块', widget.issue.bizModule),
                _buildInfoRow('问题哈希', widget.issue.digestHash.length > 20
                    ? '${widget.issue.digestHash.substring(0, 20)}...'
                    : widget.issue.digestHash),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 统计信息卡片
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: ThemeColors.borderGray),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('统计信息', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatBox(
                        '错误总数',
                        widget.issue.errorCount.toString(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatBox(
                        '错误率',
                        widget.issue.errorRate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatBox(
                        '受影响设备',
                        widget.issue.errorDeviceCount.toString(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatBox(
                        '设备影响率',
                        widget.issue.errorDeviceRate,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStackTab() {
    final issue = _issueDetails?['issue'] as Map<String, dynamic>? ?? {};
    final backtrace = issue['Backtrace'] as String? ?? '无堆栈信息';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: ThemeColors.borderGray),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            backtrace,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.6,
              color: ThemeColors.textBlack,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDistributionTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '版本分布',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: ThemeColors.borderGray),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '版本分布数据暂无',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSamplesTab() {
    if (_samples == null || _samples!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '暂无样本数据',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _samples!.length,
      itemBuilder: (context, index) {
        final sample = _samples![index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: ThemeColors.borderGray),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Text(
              'Sample ${index + 1}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  'UUID: ${sample['Uuid'] ?? 'N/A'}',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'ClientTime: ${sample['ClientTime'] ?? 'N/A'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }

  Widget _buildAnalysisTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline, size: 48, color: Colors.blue),
            const SizedBox(height: 16),
            Text(
              '待分析',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '点击 [执行分析] 按钮触发智能分析流程',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: ThemeColors.textGray,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: ThemeColors.textBlack,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeColors.primaryGreen.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: ThemeColors.primaryGreen.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: ThemeColors.textGray,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: ThemeColors.primaryGreen,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
