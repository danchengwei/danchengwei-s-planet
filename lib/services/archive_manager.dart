import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

/// 压缩包管理服务
class ArchiveManager {
  ArchiveManager._();

  /// 检查文件是否是支持的压缩包
  static bool isSupportedArchive(String filePath) {
    final lower = filePath.toLowerCase();
    return lower.endsWith('.zip') ||
           lower.endsWith('.tar.gz') ||
           lower.endsWith('.tgz') ||
           lower.endsWith('.tar');
  }

  /// 获取压缩包信息
  static Future<ArchiveInfo?> getArchiveInfo(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final size = await file.length();
      final filename = file.path.split('/').last;

      // 提取文件列表
      final files = await _listArchiveFiles(filePath);

      return ArchiveInfo(
        filename: filename,
        path: filePath,
        size: size,
        fileCount: files.length,
        files: files,
      );
    } catch (e) {
      debugPrint('[ArchiveManager] 获取压缩包信息失败: $e');
      return null;
    }
  }

  /// 列出压缩包内的文件
  static Future<List<String>> _listArchiveFiles(String filePath) async {
    try {
      final lower = filePath.toLowerCase();

      if (lower.endsWith('.zip')) {
        final file = File(filePath);
        final bytes = await file.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);
        return archive.files
            .where((f) => !f.isFile)
            .map((f) => f.name)
            .toList();
      } else if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
        final file = File(filePath);
        final bytes = await file.readAsBytes();
        final archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
        return archive.files
            .where((f) => f.name.isNotEmpty)
            .map((f) => f.name)
            .toList();
      } else if (lower.endsWith('.tar')) {
        final file = File(filePath);
        final bytes = await file.readAsBytes();
        final archive = TarDecoder().decodeBytes(bytes);
        return archive.files
            .where((f) => f.name.isNotEmpty)
            .map((f) => f.name)
            .toList();
      }
    } catch (e) {
      debugPrint('[ArchiveManager] 列出压缩包文件失败: $e');
    }
    return [];
  }

  /// 解压压缩包到指定目录
  static Future<bool> extractArchive(String archivePath, String extractPath) async {
    try {
      final archive = File(archivePath);
      if (!await archive.exists()) return false;

      final extractDir = Directory(extractPath);
      if (!await extractDir.exists()) {
        await extractDir.create(recursive: true);
      }

      final lower = archivePath.toLowerCase();
      final bytes = await archive.readAsBytes();

      if (lower.endsWith('.zip')) {
        final zipArchive = ZipDecoder().decodeBytes(bytes);
        extractArchiveToDisk(zipArchive, extractPath);
      } else if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
        final tarArchive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
        extractArchiveToDisk(tarArchive, extractPath);
      } else if (lower.endsWith('.tar')) {
        final tarArchive = TarDecoder().decodeBytes(bytes);
        extractArchiveToDisk(tarArchive, extractPath);
      }

      return true;
    } catch (e) {
      debugPrint('[ArchiveManager] 解压失败: $e');
      return false;
    }
  }

  /// 获取压缩包内单个文件的内容
  static Future<String?> readFileFromArchive(String archivePath, String fileName) async {
    try {
      final lower = archivePath.toLowerCase();
      final bytes = await File(archivePath).readAsBytes();

      if (lower.endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final file in archive.files) {
          if (file.name == fileName && file.isFile) {
            return String.fromCharCodes(file.content as List<int>);
          }
        }
      } else if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
        final archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
        for (final file in archive.files) {
          if (file.name == fileName) {
            return String.fromCharCodes(file.content);
          }
        }
      } else if (lower.endsWith('.tar')) {
        final archive = TarDecoder().decodeBytes(bytes);
        for (final file in archive.files) {
          if (file.name == fileName) {
            return String.fromCharCodes(file.content);
          }
        }
      }
    } catch (e) {
      debugPrint('[ArchiveManager] 读取压缩包文件失败: $e');
    }
    return null;
  }
}

/// 压缩包信息
class ArchiveInfo {
  final String filename;
  final String path;
  final int size;
  final int fileCount;
  final List<String> files;

  ArchiveInfo({
    required this.filename,
    required this.path,
    required this.size,
    required this.fileCount,
    required this.files,
  });

  String get formattedSize {
    const units = ['B', 'KB', 'MB', 'GB'];
    double bytes = size.toDouble();
    int unitIndex = 0;

    while (bytes >= 1024 && unitIndex < units.length - 1) {
      bytes /= 1024;
      unitIndex++;
    }

    return '${bytes.toStringAsFixed(2)} ${units[unitIndex]}';
  }
}
