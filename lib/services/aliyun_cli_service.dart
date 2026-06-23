import 'dart:convert';
import 'dart:io';

import '../models/tool_config.dart';
import '../aliyun/emas_appmonitor_client.dart';

/// 通过阿里云 CLI 调用 EMAS API
///
/// 包装所有 4 个核心 API 调用：get-issues、get-issue、get-errors、get-error
///
/// 使用示例：
/// ```dart
/// final service = AliyunCliService(config: toolConfig);
///
/// // 1. 获取问题列表
/// final issues = await service.getIssues(
///   bizModule: 'crash',
///   startTimeMs: startTime,
///   endTimeMs: endTime,
///   os: 'android',
///   firstVersion: '3.5.0',  // 版本筛选
/// );
///
/// // 2. 获取单个问题详情（包括受影响版本列表）
/// final issue = await service.getIssue(
///   bizModule: 'crash',
///   digestHash: issues.items[0].digestHash,
///   startTimeMs: startTime,
///   endTimeMs: endTime,
/// );
///
/// // 3. 获取错误样本列表
/// final errors = await service.getErrors(
///   bizModule: 'crash',
///   digestHash: issues.items[0].digestHash,
///   startTimeMs: startTime,
///   endTimeMs: endTime,
///   pageSize: 5,
/// );
///
/// // 4. 获取单个错误样本的完整信息
/// final error = await service.getError(
///   bizModule: 'crash',
///   digestHash: issues.items[0].digestHash,
///   clientTime: errors['Model']['Items'][0]['ClientTime'],
///   uuid: errors['Model']['Items'][0]['Uuid'],
///   did: errors['Model']['Items'][0]['Did'],
/// );
/// ```
class AliyunCliService {
  final ToolConfig _config;

  AliyunCliService({required ToolConfig config}) : _config = config;

  /// 内部方法：执行 aliyun CLI 命令
  Future<Map<String, dynamic>> _runCliCommand(List<String> args) async {
    try {
      print('[CLI] 执行: aliyun ${args.join(' ')}');

      final result = await Process.run('aliyun', args);

      if (result.exitCode != 0) {
        final stderr = result.stderr.toString();
        print('[CLI] 错误输出: $stderr');
        throw Exception('CLI 执行失败: $stderr');
      }

      final jsonStr = result.stdout.toString().trim();
      if (jsonStr.isEmpty) {
        throw Exception('CLI 返回空响应');
      }

      print('[CLI] 响应长度: ${jsonStr.length} 字节');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (json['Success'] != true) {
        final message = json['Message'] as String?;
        final code = json['Code'] as String?;
        final errorMsg = message ?? code ?? 'Unknown Error';
        print('[CLI] API 错误 - Code: $code, Message: $message');
        throw Exception('API 查询失败: $errorMsg');
      }

      return json;
    } catch (e) {
      print('[CLI] 错误: $e');
      rethrow;
    }
  }

  /// 构建组合筛选条件（支持 AND/OR 逻辑）
  ///
  /// 示例：
  /// ```dart
  /// buildCompositeFilter('and', [
  ///   {'Key': 'appVersion', 'Operator': 'in', 'Values': ['3.5.0', '3.5.1']},
  ///   {'Key': 'brand', 'Operator': '=', 'Values': ['Apple']},
  /// ])
  /// ```
  static Map<String, dynamic> buildCompositeFilter(
    String operator,
    List<Map<String, dynamic>> filters,
  ) {
    return {
      'Key': '',
      'Operator': operator,
      'Values': [],
      'SubFilters': filters,
    };
  }

  /// 构建简单筛选条件
  ///
  /// 示例：
  /// ```dart
  /// buildSimpleFilter('appVersion', '=', ['3.5.0'])
  /// ```
  static Map<String, dynamic> buildSimpleFilter(
    String key,
    String operator,
    List<String> values,
  ) {
    return {
      'Key': key,
      'Operator': operator,
      'Values': values,
    };
  }

  /// 构建基础参数
  List<String> _buildBaseArgs(String command, {
    required String bizModule,
    String? os,
  }) {
    // 验证必需的配置
    final appKey = _config.appKey.trim();
    final region = _config.region.trim();

    print('[CLI] 配置检查 - AppKey: "$appKey", Region: "$region"');

    if (appKey.isEmpty) {
      throw Exception('AppKey 未配置或为空');
    }
    if (region.isEmpty) {
      throw Exception('Region 未配置或为空');
    }

    final args = [
      'emas-appmonitor',
      command,
      '--region', region,
      '--app-key', appKey,
      '--biz-module', bizModule,
    ];

    if (os != null && os.isNotEmpty) {
      args.addAll(['--os', os]);
    }

    return args;
  }

