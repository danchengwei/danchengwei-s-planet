import 'dart:convert';

/// 灰度监听任务定义
class GraytestMonitoringTask {
  GraytestMonitoringTask({
    required this.id,
    required this.name,
    required this.enabled,
    required this.targetVersions,
    required this.webhookUrl,
    required this.bizModule,
    required this.checkIntervalSeconds,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 任务唯一 ID（时间戳 + 随机数）
  final String id;

  /// 任务名称（用户设置）
  final String name;

  /// 启用/禁用状态
  final bool enabled;

  /// 监听的版本列表（支持多版本）
  final List<String> targetVersions;

  /// Webhook 通知 URL
  final String webhookUrl;

  /// 业务模块（crash/anr/lag/custom）
  final String bizModule;

  /// 检查间隔（秒），如 10, 30, 60, 300
  final int checkIntervalSeconds;

  /// 创建时间
  final DateTime createdAt;

  /// 最后修改时间
  final DateTime updatedAt;

  /// 创建副本，支持修改指定字段
  GraytestMonitoringTask copyWith({
    String? id,
    String? name,
    bool? enabled,
    List<String>? targetVersions,
    String? webhookUrl,
    String? bizModule,
    int? checkIntervalSeconds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GraytestMonitoringTask(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      targetVersions: targetVersions ?? this.targetVersions,
      webhookUrl: webhookUrl ?? this.webhookUrl,
      bizModule: bizModule ?? this.bizModule,
      checkIntervalSeconds: checkIntervalSeconds ?? this.checkIntervalSeconds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 从 JSON 反序列化
  factory GraytestMonitoringTask.fromJson(Map<String, dynamic> j) {
    return GraytestMonitoringTask(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      enabled: j['enabled'] == true,
      targetVersions: List<String>.from(j['targetVersions'] as List<dynamic>? ?? []),
      webhookUrl: j['webhookUrl']?.toString() ?? '',
      bizModule: j['bizModule']?.toString() ?? 'crash',
      checkIntervalSeconds: j['checkIntervalSeconds'] as int? ?? 30,
      createdAt:
          j['createdAt'] != null ? DateTime.parse(j['createdAt'].toString()) : null,
      updatedAt: j['updatedAt'] != null ? DateTime.parse(j['updatedAt'].toString()) : null,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'targetVersions': targetVersions,
        'webhookUrl': webhookUrl,
        'bizModule': bizModule,
        'checkIntervalSeconds': checkIntervalSeconds,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraytestMonitoringTask &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          enabled == other.enabled &&
          targetVersions == other.targetVersions &&
          webhookUrl == other.webhookUrl &&
          bizModule == other.bizModule &&
          checkIntervalSeconds == other.checkIntervalSeconds;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      enabled.hashCode ^
      targetVersions.hashCode ^
      webhookUrl.hashCode ^
      bizModule.hashCode ^
      checkIntervalSeconds.hashCode;

  @override
  String toString() =>
      'GraytestMonitoringTask(id: $id, name: $name, enabled: $enabled, versions: $targetVersions)';
}

/// 任务执行记录
class TaskExecutionRecord {
  TaskExecutionRecord({
    required this.id,
    required this.taskId,
    required this.digestHash,
    required this.issueTitle,
    required this.issueVersion,
    required this.analysisReportContent,
    required this.executedAt,
    this.webhookStatus = 'pending',
    this.webhookError,
  });

  /// 执行记录 ID
  final String id;

  /// 所属任务 ID
  final String taskId;

  /// Crash digestHash
  final String digestHash;

  /// Crash 标题
  final String issueTitle;

  /// 受影响版本
  final String issueVersion;

  /// 生成的 Markdown 分析报告
  final String analysisReportContent;

  /// 执行时间
  final DateTime executedAt;

  /// Webhook 状态（pending/sent/failed）
  final String webhookStatus;

  /// Webhook 失败原因（如有）
  final String? webhookError;

  /// 从 JSON 反序列化
  factory TaskExecutionRecord.fromJson(Map<String, dynamic> j) {
    return TaskExecutionRecord(
      id: j['id']?.toString() ?? '',
      taskId: j['taskId']?.toString() ?? '',
      digestHash: j['digestHash']?.toString() ?? '',
      issueTitle: j['issueTitle']?.toString() ?? '',
      issueVersion: j['issueVersion']?.toString() ?? '',
      analysisReportContent: j['analysisReportContent']?.toString() ?? '',
      executedAt:
          j['executedAt'] != null ? DateTime.parse(j['executedAt'].toString()) : DateTime.now(),
      webhookStatus: j['webhookStatus']?.toString() ?? 'pending',
      webhookError: j['webhookError']?.toString(),
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'taskId': taskId,
        'digestHash': digestHash,
        'issueTitle': issueTitle,
        'issueVersion': issueVersion,
        'analysisReportContent': analysisReportContent,
        'executedAt': executedAt.toIso8601String(),
        'webhookStatus': webhookStatus,
        'webhookError': webhookError,
      };

  @override
  String toString() =>
      'TaskExecutionRecord(taskId: $taskId, digestHash: $digestHash, status: $webhookStatus)';
}
