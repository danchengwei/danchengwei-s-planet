import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../app_controller.dart';
import '../core/baymax_report_parser.dart';
import '../models/analysis_session.dart';
import '../services/analysis_logs_manager.dart';
import '../services/html_analysis_pipeline_service.dart';

/// 分析阶段
enum AnalysisPhase { selectFile, selectIssues, analyzing, results }

/// HTML 报告分析页面：支持多选崩溃问题、完整分析流程、日志管理
class HtmlReportAnalysisTab extends StatefulWidget {
  const HtmlReportAnalysisTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<HtmlReportAnalysisTab> createState() => _HtmlReportAnalysisTabState();
}

class _HtmlReportAnalysisTabState extends State<HtmlReportAnalysisTab> with SingleTickerProviderStateMixin {
  // 当前阶段
  AnalysisPhase _currentPhase = AnalysisPhase.selectFile;

  // 报告解析数据
  BaymaxReportSummary? _parsedReport;
  String? _selectedReportPath;
  String? _errorMessage;
  bool _isLoading = false;

  // 问题选择
  final Set<String> _selectedJavaCrashes = {};
  final Set<String> _selectedNativeCrashes = {};

  // 分析会话
  late HtmlAnalysisPipelineService _pipelineService;
  AnalysisSession? _currentSession;
  late TabController _resultTabController;

  // 日志管理
  final _logsManager = AnalysisLogsManager();
  List<FileInfo>? _sessionLogFiles;
  List<FileInfo> _allDownloadedLogs = [];
  final Set<String> _selectedLogPaths = {};

  // 标签页导航拦截
  bool _isAnalyzing = false;
  bool _showNavigationWarning = false;

  @override
  void initState() {
    super.initState();
    _pipelineService = HtmlAnalysisPipelineService(config: widget.controller.config);
    _pipelineService.addListener(_onPipelineProgress);
    _resultTabController = TabController(length: 2, vsync: this);
    _checkOngoingAnalysis();
  }

  /// 检查是否有正在进行的分析，并恢复 UI 状态
  void _checkOngoingAnalysis() {
    // 如果 Pipeline 还在运行，恢复 UI 到分析中状态
    if (_pipelineService.isRunning) {
      debugPrint('检测到正在进行的分析，恢复 UI 状态');
      setState(() {
        _currentPhase = AnalysisPhase.analyzing;
        _isAnalyzing = true;
      });
    } else if (_currentSession != null &&
               _pipelineService.currentProgress?.status == AnalysisSessionStatus.done) {
      // 如果分析已完成，切换到结果页面
      debugPrint('分析已完成，切换到结果页面');
      setState(() {
        _currentPhase = AnalysisPhase.results;
        _isAnalyzing = false;
      });
    }
  }

  @override
  void dispose() {
    _pipelineService.removeListener(_onPipelineProgress);
    _pipelineService.dispose();
    _resultTabController.dispose();
    super.dispose();
  }

