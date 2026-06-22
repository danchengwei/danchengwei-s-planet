import 'package:flutter/material.dart';
import '../services/emas_intelligent_analyzer.dart';
import '../services/report_generator.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:io';
import 'app_icons.dart';

// 主题色定义
class _ThemeColors {
  static const Color primaryGreen = Color(0xFF7B9E89);      // 低饱和草绿色
  static const Color lightGray = Color(0xFFF5F5F5);         // 浅灰色背景
  static const Color borderGray = Color(0xFFE8E8E8);        // 边框灰色
  static const Color textBlack = Color(0xFF1F1F1F);         // 黑色文字
  static const Color textGray = Color(0xFF666666);          // 灰色文字
  static const Color white = Colors.white;
}

/// 分析结果展示页面
class AnalysisResultPage extends StatefulWidget {
  const AnalysisResultPage({
    required this.report,
    required this.onExport,
    super.key,
  });

  final AnalysisReport report;
  final Function(String format) onExport;

  @override
  State<AnalysisResultPage> createState() => _AnalysisResultPageState();
}

class _AnalysisResultPageState extends State<AnalysisResultPage> with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ThemeColors.lightGray,
      appBar: AppBar(
        title: const Text(
          '分析结果',
          style: TextStyle(color: _ThemeColors.textBlack, fontWeight: FontWeight.w600),
        ),
        backgroundColor: _ThemeColors.white,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _ThemeColors.primaryGreen,
          indicatorWeight: 3,
          labelColor: _ThemeColors.primaryGreen,
          unselectedLabelColor: _ThemeColors.textGray,
          splashFactory: NoSplash.splashFactory,
          tabs: [
            Tab(text: '概览', icon: AppIcons.getOverviewIcon(size: 18)),
            Tab(text: '堆栈', icon: AppIcons.getStackIcon(size: 18)),
            Tab(text: '分布', icon: AppIcons.getDistributionIcon(size: 18)),
            Tab(text: '分析', icon: AppIcons.getAnalysisIcon(size: 18)),
            Tab(text: '导出', icon: AppIcons.getExportIcon(size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildStackTab(),
          _buildDistributionTab(),
          _buildAnalysisTab(),
          _buildExportTab(),
        ],
      ),
    );
  }

  /// 概览标签
  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCard(
            title: '基本信息',
            children: [
              _buildInfoRow('问题类型', widget.report.issueType),
              _buildInfoRow('Digest Hash', '${widget.report.digestHash.substring(0, 16)}...'),
              _buildInfoRow('堆栈类型', widget.report.stackInfo.crashType),
              _buildInfoRow('堆栈行数', widget.report.stackInfo.lineCount.toString()),
              _buildInfoRow('分析时间', widget.report.createdAt.toString().split('.')[0]),
            ],
          ),
          const SizedBox(height: 16),
          _buildCard(
            title: '异常信息',
            children: [
              if (widget.report.stackInfo.applicationCodeLocation != null) ...[
                _buildInfoRow(
                  '应用类',
                  widget.report.stackInfo.applicationCodeLocation!.className,
                ),
                _buildInfoRow(
                  '方法',
                  widget.report.stackInfo.applicationCodeLocation!.methodName,
                ),
                _buildInfoRow(
                  '文件',
                  widget.report.stackInfo.applicationCodeLocation!.fileName,
                ),
                _buildInfoRow(
                  '行号',
                  widget.report.stackInfo.applicationCodeLocation!.lineNumber.toString(),
                ),
              ] else
                const Text(
                  '无应用代码定位',
                  style: TextStyle(color: _ThemeColors.textGray),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 堆栈标签
  Widget _buildStackTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.report.stackInfo.javaClasses.isNotEmpty) ...[
            _buildCard(
              title: 'Java 类 (${widget.report.stackInfo.javaClasses.length})',
              children: [
                for (final cls in widget.report.stackInfo.javaClasses.take(10))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '• $cls',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: _ThemeColors.textBlack,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          _buildCard(
            title: '完整堆栈',
            children: [
              Container(
                decoration: BoxDecoration(
                  color: _ThemeColors.borderGray,
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.all(12),
                child: Text(
                  widget.report.stackInfo.rawStack,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: _ThemeColors.textBlack,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 分布分析标签
  Widget _buildDistributionTab() {
    final dist = widget.report.distribution;
    if (dist.totalCount == 0) {
      return const Center(
        child: Text(
          '无分布数据',
          style: TextStyle(color: _ThemeColors.textGray),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCard(
            title: '总体统计',
            children: [
              _buildInfoRow('总崩溃数', dist.totalCount.toString()),
              _buildInfoRow('涉及版本', dist.versions.length.toString()),
              _buildInfoRow('涉及系统', dist.osVersions.length.toString()),
              _buildInfoRow('涉及品牌', dist.brands.length.toString()),
            ],
          ),
          const SizedBox(height: 16),
          if (dist.versions.isNotEmpty)
            _buildDistributionTable('版本分布', dist.versions),
          const SizedBox(height: 16),
          if (dist.osVersions.isNotEmpty)
            _buildDistributionTable('系统分布', dist.osVersions),
        ],
      ),
    );
  }

  /// 分析结果标签
  Widget _buildAnalysisTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCard(
            title: 'AI 分析结果',
            children: [
              Text(
                widget.report.analysisText,
                style: const TextStyle(
                  height: 1.8,
                  color: _ThemeColors.textBlack,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 导出标签
  Widget _buildExportTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildExportButton('Markdown (.md)', 'markdown'),
            const SizedBox(height: 12),
            _buildExportButton('HTML (.html)', 'html'),
            const SizedBox(height: 12),
            _buildExportButton('JSON (.json)', 'json'),
            const SizedBox(height: 12),
            _buildExportButton('TSV (.tsv)', 'tsv'),
          ],
        ),
      ),
    );
  }

  /// 导出按钮
  Widget _buildExportButton(String label, String format) {
    return ElevatedButton(
      onPressed: _isExporting ? null : () => _exportReport(format),
      style: ElevatedButton.styleFrom(
        backgroundColor: _ThemeColors.primaryGreen,
        disabledBackgroundColor: Colors.grey[400],
        minimumSize: const Size(200, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: _isExporting
                ? AppIcons.createLoadingIcon(
                    assetPath: AppIcons.orangeCatPng,
                    size: 18,
                  )
                : Image.asset(
                    AppIcons.orangeCatPng,
                    width: 18,
                    height: 18,
                    fit: BoxFit.contain,
                  ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: _ThemeColors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 执行导出
  Future<void> _exportReport(String format) async {
    setState(() => _isExporting = true);

    try {
      String content;
      String ext;

      switch (format) {
        case 'markdown':
          content = ReportGenerator.toMarkdown(widget.report);
          ext = '.md';
          break;
        case 'html':
          content = ReportGenerator.toHtml(widget.report);
          ext = '.html';
          break;
        case 'json':
          content = ReportGenerator.toJson(widget.report);
          ext = '.json';
          break;
        case 'tsv':
          content = ReportGenerator.toTsv(widget.report);
          ext = '.tsv';
          break;
        default:
          throw Exception('未知格式: $format');
      }

      // 选择保存路径
      final location = await getSaveLocation(
        suggestedName: 'analysis_${widget.report.digestHash.substring(0, 8)}$ext',
      );

      if (location != null) {
        final file = File(location.path);
        await file.writeAsString(content);
        _showSnackBar('已导出到: ${file.path}');
      }
    } catch (e) {
      _showSnackBar('导出失败: $e', isError: true);
    } finally {
      setState(() => _isExporting = false);
    }
  }

  /// 信息行
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: _ThemeColors.textBlack,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: _ThemeColors.textGray,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 卡片容器
  Widget _buildCard({required String title, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: _ThemeColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _ThemeColors.borderGray, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _ThemeColors.textBlack,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  /// 分布表格
  Widget _buildDistributionTable(String title, dynamic data) {
    return _buildCard(
      title: title,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(_ThemeColors.borderGray),
            dataRowColor: WidgetStateProperty.all(_ThemeColors.white),
            columns: const [
              DataColumn(
                label: Text(
                  '名称',
                  style: TextStyle(
                    color: _ThemeColors.textBlack,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              DataColumn(
                label: Text(
                  '数量',
                  style: TextStyle(
                    color: _ThemeColors.textBlack,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                numeric: true,
              ),
              DataColumn(
                label: Text(
                  '占比',
                  style: TextStyle(
                    color: _ThemeColors.textBlack,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                numeric: true,
              ),
            ],
            rows: (data as List).take(10).map((item) {
              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      item.name ?? item.toString(),
                      style: const TextStyle(color: _ThemeColors.textBlack),
                    ),
                  ),
                  DataCell(
                    Text(
                      item.count.toString(),
                      style: const TextStyle(color: _ThemeColors.textGray),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${item.percentage?.toStringAsFixed(2) ?? "0"}%',
                      style: const TextStyle(color: _ThemeColors.textGray),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// 显示提示信息
  void _showSnackBar(String message, {bool isError = false}) {
    final bgColor = isError ? Colors.red[600] : _ThemeColors.primaryGreen;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: _ThemeColors.white),
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
