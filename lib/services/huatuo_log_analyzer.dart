import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// 华佗日志分析服务
class HuatuoLogAnalyzer {
  /// 分析日志内容，提取关键信息
  Future<Map<String, dynamic>> analyzeLogContent(
    List<String> filePaths,
    String crashStackInfo,
    String crashType,
  ) async {
    final analysis = <String, dynamic>{
      'total_lines': 0,
      'total_events': 0,
      'page_history': <Map<String, dynamic>>[],
      'http_requests': <Map<String, dynamic>>[],
      'error_events': <Map<String, dynamic>>[],
      'warning_events': <Map<String, dynamic>>[],
      'stack_matches': <Map<String, dynamic>>[],
      'time_range': {'start': null, 'end': null},
      'device_info': <String, dynamic>{},
      'app_version': null,
    };

    // 从堆栈提取关键词
    final keywords = extractStackKeywords(crashStackInfo, crashType);
    analysis['search_keywords'] = keywords.toList().take(10).toList();

    // 分析每个日志文件
    for (final filePath in filePaths) {
      try {
        final file = File(filePath);
        if (!await file.exists()) continue;

        final lines = await file.readAsLines();
        for (final line in lines) {
          analysis['total_lines'] = (analysis['total_lines'] as int) + 1;
          final events = parseLogLine(line);

          for (final evt in events) {
            if (evt is! Map<String, dynamic>) continue;
            analysis['total_events'] = (analysis['total_events'] as int) + 1;

            // 提取设备信息（只取一次）
            if (analysis['app_version'] == null && evt.containsKey('version')) {
              analysis['app_version'] = evt['version'];
              final deviceInfo = analysis['device_info'] as Map<String, dynamic>;
              deviceInfo['device_name'] = evt['devicename'] ?? '';
              deviceInfo['system_version'] = evt['systemVersion'] ?? '';
            }

            // 时间范围
            if (evt.containsKey('date')) {
              final timeRange = analysis['time_range'] as Map<String, dynamic>;
              if (timeRange['start'] == null) {
                timeRange['start'] = evt['date'];
              }
              timeRange['end'] = evt['date'];
            }

            // pageid 切换
            if (evt.containsKey('pageid')) {
              final pageHistory = analysis['page_history'] as List<Map<String, dynamic>>;
              if (pageHistory.isEmpty || pageHistory.last['page'] != evt['pageid']) {
                pageHistory.add({
                  'page': evt['pageid'],
                  'eventid': evt['eventid'] ?? '',
                  'date': evt['date'] ?? '',
                  'time': evt['clits'] ?? '',
                  'logtype': evt['logtype'] ?? '',
                });
              }
            }

            // HTTP 请求
            final eid = evt['eventid']?.toString() ?? '';
            final logtype = evt['logtype']?.toString() ?? '';
            if (eid.toLowerCase().contains('http') || logtype.toLowerCase().contains('http')) {
              (analysis['http_requests'] as List<Map<String, dynamic>>).add({
                'eventid': eid,
                'logtype': logtype,
                'url': evt['url'] ?? '',
                'date': evt['date'] ?? '',
                'message': evt['message'] ?? evt['msg'] ?? '',
              });
            }

            // 错误事件
            final evtStr = jsonEncode(evt);
            if (evtStr.toLowerCase().contains('error') ||
                evtStr.toLowerCase().contains('fail') ||
                evtStr.toLowerCase().contains('exception')) {
              (analysis['error_events'] as List<Map<String, dynamic>>).add({
                'eventid': eid,
                'logtype': logtype,
                'message': evt['message'] ?? evt['msg'] ?? evt['attachment'] ?? '',
                'date': evt['date'] ?? '',
                'tag': evt['tag'] ?? '',
                'pageid': evt['pageid'] ?? '',
                'xes_level': evt['xes_level'] ?? '',
              });
            }

            // 警告事件
            if (evtStr.toLowerCase().contains('warn') ||
                evt['xes_level'] == 'xes_warn' ||
                evt['xes_level'] == 'xes_error') {
              (analysis['warning_events'] as List<Map<String, dynamic>>).add({
                'eventid': eid,
                'logtype': logtype,
                'message': evt['message'] ?? evt['msg'] ?? evt['attachment'] ?? '',
                'date': evt['date'] ?? '',
                'pageid': evt['pageid'] ?? '',
                'xes_level': evt['xes_level'] ?? '',
              });
            }

            // 堆栈关键词匹配
            for (final kw in keywords) {
              if (kw.isEmpty || kw.length <= 3) continue;
              if (evtStr.contains(kw)) {
                (analysis['stack_matches'] as List<Map<String, dynamic>>).add({
                  'keyword': kw,
                  'eventid': eid,
                  'logtype': logtype,
                  'pageid': evt['pageid'] ?? '',
                  'message': evt['message'] ?? evt['msg'] ?? evt['attachment'] ?? '',
                  'date': evt['date'] ?? '',
                });
              }
            }
          }
        }
      } catch (e) {
        debugPrint('日志解析错误: $e');
      }
    }

    // 去重并限制数量
    final pageHistory = analysis['page_history'] as List<Map<String, dynamic>>;
    final httpRequests = analysis['http_requests'] as List<Map<String, dynamic>>;
    final errorEvents = analysis['error_events'] as List<Map<String, dynamic>>;
    final warningEvents = analysis['warning_events'] as List<Map<String, dynamic>>;
    final stackMatches = analysis['stack_matches'] as List<Map<String, dynamic>>;

    // 保留最后 N 个
    if (pageHistory.length > 15) {
      analysis['page_history'] = pageHistory.sublist(pageHistory.length - 15);
    }
    if (httpRequests.length > 10) {
      analysis['http_requests'] = httpRequests.sublist(httpRequests.length - 10);
    }
    if (errorEvents.length > 15) {
      analysis['error_events'] = errorEvents.sublist(errorEvents.length - 15);
    }
    if (warningEvents.length > 15) {
      analysis['warning_events'] = warningEvents.sublist(warningEvents.length - 15);
    }
    if (stackMatches.length > 20) {
      analysis['stack_matches'] = stackMatches.sublist(stackMatches.length - 20);
    }

    return analysis;
  }

