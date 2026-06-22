import 'package:flutter/material.dart';

import '../core/baymax_report_parser.dart';
import '../core/report_exporter.dart';
import '../ui/theme_colors.dart';

/// 报告详情页面 (含导出功能)
class ReportDetailPage extends StatefulWidget {
  const ReportDetailPage({
    super.key,
    required this.report,
    required this.reportName,
  });

  final BaymaxReportSummary report;
  final String reportName;

  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _exportMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _exportReport(String format) async {
    try {
      String content;
      switch (format) {
        case 'md':
          content = ReportExporter.exportAsMarkdown(widget.report);
          break;
        case 'json':
          content = ReportExporter.exportAsJson(widget.report);
          break;
        case 'csv':
          content = ReportExporter.exportAsCsv(widget.report);
          break;
        default:
          return;
      }

      final filePath = await ReportExporter.saveExportFile(
        content: content,
        format: format,
        baseFileName: widget.reportName.replaceAll('.html', ''),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已导出到: $filePath'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.lightGray,
      appBar: AppBar(
        title: Text(widget.reportName),
        backgroundColor: Colors.white,
        elevation: 2,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '总览'),
            Tab(text: 'Java Crashes'),
            Tab(text: 'Native Crashes'),
          ],
          indicatorColor: ThemeColors.primaryGreen,
          labelColor: ThemeColors.primaryGreen,
          unselectedLabelColor: ThemeColors.textGray,
        ),
      ),
      floatingActionButton: _buildExportFab(),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSummaryTab(),
          _buildCrashListTab(widget.report.javaCrashes, 'Java'),
          _buildCrashListTab(widget.report.nativeCrashes, 'Native'),
        ],
      ),
    );
  }

  Widget _buildSummaryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 汇总卡片
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
                  Text('崩溃分布', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  if (widget.report.javaCrashPercent != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Java Crash',
                              style: Theme.of(context).textTheme.bodyMedium),
                          Text(
                            '${widget.report.javaCrashPercent!.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: ThemeColors.primaryGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.report.nativeCrashPercent != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Native Crash',
                            style: Theme.of(context).textTheme.bodyMedium),
                        Text(
                          '${widget.report.nativeCrashPercent!.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: ThemeColors.primaryGreen,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 项目统计
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
                  Text('项目统计', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatItem(
                          'Java Crashes',
                          widget.report.javaCrashes.length.toString(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatItem(
                          'Native Crashes',
                          widget.report.nativeCrashes.length.toString(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatItem(
                          'Total',
                          widget.report.totalCrashItems.toString(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCrashListTab(List<BaymaxCrashItem> crashes, String type) {
    if (crashes.isEmpty) {
      return Center(
        child: Text('暂无 $type Crash 数据'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: crashes.length,
      itemBuilder: (context, index) => _buildCrashItemCard(crashes[index], index + 1),
    );
  }

  Widget _buildCrashItemCard(BaymaxCrashItem crash, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: ThemeColors.borderGray),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: ThemeColors.primaryGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '#$index',
                    style: const TextStyle(
                      color: ThemeColors.primaryGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    crash.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              children: [
                _buildMetaTag('设备: ${crash.affectedDevices}'),
                _buildMetaTag('错误: ${crash.errorCount}'),
                _buildMetaTag('率: ${crash.errorRate.toStringAsFixed(2)}%'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeColors.primaryGreen.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: ThemeColors.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: ThemeColors.textGray,
            ),
      ),
    );
  }

  Widget _buildExportFab() {
    return FloatingActionButton(
      backgroundColor: ThemeColors.primaryGreen,
      onPressed: () {
        showModalBottomSheet(
          context: context,
          builder: (context) => Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '选择导出格式',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.description),
                  title: const Text('Markdown (.md)'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportReport('md');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.data_object),
                  title: const Text('JSON (.json)'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportReport('json');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.table_chart),
                  title: const Text('CSV (.csv)'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportReport('csv');
                  },
                ),
              ],
            ),
          ),
        );
      },
      child: const Icon(Icons.download),
    );
  }
}
