import 'dart:math';

/// 单条「智能分析」产出：用于本地报告库、挂载到对话供后续 Claude Code / MCP 跟进。
class AnalysisReportRecord {
  AnalysisReportRecord({
    required this.id,
    required this.projectId,
    required this.digestHash,
    required this.title,
    required this.bizModule,
    required this.createdAtMs,
    required this.reportBody,
    this.stackSnippet,
    this.gitlabContext,
  });

  final String id;
  final String projectId;
  final String digestHash;
  final String title;
  final String bizModule;
  final int createdAtMs;
  /// 模型完整 Markdown 输出（原因 / 分析 / 如何处理等）。
  final String reportBody;
  final String? stackSnippet;
  final String? gitlabContext;

  static String newId() {
    final r = Random();
    return 'r_${DateTime.now().microsecondsSinceEpoch}_${r.nextInt(0x7fffffff)}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'digestHash': digestHash,
        'title': title,
        'bizModule': bizModule,
        'createdAtMs': createdAtMs,
        'reportBody': reportBody,
        if (stackSnippet != null) 'stackSnippet': stackSnippet,
        if (gitlabContext != null) 'gitlabContext': gitlabContext,
      };

  factory AnalysisReportRecord.fromJson(Map<String, dynamic> j) {
    return AnalysisReportRecord(
      id: j['id']?.toString() ?? newId(),
      projectId: j['projectId']?.toString() ?? '',
      digestHash: j['digestHash']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      bizModule: j['bizModule']?.toString() ?? '',
      createdAtMs: (j['createdAtMs'] as num?)?.toInt() ?? 0,
      reportBody: j['reportBody']?.toString() ?? '',
      stackSnippet: j['stackSnippet']?.toString(),
      gitlabContext: j['gitlabContext']?.toString(),
    );
  }

  String get shortTitle {
    final t = title.trim();
    if (t.length <= 42) return t;
    return '${t.substring(0, 40)}…';
  }
}
