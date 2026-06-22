import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

/// 报告存储记录
class StoredReport {
  final String id;
  final String fileName;
  final String filePath;
  final DateTime importTime;
  final int javaCrashCount;
  final int nativeCrashCount;
  final double? javaCrashPercent;
  final double? nativeCrashPercent;

  StoredReport({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.importTime,
    required this.javaCrashCount,
    required this.nativeCrashCount,
    this.javaCrashPercent,
    this.nativeCrashPercent,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'filePath': filePath,
    'importTime': importTime.toIso8601String(),
    'javaCrashCount': javaCrashCount,
    'nativeCrashCount': nativeCrashCount,
    'javaCrashPercent': javaCrashPercent,
    'nativeCrashPercent': nativeCrashPercent,
  };

  factory StoredReport.fromJson(Map<String, dynamic> json) => StoredReport(
    id: json['id'] as String,
    fileName: json['fileName'] as String,
    filePath: json['filePath'] as String,
    importTime: DateTime.parse(json['importTime'] as String),
    javaCrashCount: json['javaCrashCount'] as int,
    nativeCrashCount: json['nativeCrashCount'] as int,
    javaCrashPercent: json['javaCrashPercent'] as double?,
    nativeCrashPercent: json['nativeCrashPercent'] as double?,
  );

  @override
  String toString() => 'StoredReport($id, $fileName, java=$javaCrashCount, native=$nativeCrashCount)';
}

/// 报告存储服务
class ReportStorageService {
  static const String _storageFileName = 'reports_index.json';
  late Directory _appDocDir;
  late Directory _reportsDir;
  late File _indexFile;

  ReportStorageService();

  Future<void> initialize() async {
    _appDocDir = await getApplicationDocumentsDirectory();
    _reportsDir = Directory('${_appDocDir.path}/reports');
    _indexFile = File('${_appDocDir.path}/$_storageFileName');

    // 创建报告目录
    if (!await _reportsDir.exists()) {
      await _reportsDir.create(recursive: true);
    }
  }

  /// 保存报告记录
  Future<StoredReport> saveReport({
    required String sourceFilePath,
    required int javaCrashCount,
    required int nativeCrashCount,
    required double? javaCrashPercent,
    required double? nativeCrashPercent,
  }) async {
    try {
      final sourceFile = File(sourceFilePath);
      if (!await sourceFile.exists()) {
        throw Exception('源文件不存在: $sourceFilePath');
      }

      final fileName = sourceFile.path.split('/').last;
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final destPath = '${_reportsDir.path}/${id}_$fileName';

      // 复制文件到应用文档目录
      await sourceFile.copy(destPath);

      final report = StoredReport(
        id: id,
        fileName: fileName,
        filePath: destPath,
        importTime: DateTime.now(),
        javaCrashCount: javaCrashCount,
        nativeCrashCount: nativeCrashCount,
        javaCrashPercent: javaCrashPercent,
        nativeCrashPercent: nativeCrashPercent,
      );

      // 更新索引文件
      await _addToIndex(report);

      return report;
    } catch (e) {
      throw Exception('保存报告失败: $e');
    }
  }

  /// 加载所有报告记录
  Future<List<StoredReport>> loadAllReports() async {
    try {
      if (!await _indexFile.exists()) {
        return [];
      }

      final content = await _indexFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final reports = json['reports'] as List<dynamic>? ?? [];

      return reports
          .cast<Map<String, dynamic>>()
          .map((json) => StoredReport.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('加载报告索引失败: $e');
    }
  }

  /// 删除报告
  Future<void> deleteReport(String reportId) async {
    try {
      // 删除文件
      final reports = await loadAllReports();
      final report = reports.firstWhere((r) => r.id == reportId);

      final file = File(report.filePath);
      if (await file.exists()) {
        await file.delete();
      }

      // 更新索引
      reports.removeWhere((r) => r.id == reportId);
      await _saveIndex(reports);
    } catch (e) {
      throw Exception('删除报告失败: $e');
    }
  }

  /// 导出报告为 JSON
  Future<String> exportReportAsJson(String reportId) async {
    try {
      final reports = await loadAllReports();
      final report = reports.firstWhere((r) => r.id == reportId);
      return jsonEncode(report.toJson());
    } catch (e) {
      throw Exception('导出报告失败: $e');
    }
  }

  /// 更新索引文件
  Future<void> _addToIndex(StoredReport report) async {
    try {
      List<StoredReport> reports = [];

      if (await _indexFile.exists()) {
        final content = await _indexFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final list = json['reports'] as List<dynamic>? ?? [];
        reports = list
            .cast<Map<String, dynamic>>()
            .map((json) => StoredReport.fromJson(json))
            .toList();
      }

      reports.add(report);
      await _saveIndex(reports);
    } catch (e) {
      throw Exception('更新索引失败: $e');
    }
  }

  /// 保存索引文件
  Future<void> _saveIndex(List<StoredReport> reports) async {
    try {
      final json = {
        'version': 1,
        'lastUpdated': DateTime.now().toIso8601String(),
        'reports': reports.map((r) => r.toJson()).toList(),
      };

      await _indexFile.writeAsString(
        jsonEncode(json),
        flush: true,
      );
    } catch (e) {
      throw Exception('保存索引失败: $e');
    }
  }

  /// 获取报告文件路径
  Future<String> getReportFilePath(String reportId) async {
    try {
      final reports = await loadAllReports();
      final report = reports.firstWhere((r) => r.id == reportId);
      return report.filePath;
    } catch (e) {
      throw Exception('获取报告文件路径失败: $e');
    }
  }
}
