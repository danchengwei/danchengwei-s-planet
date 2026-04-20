import 'dart:convert';

import 'package:http/http.dart' as http;

import '../services/http_retry_policy.dart';
import 'acs4_signer.dart';
import 'form_flatten.dart';

/// RPC 产品标识；与控制台 **应用监控**（移动监控 / AppMonitor）一致，**不是** EMAS 下其它子产品（如移动测试、热修复等）。
const _productId = 'emas-appmonitor';
const _apiVersion = '2019-06-11';

/// EMAS AppMonitor 支持的业务模块类型
/// 
/// 根据官方文档：https://api.aliyun.com/api/emas-appmonitor/2019-06-11/GetIssues
abstract class EmasBizModule {
  /// 崩溃分析（Crash）
  static const String crash = 'crash';
  
  /// ANR（Application Not Responding）
  static const String anr = 'anr';
  
  /// 启动性能（Startup）
  static const String startup = 'startup';
  
  /// 自定义异常（Exception）
  static const String exception = 'exception';
  
  /// H5 白屏（H5 White Screen）
  static const String h5WhiteScreen = 'h5WhiteScreen';
  
  /// 卡顿（Lag）
  static const String lag = 'lag';
  
  /// H5 JS 错误
  static const String h5JsError = 'h5JsError';
  
  /// 自定义监控（Custom）
  static const String custom = 'custom';
}

/// OS 平台类型
/// 
/// 当前项目固定使用 Android，但 API 支持多种平台
abstract class EmasOsType {
  /// Android 平台（当前项目默认）
  static const String android = 'android';
  
  /// iOS 平台
  static const String iphoneos = 'iphoneos';
  
  /// HarmonyOS 平台
  static const String harmony = 'harmony';
  
  /// H5/Web 平台
  static const String h5 = 'h5';
}

