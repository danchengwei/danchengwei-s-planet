import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;

/// Baymax HTML 报告中单个崩溃项（对齐 skills 中 parse_html_fast.py 的输出格式）
class BaymaxCrashItem {
  final String digestHash;
  final String title;
  final int affectedDevices;
  final int errorCount;
  final double errorRate;
  final String appVersion;
  final List<String> stackTop; // Top 3 stack frames
  final String crashType; // 'java' or 'native'

  BaymaxCrashItem({
    required this.digestHash,
    required this.title,
    required this.affectedDevices,
    required this.errorCount,
    required this.errorRate,
    required this.appVersion,
    required this.stackTop,
    required this.crashType,
  });

  Map<String, dynamic> toJson() => {
    'digest_hash': digestHash,
    'title': title,
    'affected_devices': affectedDevices,
    'error_count': errorCount,
    'error_rate': errorRate,
    'version': appVersion,
    'stack_top': stackTop,
    'type': crashType,
  };

  @override
  String toString() => 'BaymaxCrashItem($digestHash, type=$crashType, count=$errorCount)';
}

/// Baymax HTML 报告整体统计（对齐 skills 中 parse_html_fast.py 的输出格式）
class BaymaxReportSummary {
  final List<BaymaxCrashItem> javaCrashes;
  final List<BaymaxCrashItem> nativeCrashes;
  final String sourceFilePath;

  BaymaxReportSummary({
    required this.javaCrashes,
    required this.nativeCrashes,
    this.sourceFilePath = '',
  });

  int get totalCrashItems => javaCrashes.length + nativeCrashes.length;

  double get javaCrashPercent {
    final total = totalCrashItems;
    if (total == 0) return 0;
    return (javaCrashes.length / total) * 100;
  }

  double get nativeCrashPercent {
    final total = totalCrashItems;
    if (total == 0) return 0;
    return (nativeCrashes.length / total) * 100;
  }

  Map<String, dynamic> toJson() => {
    'java_crashes': javaCrashes.map((c) => c.toJson()).toList(),
    'native_crashes': nativeCrashes.map((c) => c.toJson()).toList(),
    'total': totalCrashItems,
    'java_percent': javaCrashPercent,
    'native_percent': nativeCrashPercent,
    'source_file_path': sourceFilePath,
  };

  @override
  String toString() => 'BaymaxReportSummary(java=$javaCrashPercent%, native=$nativeCrashPercent%, items=$totalCrashItems)';
}

