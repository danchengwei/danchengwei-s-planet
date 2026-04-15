import 'dart:convert';

import 'package:http/http.dart' as http;

import '../services/http_retry_policy.dart';
import 'acs4_signer.dart';
import 'form_flatten.dart';

const _productId = 'emas-appmonitor';
const _apiVersion = '2019-06-11';

/// EMAS AppMonitor **OpenAPI**（`GetIssues` / `GetIssue`）：HTTPS + form + ACS4 签名。
///
/// [httpClient] 须由 `newOutboundHttpClient`（`outbound_http_client_for_config.dart`）创建，
/// 与 `tool/emas_openapi_probe.dart` 行为一致。
///
/// 与 **Android 端 SDK 上报接口** 不同：App 内自定义异常、日志、自定义维度（如
/// `ApmCrashAnalysis.recordException`、`setCustomKey` 等）见官方文档
/// [崩溃分析相关接口（Android SDK）](https://help.aliyun.com/zh/document_detail/2880532.html)。
/// 本类仅负责在服务端用 AK 拉取已上报的聚合数据。
class EmasAppMonitorClient {
  EmasAppMonitorClient({
    required this.accessKeyId,
    required this.accessKeySecret,
    required this.regionId,
    required http.Client httpClient,
  }) : _http = httpClient;

  final String accessKeyId;
  final String accessKeySecret;
  final String regionId;
  final http.Client _http;

  String get _host => 'emas-appmonitor.$regionId.aliyuncs.com';

  Uri get _baseUri => Uri.https(_host, '/');

