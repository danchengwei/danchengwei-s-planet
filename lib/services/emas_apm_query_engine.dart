import 'dart:convert';
import 'package:process/process.dart';

/// EMAS APM 查询引擎 - 封装 aliyun emas-appmonitor 的 4 个只读 API
/// GetIssues / GetIssue / GetErrors / GetError
class EmasApmQueryEngine {
  EmasApmQueryEngine({
    ProcessManager? processManager,
  }) : _processManager = processManager ?? const LocalProcessManager();

  final ProcessManager _processManager;

  /// 执行 aliyun 命令
  Future<Map<String, dynamic>> _runAliyunCommand(List<String> args) async {
    try {
      final result = await _processManager.run(
        ['aliyun', 'emas-appmonitor', ...args],
      );

      if (result.exitCode != 0) {
        throw EmasException('aliyun command failed: ${result.stderr}');
      }

      final output = result.stdout.toString().trim();
      if (output.isEmpty) {
        return {};
      }

      return jsonDecode(output) as Map<String, dynamic>;
    } catch (e) {
      throw EmasException('EMAS query failed: $e');
    }
  }

  /// GetIssues - 获取问题列表
  /// bizModule: crash/anr/lag/custom/memory_leak/memory_alloc
  /// os: android/iphoneos/harmony
  Future<Map<String, dynamic>> getIssues({
    required String appKey,
    required String bizModule,
    required DateTime startDate,
    required DateTime endDate,
    String os = 'android',
    int pageSize = 20,
    int pageIndex = 1,
  }) async {
    final startTime = startDate.millisecondsSinceEpoch;
    final endTime = endDate.millisecondsSinceEpoch;

    return _runAliyunCommand([
      'get-issues',
      '--app-key',
      appKey,
      '--biz-module',
      bizModule,
      '--os',
      os,
      '--time-range',
      'StartTime=$startTime EndTime=$endTime Granularity=1 GranularityUnit=day',
      '--page-size',
      pageSize.toString(),
      '--page-index',
      pageIndex.toString(),
      '--order-by',
      'ErrorCount',
      '--order-type',
      'desc',
    ]);
  }

  /// GetIssue - 获取单个问题的详细信息
  Future<Map<String, dynamic>> getIssue({
    required String appKey,
    required String bizModule,
    required String digestHash,
    required DateTime startDate,
    required DateTime endDate,
    String os = 'android',
  }) async {
    final startTime = startDate.millisecondsSinceEpoch;
    final endTime = endDate.millisecondsSinceEpoch;

    return _runAliyunCommand([
      'get-issue',
      '--app-key',
      appKey,
      '--biz-module',
      bizModule,
      '--digest-hash',
      digestHash,
      '--os',
      os,
      '--time-range',
      'StartTime=$startTime EndTime=$endTime Granularity=1 GranularityUnit=day',
    ]);
  }

  /// GetErrors - 获取错误样本列表（用于 ANR 等）
  Future<Map<String, dynamic>> getErrors({
    required String appKey,
    required String bizModule,
    required DateTime startDate,
    required DateTime endDate,
    String os = 'android',
    int pageSize = 10,
    int pageIndex = 1,
  }) async {
    final startTime = startDate.millisecondsSinceEpoch;
    final endTime = endDate.millisecondsSinceEpoch;

    return _runAliyunCommand([
      'get-errors',
      '--app-key',
      appKey,
      '--biz-module',
      bizModule,
      '--os',
      os,
      '--time-range',
      'StartTime=$startTime EndTime=$endTime',
      '--page-size',
      pageSize.toString(),
      '--page-index',
      pageIndex.toString(),
    ]);
  }

  /// GetError - 获取单个错误样本的详细信息
  Future<Map<String, dynamic>> getError({
    required String appKey,
    required String bizModule,
    required String errorId,
    String os = 'android',
  }) async {
    return _runAliyunCommand([
      'get-error',
      '--app-key',
      appKey,
      '--biz-module',
      bizModule,
      '--error-id',
      errorId,
      '--os',
      os,
    ]);
  }

  /// 提取问题列表中的基本信息
  static List<IssueBasicInfo> parseIssuesList(Map<String, dynamic> response) {
    final issues = <IssueBasicInfo>[];

    final model = response['Model'];
    if (model is! Map) return issues;

    final items = model['Items'];
    if (items is! List) return issues;

    for (final item in items) {
      if (item is Map<String, dynamic>) {
        issues.add(IssueBasicInfo(
          digestHash: item['DigestHash']?.toString() ?? '',
          name: item['Name']?.toString() ?? '',
          errorCount: (item['ErrorCount'] as num?)?.toInt() ?? 0,
          affectedDevices: (item['AffectedDevices'] as num?)?.toInt() ?? 0,
          errorRate: (item['ErrorRate'] as num?)?.toDouble() ?? 0.0,
          firstVersion: item['FirstVersion']?.toString() ?? '',
          versionDistribution: _parseVersionDistribution(item['VersionDistribution']),
        ));
      }
    }

    return issues;
  }

  static List<String> _parseVersionDistribution(dynamic data) {
    if (data is! List) return [];
    return data
        .whereType<Map<String, dynamic>>()
        .map((e) => e['Version']?.toString() ?? '')
        .where((v) => v.isNotEmpty)
        .toList();
  }
}

/// 问题基本信息
class IssueBasicInfo {
  IssueBasicInfo({
    required this.digestHash,
    required this.name,
    required this.errorCount,
    required this.affectedDevices,
    required this.errorRate,
    required this.firstVersion,
    required this.versionDistribution,
  });

  final String digestHash;
  final String name;
  final int errorCount;
  final int affectedDevices;
  final double errorRate;
  final String firstVersion;
  final List<String> versionDistribution;

  Map<String, dynamic> toJson() => {
        'digestHash': digestHash,
        'name': name,
        'errorCount': errorCount,
        'affectedDevices': affectedDevices,
        'errorRate': errorRate,
        'firstVersion': firstVersion,
        'versionDistribution': versionDistribution,
      };
}

/// EMAS 异常
class EmasException implements Exception {
  EmasException(this.message);
  final String message;

  @override
  String toString() => message;
}