/// Baymax HTML 报告解析器 - 使用 Dart html 包进行解析
class BaymaxReportParser {
  static Future<BaymaxReportSummary> parseFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('HTML 文件不存在: $filePath');
      }

      final htmlContent = await file.readAsString();
      final document = html_parser.parse(htmlContent);

      final javaCrashes = _parseJavaCrashes(document);
      final nativeCrashes = _parseNativeCrashes(document);

      return BaymaxReportSummary(
        javaCrashes: javaCrashes,
        nativeCrashes: nativeCrashes,
        sourceFilePath: filePath,
      );
    } catch (e) {
      throw Exception('HTML 报告解析失败: $e');
    }
  }

  /// 解析 Java 崩溃（按照 parse_html_fast.py 的逻辑）
  static List<BaymaxCrashItem> _parseJavaCrashes(html_dom.Document document) {
    return _extractCrashSection(document.outerHtml, 'java');
  }

  /// 解析 Native 崩溃（按照 parse_html_fast.py 的逻辑）
  static List<BaymaxCrashItem> _parseNativeCrashes(html_dom.Document document) {
    return _extractCrashSection(document.outerHtml, 'native');
  }

  /// 从 HTML 中提取指定类型的崩溃信息
  static List<BaymaxCrashItem> _extractCrashSection(String htmlContent, String crashType) {
    final crashes = <BaymaxCrashItem>[];

    final javaH2 = '<h2>☕ Java Crash详情</h2>';
    final nativeH2 = '<h2>⚙️ Native Crash详情</h2>';

    final javaStart = htmlContent.indexOf(javaH2);
    final nativeStart = htmlContent.indexOf(nativeH2);

    String section = '';
    if (crashType == 'java' && javaStart >= 0) {
      section = htmlContent.substring(
        javaStart,
        nativeStart >= 0 ? nativeStart : htmlContent.length,
      );
    } else if (crashType == 'native' && nativeStart >= 0) {
      section = htmlContent.substring(nativeStart);
    } else {
      return crashes;
    }

    // 正则表达式（按照 Python 脚本）
    final digestHashRegex = RegExp(r'digestId=([^&"]+)');
    final titleRegex = RegExp(r'<a[^>]*class="crash-title-link"[^>]*>(.*?)</a>', dotAll: true);
    final devicesRegex = RegExp(r'影响设备:</strong>\s*(\d+)');
    final errorsRegex = RegExp(r'错误次数:</strong>\s*(\d+)');
    final rateRegex = RegExp(r'崩溃率:</strong>\s*([\d.]+%)');
    final versionRegex = RegExp(r'版本:</strong>\s*([^<]+)');
    final stackRegex = RegExp(r'<div class=[^>]*stack-trace[^>]*>(.*?)</div>', dotAll: true);

    // 分割 crash-item
    final parts = section.split('<div class="crash-item">');

    for (int i = 1; i < parts.length; i++) {
      final item = parts[i];
      final crash = <String, dynamic>{};

      // 提取 digest hash
      final digestMatch = digestHashRegex.firstMatch(item);
      if (digestMatch != null) {
        crash['digest_hash'] = digestMatch.group(1)!;
      } else {
        continue; // 必须有 digest_hash
      }

      // 提取标题
      final titleMatch = titleRegex.firstMatch(item);
      if (titleMatch != null) {
        var title = titleMatch.group(1)!;
        title = title.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        crash['title'] = title;
      }

      // 提取影响设备数
      final devicesMatch = devicesRegex.firstMatch(item);
      if (devicesMatch != null) {
        crash['affected_devices'] = int.tryParse(devicesMatch.group(1)!) ?? 0;
      }

      // 提取错误次数
      final errorsMatch = errorsRegex.firstMatch(item);
      if (errorsMatch != null) {
        crash['error_count'] = int.tryParse(errorsMatch.group(1)!) ?? 0;
      }

      // 提取崩溃率
      final rateMatch = rateRegex.firstMatch(item);
      if (rateMatch != null) {
        crash['error_rate'] = double.tryParse(
          rateMatch.group(1)!.replaceAll('%', '').trim(),
        ) ?? 0.0;
      }

      // 提取版本
      final versionMatch = versionRegex.firstMatch(item);
      if (versionMatch != null) {
        crash['version'] = versionMatch.group(1)!.trim();
      }

      // 提取堆栈
      var stackTop = '';
      final stackMatch = stackRegex.firstMatch(item);
      if (stackMatch != null) {
        var stackRaw = stackMatch.group(1)!;
        stackRaw = stackRaw.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        final stackLines = stackRaw
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        stackTop = stackLines.take(3).join('\n');
      }

      crashes.add(BaymaxCrashItem(
        digestHash: crash['digest_hash'] as String? ?? '',
        title: crash['title'] as String? ?? '',
        affectedDevices: crash['affected_devices'] as int? ?? 0,
        errorCount: crash['error_count'] as int? ?? 0,
        errorRate: crash['error_rate'] as double? ?? 0.0,
        appVersion: crash['version'] as String? ?? 'unknown',
        stackTop: stackTop.isNotEmpty ? [stackTop] : [],
        crashType: crashType,
      ));
    }

    return crashes;
  }

  static List<BaymaxCrashItem> _parseCrashesFromJson(List<dynamic> crashes, String type) {
    return crashes.map((item) {
      final map = item as Map<String, dynamic>;

      List<String> stackTopList = [];
      final stackTop = map['stack_top'];
      if (stackTop != null) {
        if (stackTop is String) {
          stackTopList = stackTop.split('\n').where((s) => s.isNotEmpty).toList();
        } else if (stackTop is List) {
          stackTopList = List<String>.from(stackTop);
        }
      }

      double errorRate = 0.0;
      final rateValue = map['error_rate'];
      if (rateValue != null) {
        if (rateValue is num) {
          errorRate = rateValue.toDouble();
        } else if (rateValue is String) {
          final numStr = rateValue.replaceAll('%', '').trim();
          errorRate = double.tryParse(numStr) ?? 0.0;
        }
      }

      return BaymaxCrashItem(
        digestHash: map['digest_hash'] ?? 'unknown',
        title: map['title'] ?? 'Unknown',
        affectedDevices: (map['affected_devices'] as num?)?.toInt() ?? 0,
        errorCount: (map['error_count'] as num?)?.toInt() ?? 0,
        errorRate: errorRate,
        appVersion: map['version'] ?? 'unknown',
        stackTop: stackTopList,
        crashType: type,
      );
    }).toList();
  }
}
