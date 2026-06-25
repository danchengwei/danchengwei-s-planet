import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../aliyun/emas_appmonitor_client.dart';
import '../app_controller.dart';
import '../services/crash_analysis_report_generator.dart';
import '../services/security_redaction.dart';

/// 批量分析入口：选 N 条 issue → 顺序拉详情 → 生成合并报告 → 落盘 + 页面内展示。
///
/// 仿照 `.claude/skills/emas-intelligent-analysis2/SKILLS.md` 中"对多个崩溃进行综合分析"流程。
class BatchAnalysisPage extends StatefulWidget {
  const BatchAnalysisPage({
    super.key,
    required this.controller,
    required this.digestHashes,
    this.bizModule = 'crash',
    this.startTimeMs,
    this.endTimeMs,
  });

  final AppController controller;
  final List<String> digestHashes;
  final String bizModule;
  final int? startTimeMs;
  final int? endTimeMs;

  @override
  State<BatchAnalysisPage> createState() => _BatchAnalysisPageState();
}

class _BatchAnalysisPageState extends State<BatchAnalysisPage> {
  bool _busy = false;
  int _done = 0;
  int _total = 0;
  String? _err;
  String _markdown = '';
  String? _path;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (_busy) return;
    final hashes = widget.digestHashes;
    if (hashes.isEmpty) {
      setState(() => _err = '没有选中任何 issue');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
      _done = 0;
      _total = hashes.length;
      _markdown = '';
      _path = null;
    });

    final itemsByHash = <String, IssueListItem>{};
    for (final it in widget.controller.lastIssues?.items ?? const <IssueListItem>[]) {
      if (it.digestHash != null) itemsByHash[it.digestHash!] = it;
    }

    final inputs = <ReportInput>[];
    try {
      for (var i = 0; i < hashes.length; i++) {
        final h = hashes[i];
        Map<String, dynamic>? detail;
        String? fetchErr;
        try {
          detail = await widget.controller.fetchIssueDetail(
            h,
            startTimeMs: widget.startTimeMs,
            endTimeMs: widget.endTimeMs,
          );
        } catch (e) {
          fetchErr = e.toString();
        }
        final item = itemsByHash[h];
        inputs.add(ReportInput(
          digestHash: h,
          title: item?.displayTitles().$1 ?? h,
          issueDetailJson: detail ?? <String, dynamic>{'_error': fetchErr ?? '未拉取到详情'},
          listItem: item,
          listStack: item?.stack,
          startTimeMs: widget.startTimeMs,
          endTimeMs: widget.endTimeMs,
        ));
        if (mounted) {
          setState(() => _done = i + 1);
        }
      }

      final generator = CrashAnalysisReportGenerator(config: widget.controller.config);
      final result = await generator.generateForBatch(
        inputs: inputs,
        bizModule: widget.bizModule,
        projectPath: widget.controller.config.localProjectPath,
      );
      final path = await generator.saveReport(result);
      if (!mounted) return;
      setState(() {
        _markdown = result.markdown;
        _path = path;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = userFacingNetworkError(e);
        _busy = false;
      });
    }
  }

  Future<void> _openInFinder() async {
    final path = _path;
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) return;
    try {
      await Process.run('open', ['-R', path]);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: path));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制报告路径到剪贴板'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final progress = _total == 0 ? 0.0 : _done / _total;
    return Scaffold(
      appBar: AppBar(
        title: const Text('批量智能分析'),
        actions: [
          if (_path != null)
            IconButton(
              tooltip: '在 Finder 中查看',
              icon: const Icon(Icons.folder_open),
              onPressed: _openInFinder,
            ),
          IconButton(
            tooltip: '重新生成',
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _run,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy || _err != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _StatusBar(
                busy: _busy,
                done: _done,
                total: _total,
                err: _err,
                progress: progress,
              ),
            ),
          if (!_busy && _err == null && _path != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  '已保存：$_path',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          Expanded(
            child: _markdown.isEmpty && !_busy
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _err ?? '等待开始…',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  )
                : Container(
                    margin: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomPad),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _markdown,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.busy,
    required this.done,
    required this.total,
    required this.err,
    required this.progress,
  });

  final bool busy;
  final int done;
  final int total;
  final String? err;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (err != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          err!,
          style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (busy)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.primary),
              )
            else
              Icon(Icons.check_circle, color: cs.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              busy
                  ? '正在分析 $done / $total …'
                  : '已完成 $total / $total',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: busy ? progress : 1.0, minHeight: 6),
        ),
      ],
    );
  }
}