  /// 解析单行日志 JSON
  List<Map<String, dynamic>> parseLogLine(String line) {
    if (line.trim().isEmpty) return [];

    final results = <Map<String, dynamic>>[];
    try {
      // 尝试提取 s_l0, s_l1 等子日志
      for (int i = 0; i <= 3; i++) {
        final key = 's_l$i';
        final pattern = RegExp('"$key"\\s*:\\s*"(\\{.*?\\})"');
        final matches = pattern.allMatches(line);

        for (final m in matches) {
          final innerStr = m.group(1)!;
          try {
            final innerData = jsonDecode(innerStr) as Map<String, dynamic>;
            results.add(innerData);
          } catch (e) {
            // 简化：提取关键字段
            final dataDict = <String, dynamic>{};
            const fields = [
              'eventid',
              'pageid',
              'logtype',
              'message',
              'msg',
              'url',
              'eventtype',
              'tag',
              'xes_level',
              'attachment',
              'date',
              'devicename',
              'version',
              'systemVersion',
              'usinglogindex'
            ];

            for (final field in fields) {
              final pattern = '"$field"\\s*:\\s*"([^"]*?)"';
              final fm = RegExp(pattern).firstMatch(innerStr);
              if (fm != null) {
                dataDict[field] = fm.group(1)!;
              }
            }

            const numFields = ['clits', 'logindex'];
            for (final field in numFields) {
              final pattern = '"$field"\\s*:\\s*(\\d+)';
              final fm = RegExp(pattern).firstMatch(innerStr);
              if (fm != null) {
                dataDict[field] = fm.group(1)!;
              }
            }

            if (dataDict.isNotEmpty) {
              results.add(dataDict);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('日志行解析异常: $e');
    }

    return results;
  }

  /// 从堆栈信息提取关键词
  Set<String> extractStackKeywords(String stackInfo, String crashType) {
    final keywords = <String>{};

    if (stackInfo.isNotEmpty) {
      // 提取标识符
      final pattern = RegExp(r'[\w.]+');
      for (final m in pattern.allMatches(stackInfo)) {
        final kw = m.group(0)!;
        if (kw.length > 5 && (kw.contains('.') || kw[0].toUpperCase() == kw[0])) {
          keywords.add(kw);
        }
      }

      // 提取类名
      final classPattern = RegExp(r'at\s+([\w.]+)\(');
      for (final m in classPattern.allMatches(stackInfo)) {
        keywords.add(m.group(1)!);
      }

      // 提取异常类型
      final exceptionPattern = RegExp(r'(\w+Exception|\w+Error)');
      for (final m in exceptionPattern.allMatches(stackInfo)) {
        keywords.add(m.group(1)!);
      }
    }

    // Native 崩溃特定关键词
    if (crashType.toLowerCase() == 'native') {
      keywords.addAll(['libart', 'libhwui', 'libc', 'SIGSEGV', 'SIGABRT', 'Fatal signal', 'native']);
    }

    // 简化关键词 - 只保留最有意义的
    final meaningful = <String>{};
    for (final kw in keywords) {
      final lowKw = kw.toLowerCase();
      if (lowKw.contains('activity') ||
          lowKw.contains('fragment') ||
          lowKw.contains('view') ||
          lowKw.contains('container') ||
          lowKw.contains('exception') ||
          lowKw.contains('error') ||
          lowKw.contains('crash') ||
          lowKw.contains('nullpointer') ||
          lowKw.contains('libart') ||
          lowKw.contains('libhwui') ||
          lowKw.contains('libc') ||
          lowKw.contains('surface') ||
          lowKw.contains('native') ||
          lowKw.contains('viewmodel') ||
          lowKw.contains('init')) {
        meaningful.add(kw);
      }
    }

    // 添加堆栈中的长标识符
    if (stackInfo.isNotEmpty) {
      for (final part in stackInfo.split(RegExp(r'\s'))) {
        if (part.length > 5 && (part.contains('.') || part[0].toUpperCase() == part[0])) {
          meaningful.add(part.replaceAll(RegExp(r'[():\[\]]'), ''));
        }
      }
    }

    return meaningful;
  }
}
