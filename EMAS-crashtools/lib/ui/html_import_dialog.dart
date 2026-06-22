import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:io';
import '../services/html_report_analyzer.dart';
import '../services/emas_intelligent_analyzer.dart';
import '../services/stack_parser.dart';
import '../services/distribution_analyzer.dart';
import 'app_icons.dart';

// 主题色定义
class _DialogThemeColors {
  static const Color primaryGreen = Color(0xFF7B9E89);      // 低饱和草绿色
  static const Color lightGray = Color(0xFFF5F5F5);         // 浅灰色
  static const Color borderGray = Color(0xFFE8E8E8);        // 边框灰色
  static const Color textBlack = Color(0xFF1F1F1F);         // 黑色文字
  static const Color textGray = Color(0xFF666666);          // 灰色文字
  static const Color white = Colors.white;
}

/// HTML 报告导入对话框
class HtmlImportDialog extends StatefulWidget {
  const HtmlImportDialog({
    required this.onImport,
    super.key,
  });

  final Function(AnalysisReport) onImport;

  @override
  State<HtmlImportDialog> createState() => _HtmlImportDialogState();
}

class _HtmlImportDialogState extends State<HtmlImportDialog> {
  String? _selectedFilePath;
  bool _isLoading = false;
  String? _parseError;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _DialogThemeColors.white,
      title: const Text(
        '导入 HTML 报告',
        style: TextStyle(
          color: _DialogThemeColors.textBlack,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 文件选择区域
            Container(
              width: double.maxFinite,
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: _DialogThemeColors.borderGray, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: _DialogThemeColors.lightGray,
              ),
              child: InkWell(
                onTap: _isLoading ? null : _selectFile,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppIcons.getUploadIcon(size: 36),
                    const SizedBox(height: 8),
                    Text(
                      _selectedFilePath != null ? _getFileName(_selectedFilePath!) : '点击选择 HTML 文件',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: _selectedFilePath != null ? _DialogThemeColors.primaryGreen : _DialogThemeColors.textGray,
                        fontWeight: _selectedFilePath != null ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 错误提示
            if (_parseError != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  border: Border.all(color: Colors.red[300]!, width: 1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _parseError!,
                  style: TextStyle(color: Colors.red[700], fontSize: 12),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 加载提示
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_DialogThemeColors.primaryGreen),
                ),
              ),

            // 支持的格式说明
            Text(
              '支持的格式',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _DialogThemeColors.textBlack,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '• Baymax HTML 报告格式\n'
              '• EMAS 生成的 HTML 报告\n'
              '• 包含堆栈和分布数据的 HTML',
              style: TextStyle(
                fontSize: 12,
                color: _DialogThemeColors.textGray,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text(
            '取消',
            style: TextStyle(color: _DialogThemeColors.textGray),
          ),
        ),
        ElevatedButton(
          onPressed: _selectedFilePath == null || _isLoading ? null : _importFile,
          style: ElevatedButton.styleFrom(
            backgroundColor: _DialogThemeColors.primaryGreen,
            disabledBackgroundColor: Colors.grey[400],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_DialogThemeColors.white),
                  ),
                )
              : const Text(
                  '导入',
                  style: TextStyle(color: _DialogThemeColors.white),
                ),
        ),
      ],
    );
  }

  /// 选择文件
  Future<void> _selectFile() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'HTML Files',
          extensions: ['html', 'htm'],
        ),
      ],
    );

    if (file != null) {
      setState(() {
        _selectedFilePath = file.path;
        _parseError = null;
      });
    }
  }

  /// 导入文件
  Future<void> _importFile() async {
    if (_selectedFilePath == null) return;

    setState(() {
      _isLoading = true;
      _parseError = null;
    });

    try {
      // 读取文件
      final file = File(_selectedFilePath!);
      final htmlContent = await file.readAsString();

      // 解析 HTML
      final analyzer = HtmlReportAnalyzer(htmlContent);
      final parsed = analyzer.parseReport();
      final issueData = analyzer.toIssueData();

      // 构造 AnalysisReport（这里简化处理，实际需要更多初始化）
      // 注：这是一个简化版本，真实使用中需要完整的分析流程
      final report = _buildReportFromParsedData(parsed, issueData);

      // 回调
      if (mounted) {
        Navigator.pop(context);
        widget.onImport(report);
      }
    } catch (e) {
      setState(() {
        _parseError = '解析失败: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 从解析数据构建报告（简化版）
  AnalysisReport _buildReportFromParsedData(
    Map<String, dynamic> parsed,
    Map<String, dynamic> issueData,
  ) {
    // 这是一个简化实现，真实场景可能需要更复杂的处理
    return AnalysisReport(
      digestHash: parsed['digestHash'] as String? ?? 'unknown',
      issueType: parsed['issueType'] as String? ?? 'Unknown',
      stackInfo: _parseStackInfo(parsed['stackTrace'] as String? ?? ''),
      distribution: _parseDistribution(parsed['distribution'] as Map<String, dynamic>),
      sourceCode: const {},
      contributors: const {},
      analysisText: parsed['analysisText'] as String? ?? '(从 HTML 导入，未执行 LLM 分析)',
      createdAt: DateTime.now(),
    );
  }

  /// 解析堆栈信息
  StructuredStackInfo _parseStackInfo(String stackTrace) {
    // 这里应该调用实际的 StackParser
    // 为了简化，这里返回一个基础对象
    return StructuredStackInfo(
      rawStack: stackTrace,
      crashType: stackTrace.contains('Exception') ? 'Java' : 'Unknown',
      lineCount: stackTrace.split('\n').length,
    );
  }

  /// 解析分布信息
  DistributionAnalysis _parseDistribution(Map<String, dynamic> data) {
    return DistributionAnalysis(
      totalCount: data['ErrorCount'] as int? ?? 0,
      versions: const [],
      osVersions: const [],
      devices: const [],
      brands: const [],
    );
  }

  /// 获取文件名
  String _getFileName(String path) {
    return path.split('/').last;
  }
}

/// 导入对话框显示器
Future<void> showHtmlImportDialog(
  BuildContext context, {
  required Function(AnalysisReport) onImport,
}) {
  return showDialog(
    context: context,
    builder: (context) => HtmlImportDialog(onImport: onImport),
  );
}
