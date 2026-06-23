import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../app_controller.dart';
import '../services/analysis_logs_manager.dart';

/// 分析报告查看页面：查看历史分析会话
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

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  /// 加载所有分析会话
  Future<void> _loadSessions() async {
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final analysisLogsDir = Directory('${appSupportDir.path}/analysis_logs');

      debugPrint('[LoadSessions] 查询目录: ${analysisLogsDir.path}');

      if (!await analysisLogsDir.exists()) {
        debugPrint('[LoadSessions] 目录不存在');
        setState(() => _isLoadingSessions = false);
        return;
      }

      final sessions = <_SessionInfo>[];
      final entities = analysisLogsDir.listSync();
      debugPrint('[LoadSessions] 找到 ${entities.length} 个项目');

      for (final entity in entities) {
        if (entity is Directory) {
          final sessionId = entity.path.split('/').last;
          final reportFile = File('${entity.path}/analysis_report.md');

          if (await reportFile.exists()) {
            final stat = await reportFile.stat();
            final content = await reportFile.readAsString();
            debugPrint('[LoadSessions] 加载会话: $sessionId (${stat.size} bytes)');
            sessions.add(_SessionInfo(
              id: sessionId,
              reportPath: reportFile.path,
              fileSize: stat.size,
              modified: stat.modified,
              content: content,
            ));
          }
        }
      }

      debugPrint('[LoadSessions] 成功加载 ${sessions.length} 个会话');

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

  /// 删除会话
  Future<void> _deleteSession(_SessionInfo session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除此分析会话吗？\n会话 ID: ${session.id}'),
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
        // 解析出父目录
        final parentPath = session.reportPath.split('/').take(session.reportPath.split('/').length - 1).join('/');
        final sessionDirToDelete = Directory(parentPath);

        if (await sessionDirToDelete.exists()) {
          await sessionDirToDelete.delete(recursive: true);
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
            const SnackBar(content: Text('已删除分析会话')),
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                _selectedReportContent!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.6),
              ),
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
              '完成 HTML 分析后报告将显示在这里',
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
        return Card(
          child: InkWell(
            onTap: () => _viewSession(session),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
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
  final String content;

  _SessionInfo({
    required this.id,
    required this.reportPath,
    required this.fileSize,
    required this.modified,
    required this.content,
  });
}