/// 阿里云 **应用监控** OpenAPI（`GetIssues` / `GetIssue`）：HTTPS + form + ACS4 签名。
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

  /// 测试 API 调用（用于调试）
  Future<Map<String, dynamic>> testCall(String action, Map<String, dynamic> bodyMap) {
    return _call(action, bodyMap);
  }

  Future<Map<String, dynamic>> _callOnce(String action, Map<String, dynamic> bodyMap) async {
    // 始终使用扁平化 form 格式（与控制台实际请求一致）
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

  /// 构造 GetErrors 请求体（OpenAPI 标准参数格式）
  /// 
  /// 根据官方文档：https://api.aliyun.com/api/emas-appmonitor/2019-06-11/GetErrors
  /// 
  /// **必填参数：**
  /// - AppKey: 项目 AppKey（整数类型）
  /// - BizModule: 业务模块类型（同 GetIssues，如 crash/anr/startup 等）
  /// - Os: OS 平台类型（android/iphoneos/harmony/h5），**当前项目固定使用 android**
  /// - TimeRange.StartTime: 开始时间（毫秒时间戳）
  /// - TimeRange.EndTime: 结束时间（毫秒时间戳）
  ///   - 注意：GetErrors 的 TimeRange **只包含 StartTime 和 EndTime 两个字段**，不包含 Granularity
  /// - PageIndex: 页号（从 1 开始，**必填**）
  /// - PageSize: 每页数量（建议 1-100，**必填**）
  /// 
  /// **可选参数：**
  /// - Utdid: 设备唯一标识符
  /// - DigestHash: 聚合错误的摘要哈希（从 GetIssues 或 GetIssue 获取）
  ///   - 用于指定查询哪个聚合错误下的实例列表
  /// - ExtraBody: 额外的自定义参数
  static Map<String, dynamic> buildGetErrorsBody({
    required int appKey,
    required String bizModule,
    required String os,
    required int startTimeMs,
    required int endTimeMs,
    required int pageIndex,
    required int pageSize,
    String? utdid,
    String? digestHash,
    Map<String, dynamic>? extraBody,
  }) {
    final body = <String, dynamic>{
      'AppKey': appKey,
      'BizModule': bizModule,
      'Os': os.toLowerCase(),
      'PageIndex': pageIndex,
      'PageSize': pageSize,
      'TimeRange': {
        'StartTime': startTimeMs,
        'EndTime': endTimeMs,
      },
    };
    
    if (utdid != null && utdid.isNotEmpty) {
      body['Utdid'] = utdid;
    }
    
    if (digestHash != null && digestHash.isNotEmpty) {
      body['DigestHash'] = digestHash;
    }
    
    if (extraBody != null && extraBody.isNotEmpty) {
      body.addAll(extraBody);
    }
    return body;
  }

  /// GetErrors 原始 JSON（错误列表）
  Future<Map<String, dynamic>> getErrorsRaw({
    required int appKey,
    required String bizModule,
    required String os,
    required int startTimeMs,
    required int endTimeMs,
    required int pageIndex,
    required int pageSize,
    String? utdid,
    String? digestHash,
    Map<String, dynamic>? extraBody,
  }) {
    return _call(
      'GetErrors',
      buildGetErrorsBody(
        appKey: appKey,
        bizModule: bizModule,
        startTimeMs: startTimeMs,
        endTimeMs: endTimeMs,
        pageIndex: pageIndex,
        pageSize: pageSize,
        os: os,
        utdid: utdid,
        digestHash: digestHash,
        extraBody: extraBody,
      ),
    );
  }

  /// 构造 GetIssues 请求体（OpenAPI 标准参数格式）
  /// 
  /// 根据官方文档：https://api.aliyun.com/api/emas-appmonitor/2019-06-11/GetIssues
  /// 
  /// **必填参数：**
  /// - AppKey: 项目 AppKey（整数类型）
  /// - BizModule: 业务模块类型
  ///   - crash: 崩溃分析
  ///   - anr: ANR（Application Not Responding）
  ///   - startup: 启动性能
  ///   - exception: 自定义异常
  ///   - h5WhiteScreen: H5 白屏
  ///   - lag: 卡顿
  ///   - h5JsError: H5 JS 错误
  ///   - custom: 自定义监控
  /// - TimeRange.StartTime: 开始时间（毫秒时间戳）
  /// - TimeRange.EndTime: 结束时间（毫秒时间戳）
  /// 
  /// **可选参数：**
  /// - Os: OS 平台类型（android/iphoneos/harmony/h5），**当前项目固定使用 android**
  /// - PageIndex: 页号（从 1 开始）
  /// - PageSize: 每页数量（建议 1-100）
  /// - OrderBy: 排序字段
  ///   - ErrorCount: 按错误次数排序
  ///   - ErrorDeviceCount: 按影响设备数排序
  ///   - ErrorRate: 按错误率排序
  ///   - ErrorDeviceRate: 按影响设备率排序
  /// - OrderType: 排序方式（asc/desc/1）
  /// - Name: 应用版本筛选（模糊搜索，对应控制台「应用版本」）
  /// - Status: 错误状态（1/2/3/4）
  /// - Granularity: 时间粒度值
  /// - GranularityUnit: 时间粒度单位（hour/day/minute）
  /// - PackageName: 应用包名（如 com.example.app）
  /// - ExtraBody: 额外的自定义参数
  static Map<String, dynamic> buildGetIssuesBody({
    required int appKey,
    required String bizModule,
    required int startTimeMs,
    required int endTimeMs,
    String? os,  // 可选：harmony/iphoneos/android/h5
    int? pageIndex,
    int? pageSize,
    String? orderBy,  // 可选：ErrorDeviceRate/ErrorDeviceCount/ErrorCount/ErrorRate
    String? orderType,  // 可选：1/asc/desc
    String? name,  // 可选：错误名（模糊搜索）
    int? status,  // 可选：错误状态 1/2/3/4
    int? granularity,  // 可选：粒度
    String? granularityUnit,  // 可选：hour/day/minute
    String? packageName,
    Map<String, dynamic>? extraBody,
  }) {
    final body = <String, dynamic>{
      'AppKey': appKey,
      'BizModule': bizModule,
      'TimeRange': {
        'StartTime': startTimeMs,
        'EndTime': endTimeMs,
      },
    };
    
    // TimeRange 可选参数
    if (granularity != null) {
      body['TimeRange']['Granularity'] = granularity;
    }
    if (granularityUnit != null && granularityUnit.isNotEmpty) {
      body['TimeRange']['GranularityUnit'] = granularityUnit;
    }
    
    // 可选参数
    if (os != null && os.isNotEmpty) {
      body['Os'] = os;
    }
    if (pageIndex != null) {
      body['PageIndex'] = pageIndex;
    }
    if (pageSize != null) {
      body['PageSize'] = pageSize;
    }
    if (orderBy != null && orderBy.isNotEmpty) {
      body['OrderBy'] = orderBy;
    }
    if (orderType != null && orderType.isNotEmpty) {
      body['OrderType'] = orderType;
    }
    if (name != null && name.isNotEmpty) {
      body['Name'] = name;
    }
    if (status != null) {
      body['Status'] = status;
    }
    if (packageName != null && packageName.isNotEmpty) {
      body['PackageName'] = packageName;
    }
    if (extraBody != null && extraBody.isNotEmpty) {
      body.addAll(extraBody);
    }
    return body;
  }

  /// GetIssues 原始 JSON（含 `Model`、`RequestId` 等），便于调试或未解析字段。
  Future<Map<String, dynamic>> getIssuesRaw({
    required int appKey,
    required String bizModule,
    required int startTimeMs,
    required int endTimeMs,
    String? os,
    int? pageIndex,
    int? pageSize,
    String? orderBy,
    String? orderType,
    String? name,
    int? status,
    int? granularity,
    String? granularityUnit,
    String? packageName,
    Map<String, dynamic>? extraBody,
  }) {
    return _call(
      'GetIssues',
      buildGetIssuesBody(
        appKey: appKey,
        bizModule: bizModule,
        startTimeMs: startTimeMs,
        endTimeMs: endTimeMs,
        os: os,
        pageIndex: pageIndex,
        pageSize: pageSize,
        orderBy: orderBy,
        orderType: orderType,
        name: name,
        status: status,
        granularity: granularity,
        granularityUnit: granularityUnit,
        packageName: packageName,
        extraBody: extraBody,
      ),
    );
  }

  /// 聚合问题列表（时间范围由调用方按「自然日」切片；列表侧仅提供最近/7/30 天三种口径）。
  ///
  /// [name] 一般对应控制台「应用版本」筛选（OpenAPI `Name`）。
  /// [packageName] 对应应用包名（OpenAPI `PackageName`）；若服务端报错或无效，请以阿里云文档为准改键名。
  /// [os] 可选：OS 类型（harmony/iphoneos/android/h5）
  Future<GetIssuesResult> getIssues({
    required int appKey,
    required String bizModule,
    required int startTimeMs,
    required int endTimeMs,
    String? os,
    int? pageIndex,
    int? pageSize,
    String? orderBy,
    String? orderType,
    String? name,
    int? status,
    int? granularity,
    String? granularityUnit,
    String? packageName,
    Map<String, dynamic>? extraBody,
  }) async {
    final json = await getIssuesRaw(
      appKey: appKey,
      bizModule: bizModule,
      startTimeMs: startTimeMs,
      endTimeMs: endTimeMs,
      os: os,
      pageIndex: pageIndex,
      pageSize: pageSize,
      orderBy: orderBy,
      orderType: orderType,
      name: name,
      status: status,
      granularity: granularity,
      granularityUnit: granularityUnit,
      packageName: packageName,
      extraBody: extraBody,
    );
    return GetIssuesResult.fromJson(json);
  }

  /// 单条聚合详情（需列表项中的 DigestHash）
  /// 
  /// 根据官方文档：https://api.aliyun.com/api/emas-appmonitor/2019-06-11/GetIssue
  /// 
  /// **必填参数：**
  /// - AppKey: 项目 AppKey（整数类型）
  /// - BizModule: 业务模块类型（同 GetIssues，如 crash/anr/startup 等）
  /// - Os: OS 平台类型（android/iphoneos/harmony/h5），**当前项目固定使用 android**
  /// - DigestHash: 聚合错误的摘要哈希（从 GetIssues 获取）
  /// - TimeRange.StartTime: 开始时间（毫秒时间戳）
  /// - TimeRange.EndTime: 结束时间（毫秒时间戳）
  ///   - 注意：GetIssue 的 TimeRange **包含 4 个字段**：StartTime、EndTime、Granularity、GranularityUnit
  /// 
  /// **可选参数：**
  /// - PackageName: 应用包名（如 com.example.app）
  /// - ExtraBody: 额外的自定义参数
  Future<Map<String, dynamic>> getIssue({
    required int appKey,
    required String bizModule,
    required String os,
    required String digestHash,
    required int startTimeMs,
    required int endTimeMs,
    String? packageName,
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
    if (packageName != null && packageName.isNotEmpty) {
      body['PackageName'] = packageName;
    }
    if (extraBody != null && extraBody.isNotEmpty) {
      body.addAll(extraBody);
    }
    return _call('GetIssue', body);
  }

  /// 构造 GetError 请求体（OpenAPI 标准参数格式）
  /// 
  /// 根据官方文档：https://api.aliyun.com/api/emas-appmonitor/2019-06-11/GetError
  /// 
  /// **必填参数：**
  /// - AppKey: 项目 AppKey（整数类型）
  /// - ClientTime: 客户端时间戳（毫秒），从 GetErrors 返回的实例列表中获取
  /// 
  /// **可选参数：**
  /// - Did: 设备 ID
  /// - Force: 是否强制刷新
  /// - Os: OS 平台类型（android/iphoneos/harmony/h5），**当前项目固定使用 android**
  /// - Uuid: 错误实例的唯一标识符（从 GetErrors 返回的实例列表中获取）
  /// - BizModule: 业务模块类型（同 GetIssues，如 crash/anr/startup 等）
  /// - DigestHash: 聚合错误的摘要哈希（从 GetIssues 或 GetIssue 获取）
  /// - ExtraBody: 额外的自定义参数
  static Map<String, dynamic> buildGetErrorBody({
    required int appKey,
    required int clientTime,
    String? did,
    bool? force,
    String? os,
    String? uuid,
    String? bizModule,
    String? digestHash,
    Map<String, dynamic>? extraBody,
  }) {
    final body = <String, dynamic>{
      'AppKey': appKey,
      'ClientTime': clientTime,
    };
    
    if (did != null && did.isNotEmpty) {
      body['Did'] = did;
    }
    
    if (force != null) {
      body['Force'] = force;
    }
    
    if (os != null && os.isNotEmpty) {
      body['Os'] = os;
    }
    
    if (uuid != null && uuid.isNotEmpty) {
      body['Uuid'] = uuid;
    }
    
    if (bizModule != null && bizModule.isNotEmpty) {
      body['BizModule'] = bizModule;
    }
    
    if (digestHash != null && digestHash.isNotEmpty) {
      body['DigestHash'] = digestHash;
    }
    
    if (extraBody != null && extraBody.isNotEmpty) {
      body.addAll(extraBody);
    }
    return body;
  }

  /// GetError 原始 JSON（崩溃详情）
  /// 
  /// 获取单个错误实例的完整详情，包括堆栈信息、线程信息、设备信息等
  /// 
  /// **典型调用流程：**
  /// 1. 调用 GetIssues 获取聚合错误列表，提取 DigestHash
  /// 2. 调用 GetErrors 获取错误实例列表，提取 ClientTime 和 Uuid
  /// 3. 调用 GetError 获取单个错误实例的完整详情
  /// 
  /// **参数说明：**
  /// - appKey: 项目 AppKey（必填）
  /// - clientTime: 客户端时间戳（必填），从 GetErrors 返回的实例列表中获取
  /// - did: 设备 ID（可选）
  /// - force: 是否强制刷新（可选）
  /// - os: OS 平台类型（可选），**当前项目固定使用 android**
  /// - uuid: 错误实例的唯一标识符（可选），从 GetErrors 返回的实例列表中获取
  /// - bizModule: 业务模块类型（可选），同 GetIssues
  /// - digestHash: 聚合错误的摘要哈希（可选），从 GetIssues 或 GetIssue 获取
  /// - extraBody: 额外的自定义参数（可选）
  Future<Map<String, dynamic>> getErrorRaw({
    required int appKey,
    required int clientTime,
    String? did,
    bool? force,
    String? os,
    String? uuid,
    String? bizModule,
    String? digestHash,
    Map<String, dynamic>? extraBody,
  }) {
    return _call(
      'GetError',
      buildGetErrorBody(
        appKey: appKey,
        clientTime: clientTime,
        did: did,
        force: force,
        os: os,
        uuid: uuid,
        bizModule: bizModule,
        digestHash: digestHash,
        extraBody: extraBody,
      ),
    );
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
    final rawModel = json['Model'] ?? json['model'];
    if (rawModel is! Map) {
      return GetIssuesResult();
    }
    final model = Map<String, dynamic>.from(rawModel);
    final rawItems = model['Items'] ?? model['items'];
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
    int pickInt(List<String> keys) {
      for (final k in keys) {
        final v = model[k];
        if (v is num) return v.toInt();
        if (v is String) {
          final parsed = int.tryParse(v);
          if (parsed != null) return parsed;
        }
      }
      return 0;
    }

    return GetIssuesResult(
      items: items,
      total: pickInt(const ['Total', 'total']),
      pageNum: () {
        final v = model['PageNum'] ?? model['pageNum'];
        if (v is num) return v.toInt();
        if (v is String) {
          final parsed = int.tryParse(v);
          if (parsed != null) return parsed;
        }
        return null;
      }(),
      pageSize: () {
        final v = model['PageSize'] ?? model['pageSize'];
        if (v is num) return v.toInt();
        if (v is String) {
          final parsed = int.tryParse(v);
          if (parsed != null) return parsed;
        }
        return null;
      }(),
      pages: () {
        final v = model['Pages'] ?? model['pages'];
        if (v is num) return v.toInt();
        if (v is String) {
          final parsed = int.tryParse(v);
          if (parsed != null) return parsed;
        }
        return null;
      }(),
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
    this.errorRatePercent,
    this.deviceRatePercent,
    this.firstVersion,
    this.issueStatus,
  });

  /// 将 GetIssue 顶层 JSON（含 `Model`）转为列表行；缺 `DigestHash` 时用 [digestHint]。
  factory IssueListItem.fromGetIssueResponse(
    Map<String, dynamic> json, {
    required String digestHint,
  }) {
    final model = json['Model'];
    if (model is! Map) {
      return IssueListItem(digestHash: digestHint);
    }
    final m = Map<String, dynamic>.from(model);
    if ((m['DigestHash']?.toString().trim() ?? '').isEmpty) {
      m['DigestHash'] = digestHint;
    }
    return IssueListItem.fromJson(m);
  }

  factory IssueListItem.fromJson(Map<String, dynamic> j) {
    return IssueListItem(
      digestHash: j['DigestHash']?.toString(),
      // GetIssues API 返回的是 Name 和 Type 字段
      errorName: _firstNonEmptyString(
        j['ErrorName'],
        j['Name'],  // GetIssues API 实际字段
        j['Title'],
      ),
      stack: j['Stack']?.toString(),
      errorCount: _parseOptionalInt(j['ErrorCount']),
      errorDeviceCount: _parseOptionalInt(j['ErrorDeviceCount']),
      eventTime: j['EventTime']?.toString(),
      // GetIssues API 返回的是 Type 字段
      errorType: _firstNonEmptyString(
        j['ErrorType'],
        j['Type'],  // GetIssues API 实际字段
      ),
      errorRatePercent: _parseOptionalPercent(j['ErrorRate'] ?? j['CrashRate'] ?? j['IssueCrashRate']),
      deviceRatePercent: _parseOptionalPercent(
        j['DeviceRate'] ?? j['ErrorDeviceRate'] ?? j['IssueDeviceRate'] ?? j['AffectedDeviceRate'],
      ),
      firstVersion: _firstNonEmptyString(
        j['FirstVersion'],
        j['FirstSeenVersion'],
        j['FirstAppVersion'],
        j['AppVersion'],
      ),
      issueStatus: _firstNonEmptyString(
        j['Status'],
        j['IssueStatus'],
        j['HandleStatus'],
      ),
    );
  }

  static int? _parseOptionalInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) {
      final parsed = int.tryParse(v);
      if (parsed != null) return parsed;
    }
    return null;
  }

  final String? digestHash;
  final String? errorName;
  final String? stack;
  final int? errorCount;
  final int? errorDeviceCount;
  final String? eventTime;
  final String? errorType;
  /// 接口若返回：百分比数值（如 `0.39` 表示 0.39%）或带 `%` 的字符串。
  final double? errorRatePercent;
  final double? deviceRatePercent;
  final String? firstVersion;
  final String? issueStatus;

  /// 与控制台一致：优先 [errorType] 作粗体标题，[errorName] 作补充说明。
  (String primaryTitle, String? secondaryLine) displayTitles() {
    final et = errorType?.trim();
    if (et != null && et.isNotEmpty) {
      return (et, _nonEmpty(errorName));
    }
    final n = errorName?.trim() ?? '';
    if (n.isEmpty) return ('(无标题)', null);
    final idx = n.indexOf('\n');
    if (idx > 0) {
      return (n.substring(0, idx).trim(), n.substring(idx + 1).trim());
    }
    return (n, null);
  }

  static String? _nonEmpty(String? s) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  static String? _firstNonEmptyString(dynamic a, [dynamic b, dynamic c, dynamic d]) {
    for (final x in [a, b, c, d]) {
      if (x == null) continue;
      final s = x.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static double? _parseOptionalPercent(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    if (s.endsWith('%')) {
      return double.tryParse(s.replaceAll('%', '').trim());
    }
    return double.tryParse(s);
  }
}
