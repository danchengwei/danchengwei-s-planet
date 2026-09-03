import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../app_controller.dart';
import '../services/analysis_logs_manager.dart';
import '../services/crash_analysis_agent_service.dart';

/// 报告来源类型
enum ReportSource { htmlAnalysis, intelligentAnalysis }

/// 分析报告查看页面：查看历史分析会话（HTML分析 + 智能分析）
class AnalysisReportTab extends StatefulWidget {
  const AnalysisReportTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<AnalysisReportTab> createState() => _AnalysisReportTabState();
}

class _AnalysisReportTabState extends State<AnalysisReportTab> {
  final _logsManager = AnalysisLogsManager();
  List<_SessionInfo> _sessions = [];
  bool _isLoadingSessions = true;
  _SessionInfo? _selectedSession;
  String? _selectedReportContent;
  bool _sourceAnalyzing = false;

  late final CrashAnalysisAgentService _agentService =
      CrashAnalysisAgentService(config: widget.controller.config);

  /// 从报告内容提取 digest hash（形如 [xxxx]）。
  String _extractHash(String report) {
    final m = RegExp(r'`([0-9A-Za-z]{6,})`').firstMatch(report);
    return m?.group(1) ?? 'unknown';
  }

  /// 触发源码智能分析，并把结果作为「源码分析结果」模块追加到报告末尾、落盘。
  Future<void> _runSourceAnalysis() async {
    if (_selectedReportContent == null || _selectedSession == null) return;
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
      final base = _selectedReportContent!;
      final hash = _extractHash(base);
      final result = await _agentService.analyzeSource(
        digestHash: hash,
        reportContent: base,
      );

      final section = _buildSourceSection(result);
      // 避免重复追加：若已有「源码分析结果」模块，先去除旧模块。
      final marker = '## 🔬 源码分析结果';
      var persisted = base;
      final idx = persisted.indexOf(marker);
      if (idx >= 0) persisted = persisted.substring(0, idx).trimRight();
      persisted = '$persisted\n\n$section';

      // 落盘
      await File(_selectedSession!.reportPath).writeAsString(persisted);
      if (mounted) {
        setState(() {
          _selectedReportContent = persisted;
          _selectedSession!.content = persisted;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('源码分析失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _sourceAnalyzing = false);
    }
  }

  /// 将源码分析结果渲染为 markdown 模块。
  String _buildSourceSection(result) {
    final b = StringBuffer();
    b.writeln('## 🔬 源码分析结果');
    b.writeln();
    if (result.isError) {
      b.writeln('> ${result.summary}');
      return b.toString();
    }
    if (result.summary.isNotEmpty) {
      b.writeln('**总结**: ${result.summary}');
      b.writeln();
    }
    if (result.investigation.isNotEmpty) {
      b.writeln('### 源码排查过程');
      b.writeln();
      b.writeln(result.investigation);
      b.writeln();
    }
    if (result.rootCause.isNotEmpty) {
      b.writeln('### 源码级根因');
      b.writeln();
      b.writeln(result.rootCause);
      b.writeln();
    }
    if (result.sourceAnalysis.isNotEmpty) {
      b.writeln('### 结合源码分析');
      b.writeln();
      b.writeln(result.sourceAnalysis);
      b.writeln();
    }
    if (result.possibleCauses.isNotEmpty) {
      b.writeln('### 可能原因');
      b.writeln();
      for (final c in result.possibleCauses) {
        b.writeln('- **${c.cause}**');
        if (c.detail.isNotEmpty) b.writeln('  ${c.detail}');
        for (final ev in c.evidence) {
          b.writeln('  - $ev');
        }
      }
      b.writeln();
    }
    if (result.fixSuggestions.isNotEmpty) {
      b.writeln('### 代码修改建议');
      b.writeln();
      for (final s in result.fixSuggestions) {
        final icon = s.priority == 'high' ? '🔴' : s.priority == 'medium' ? '🟡' : '🟢';
        b.writeln('- **${s.suggestion}** $icon');
        if (s.file != null && s.file!.isNotEmpty) b.writeln('  - 涉及文件: `${s.file}`');
        if (s.implementation.isNotEmpty) b.writeln('  - ${s.implementation}');
        if (s.codeDiff != null && s.codeDiff!.isNotEmpty) {
          b.writeln();
          b.writeln('  ```diff');
          for (final line in s.codeDiff!.split('\n')) {
            b.writeln('  $line');
          }
          b.writeln('  ```');
        }
      }
      b.writeln();
    }
    if (result.conclusion.isNotEmpty) {
      b.writeln('### 结论');
      b.writeln();
      b.writeln(result.conclusion);
      b.writeln();
    }
    if (result.toolTrace.isNotEmpty) {
      b.writeln('<details><summary>源码检索轨迹</summary>');
      b.writeln();
      b.writeln('```');
      b.writeln(result.toolTrace);
      b.writeln('```');
      b.writeln();
      b.writeln('</details>');
      b.writeln();
    }
    return b.toString();
  }

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  /// 加载所有分析会话（HTML分析 + 智能分析报告）
  Future<void> _loadSessions() async {
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final sessions = <_SessionInfo>[];

      // 1. 加载 HTML 分析报告（analysis_logs/{sessionId}/analysis_report.md）
      final analysisLogsDir = Directory('${appSupportDir.path}/analysis_logs');
      debugPrint('[LoadSessions] 查询目录: ${analysisLogsDir.path}');

      if (await analysisLogsDir.exists()) {
        final entities = analysisLogsDir.listSync();
        debugPrint('[LoadSessions] analysis_logs 找到 ${entities.length} 个项目');

        for (final entity in entities) {
          if (entity is Directory) {
            final sessionId = entity.path.split('/').last;
            final reportFile = File('${entity.path}/analysis_report.md');

            if (await reportFile.exists()) {
              final stat = await reportFile.stat();
              final content = await reportFile.readAsString();
              debugPrint('[LoadSessions] 加载HTML分析会话: $sessionId (${stat.size} bytes)');
              sessions.add(_SessionInfo(
                id: sessionId,
                reportPath: reportFile.path,
                fileSize: stat.size,
                modified: stat.modified,
                content: content,
                source: ReportSource.htmlAnalysis,
              ));
            }
          }
        }
      }

      // 2. 加载智能分析报告（emas_analysis_reports/*.md）
      final emasReportsDir = Directory('${appSupportDir.path}/emas_analysis_reports');
      debugPrint('[LoadSessions] 查询目录: ${emasReportsDir.path}');

      if (await emasReportsDir.exists()) {
        final files = emasReportsDir.listSync();
        debugPrint('[LoadSessions] emas_analysis_reports 找到 ${files.length} 个文件');

        for (final entity in files) {
          if (entity is File && entity.path.endsWith('.md')) {
            final fileName = p.basenameWithoutExtension(entity.path);
            final stat = await entity.stat();
            final content = await entity.readAsString();
            debugPrint('[LoadSessions] 加载智能分析报告: $fileName (${stat.size} bytes)');
            sessions.add(_SessionInfo(
              id: fileName,
              reportPath: entity.path,
              fileSize: stat.size,
              modified: stat.modified,
              content: content,
              source: ReportSource.intelligentAnalysis,
            ));
          }
        }
      }

      debugPrint('[LoadSessions] 成功加载 ${sessions.length} 个报告');

      // 按修改时间降序排列
      sessions.sort((a, b) => b.modified.compareTo(a.modified));

      if (mounted) {
        setState(() {
          _sessions = sessions;
          _isLoadingSessions = false;
        });
      }
    } catch (e) {
      debugPrint('加载会话失败: $e');
      if (mounted) {
        setState(() => _isLoadingSessions = false);
      }
    }
  }

  /// 查看会话报告
  void _viewSession(_SessionInfo session) {
    setState(() {
      _selectedSession = session;
      _selectedReportContent = session.content;
    });
  }

  /// 删除会话或报告
  Future<void> _deleteSession(_SessionInfo session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除此${session.source == ReportSource.htmlAnalysis ? '分析会话' : '智能分析报告'}吗？\n会话 ID: ${session.id}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        if (session.source == ReportSource.htmlAnalysis) {
          // HTML分析报告：删除整个会话目录
          final parentPath = session.reportPath.split('/').take(session.reportPath.split('/').length - 1).join('/');
          final sessionDirToDelete = Directory(parentPath);

          if (await sessionDirToDelete.exists()) {
            await sessionDirToDelete.delete(recursive: true);
          }
        } else {
          // 智能分析报告：直接删除文件
          final fileToDelete = File(session.reportPath);
          if (await fileToDelete.exists()) {
            await fileToDelete.delete();
          }
        }

        if (mounted) {
          setState(() {
            _sessions.removeWhere((s) => s.id == session.id);
            if (_selectedSession?.id == session.id) {
              _selectedSession = null;
              _selectedReportContent = null;
            }
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已删除分析报告')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_isLoadingSessions) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_selectedReportContent != null) {
      // 显示报告内容
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: cs.surfaceContainer,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('会话: ${_selectedSession!.id}', style: theme.textTheme.labelSmall),
                      Text(
                        '修改: ${_selectedSession!.modified.toString().split('.')[0]}',
                        style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: _sourceAnalyzing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_fix_high_outlined),
                  tooltip: '源码智能分析',
                  onPressed: _sourceAnalyzing ? null : _runSourceAnalysis,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _selectedReportContent = null;
                    _selectedSession = null;
                  }),
                  tooltip: '关闭',
                ),
              ],
            ),
          ),
          Expanded(
            child: Markdown(
              data: _selectedReportContent!,
              selectable: true,
              padding: const EdgeInsets.all(16),
              onTapLink: (text, href, title) async {
                if (href == null) return;
                final uri = Uri.tryParse(href);
                if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
          ),
        ],
      );
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: cs.outline),
            const SizedBox(height: 16),
            Text('暂无分析报告', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text(
              '完成 HTML 分析或智能分析后报告将显示在这里',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _sessions.length,
      itemBuilder: (ctx, idx) {
        final session = _sessions[idx];
        final isHtmlReport = session.source == ReportSource.htmlAnalysis;
        return Card(
          child: InkWell(
            onTap: () => _viewSession(session),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isHtmlReport
                          ? Colors.orange.withValues(alpha: 0.15)
                          : Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isHtmlReport ? 'HTML' : '智能',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isHtmlReport ? Colors.orange : Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.id,
                          style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.calendar_today, size: 12, color: cs.outline),
                            const SizedBox(width: 4),
                            Text(
                              session.modified.toString().split('.')[0],
                              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.storage, size: 12, color: cs.outline),
                            const SizedBox(width: 4),
                            Text(
                              '${(session.fileSize / 1024).toStringAsFixed(1)} KB',
                              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteSession(session),
                    tooltip: '删除',
                    color: cs.error,
                    iconSize: 20,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SessionInfo {
  final String id;
  final String reportPath;
  final int fileSize;
  final DateTime modified;
  String content;
  final ReportSource source;

  _SessionInfo({
    required this.id,
    required this.reportPath,
    required this.fileSize,
    required this.modified,
    required this.content,
    required this.source,
  });
}
