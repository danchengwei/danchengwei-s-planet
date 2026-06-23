import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 分析会话日志文件管理器
class AnalysisLogsManager {
  /// 初始化会话日志目录
  Future<Directory> initializeSessionDirectory(String sessionId) async {
    final baseDir = await getApplicationSupportDirectory();
    final sessionLogsDir = Directory('${baseDir.path}/analysis_logs/$sessionId');

    if (!await sessionLogsDir.exists()) {
      await sessionLogsDir.create(recursive: true);
    }

    return sessionLogsDir;
  }

  /// 保存日志文件
  Future<String> saveLogFile({
    required String sessionId,
    required String fileName,
    required String content,
  }) async {
    final sessionDir = await initializeSessionDirectory(sessionId);
    final logFile = File('${sessionDir.path}/$fileName');
    await logFile.writeAsString(content);
    return logFile.path;
  }

  /// 保存二进制日志文件
  Future<String> saveBinaryLogFile({
    required String sessionId,
    required String fileName,
    required List<int> bytes,
  }) async {
    final sessionDir = await initializeSessionDirectory(sessionId);
    final logFile = File('${sessionDir.path}/$fileName');
    await logFile.writeAsBytes(bytes);
    return logFile.path;
  }

  /// 获取会话的所有日志文件
  Future<List<FileInfo>> getSessionLogFiles(String sessionId) async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      final sessionDir = Directory('${baseDir.path}/analysis_logs/$sessionId');

      if (!await sessionDir.exists()) {
        return [];
      }

      final files = sessionDir.listSync();
      final logFiles = <FileInfo>[];

      for (final entity in files) {
        if (entity is File) {
          final fileName = entity.path.split('/').last;
          // 只显示原始的华佗日志压缩包（.tar.gz 和 .zip）
          if (fileName.endsWith('.tar.gz') || fileName.endsWith('.zip')) {
            final stat = await entity.stat();
            logFiles.add(FileInfo(
              name: fileName,
              path: entity.path,
              size: stat.size,
              modified: stat.modified,
            ));
          }
        }
      }

      return logFiles;
    } catch (e) {
      return [];
    }
  }

  /// 预览日志文件（读取内容）
  Future<String> previewLogFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.readAsString();
      }
      return '文件不存在';
    } catch (e) {
      return '读取失败: $e';
    }
  }

  /// 删除单个日志文件
  Future<bool> deleteLogFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 删除整个会话目录（包括所有日志）
  Future<bool> deleteSessionDirectory(String sessionId) async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      final sessionDir = Directory('${baseDir.path}/analysis_logs/$sessionId');

      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 获取所有分析会话目录
  Future<List<String>> getAllSessionIds() async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      final logsDir = Directory('${baseDir.path}/analysis_logs');

      if (!await logsDir.exists()) {
        return [];
      }

      final sessions = <String>[];
      final entities = logsDir.listSync();

      for (final entity in entities) {
        if (entity is Directory) {
          sessions.add(entity.path.split('/').last);
        }
      }

      return sessions;
    } catch (e) {
      return [];
    }
  }

  /// 获取所有下载的日志文件（递归遍历analysis_logs下的所有文件）
  Future<List<FileInfo>> getAllDownloadedLogFiles() async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      final logsDir = Directory('${baseDir.path}/analysis_logs');

      if (!await logsDir.exists()) {
        return [];
      }

      final allFiles = <FileInfo>[];
      final entities = logsDir.listSync(recursive: true);

      for (final entity in entities) {
        if (entity is File) {
          final fileName = entity.path.split('/').last;
          // 只显示原始的华佗日志压缩包（.tar.gz 和 .zip）
          if (fileName.endsWith('.tar.gz') || fileName.endsWith('.zip')) {
            final stat = await entity.stat();
            allFiles.add(FileInfo(
              name: fileName,
              path: entity.path,
              size: stat.size,
              modified: stat.modified,
            ));
          }
        }
      }

      // 按修改时间排序（最新的在前）
      allFiles.sort((a, b) => b.modified.compareTo(a.modified));

      return allFiles;
    } catch (e) {
      return [];
    }
  }

  /// 获取会话日志总大小
  Future<int> getSessionLogsSize(String sessionId) async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      final sessionDir = Directory('${baseDir.path}/analysis_logs/$sessionId');

      if (!await sessionDir.exists()) {
        return 0;
      }

      int totalSize = 0;
      final files = sessionDir.listSync();

      for (final entity in files) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }

      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  /// 格式化文件大小显示
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 日志文件信息
class FileInfo {
  FileInfo({
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
  });

  final String name;
  final String path;
  final int size;
  final DateTime modified;

  String get formattedSize => AnalysisLogsManager.formatFileSize(size);

  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(modified);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';

    return '${modified.year}-${modified.month.toString().padLeft(2, '0')}-${modified.day.toString().padLeft(2, '0')}';
  }
}
