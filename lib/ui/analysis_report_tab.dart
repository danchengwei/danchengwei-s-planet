import 'package:flutter/material.dart';
import 'dart:io';

import '../app_controller.dart';
import '../services/analysis_report_generator.dart';
import '../constants/app_constants.dart';

/// 分析报告生成页面：聚合分析数据，生成完整报告
class AnalysisReportTab extends StatefulWidget {
  const AnalysisReportTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<AnalysisReportTab> createState() => _AnalysisReportTabState();
}

class _AnalysisReportTabState extends State<AnalysisReportTab> {
  late final TextEditingController _reportTitleController;
  late final TextEditingController _reportDescController;

  @override
  void initState() {
    super.initState();
    _reportTitleController = TextEditingController();
    _reportDescController = TextEditingController();
  }

  bool _isGenerating = false;
  String? _lastReportPath;
  String? _successMessage;
  String? _errorMessage;

  bool _includeTopCrashes = true;
  bool _includeTopAnrs = true;
  bool _includeStackAnalysis = true;
  bool _includeSuggestions = true;
  int _topItemsCount = 10;

  @override
  void dispose() {
    _reportTitleController.dispose();
    _reportDescController.dispose();
    super.dispose();
  }

  Future<void> _generateReport() async {
    if (_reportTitleController.text.isEmpty) {
      setState(() => _errorMessage = '请输入报告标题');
      return;
    }

    try {
      setState(() {
        _isGenerating = true;
        _errorMessage = null;
        _successMessage = null;
      });

      final generator = AnalysisReportGenerator();
      final reportPath = await generator.generateReport(
        title: _reportTitleController.text,
        description: _reportDescController.text,
        includeTopCrashes: _includeTopCrashes,
        includeTopAnrs: _includeTopAnrs,
        includeStackAnalysis: _includeStackAnalysis,
        includeSuggestions: _includeSuggestions,
        topItemsCount: _topItemsCount,
      );

      setState(() {
        _lastReportPath = reportPath;
        _successMessage = '报告已生成：${reportPath.split('/').last}';
        _isGenerating = false;
      });

      // 3秒后清除成功消息
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        setState(() => _successMessage = null);
      }
    } catch (e) {
      setState(() {
        _errorMessage = '生成失败：$e';
        _isGenerating = false;
      });
    }
  }

  void _openReportFile() {
    final path = _lastReportPath;
    if (path != null) {
      if (Platform.isMacOS) {
        Process.run('open', [path]);
      } else if (Platform.isWindows) {
        Process.run('explorer', [path]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [path]);
      }
    }
  }

  void _copyReportPath() {
    if (_lastReportPath != null) {
      // 这里可以集成剪贴板功能
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制：$_lastReportPath')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: [
        // 顶部标题栏
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('分析报告生成', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '聚合 EMAS 数据，生成完整的崩溃/ANR 分析报告',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),

        Expanded(
          child: _isGenerating
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: cs.primary),
                      const SizedBox(height: 16),
                      const Text('正在生成报告...'),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 成功消息
                      if (_successMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.tertiaryContainer,
                            borderRadius: AppBorderRadius.xs,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: cs.tertiary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _successMessage!,
                                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onTertiaryContainer),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 错误消息
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: AppBorderRadius.xs,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: cs.error),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onErrorContainer),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 报告基本信息
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('报告信息', style: theme.textTheme.titleSmall),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _reportTitleController,
                                decoration: InputDecoration(
                                  labelText: '报告标题 *',
                                  hintText: '例如：2024-06-18 崩溃分析报告',
                                  border: OutlineInputBorder(
                                    borderRadius: AppBorderRadius.xs,
                                  ),
                                  prefixIcon: const Icon(Icons.title),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _reportDescController,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  labelText: '报告描述',
                                  hintText: '可选：添加报告摘要或备注',
                                  border: OutlineInputBorder(
                                    borderRadius: AppBorderRadius.xs,
                                  ),
                                  prefixIcon: const Icon(Icons.description),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 生成选项
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('生成选项', style: theme.textTheme.titleSmall),
                              const SizedBox(height: 12),
                              CheckboxListTile(
                                title: const Text('包含 Top 崩溃'),
                                subtitle: const Text('从 EMAS 获取排名前 N 的崩溃'),
                                value: _includeTopCrashes,
                                onChanged: (v) => setState(() => _includeTopCrashes = v ?? true),
                              ),
                              CheckboxListTile(
                                title: const Text('包含 Top ANR'),
                                subtitle: const Text('从 EMAS 获取排名前 N 的 ANR'),
                                value: _includeTopAnrs,
                                onChanged: (v) => setState(() => _includeTopAnrs = v ?? true),
                              ),
                              CheckboxListTile(
                                title: const Text('包含堆栈分析'),
                                subtitle: const Text('对关键异常进行代码级分析'),
                                value: _includeStackAnalysis,
                                onChanged: (v) => setState(() => _includeStackAnalysis = v ?? true),
                              ),
                              CheckboxListTile(
                                title: const Text('包含修复建议'),
                                subtitle: const Text('基于堆栈和源码生成修复建议'),
                                value: _includeSuggestions,
                                onChanged: (v) => setState(() => _includeSuggestions = v ?? true),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('显示项数'),
                                        const SizedBox(height: 8),
                                        Slider(
                                          value: _topItemsCount.toDouble(),
                                          min: 5,
                                          max: 50,
                                          divisions: 9,
                                          label: _topItemsCount.toString(),
                                          onChanged: (v) {
                                            setState(() => _topItemsCount = v.toInt());
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: 80,
                                    child: Align(
                                      alignment: Alignment.center,
                                      child: Text(
                                        '最多 $_topItemsCount 项',
                                        style: theme.textTheme.labelSmall,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 生成按钮
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isGenerating ? null : _generateReport,
                          icon: const Icon(Icons.assessment),
                          label: const Text('生成报告'),
                        ),
                      ),

                      // 之前生成的报告操作
                      if (_lastReportPath != null) ...[
                        const SizedBox(height: 16),
                        Card(
                          color: cs.tertiaryContainer.withValues(alpha: 0.3),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('最新报告', style: theme.textTheme.labelSmall),
                                const SizedBox(height: 8),
                                Text(
                                  _lastReportPath!.split('/').last,
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _openReportFile,
                                        icon: const Icon(Icons.open_in_new_rounded),
                                        label: const Text('打开文件'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _copyReportPath,
                                        icon: const Icon(Icons.content_copy),
                                        label: const Text('复制路径'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