  /// 获取问题列表
  Future<GetIssuesResult> getIssues({
    required String bizModule,
    required int startTimeMs,
    required int endTimeMs,
    String? os,
    int pageIndex = 1,
    int pageSize = 500,
    String orderBy = 'ErrorRate',
    String? orderType,
    String? name,
    int? status,
    String? firstVersion,
    String? appVersion,
  }) async {
    final args = _buildBaseArgs('get-issues', bizModule: bizModule, os: os);

    args.addAll([
      '--time-range', 'StartTime=$startTimeMs EndTime=$endTimeMs Granularity=1 GranularityUnit=DAY',
      '--page-index', pageIndex.toString(),
      '--page-size', pageSize.toString(),
      '--order-by', orderBy,
    ]);

    if (orderType != null && orderType.isNotEmpty) {
      args.addAll(['--order-type', orderType]);
    }
    if (name != null && name.isNotEmpty) {
      args.addAll(['--name', name]);
    }
    if (status != null) {
      args.addAll(['--status', status.toString()]);
    }

    // 版本筛选（FirstVersion 和 AppVersion）
    if ((firstVersion != null && firstVersion.isNotEmpty) ||
        (appVersion != null && appVersion.isNotEmpty)) {
      final filters = <Map<String, dynamic>>[];

      if (firstVersion != null && firstVersion.isNotEmpty) {
        filters.add({
          'Key': 'firstVersion',
          'Operator': '=',
          'Values': [firstVersion.trim()],
        });
        print('[CLI] FirstVersion 筛选: $firstVersion');
      }

      if (appVersion != null && appVersion.isNotEmpty) {
        filters.add({
          'Key': 'appVersion',
          'Operator': '=',
          'Values': [appVersion.trim()],
        });
        print('[CLI] AppVersion 筛选: $appVersion');
      }

      // 如果只有一个过滤条件，直接使用；如果两个都有，使用 AND 组合
      final filter = filters.length == 1
          ? filters[0]
          : {
              'Operator': 'and',
              'SubFilters': filters,
            };

      args.addAll(['--filter', jsonEncode(filter)]);
    }

    final json = await _runCliCommand(args);
    return GetIssuesResult.fromJson(json);
  }

  /// 获取单个问题详情
  ///
  /// 返回字段包括：受影响版本列表、环比增长率、完整堆栈等
  Future<Map<String, dynamic>> getIssue({
    required String bizModule,
    required String digestHash,
    required int startTimeMs,
    required int endTimeMs,
    String? os,
    Map<String, dynamic>? filter,
  }) async {
    final args = _buildBaseArgs('get-issue', bizModule: bizModule, os: os);

    args.addAll([
      '--digest-hash', digestHash,
      '--time-range', 'StartTime=$startTimeMs EndTime=$endTimeMs Granularity=1 GranularityUnit=DAY',
    ]);

    if (filter != null) {
      args.addAll(['--filter', jsonEncode(filter)]);
      print('[CLI] 应用筛选: ${filter['Key']}');
    }

    final json = await _runCliCommand(args);
    return json['Model'] ?? json;
  }

  /// 获取错误列表（样本列表）
  ///
  /// 返回样本的 ClientTime、Uuid、Did 等信息，用于后续 getError 调用
  /// 注意：time-range 只支持 StartTime + EndTime，不支持 Granularity
  Future<Map<String, dynamic>> getErrors({
    required String bizModule,
    required String digestHash,
    required int startTimeMs,
    required int endTimeMs,
    String? os,
    int pageIndex = 1,
    int pageSize = 500,
    String? orderBy,
    String? name,
    String? utdid,
    Map<String, dynamic>? filter,
  }) async {
    final args = _buildBaseArgs('get-errors', bizModule: bizModule, os: os);

    args.addAll([
      '--digest-hash', digestHash,
      '--time-range', 'StartTime=$startTimeMs EndTime=$endTimeMs',
      '--page-index', pageIndex.toString(),
      '--page-size', pageSize.toString(),
    ]);

    if (orderBy != null && orderBy.isNotEmpty) {
      args.addAll(['--order-by', orderBy]);
    }
    if (name != null && name.isNotEmpty) {
      args.addAll(['--name', name]);
    }
    if (utdid != null && utdid.isNotEmpty) {
      args.addAll(['--utdid', utdid]);
    }
    if (filter != null) {
      args.addAll(['--filter', jsonEncode(filter)]);
      print('[CLI] 样本筛选: ${filter['Key']}');
    }

    final json = await _runCliCommand(args);
    return json;
  }

  /// 获取单个错误详情（完整样本信息）
  ///
  /// 返回约 65 个字段的详细信息，包括：
  /// - 基础维度：AppVersion、DeviceModel、OsVersion 等
  /// - 异常描述：ExceptionType、ExceptionMsg、Stack 等
  /// - 业务日志：EventLog、Controllers、CustomInfo 等
  /// - 内存信息：MemInfo、FileDescriptor 等
  ///
  /// 必需参数来自 getErrors 返回的样本列表
  Future<Map<String, dynamic>> getError({
    required String bizModule,
    required String digestHash,
    required int clientTime,
    required String uuid,
    required String did,
    String? os,
    bool bizForce = false,
  }) async {
    final args = _buildBaseArgs('get-error', bizModule: bizModule, os: os);

    args.addAll([
      '--digest-hash', digestHash,
      '--client-time', clientTime.toString(),
      '--uuid', uuid,
      '--did', did,
    ]);

    if (bizForce) {
      args.addAll(['--biz-force', 'true']);
    }

    final json = await _runCliCommand(args);
    return (json['Model'] ?? json) as Map<String, dynamic>;
  }
}
