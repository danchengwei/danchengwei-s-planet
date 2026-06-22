import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../core/baymax_report_parser.dart';
import '../ui/theme_colors.dart';

/// 报告导入页面
class ReportImportPage extends StatefulWidget {
  const ReportImportPage({super.key, required this.onReportLoaded});

  final Function(BaymaxReportSummary) onReportLoaded;

  @override
  State<ReportImportPage> createState() => _ReportImportPageState();
}

class _ReportImportPageState extends State<ReportImportPage> {
  BaymaxReportSummary? _report;
  bool _isLoading = false;
  String? _error;
  String? _selectedFilePath;

  Future<void> _selectAndParseFile() async {
    try {
      setState(() => _isLoading = true);

      const typeGroup = XTypeGroup(
        label: 'HTML Reports',
        extensions: ['html', 'htm'],
      );

      final file = await openFile(
        acceptedTypeGroups: [typeGroup],
      );

      if (file == null) {
        setState(() => _isLoading = false);
        return;
      }

      setState(() => _selectedFilePath = file.path);

      final report = await BaymaxReportParser.parseFile(file.path);

      if (mounted) {
        setState(() {
          _report = report;
          _isLoading = false;
          _error = null;
        });

        widget.onReportLoaded(report);
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
          title: const Text('导入报告'),
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
                  size: 64,
                  color: ThemeColors.primaryGreen.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 24),
                Text(
                  '导入 Baymax 崩溃报告',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  '选择 HTML 格式的 Baymax 报告进行分析',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: ThemeColors.textGray,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _selectAndParseFile,
                  icon: const Icon(Icons.folder_open),
                  label: _isLoading ? const Text('处理中...') : const Text('选择文件'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ThemeColors.primaryGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(200, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 32),
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
                              const Icon(Icons.error_outline, color: Colors.red, size: 20),
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

    return Scaffold(
      backgroundColor: ThemeColors.lightGray,
      appBar: AppBar(
        title: const Text('报告概览'),
        backgroundColor: Colors.white,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 文件信息卡片
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
                    _buildInfoRow('文件路径', _selectedFilePath ?? 'N/A'),
                    _buildInfoRow(
                      '解析时间',
                      DateTime.now().toString().split('.')[0],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 统计信息卡片
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

            // 项目汇总
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
                    Text('项目汇总', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _buildSummaryRow('Java Crashes', _report!.javaCrashes.length.toString()),
                    _buildSummaryRow('Native Crashes', _report!.nativeCrashes.length.toString()),
                    _buildSummaryRow('总计', _report!.totalCrashItems.toString()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _report = null);
                    },
                    icon: const Icon(Icons.clear),
                    label: const Text('重新选择'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeColors.borderGray,
                      foregroundColor: ThemeColors.textBlack,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context, _report);
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('确认导入'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeColors.primaryGreen,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ],
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
              overflow: TextOverflow.ellipsis,
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
