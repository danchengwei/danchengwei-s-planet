import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/issue_individual_llm_result.dart';
import '../services/security_redaction.dart';
import 'issue_detail_page.dart';
import 'llm_output_sections.dart';

/// 对当前列表前 [kTopN] 条逐条独立调用大模型，以列表展示（与「勾选批量 LLM」的串联摘要不同）。
class TopIssuesLlmPage extends StatefulWidget {
  const TopIssuesLlmPage({super.key, required this.controller, this.topN = 15});

  final AppController controller;
  final int topN;

  static const int kDefaultTopN = 15;

  @override
  State<TopIssuesLlmPage> createState() => _TopIssuesLlmPageState();
}

class _TopIssuesLlmPageState extends State<TopIssuesLlmPage> {
  List<IssueIndividualLlmResult>? _rows;
  String? _fatalError;
  int _done = 0;
  int _total = 0;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _fatalError = null;
      _rows = null;
      _done = 0;
      _total = 0;
    });
    try {
      final list = await widget.controller.analyzeTopIssuesIndividually(
        limit: widget.topN,
        onProgress: (c, t) {
          if (!mounted) return;
          setState(() {
            _done = c;
            _total = t;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _rows = list;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fatalError = userFacingNetworkError(e);
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Top${widget.topN} 逐条分析'),
        actions: [
          if (!_running && _fatalError == null && _rows != null)
            IconButton(
              tooltip: '重新分析',
              icon: const Icon(Icons.refresh),
              onPressed: _run,
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_fatalError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _fatalError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('返回')),
            ],
          ),
        ),
      );
    }

    if (_running) {
      final t = _total > 0 ? _total : 1;
      final v = _total > 0 ? _done / t : null;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LinearProgressIndicator(value: v),
                const SizedBox(height: 20),
                Text(
                  _total > 0 ? '正在逐条分析：$_done / $_total' : '准备中…',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '每条独立请求模型，互不引用其它 digest。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final rows = _rows ?? const <IssueIndividualLlmResult>[];
    if (rows.isEmpty) {
      return const Center(child: Text('无结果'));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final r = rows[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _TopIssueAnalysisCard(
            result: r,
            controller: widget.controller,
          ),
        );
      },
    );
  }
}

class _TopIssueAnalysisCard extends StatelessWidget {
  const _TopIssueAnalysisCard({required this.result, required this.controller});

  final IssueIndividualLlmResult result;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: result.rank <= 2,
          tilePadding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: cs.primaryContainer,
                child: Text(
                  '${result.rank}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.errorName ?? '(无标题)',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      result.digestHash,
                      style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          subtitle: result.stackPreview != null
              ? Padding(
                  padding: const EdgeInsets.only(left: 56, top: 8),
                  child: Text(
                    result.stackPreview!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (result.isSuccess)
                Icon(Icons.check_circle_outline, color: cs.primary, size: 22)
              else
                Icon(Icons.error_outline, color: cs.error, size: 22),
              const Icon(Icons.expand_more),
            ],
          ),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => IssueDetailPage(
                        controller: controller,
                        digestHash: result.digestHash,
                        title: result.errorName ?? '详情',
                        listStack: null,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('打开详情（GitLab / 去修改）'),
              ),
            ),
            if (result.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SelectableText(
                  result.errorMessage!,
                  style: TextStyle(color: cs.error, height: 1.35),
                ),
              )
            else if (result.analysisText != null)
              buildLlmSectionCards(context, result.analysisText!),
          ],
        ),
      ),
    );
  }
}
