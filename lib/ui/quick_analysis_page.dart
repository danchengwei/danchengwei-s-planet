import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../core/baymax_report_parser.dart';
import '../ui/theme_colors.dart';
import '../ui/report_detail_page.dart';

/// 快速分析页面 — 导入 HTML 报告并立即分析
class QuickAnalysisPage extends StatefulWidget {
  const QuickAnalysisPage({super.key});

  @override
  State<QuickAnalysisPage> createState() => _QuickAnalysisPageState();
}

class _QuickAnalysisPageState extends State<QuickAnalysisPage> {
  BaymaxReportSummary? _report;
  bool _isLoading = false;
  String? _error;
  String? _fileName;

  Future<void> _selectAndAnalyze() async {
    try {
      setState(() => _isLoading = true);

      const typeGroup = XTypeGroup(
        label: 'HTML Reports',
        extensions: ['html', 'htm'],
      );

      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) {
        setState(() => _isLoading = false);
        return;
      }

      setState(() => _fileName = file.name);

      final report = await BaymaxReportParser.parseFile(file.path);

      if (mounted) {
        setState(() {
          _report = report;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_report == null) {
      return Scaffold(
        backgroundColor: ThemeColors.lightGray,
        appBar: AppBar(
          title: const Text('🔍 快速分析'),
          backgroundColor: Colors.white,
          elevation: 2,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.upload_file,
                  size: 80,
                  color: ThemeColors.primaryGreen.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 32),
                Text(
                  '导入 HTML 报告',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  '从 Baymax 导出 HTML 报告\n立即进行智能分析',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: ThemeColors.textGray,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _selectAndAnalyze,
                  icon: const Icon(Icons.folder_open),
                  label: _isLoading ? const Text('处理中...') : const Text('选择 HTML 文件'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ThemeColors.primaryGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(240, 56),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '解析失败',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        color: Colors.red,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _error ?? 'Unknown error',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // 已加载报告，显示分析结果
    final displayName = _fileName ?? 'Analysis Report';
    return Scaffold(
      backgroundColor: ThemeColors.lightGray,
      appBar: AppBar(
        title: Text('✅ $displayName'),
        backgroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _report = null;
                _fileName = null;
                _error = null;
              });
            },
            tooltip: '关闭',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReportDetailPage(
                report: _report!,
                reportName: _fileName ?? 'Quick Analysis Report',
              ),
            ),
          );
        },
        icon: const Icon(Icons.open_in_new),
        label: const Text('查看详情'),
        backgroundColor: ThemeColors.primaryGreen,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 文件信息
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
                    Text('文件信息', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _buildInfoRow('文件名', _fileName ?? 'N/A'),
                    _buildInfoRow(
                      '解析时间',
                      DateTime.now().toString().split('.')[0],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 统计信息
            if (_report!.javaCrashPercent != null || _report!.nativeCrashPercent != null)
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
                      Row(
                        children: [
                          if (_report!.javaCrashPercent != null)
                            Expanded(
                              child: _buildStatBox(
                                'Java Crash',
                                '${_report!.javaCrashPercent!.toStringAsFixed(1)}%',
                              ),
                            ),
                          if (_report!.javaCrashPercent != null && _report!.nativeCrashPercent != null)
                            const SizedBox(width: 12),
                          if (_report!.nativeCrashPercent != null)
                            Expanded(
                              child: _buildStatBox(
                                'Native Crash',
                                '${_report!.nativeCrashPercent!.toStringAsFixed(1)}%',
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
                    const SizedBox(height: 12),
                    _buildSummaryRow('Java Crashes', _report!.javaCrashes.length.toString()),
                    _buildSummaryRow('Native Crashes', _report!.nativeCrashes.length.toString()),
                    _buildSummaryRow('总计', _report!.totalCrashItems.toString()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 建议
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ThemeColors.primaryGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: ThemeColors.primaryGreen.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, color: ThemeColors.primaryGreen, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '💡 提示',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: ThemeColors.primaryGreen,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击"查看详情"按钮查看完整的 5 标签页分析结果，支持 Markdown/JSON/CSV 导出。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ThemeColors.textGray,
                        ),
                  ),
                ],
              ),
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
              style: TextStyle(color: ThemeColors.textGray, fontSize: 13),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: ThemeColors.textGray, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(
              color: ThemeColors.primaryGreen,
              fontSize: 14,
              fontWeight: FontWeight.bold,
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
}
