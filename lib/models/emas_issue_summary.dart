/// EMAS 问题摘要信息 (来自 GetIssues API)
class EmasIssueSummary {
  /// 问题唯一哈希值
  final String digestHash;

  /// 问题名称 (自动从堆栈提取)
  final String name;

  /// 问题类型: crash / anr / lag / custom / memory_leak / memory_alloc
  final String type;

  /// 业务模块类型 (用于后续 GetIssue 调用)
  final String bizModule;

  /// 错误总次数
  final int errorCount;

  /// 错误率 (百分比形式的字符串，如 "45%")
  final String errorRate;

  /// 错误设备数
  final int errorDeviceCount;

  /// 错误设备率 (百分比)
  final String errorDeviceRate;

  EmasIssueSummary({
    required this.digestHash,
    required this.name,
    required this.type,
    required this.bizModule,
    required this.errorCount,
    required this.errorRate,
    required this.errorDeviceCount,
    required this.errorDeviceRate,
  });

  /// 从 JSON 创建 (来自 list_top_issues.sh 的输出)
  factory EmasIssueSummary.fromJson(Map<String, dynamic> json) {
    return EmasIssueSummary(
      digestHash: json['digestHash'] as String? ?? '',
      name: json['name'] as String? ?? json['digestHash'] as String? ?? 'Unknown',
      type: json['type'] as String? ?? 'unknown',
      bizModule: json['bm'] as String? ?? json['bizModule'] as String? ?? 'crash',
      errorCount: json['ec'] as int? ?? json['errorCount'] as int? ?? 0,
      errorRate: json['er'] as String? ?? json['errorRate'] as String? ?? '0%',
      errorDeviceCount: json['edc'] as int? ?? json['errorDeviceCount'] as int? ?? 0,
      errorDeviceRate: json['edr'] as String? ?? json['errorDeviceRate'] as String? ?? '0%',
    );
  }

  Map<String, dynamic> toJson() => {
        'digestHash': digestHash,
        'name': name,
        'type': type,
        'bm': bizModule,
        'ec': errorCount,
        'er': errorRate,
        'edc': errorDeviceCount,
        'edr': errorDeviceRate,
      };

  @override
  String toString() => 'Issue($name, $type, $errorCount errors, $errorRate rate)';
}