  void _onPipelineProgress() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 当此 widget 重新获得焦点时（如从其他标签返回），检查分析状态
    _checkOngoingAnalysis();
  }

  Future<void> _selectAndParseFile() async {
    try {
      setState(() => _isLoading = true);
      const XTypeGroup typeGroup = XTypeGroup(
        label: 'HTML reports',
        extensions: <String>['html'],
      );
      final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);

      if (file == null) {
        setState(() => _isLoading = false);
        return;
      }

      final report = await BaymaxReportParser.parseFile(file.path);

      setState(() {
        _parsedReport = report;
        _selectedReportPath = file.path;
        _errorMessage = null;
        _isLoading = false;
        _currentPhase = AnalysisPhase.selectIssues;
        _selectedJavaCrashes.clear();
        _selectedNativeCrashes.clear();
      });
    } catch (e) {
      setState(() {
        _errorMessage = '解析失败：$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _startAnalysis() async {
    debugPrint('[UI] 点击开始分析按钮');

    if (_selectedJavaCrashes.isEmpty && _selectedNativeCrashes.isEmpty) {
      debugPrint('[UI] 错误: 未选择任何崩溃');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个崩溃问题')),
      );
      return;
    }

    final selectedHashes = {..._selectedJavaCrashes, ..._selectedNativeCrashes}.toList();
    debugPrint('[UI] 已选择 ${selectedHashes.length} 个崩溃: $selectedHashes');

    _currentSession = AnalysisSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      htmlReportPath: _parsedReport?.sourceFilePath ?? _selectedReportPath ?? '',
      selectedDigestHashes: selectedHashes,
      createdAt: DateTime.now(),
    );
    debugPrint('[UI] 创建分析会话: ${_currentSession!.id}');

    debugPrint('[UI] 更新 UI 状态为 analyzing');
    setState(() {
      _currentPhase = AnalysisPhase.analyzing;
      _isAnalyzing = true;
      _showNavigationWarning = false;
    });

    debugPrint('[UI] 开始异步分析流程');
    // 异步运行分析，不阻塞 UI
    _pipelineService.startAnalysis(_currentSession!).then((_) async {
      debugPrint('[UI] 分析流程完成');
      if (mounted) {
        debugPrint('[UI] 获取会话日志文件');
        final logFiles = await _logsManager.getSessionLogFiles(_currentSession!.id);
        debugPrint('[UI] 收到 ${logFiles.length} 个日志文件');

        // 加载分析报告内容
        debugPrint('[UI] 尝试加载分析报告内容');
        String? reportContent;
        try {
          final sessionDir = await _logsManager.initializeSessionDirectory(_currentSession!.id);
          final reportFile = File('${sessionDir.path}/analysis_report.md');
          if (await reportFile.exists()) {
            reportContent = await reportFile.readAsString();
            debugPrint('[UI] 成功读取报告文件: ${reportContent.length} 字符');
          } else {
            debugPrint('[UI] 报告文件不存在: ${reportFile.path}');
          }
        } catch (e) {
          debugPrint('[UI] 读取报告文件失败: $e');
        }

        setState(() {
          _sessionLogFiles = logFiles;
          if (reportContent != null) {
            _currentSession!.analysisReportContent = reportContent;
          }
          _isAnalyzing = false;
          if (_pipelineService.currentProgress?.status == AnalysisSessionStatus.done) {
            _currentPhase = AnalysisPhase.results;
            debugPrint('[UI] 转换到 results 阶段');
          }
        });
      }
    }).catchError((e) {
      debugPrint('[UI] 分析失败: $e');
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    });
  }

  Future<void> _previewLogFile(String filePath) async {
    final content = await _logsManager.previewLogFile(filePath);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(filePath.split('/').last),
        content: SingleChildScrollView(
          child: SelectableText(content, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  /// 加载所有下载的日志文件
  Future<void> _loadAllDownloadedLogs() async {
    final logs = await _logsManager.getAllDownloadedLogFiles();

    if (mounted) {
      setState(() {
        _allDownloadedLogs = logs;
        _selectedLogPaths.clear();
      });
    }
  }

  /// 批量删除选中的日志文件
  Future<void> _deleteSelectedLogs() async {
    if (_selectedLogPaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择要删除的日志文件')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedLogPaths.length} 个日志文件吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );

    if (confirmed == true) {
      for (final path in _selectedLogPaths) {
        await _logsManager.deleteLogFile(path);
      }
      if (mounted) {
        _loadAllDownloadedLogs();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 ${_selectedLogPaths.length} 个文件')),
        );
      }
    }
  }

  Future<void> _deleteSessionLogs() async {
    if (_currentSession == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理日志文件'),
        content: const Text('确定要删除所有日志文件吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );

    if (confirmed == true) {
      await _logsManager.deleteSessionDirectory(_currentSession!.id);
      if (mounted) {
        setState(() => _sessionLogFiles = []);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日志文件已清理')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: [
        // 顶部操作栏
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('HTML 报告分析', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      '导入 Baymax HTML 报告，选择问题进行完整分析',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: () async {
                  // 加载所有下载的日志
                  await _loadAllDownloadedLogs();

                  if (!mounted) return;

                  // 显示下载日志对话框
                  showDialog(
                    context: context,
                    builder: (ctx) => _buildDownloadedLogsDialog(theme, cs, ctx),
                  );
                },
                icon: const Icon(Icons.download_outlined),
                label: const Text('下载日志'),
              ),
            ],
          ),
        ),

        // 内容区域
        Expanded(
          child: _isLoading
              ? _buildLoadingView(theme, cs)
              : _errorMessage != null
                  ? _buildErrorView(theme, cs)
                  : _currentPhase == AnalysisPhase.selectFile
                      ? _buildUploadPrompt(theme, cs)
                      : _currentPhase == AnalysisPhase.selectIssues
                          ? _buildIssueSelectionView(theme, cs)
                          : _currentPhase == AnalysisPhase.analyzing
                              ? _buildAnalyzingView(theme, cs)
                              : _buildResultsView(theme, cs),
        ),
      ],
    );
  }

  Widget _buildLoadingView(ThemeData theme, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: cs.primary),
          const SizedBox(height: 16),
          const Text('正在解析报告...'),
        ],
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: cs.error),
          const SizedBox(height: 16),
          Text('解析失败', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? '未知错误',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              setState(() {
                _errorMessage = null;
                _currentPhase = AnalysisPhase.selectFile;
                _parsedReport = null;
              });
              _selectAndParseFile();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadPrompt(ThemeData theme, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_upload_outlined, size: 64, color: cs.outline),
          const SizedBox(height: 16),
          Text('选择 HTML 报告文件', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '支持 Baymax 格式的 HTML 报告',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _selectAndParseFile,
            icon: const Icon(Icons.upload_file),
            label: const Text('选择文件'),
          ),
        ],
      ),
    );
  }

  Widget _buildIssueSelectionView(ThemeData theme, ColorScheme cs) {
    if (_parsedReport == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Java Crash 列表
          if (_parsedReport!.javaCrashes.isNotEmpty) ...[
            Text('Java Crashes (${_parsedReport!.javaCrashes.length})',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            ..._buildCrashCheckboxList(
              _parsedReport!.javaCrashes,
              _selectedJavaCrashes,
              theme,
              cs,
            ),
            const SizedBox(height: 24),
          ],

          // Native Crash 列表
          if (_parsedReport!.nativeCrashes.isNotEmpty) ...[
            Text('Native Crashes (${_parsedReport!.nativeCrashes.length})',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            ..._buildCrashCheckboxList(
              _parsedReport!.nativeCrashes,
              _selectedNativeCrashes,
              theme,
              cs,
            ),
            const SizedBox(height: 24),
          ],

          // 操作按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _currentPhase = AnalysisPhase.selectFile;
                    _parsedReport = null;
                    _selectedJavaCrashes.clear();
                    _selectedNativeCrashes.clear();
                  }),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('重新选择文件'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _startAnalysis,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('确认解析'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCrashCheckboxList(
    List<BaymaxCrashItem> crashes,
    Set<String> selectedSet,
    ThemeData theme,
    ColorScheme cs,
  ) {
    return List.generate(crashes.length, (index) {
      final crash = crashes[index];
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: selectedSet.contains(crash.digestHash),
          onChanged: (v) => setState(() {
            if (v == true) {
              selectedSet.add(crash.digestHash);
            } else {
              selectedSet.remove(crash.digestHash);
            }
          }),
          title: Text('${index + 1}. ${crash.title}',
              maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '错误率: ${crash.errorRate.toStringAsFixed(2)}% | 受影响设备: ${crash.affectedDevices}',
          ),
        ),
      );
    });
  }

  Widget _buildAnalyzingView(ThemeData theme, ColorScheme cs) {
    final progress = _pipelineService.currentProgress;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ⚠️ 警告：不要离开此页面
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              border: Border.all(color: cs.error),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_rounded, color: cs.error, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '分析进行中',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: cs.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '请勿切换页面，否则分析进度会丢失',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text('分析进度', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),

          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress?.progress ?? 0.0,
              minHeight: 8,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${((progress?.progress ?? 0.0) * 100).toStringAsFixed(1)}% - ${progress?.stepName ?? "待开始"}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),

          // 步骤指示
          ..._buildStepIndicators(progress, cs, theme),
          const SizedBox(height: 24),

          // 消息输出
          Container(
            height: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                progress?.message ?? '等待开始...',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 取消按钮
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _pipelineService.cancelAnalysis(),
              icon: const Icon(Icons.stop),
              label: const Text('取消分析'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStepIndicators(AnalysisProgress? progress, ColorScheme cs, ThemeData theme) {
    const steps = ['采样', '华佗', '分析', '报告'];
    final currentStep = progress?.currentStep ?? 1;

    return [
      Row(
        children: List.generate(steps.length, (index) {
          final stepNum = index + 1;
          final isDone = currentStep > stepNum;
          final isCurrent = currentStep == stepNum;

          return Expanded(
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDone ? cs.primary : isCurrent ? cs.primary : cs.surfaceContainer,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Center(
                    child: isDone
                        ? Icon(Icons.check, size: 20, color: cs.onPrimary)
                        : Text('$stepNum', style: theme.textTheme.labelSmall),
                  ),
                ),
                const SizedBox(height: 8),
                Text(steps[index], style: theme.textTheme.labelSmall),
              ],
            ),
          );
        }),
      ),
    ];
  }

  Widget _buildResultsView(ThemeData theme, ColorScheme cs) {
    return Column(
      children: [
        TabBar(
          controller: _resultTabController,
          tabs: const [
            Tab(text: '分析报告'),
            Tab(text: '日志文件'),
          ],
        ),

        Expanded(
          child: TabBarView(
            controller: _resultTabController,
            children: [
              _buildReportContent(theme, cs),
              _buildLogFilesView(theme, cs),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReportContent(ThemeData theme, ColorScheme cs) {
    final reportContent = _currentSession?.analysisReportContent;

    if (reportContent == null) {
      return Center(
        child: Text('暂无报告内容', style: theme.textTheme.bodyMedium),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            reportContent,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => setState(() => _currentPhase = AnalysisPhase.selectFile),
              icon: const Icon(Icons.refresh),
              label: const Text('分析新报告'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogFilesView(ThemeData theme, ColorScheme cs) {
    final logFiles = _sessionLogFiles;

    if (logFiles == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (logFiles.isEmpty) {
      return Center(
        child: Text('暂无日志文件', style: theme.textTheme.bodyMedium),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('日志文件 (${logFiles.length})', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),

          ...logFiles.map((file) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.description, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(file.name, style: theme.textTheme.labelMedium),
                          Text(
                            '${file.formattedSize} | ${file.formattedTime}',
                            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.preview, size: 20),
                      tooltip: '预览',
                      onPressed: () => _previewLogFile(file.path),
                    ),
                  ],
                ),
              ),
            ),
          )),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _deleteSessionLogs,
              icon: const Icon(Icons.delete_outline),
              label: const Text('清理所有日志'),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建已下载日志的对话框
  Widget _buildDownloadedLogsDialog(ThemeData theme, ColorScheme cs, BuildContext ctx) {
    return StatefulBuilder(
      builder: (dialogCtx, setDialogState) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.download_outlined),
            const SizedBox(width: 8),
            Text('已下载的日志文件 (${_allDownloadedLogs.length})'),
          ],
        ),
        content: SizedBox(
          width: 700,
          height: 500,
          child: _allDownloadedLogs.isEmpty
              ? Center(
                  child: Text('暂无下载的日志文件', style: theme.textTheme.bodyMedium),
                )
              : Column(
                  children: [
                    // 日志列表
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: List.generate(_allDownloadedLogs.length, (index) {
                            final file = _allDownloadedLogs[index];
                            final isSelected = _selectedLogPaths.contains(file.path);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: (v) {
                                          setDialogState(() {
                                            setState(() {
                                              if (v == true) {
                                                _selectedLogPaths.add(file.path);
                                              } else {
                                                _selectedLogPaths.remove(file.path);
                                              }
                                            });
                                          });
                                        },
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(file.name, style: theme.textTheme.labelMedium),
                                            Text(
                                              '${file.formattedSize} | ${file.formattedTime}',
                                              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.preview, size: 20),
                                        tooltip: '预览',
                                        onPressed: () => _previewLogFile(file.path),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 信息栏
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '已选择 ${_selectedLogPaths.length} 个文件',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          // 取消按钮
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          // 删除按钮
          if (_selectedLogPaths.isNotEmpty)
            FilledButton.icon(
              onPressed: () async {
                await _deleteSelectedLogs();
                if (mounted) {
                  _loadAllDownloadedLogs();
                  setDialogState(() {});
                  Navigator.pop(ctx);
                }
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除选中'),
            ),
        ],
      ),
    );
  }
}
