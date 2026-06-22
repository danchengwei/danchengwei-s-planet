import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/analysis_report_record.dart';

/// 分析报告本地存储（与加密工作区分离；不含密钥类字段）。
class AnalysisReportStorage {
  AnalysisReportStorage._();

  static const _fileName = 'crash-tools-analysis-reports.json';
  static const _schemaVersion = 1;

  static Future<File?> _file() async {
    if (kIsWeb) return null;
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }

  static Future<Map<String, List<AnalysisReportRecord>>> load() async {
    final f = await _file();
    if (f == null || !await f.exists()) return {};
    try {
      final text = await f.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return {};
      final by = decoded['byProject'];
      if (by is! Map) return {};
      final out = <String, List<AnalysisReportRecord>>{};
      for (final e in by.entries) {
        final key = e.key.toString();
        final raw = e.value;
        if (raw is! List) continue;
        final list = <AnalysisReportRecord>[];
        for (final item in raw) {
          if (item is Map<String, dynamic>) {
            list.add(AnalysisReportRecord.fromJson(item));
          } else if (item is Map) {
            list.add(AnalysisReportRecord.fromJson(Map<String, dynamic>.from(item)));
          }
        }
        if (list.isNotEmpty) out[key] = list;
      }
      return out;
    } catch (e, st) {
      debugPrint('AnalysisReportStorage.load: $e\n$st');
      return {};
    }
  }

  static Future<void> save(Map<String, List<AnalysisReportRecord>> byProject) async {
    final f = await _file();
    if (f == null) return;
    try {
      final map = <String, dynamic>{
        'schemaVersion': _schemaVersion,
        'byProject': <String, dynamic>{
          for (final e in byProject.entries)
            if (e.value.isNotEmpty) e.key: e.value.map((r) => r.toJson()).toList(),
        },
      };
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
    } catch (e, st) {
      debugPrint('AnalysisReportStorage.save: $e\n$st');
    }
  }
}
