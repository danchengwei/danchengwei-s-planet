/// 单次 HTML 报告分析会话
class AnalysisSession {
  AnalysisSession({
    required this.id,
    required this.htmlReportPath,
    required this.selectedDigestHashes,
    required this.createdAt,
    this.analysisReportContent,
    this.logFilesPaths = const [],
    this.status = AnalysisSessionStatus.pending,
  });

  /// 会话 ID（时间戳）
  final String id;

  /// 原始 HTML 报告文件路径
  final String htmlReportPath;

  /// 用户选中的崩溃问题 digestHash 列表
  final List<String> selectedDigestHashes;

  /// 创建时间
  final DateTime createdAt;

  /// 生成的分析报告（Markdown）
  String? analysisReportContent;

  /// 下载的日志文件路径列表
  final List<String> logFilesPaths;

  /// 会话状态
  AnalysisSessionStatus status;

  /// 错误信息（如有）
  String? errorMessage;

  /// 本地分析日志目录
  String get logsDirPath => 'analysis_logs/$id';

  /// 添加日志文件路径
  void addLogFile(String filePath) {
    if (!logFilesPaths.contains(filePath)) {
      logFilesPaths.add(filePath);
    }
  }

  /// 清空所有日志文件路径
  void clearLogFiles() {
    logFilesPaths.clear();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'htmlReportPath': htmlReportPath,
        'selectedDigestHashes': selectedDigestHashes,
        'createdAt': createdAt.toIso8601String(),
        'analysisReportContent': analysisReportContent,
        'logFilesPaths': logFilesPaths,
        'status': status.name,
        'errorMessage': errorMessage,
      };

  factory AnalysisSession.fromJson(Map<String, dynamic> json) {
    return AnalysisSession(
      id: json['id']?.toString() ?? '',
      htmlReportPath: json['htmlReportPath']?.toString() ?? '',
      selectedDigestHashes: List<String>.from(json['selectedDigestHashes'] ?? []),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      analysisReportContent: json['analysisReportContent']?.toString(),
      logFilesPaths: List<String>.from(json['logFilesPaths'] ?? []),
      status: AnalysisSessionStatus.values.firstWhere(
        (e) => e.name == json['status']?.toString(),
        orElse: () => AnalysisSessionStatus.pending,
      ),
    );
  }
}

/// 分析会话状态
enum AnalysisSessionStatus {
  pending,     // 待分析
  sampling,    // 采样阶段（阿里云 API）
  huatuo,      // 华佗日志分析阶段
  analyzing,   // 本地日志分析阶段
  generating,  // 报告生成阶段
  done,        // 完成
  error,       // 失败
  cancelled,   // 已取消
}

/// 分析进度信息
class AnalysisProgress {
  AnalysisProgress({
    required this.status,
    required this.currentStep,
    required this.totalSteps,
    this.message = '',
    this.errorMessage,
  });

  /// 当前状态
  final AnalysisSessionStatus status;

  /// 当前步骤（1-4）
  final int currentStep;

  /// 总步骤数（4）
  final int totalSteps;

  /// 进度百分比（0.0-1.0）
  double get progress => totalSteps > 0 ? currentStep / totalSteps : 0.0;

  /// 状态消息
  final String message;

  /// 错误信息
  final String? errorMessage;

  /// 步骤名称
  String get stepName {
    switch (currentStep) {
      case 1:
        return '采样阶段';
      case 2:
        return '华佗日志分析';
      case 3:
        return '本地日志分析';
      case 4:
        return '报告生成';
      default:
        return '未知步骤';
    }
  }
}
