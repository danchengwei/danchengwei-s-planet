import 'dart:io';
import 'dart:convert';
import '../core/baymax_report_parser.dart';

/// 报告导出器
class ReportExporter {
  /// 导出为 Markdown 格式
  static String exportAsMarkdown(BaymaxReportSummary report) {
    final sb = StringBuffer();

    sb.writeln('# Baymax 崩溃分析报告\n');
    sb.writeln('生成时间: ${DateTime.now().toString().split('.')[0]}\n');

    // 汇总统计
    sb.writeln('## 汇总统计\n');
    if (report.javaCrashPercent != null) {
      sb.writeln('- **Java Crash**: ${report.javaCrashPercent!.toStringAsFixed(1)}%');
    }
    if (report.nativeCrashPercent != null) {
      sb.writeln('- **Native Crash**: ${report.nativeCrashPercent!.toStringAsFixed(1)}%');
    }
    sb.writeln('- **总项目数**: ${report.javaCrashes.length + report.nativeCrashes.length}\n');

    // Java Crashes
    if (report.javaCrashes.isNotEmpty) {
      sb.writeln('## Java Crash 详情 (${report.javaCrashes.length})\n');
      for (int i = 0; i < report.javaCrashes.length; i++) {
        final crash = report.javaCrashes[i];
        sb.writeln('### #${i + 1} ${crash.title}\n');
        sb.writeln('| 指标 | 数值 |');
        sb.writeln('|------|------|');
        sb.writeln('| 影响设备 | ${crash.affectedDevices} |');
        sb.writeln('| 错误次数 | ${crash.errorCount} |');
        sb.writeln('| 崩溃率 | ${crash.errorRate.toStringAsFixed(2)}% |');
        sb.writeln('| 版本 | ${crash.appVersion} |\n');

        if (crash.stackTop.isNotEmpty) {
          sb.writeln('**堆栈信息（前3帧）:**\n');
          sb.writeln('```\n${crash.stackTop.join('\n')}\n```\n');
        }
      }
    }

    // Native Crashes
    if (report.nativeCrashes.isNotEmpty) {
      sb.writeln('## Native Crash 详情 (${report.nativeCrashes.length})\n');
      for (int i = 0; i < report.nativeCrashes.length; i++) {
        final crash = report.nativeCrashes[i];
        sb.writeln('### #${i + 1} ${crash.title}\n');
        sb.writeln('| 指标 | 数值 |');
        sb.writeln('|------|------|');
        sb.writeln('| 影响设备 | ${crash.affectedDevices} |');
        sb.writeln('| 错误次数 | ${crash.errorCount} |');
        sb.writeln('| 崩溃率 | ${crash.errorRate.toStringAsFixed(2)}% |');
        sb.writeln('| 版本 | ${crash.appVersion} |\n');

        if (crash.stackTop.isNotEmpty) {
          sb.writeln('**堆栈信息（前3帧）:**\n');
          sb.writeln('```\n${crash.stackTop.join('\n')}\n```\n');
        }
      }
    }

    return sb.toString();
  }

  /// 导出为 JSON 格式
  static String exportAsJson(BaymaxReportSummary report) {
    final data = {
      'generatedAt': DateTime.now().toIso8601String(),
      'summary': {
        'javaCrashPercent': report.javaCrashPercent,
        'nativeCrashPercent': report.nativeCrashPercent,
        'totalItems': report.javaCrashes.length + report.nativeCrashes.length,
      },
      'javaCrashes': report.javaCrashes
          .map((c) => {
                'digestHash': c.digestHash,
                'title': c.title,
                'affectedDevices': c.affectedDevices,
                'errorCount': c.errorCount,
                'errorRate': c.errorRate,
                'appVersion': c.appVersion,
                'stackTop': c.stackTop,
              })
          .toList(),
      'nativeCrashes': report.nativeCrashes
          .map((c) => {
                'digestHash': c.digestHash,
                'title': c.title,
                'affectedDevices': c.affectedDevices,
                'errorCount': c.errorCount,
                'errorRate': c.errorRate,
                'appVersion': c.appVersion,
                'stackTop': c.stackTop,
              })
          .toList(),
    };

    return jsonEncode(data);
  }

  /// 导出为 CSV 格式
  static String exportAsCsv(BaymaxReportSummary report) {
    final sb = StringBuffer();

    // CSV 头
    sb.writeln('Type,Index,Title,AffectedDevices,ErrorCount,ErrorRate,AppVersion,DigestHash');

    // Java Crashes
    for (int i = 0; i < report.javaCrashes.length; i++) {
      final crash = report.javaCrashes[i];
      final escapedTitle = crash.title.replaceAll('"', '""');
      sb.writeln(
          'Java,$i,"$escapedTitle",${crash.affectedDevices},${crash.errorCount},${crash.errorRate.toStringAsFixed(2)}%,${crash.appVersion},${crash.digestHash}');
    }

    // Native Crashes
    for (int i = 0; i < report.nativeCrashes.length; i++) {
      final crash = report.nativeCrashes[i];
      final escapedTitle = crash.title.replaceAll('"', '""');
      sb.writeln(
          'Native,$i,"$escapedTitle",${crash.affectedDevices},${crash.errorCount},${crash.errorRate.toStringAsFixed(2)}%,${crash.appVersion},${crash.digestHash}');
    }

    return sb.toString();
  }

  /// 保存导出文件
  static Future<String> saveExportFile({
    required String content,
    required String format, // 'md', 'json', 'csv'
    required String baseFileName,
  }) async {
    try {
      final ext = _getExtension(format);
      final fileName = '${baseFileName}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      // 使用系统临时目录或下载目录
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/$fileName');

      await file.writeAsString(content);
      return file.path;
    } catch (e) {
      throw Exception('保存导出文件失败: $e');
    }
  }

  static String _getExtension(String format) {
    switch (format.toLowerCase()) {
      case 'md':
      case 'markdown':
        return 'md';
      case 'json':
        return 'json';
      case 'csv':
        return 'csv';
      default:
        return 'txt';
    }
  }
}
