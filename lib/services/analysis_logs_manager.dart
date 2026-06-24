import 'dart:io';
import 'package:flutter/foundation.dart';
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
        final fileName = entity.path.split('/').last;

        if (entity is Directory) {
          // 只显示解压后的日志目录（03_*_logs）
          if (fileName.startsWith('03_') && fileName.endsWith('_logs')) {
            final stat = await entity.stat();
            final size = await _getDirectorySize(entity.path);
            logFiles.add(FileInfo(
              name: fileName,
              path: entity.path,
              size: size,
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

  /// 计算目录总大小
  Future<int> _getDirectorySize(String dirPath) async {
    int totalSize = 0;
    try {
      final dir = Directory(dirPath);
      final files = dir.listSync(recursive: true, followLinks: false);
      for (final entity in files) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    } catch (e) {
      debugPrint('[AnalysisLogsManager] 计算目录大小失败: $e');
    }
    return totalSize;
  }

  /// 预览日志文件或目录
  /// 如果是文件，读取文件内容；如果是目录，列出目录内的文件及其大小
  Future<String> previewLogFile(String filePath) async {
    try {
      final dir = Directory(filePath);
      if (await dir.exists()) {
        // 这是一个目录，列出其中的文件
        final buffer = StringBuffer();
        buffer.writeln('📁 目录：${filePath.split('/').last}');
        buffer.writeln('═' * 80);

        final files = dir.listSync(recursive: true, followLinks: false);
        final fileEntries = files.whereType<File>().toList();

        if (fileEntries.isEmpty) {
          buffer.writeln('(目录为空)');
        } else {
          buffer.writeln('共 ${fileEntries.length} 个文件：\n');
          for (final file in fileEntries) {
            final relativePath = file.path.replaceFirst('$filePath/', '');
            final size = await file.length();
            final formattedSize = formatFileSize(size);
            buffer.writeln('📄 $relativePath ($formattedSize)');
          }
        }
        return buffer.toString();
      }

      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        // 限制预览大小
        if (content.length > 500 * 1024) {
          return '${content.substring(0, 500 * 1024)}\n\n...[文件过大，已截断，总大小: ${formatFileSize(content.length)}]';
        }
        return content;
      }
      return '文件不存在';
    } catch (e) {
      return '读取失败: $e';
    }
  }

  /// 删除单个日志文件或目录
  Future<bool> deleteLogFile(String filePath) async {
    try {
      final dir = Directory(filePath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        return true;
      }

      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[AnalysisLogsManager] 删除文件/目录失败: $e');
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

  /// 获取所有下载的日志文件（只显示解压后的日志目录）
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
        final fileName = entity.path.split('/').last;

        if (entity is Directory) {
          // 只显示解压后的日志目录（03_*_logs），用户可直接查看原始日志文件
          if (fileName.startsWith('03_') && fileName.endsWith('_logs')) {
            final stat = await entity.stat();
            final size = await _getDirectorySize(entity.path);
            allFiles.add(FileInfo(
              name: fileName,
              path: entity.path,
              size: size,
              modified: stat.modified,
            ));
          }
        }
      }

      // 按修改时间排序（最新的在前）
      allFiles.sort((a, b) => b.modified.compareTo(a.modified));

      return allFiles;
    } catch (e) {
      debugPrint('[AnalysisLogsManager] 获取所有下载文件失败: $e');
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