  /// 业务上可退避重试的 EMAS 错误（限流、服务端忙等）；参数/权限类返回 false。
  static bool isRetriableEmasError(EmasApiException e) {
    final sc = e.statusCode;
    if (sc != null && HttpRetryPolicy.isRetriableHttpStatus(sc)) return true;
    final c = e.code?.toLowerCase() ?? '';
    if (c.contains('throttl')) return true;
    if (c == 'serviceunavailable' ||
        c == 'internalerror' ||
        c == 'internal.error' ||
        c.contains('unavailable') && c.contains('service')) {
      return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> _call(String action, Map<String, dynamic> bodyMap) async {
    return HttpRetryPolicy.run(
      () => _callOnce(action, bodyMap),
      isRetryable: (e) {
        if (HttpRetryPolicy.defaultIsRetryable(e)) return true;
        if (e is EmasApiException) return isRetriableEmasError(e);
        return false;
      },
    );
  }

  Future<Map<String, dynamic>> _callOnce(String action, Map<String, dynamic> bodyMap) async {
    final flat = <String, String>{};
    flattenToStringMap(flat, bodyMap);
    final form = toFormString(flat);

    final headers = Acs4Signer.buildAuthorizedHeaders(
      host: _host,
      method: 'POST',
      pathname: '/',
      action: action,
      version: _apiVersion,
      accessKeyId: accessKeyId,
      accessKeySecret: accessKeySecret,
      formBody: form,
      productId: _productId,
    );

    final res = await _http.post(_baseUri, headers: headers, body: form);
    if (HttpRetryPolicy.isRetriableHttpStatus(res.statusCode)) {
      throw TransientHttpStatusException(res.statusCode);
    }
    final text = utf8.decode(res.bodyBytes);
    Map<String, dynamic> json;
    try {
      json = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw EmasApiException('响应非 JSON：HTTP ${res.statusCode}');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw EmasApiException._fromJson(json, res.statusCode);
    }
    final success = json['Success'];
    if (success == false) {
      throw EmasApiException._fromJson(json, res.statusCode);
    }
    return json;
  }

  /// 启动分析：将界面选项转为 GetIssues / GetIssue 附加字段。
  /// 阿里云不同租户或版本可能使用不同参数名/枚举值；若接口报错或筛选项无效，
  /// 请以控制台实际请求或 OpenAPI 文档为准，调整 [startupLaunchKindToExtra] 内的键值。
  static Map<String, dynamic>? startupLaunchKindToExtra(String kind) {
    switch (kind) {
      case 'cold':
        // 若接口要求英文枚举，可改为 'COLD' / 'cold_start' 等，以 OpenAPI 为准。
        return const {'LaunchType': '冷启动'};
      case 'hot':
        return const {'LaunchType': '热启动'};
      default:
        return null;
    }
  }

  /// 聚合问题列表
  Future<GetIssuesResult> getIssues({
    required int appKey,
    required String bizModule,
    required String os,
    required int startTimeMs,
    required int endTimeMs,
    int pageIndex = 1,
    int pageSize = 20,
    String orderBy = 'instances',
    String orderType = 'desc',
    String? name,
    Map<String, dynamic>? extraBody,
  }) async {
    final body = <String, dynamic>{
      'AppKey': appKey,
      'BizModule': bizModule,
      'Os': os,
      'PageIndex': pageIndex,
      'PageSize': pageSize,
      'OrderBy': orderBy,
      'OrderType': orderType,
      'TimeRange': {
        'StartTime': startTimeMs,
        'EndTime': endTimeMs,
      },
    };
    if (name != null && name.isNotEmpty) {
      body['Name'] = name;
    }
    if (extraBody != null && extraBody.isNotEmpty) {
      body.addAll(extraBody);
    }
    final json = await _call('GetIssues', body);
    return GetIssuesResult.fromJson(json);
  }

  /// 单条聚合详情（需列表项中的 DigestHash）
  Future<Map<String, dynamic>> getIssue({
    required int appKey,
    required String bizModule,
    required String os,
    required String digestHash,
    required int startTimeMs,
    required int endTimeMs,
    Map<String, dynamic>? extraBody,
  }) async {
    final body = <String, dynamic>{
      'AppKey': appKey,
      'BizModule': bizModule,
      'Os': os,
      'DigestHash': digestHash,
      'TimeRange': {
        'StartTime': startTimeMs,
        'EndTime': endTimeMs,
      },
    };
    if (extraBody != null && extraBody.isNotEmpty) {
      body.addAll(extraBody);
    }
    return _call('GetIssue', body);
  }

  void close() => _http.close();
}

class EmasApiException implements Exception {
  EmasApiException(this.message, {this.code, this.requestId, this.statusCode});

  factory EmasApiException._fromJson(Map<String, dynamic> json, int status) {
    final code = json['Code']?.toString() ?? json['code']?.toString();
    final msg = json['Message']?.toString() ??
        json['message']?.toString() ??
        json['Message']?.toString() ??
        json.toString();
    final rid = json['RequestId']?.toString() ?? json['requestId']?.toString();
    return EmasApiException(msg, code: code, requestId: rid, statusCode: status);
  }

  final String message;
  final String? code;
  final String? requestId;
  final int? statusCode;

  @override
  String toString() =>
      'EmasApiException($code, $message${requestId != null ? ', RequestId=$requestId' : ''})';
}

class GetIssuesResult {
  GetIssuesResult({this.items = const [], this.total = 0, this.pageNum, this.pageSize, this.pages});

  factory GetIssuesResult.fromJson(Map<String, dynamic> json) {
    final model = json['Model'];
    if (model is! Map<String, dynamic>) {
      return GetIssuesResult();
    }
    final rawItems = model['Items'];
    final items = <IssueListItem>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map<String, dynamic>) {
          items.add(IssueListItem.fromJson(e));
        } else if (e is Map) {
          items.add(IssueListItem.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return GetIssuesResult(
      items: items,
      total: (model['Total'] as num?)?.toInt() ?? 0,
      pageNum: (model['PageNum'] as num?)?.toInt(),
      pageSize: (model['PageSize'] as num?)?.toInt(),
      pages: (model['Pages'] as num?)?.toInt(),
    );
  }

  final List<IssueListItem> items;
  final int total;
  final int? pageNum;
  final int? pageSize;
  final int? pages;
}

class IssueListItem {
  IssueListItem({
    this.digestHash,
    this.errorName,
    this.stack,
    this.errorCount,
    this.errorDeviceCount,
    this.eventTime,
    this.errorType,
  });

  factory IssueListItem.fromJson(Map<String, dynamic> j) {
    return IssueListItem(
      digestHash: j['DigestHash']?.toString(),
      errorName: j['ErrorName']?.toString(),
      stack: j['Stack']?.toString(),
      errorCount: (j['ErrorCount'] as num?)?.toInt(),
      errorDeviceCount: (j['ErrorDeviceCount'] as num?)?.toInt(),
      eventTime: j['EventTime']?.toString(),
      errorType: j['ErrorType']?.toString(),
    );
  }

  final String? digestHash;
  final String? errorName;
  final String? stack;
  final int? errorCount;
  final int? errorDeviceCount;
  final String? eventTime;
  final String? errorType;
}
