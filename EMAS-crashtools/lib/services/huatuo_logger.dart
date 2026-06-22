import 'package:http/http.dart' as http;
import 'dart:convert';

/// 华佗日志条目
class HuatuoLogEntry {
  HuatuoLogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.source,
    this.stack,
  });

  final DateTime timestamp;
  final String level;
  final String message;
  final String? source;
  final String? stack;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'level': level,
        'message': message,
        'source': source,
        'stack': stack,
      };
}

/// 华佗日志查询器
/// API: http://basiclog.xesv5.com/query
/// 参数：user（用户ID）、dae（应用标识）、start/end（时间范围）、keyword（关键字）
class HuatuoLogger {
  HuatuoLogger({
    required this.user,
    required this.dae,
    this.baseUrl = 'http://basiclog.xesv5.com',
    this.httpClient,
  });

  final String user;              // 用户 ID（需从配置获取）
  final String dae;               // 应用标识
  final String baseUrl;           // 基础 URL
  final http.Client? httpClient;

  static const String _apiPath = '/query';
  static const Duration _defaultTimeRange = Duration(hours: 24);

  /// 查询日志
  /// startTime / endTime：可选，默认查询最近 24 小时
  /// keyword：搜索关键词，可选
  /// limit：返回最多条数，默认 1000
  Future<List<HuatuoLogEntry>> queryLogs({
    DateTime? startTime,
    DateTime? endTime,
    String? keyword,
    int limit = 1000,
  }) async {
    try {
      startTime ??= DateTime.now().subtract(_defaultTimeRange);
      endTime ??= DateTime.now();

      final client = httpClient ?? http.Client();
      final queryParams = {
        'user': user,
        'dae': dae,
        'start': startTime.toUtc().toIso8601String(),
        'end': endTime.toUtc().toIso8601String(),
        'limit': limit.toString(),
      };

      if (keyword != null && keyword.isNotEmpty) {
        queryParams['keyword'] = keyword;
      }

      final uri = Uri.parse(baseUrl + _apiPath).replace(queryParameters: queryParams);
      final response = await client.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return _parseResponse(response.body);
      } else {
        throw Exception('华佗 API 返回 ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('查询华佗日志失败: $e');
    }
  }

  /// 根据崩溃时间查询相关日志
  Future<List<HuatuoLogEntry>> queryByIssue({
    required DateTime crashTime,
    String? exceptionName,
    Duration timeWindow = const Duration(minutes: 5),
  }) async {
    final startTime = crashTime.subtract(timeWindow);
    final endTime = crashTime.add(timeWindow);

    return queryLogs(
      startTime: startTime,
      endTime: endTime,
      keyword: exceptionName,
    );
  }

  /// 查询错误日志（ERROR 级别）
  Future<List<HuatuoLogEntry>> queryErrorLogs({
    DateTime? startTime,
    DateTime? endTime,
    int limit = 500,
  }) async {
    final logs = await queryLogs(
      startTime: startTime,
      endTime: endTime,
      limit: limit,
    );

    return logs.where((log) => log.level.toUpperCase() == 'ERROR').toList();
  }

  /// 查询异常日志（Exception 相关）
  Future<List<HuatuoLogEntry>> queryExceptionLogs({
    DateTime? startTime,
    DateTime? endTime,
    String? exceptionType,
    int limit = 500,
  }) async {
    return queryLogs(
      startTime: startTime,
      endTime: endTime,
      keyword: exceptionType ?? 'Exception',
      limit: limit,
    );
  }

  /// 解析华佗 API 响应
  List<HuatuoLogEntry> _parseResponse(String jsonString) {
    try {
      final json = jsonDecode(jsonString);
      final logs = <HuatuoLogEntry>[];

      // 假设响应格式为 { "data": [...] } 或 { "logs": [...] }
      List<dynamic> items = [];

      if (json is Map) {
        if (json['data'] is List) {
          items = json['data'] as List;
        } else if (json['logs'] is List) {
          items = json['logs'] as List;
        } else if (json['items'] is List) {
          items = json['items'] as List;
        }
      } else if (json is List) {
        items = json;
      }

      for (final item in items) {
        if (item is Map<String, dynamic>) {
          try {
            logs.add(_parseLogEntry(item));
          } catch (e) {
            // 跳过解析失败的条目
          }
        }
      }

      return logs;
    } catch (e) {
      throw Exception('解析华佗日志失败: $e');
    }
  }

  /// 解析单条日志
  HuatuoLogEntry _parseLogEntry(Map<String, dynamic> data) {
    // 解析时间戳
    DateTime timestamp;
    final tsValue = data['timestamp'] ?? data['time'] ?? data['ts'] ?? data['createdAt'];

    if (tsValue is String) {
      timestamp = DateTime.parse(tsValue);
    } else if (tsValue is int) {
      // Unix 时间戳（毫秒或秒）
      timestamp = DateTime.fromMillisecondsSinceEpoch(
        tsValue > 10000000000 ? tsValue : tsValue * 1000,
      );
    } else {
      timestamp = DateTime.now();
    }

    return HuatuoLogEntry(
      timestamp: timestamp,
      level: data['level']?.toString().toUpperCase() ?? 'INFO',
      message: data['message']?.toString() ?? data['msg']?.toString() ?? '',
      source: data['source']?.toString() ?? data['logger']?.toString(),
      stack: data['stack']?.toString() ?? data['stackTrace']?.toString(),
    );
  }

  /// 获取日志统计（按级别分类）
  Future<Map<String, int>> getLogStats({
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final logs = await queryLogs(startTime: startTime, endTime: endTime, limit: 10000);

    final stats = <String, int>{};
    for (final log in logs) {
      final level = log.level.toUpperCase();
      stats[level] = (stats[level] ?? 0) + 1;
    }

    return stats;
  }
}

/// 华佗日志管理器 - 缓存和聚合多次查询
class HuatuoLogManager {
  HuatuoLogManager({required this.logger});

  final HuatuoLogger logger;
  final _cache = <String, List<HuatuoLogEntry>>{};

  /// 生成缓存 key
  String _cacheKey(DateTime start, DateTime end, String? keyword) {
    return '${start.toIso8601String()}_${end.toIso8601String()}_${keyword ?? ""}';
  }

  /// 查询日志（带缓存）
  Future<List<HuatuoLogEntry>> query({
    DateTime? startTime,
    DateTime? endTime,
    String? keyword,
    bool useCache = true,
  }) async {
    startTime ??= DateTime.now().subtract(const Duration(hours: 24));
    endTime ??= DateTime.now();

    final key = _cacheKey(startTime, endTime, keyword);

    if (useCache && _cache.containsKey(key)) {
      return _cache[key]!;
    }

    final logs = await logger.queryLogs(
      startTime: startTime,
      endTime: endTime,
      keyword: keyword,
    );

    _cache[key] = logs;
    return logs;
  }

  /// 清空缓存
  void clearCache() {
    _cache.clear();
  }

  /// 根据崩溃信息自动查询相关日志
  Future<Map<String, dynamic>> analyzeIssue({
    required DateTime crashTime,
    required String? exceptionName,
    Duration timeWindow = const Duration(minutes: 5),
  }) async {
    final logs = await logger.queryByIssue(
      crashTime: crashTime,
      exceptionName: exceptionName,
      timeWindow: timeWindow,
    );

    return {
      'totalLogs': logs.length,
      'errorLogs': logs.where((l) => l.level.toUpperCase() == 'ERROR').length,
      'warningLogs': logs.where((l) => l.level.toUpperCase() == 'WARN').length,
      'logs': logs,
      'relatedMessages': _extractRelatedMessages(logs, exceptionName),
    };
  }

  /// 提取相关日志信息
  List<String> _extractRelatedMessages(List<HuatuoLogEntry> logs, String? keyword) {
    final messages = <String>[];

    for (final log in logs) {
      if (keyword == null || log.message.contains(keyword)) {
        messages.add('[${log.timestamp}] ${log.level}: ${log.message}');
      }
    }

    return messages;
  }
}
