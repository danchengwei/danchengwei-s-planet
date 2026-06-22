import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/baymax_report_parser.dart';
import '../models/unified_report_model.dart';
import '../ui/theme_colors.dart';
import '../ui/report_detail_page.dart';

/// 统一报告中心（整合 EMAS + Baymax）
class UnifiedReportHub extends StatefulWidget {
  const UnifiedReportHub({
    super.key,
    required this.controller,
  });

  final AppController controller;

  @override
  State<UnifiedReportHub> createState() => _UnifiedReportHubState();
}

class _UnifiedReportHubState extends State<UnifiedReportHub>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Map<String, UnifiedReport> _reportCache = {};
  List<UnifiedReport> _localReports = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }


  void _deleteReport(String reportId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除报告'),
        content: const Text('确定要删除此报告吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _reportCache.remove(reportId);
                _localReports.removeWhere((r) => r.metadata.id == reportId);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ 报告已删除')),
              );
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.lightGray,
      appBar: AppBar(
        title: const Text('📊 报告中心'),
        backgroundColor: Colors.white,
        elevation: 2,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Baymax 报告'),
            Tab(text: '本地库'),
          ],
          indicatorColor: ThemeColors.primaryGreen,
          labelColor: ThemeColors.primaryGreen,
          unselectedLabelColor: ThemeColors.textGray,
        ),
      ),
      floatingActionButton: null,
      body: TabBarView(
        controller: _tabController,
        children: [
          // 标签 1：Baymax 报告库
          _buildBaymaxTab(),

          // 标签 2：本地报告库
          _buildLocalReportsTab(),
        ],
      ),
    );
  }

  Widget _buildBaymaxTab() {
    if (_localReports.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.upload_file,
                size: 64,
                color: ThemeColors.primaryGreen.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 24),
              Text(
                '暂无报告',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                '点击右下角按钮导入 Baymax HTML 报告',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ThemeColors.textGray,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _localReports.length,
      itemBuilder: (context, index) {
        final report = _localReports[index];
        if (report.type != ReportType.baymax) return SizedBox.shrink();

        return _buildReportCard(report, index);
      },
    );
  }

  Widget _buildLocalReportsTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: ThemeColors.primaryGreen.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              '本地分析报告',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              '执行分析后\n报告将保存在此',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ThemeColors.textGray,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(UnifiedReport report, int index) {
    final data = report.data;
    final isBaymax = data is BaymaxReportSummary;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: ThemeColors.borderGray),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: ThemeColors.primaryGreen.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(
            Icons.assessment,
            color: ThemeColors.primaryGreen,
          ),
        ),
        title: Text(
          report.displayName,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              report.metadata.createdAt.toString().split('.')[0],
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: ThemeColors.textGray,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              report.summary,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: ThemeColors.primaryGreen,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        trailing: SizedBox(
          width: 100,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isBaymax)
                IconButton(
                  icon: const Icon(Icons.zoom_in),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ReportDetailPage(
                          report: data,
                          reportName: report.displayName,
                        ),
                      ),
                    );
                  },
                  tooltip: '详情',
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteReport(report.metadata.id),
                tooltip: '删除',
                color: Colors.red.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
        onTap: isBaymax
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ReportDetailPage(
                      report: data,
                      reportName: report.displayName,
                    ),
                  ),
                );
              }
            : null,
      ),
    );
  }
}
