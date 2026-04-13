/// 列表 Top N 中某一条的独立大模型分析结果（与其它条目不串联上下文）。
class IssueIndividualLlmResult {
  IssueIndividualLlmResult({
    required this.rank,
    required this.digestHash,
    this.errorName,
    this.stackPreview,
    this.analysisText,
    this.errorMessage,
  });

  /// 在当前批次中的序号（从 1 开始）。
  final int rank;
  final String digestHash;
  final String? errorName;
  final String? stackPreview;
  final String? analysisText;
  final String? errorMessage;

  bool get isSuccess =>
      errorMessage == null && analysisText != null && analysisText!.trim().isNotEmpty;
}
