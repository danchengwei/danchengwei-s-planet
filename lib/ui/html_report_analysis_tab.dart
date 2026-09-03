import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../core/baymax_report_parser.dart';
import '../models/analysis_session.dart';
import '../services/analysis_logs_manager.dart';
import '../services/html_analysis_pipeline_service.dart';
import '../services/crash_analysis_agent_service.dart';

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

  // 源码智能分析
  bool _sourceAnalyzing = false;

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

  /// 当前阶段返回按钮提示
  String get _backTooltip {
    switch (_currentPhase) {
      case AnalysisPhase.selectIssues:
        return '返回文件选择';
      case AnalysisPhase.analyzing:
        return '分析进行中';
      case AnalysisPhase.results:
        return '返回问题选择';
      case AnalysisPhase.selectFile:
        return '返回';
    }
  }

  /// 阶段返回：回退到上一步，并同步日志/会话数据。
  ///
  /// results → selectIssues（保留已解析报告，可重新选择问题）；
  /// selectIssues → selectFile（清空报告，重新导入）。
  /// analyzing 阶段不允许返回（按钮禁用），需先取消分析。
  void _goBack() {
    if (_isAnalyzing || _pipelineService.isRunning) return;

    setState(() {
      switch (_currentPhase) {
        case AnalysisPhase.results:
          // 返回问题选择：保留解析结果，刷新会话数据
          _currentPhase = AnalysisPhase.selectIssues;
          _currentSession = _pipelineService.currentSession;
          break;
        case AnalysisPhase.selectIssues:
          // 返回文件选择：清空解析与选择
          _currentPhase = AnalysisPhase.selectFile;
          _parsedReport = null;
          _selectedReportPath = null;
          _errorMessage = null;
          _selectedJavaCrashes.clear();
          _selectedNativeCrashes.clear();
          _sessionLogFiles = null;
          break;
        case AnalysisPhase.analyzing:
        case AnalysisPhase.selectFile:
          break;
      }
    });

    // 同步刷新下载日志列表（返回前后数据保持一致）
    _loadAllDownloadedLogs();
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
          final status = _pipelineService.currentProgress?.status;
          if (status == AnalysisSessionStatus.done) {
            _currentPhase = AnalysisPhase.results;
            debugPrint('[UI] 转换到 results 阶段');
          } else if (status == AnalysisSessionStatus.cancelled) {
            // 用户取消：回到问题选择阶段，并重置取消标志
            _pipelineService.reset();
            _currentPhase = AnalysisPhase.selectIssues;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('分析已取消')),
            );
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

  /// 预览日志：若是目录则展示其中的文件列表，点文件可查看内容；若是文件则直接展示。
  Future<void> _previewLogFile(String filePath) async {
    final isDir = await FileSystemEntity.isDirectory(filePath);

    if (isDir) {
      final files = await _logsManager.listFilesInDirectory(filePath);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(filePath.split('/').last),
          content: SizedBox(
            width: 640,
            height: 420,
            child: files.isEmpty
                ? const Center(child: Text('目录为空'))
                : ListView.separated(
                    itemCount: files.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final f = files[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.description_outlined, size: 20),
                        title: Text(f.name, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        subtitle: Text(f.formattedSize),
                        onTap: () {
                          Navigator.pop(ctx);
                          _previewLogFile(f.path);
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          ],
        ),
      );
      return;
    }

    // 文件：应用内展示内容
    String content;
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文件不存在')));
        return;
      }
      content = await file.readAsString();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('读取失败: $e')));
      return;
    }

    if (!mounted) return;
    final display = content.length > 200 * 1024
        ? '${content.substring(0, 200 * 1024)}\n\n...[已截断，共 ${content.length} 字符]'
        : content;

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: 760,
          height: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                child: Row(
                  children: [
                    Expanded(child: Text(filePath.split('/').last,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace', fontSize: 13))),
                    IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    display,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.45),
                  ),
                ),
              ),
            ],
          ),
        ),
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
              // 阶段返回按钮：非首阶段时显示
              if (_currentPhase != AnalysisPhase.selectFile) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: _backTooltip,
                  onPressed: _isAnalyzing ? null : _goBack,
                ),
                const SizedBox(width: 4),
              ],
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
    final pct = (progress?.progress ?? 0.0) * 100;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          // 标题
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Text('正在分析崩溃…', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '正在查询样本、下载华佗日志并进行智能分析，可能需要一些时间',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // 进度百分比卡片
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                    fontFeatures: const [],
                  ),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (progress?.progress ?? 0).clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
                const SizedBox(height: 16),
                ..._buildStepIndicators(progress, cs, theme),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 实时日志
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                progress?.message ?? '等待开始…',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 取消按钮
          OutlinedButton.icon(
            onPressed: _isAnalyzing ? () => _pipelineService.cancelAnalysis() : null,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('取消分析'),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.error,
              side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStepIndicators(AnalysisProgress? progress, ColorScheme cs, ThemeData theme) {
    const steps = [
      ['采样', Icons.travel_explore],
      ['华佗日志', Icons.download_rounded],
      ['智能分析', Icons.psychology_alt_outlined],
      ['生成报告', Icons.summarize_outlined],
    ];
    final currentStep = progress?.currentStep ?? 0;

    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            // 连接线
            final stepAfter = (i ~/ 2) + 1;
            final done = currentStep > stepAfter;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  height: 2.5,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: done ? cs.primary : cs.surfaceContainerHighest,
                ),
              ),
            );
          }
          final index = i ~/ 2;
          final stepNum = index + 1;
          final isDone = currentStep > stepNum;
          final isCurrent = currentStep == stepNum;
          return Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDone || isCurrent ? cs.primary : cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDone
                      ? Icons.check_rounded
                      : steps[index][1] as IconData,
                  size: isDone ? 20 : 17,
                  color: isDone || isCurrent ? cs.onPrimary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                steps[index][0] as String,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isCurrent
                      ? cs.primary
                      : isDone
                          ? cs.onSurface
                          : cs.onSurfaceVariant,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
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

  /// 触发源码智能分析，结果以「源码分析结果」模块追加到报告末尾并落盘。
  Future<void> _runSourceAnalysis() async {
    final session = _currentSession;
    if (session == null) return;
    final cfg = widget.controller.config;
    final miss = cfg.validateLlm();
    if (miss.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在「配置」填写大模型：${miss.join('、')}')),
      );
      return;
    }
    // 未配置项目路径：阻断，提示先配置
    if (cfg.localProjectPath.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在「配置 → 源码分析」中填写本地项目源码路径，再进行源码智能分析。')),
      );
      return;
    }
    // 未配置项目提示词：不阻断，仅提示将使用内置默认说明
    if (cfg.sourceAnalysisPrompt.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未配置「项目说明提示词」，将使用内置的学而思网校项目默认结构说明进行检索。')),
      );
    }

    setState(() => _sourceAnalyzing = true);
    try {
      final agent = CrashAnalysisAgentService(config: widget.controller.config);
      final base = session.analysisReportContent ?? '';
      final hash = RegExp(r'`([0-9A-Za-z]{6,})`').firstMatch(base)?.group(1) ?? 'unknown';

      final result = await agent.analyzeSource(
        digestHash: hash,
        reportContent: base,
      );

      final section = StringBuffer()
        ..writeln('## 🔬 源码分析结果')
        ..writeln();
      if (result.isError) {
        section.writeln('> ${result.summary}');
      } else {
        if (result.summary.isNotEmpty) {
          section.writeln('**总结**: ${result.summary}');
          section.writeln();
        }
        if (result.investigation.isNotEmpty) {
          section.writeln('### 源码排查过程');
          section.writeln(result.investigation);
          section.writeln();
        }
        if (result.rootCause.isNotEmpty) {
          section.writeln('### 源码级根因');
          section.writeln(result.rootCause);
          section.writeln();
        }
        if (result.sourceAnalysis.isNotEmpty) {
          section.writeln('### 结合源码分析');
          section.writeln(result.sourceAnalysis);
          section.writeln();
        }
        if (result.possibleCauses.isNotEmpty) {
          section.writeln('### 可能原因');
          section.writeln();
          for (final c in result.possibleCauses) {
            section.writeln('- **${c.cause}**');
            if (c.detail.isNotEmpty) section.writeln('  ${c.detail}');
            for (final ev in c.evidence) {
              section.writeln('  - $ev');
            }
          }
          section.writeln();
        }
        if (result.fixSuggestions.isNotEmpty) {
          section.writeln('### 代码修改建议');
          section.writeln();
          for (final s in result.fixSuggestions) {
            final icon = s.priority == 'high' ? '🔴' : s.priority == 'medium' ? '🟡' : '🟢';
            section.writeln('- **${s.suggestion}** $icon');
            if (s.file != null && s.file!.isNotEmpty) section.writeln('  - 涉及文件: `${s.file}`');
            if (s.implementation.isNotEmpty) section.writeln('  - ${s.implementation}');
            if (s.codeDiff != null && s.codeDiff!.isNotEmpty) {
              section.writeln();
              section.writeln('  ```diff');
              for (final line in s.codeDiff!.split('\n')) {
                section.writeln('  $line');
              }
              section.writeln('  ```');
            }
          }
          section.writeln();
        }
        if (result.conclusion.isNotEmpty) {
          section.writeln('### 结论');
          section.writeln(result.conclusion);
          section.writeln();
        }
        if (result.toolTrace.isNotEmpty) {
          section.writeln('<details><summary>源码检索轨迹</summary>');
          section.writeln();
          section.writeln('```');
          section.writeln(result.toolTrace);
          section.writeln('```');
          section.writeln('</details>');
        }
      }

      // 避免重复追加：去掉旧的源码分析模块
      final marker = '## 🔬 源码分析结果';
      var persisted = base;
      final idx = persisted.indexOf(marker);
      if (idx >= 0) persisted = persisted.substring(0, idx).trimRight();
      persisted = '$persisted\n\n${section.toString().trimRight()}\n';

      // 落盘到会话报告文件
      final sessionDir = await _logsManager.initializeSessionDirectory(session.id);
      final reportFile = File('${sessionDir.path}/analysis_report.md');
      await reportFile.writeAsString(persisted);
      session.analysisReportContent = persisted;

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('源码分析失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _sourceAnalyzing = false);
    }
  }

  Widget _buildReportContent(ThemeData theme, ColorScheme cs) {
    final reportContent = _currentSession?.analysisReportContent;

    if (reportContent == null) {
      return Center(
        child: Text('暂无报告内容', style: theme.textTheme.bodyMedium),
      );
    }

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Markdown(
                data: reportContent,
                selectable: true,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                onTapLink: (text, href, title) async {
                  if (href == null) return;
                  final uri = Uri.tryParse(href);
                  if (uri == null) return;
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  codeblockPadding: const EdgeInsets.all(10),
                  codeblockDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  code: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4),
                  a: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline),
                ),
                builders: {
                  'pre': _WrappingCodeBlockBuilder(),
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: FilledButton.icon(
                onPressed: () => setState(() => _currentPhase = AnalysisPhase.selectFile),
                icon: const Icon(Icons.refresh),
                label: const Text('分析新报告'),
              ),
            ),
          ],
        ),
        // 右上角固定小按钮：源码智能分析
        Positioned(
          top: 8,
          right: 12,
          child: FloatingActionButton.small(
            heroTag: 'html_source_analysis',
            onPressed: _sourceAnalyzing ? null : _runSourceAnalysis,
            tooltip: '源码智能分析',
            child: _sourceAnalyzing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.auto_fix_high_outlined, size: 22),
          ),
        ),
      ],
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
                          const SizedBox(height: 2),
                          SelectableText(
                            file.path,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                            ),
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
                                            const SizedBox(height: 2),
                                            SelectableText(
                                              file.path,
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                fontFamily: 'monospace',
                                                fontSize: 10,
                                                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                                              ),
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

/// 让 Markdown 代码块（```...```）内的长文本自动换行、可选中复制，
/// 避免长 URL/JSON 需要横向滑动。
class _WrappingCodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final cs = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark
        ? const ColorScheme.dark()
        : const ColorScheme.light();
    final codeText = element.textContent.trimRight();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        codeText,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: ['Menlo', 'Courier New', 'monospace'],
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }
}
