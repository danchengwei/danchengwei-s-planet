import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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

  /// 解压压缩包到指定目录。
  ///
  /// 手动逐文件写出，而不是用 extractArchiveToDisk：华佗日志包里的按日期
  /// 文件条目（无扩展名、目录条目标记不标准）会导致 extractArchiveToDisk
  /// 静默跳过（0 个文件），手动遍历写出可正确处理。
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

      Archive decoded;
      if (lower.endsWith('.zip')) {
        decoded = ZipDecoder().decodeBytes(bytes);
      } else if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
        decoded = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
      } else if (lower.endsWith('.tar')) {
        decoded = TarDecoder().decodeBytes(bytes);
      } else {
        return false;
      }

      var fileCount = 0;
      for (final f in decoded.files) {
        if (f.isFile) {
          // 规范化路径分隔符，并防止 zip slip（路径越界）
          final rel = f.name.replaceAll('\\', '/');
          final outPath = p.join(extractPath, rel);
          final outFile = File(outPath);
          outFile.parent.createSync(recursive: true);
          outFile.writeAsBytesSync(f.content as List<int>, flush: true);
          fileCount++;
        } else {
          final rel = f.name.replaceAll('\\', '/');
          final dir = Directory(p.join(extractPath, rel));
          if (!dir.existsSync()) dir.createSync(recursive: true);
        }
      }

      debugPrint('[ArchiveManager] 解压完成：$fileCount 个文件 -> $extractPath');
      return fileCount > 0;
    } catch (e) {
      debugPrint('[ArchiveManager] 解压失败: $e');
      return false;
    }
  }

  /// 从压缩包内存归档中仅提取 tombstone 文件，写入 [destDir]，返回其文件名。
  ///
  /// 不做全量磁盘解压（华佗日志包内含大量按日期分割的超大文件，全量解压极慢）。
  static Future<String?> extractTombstoneOnly(String archivePath, String destDir) async {
    try {
      final lower = archivePath.toLowerCase();
      final bytes = await File(archivePath).readAsBytes();

      Archive archive;
      if (lower.endsWith('.zip')) {
        archive = ZipDecoder().decodeBytes(bytes);
      } else if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
        archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
      } else if (lower.endsWith('.tar')) {
        archive = TarDecoder().decodeBytes(bytes);
      } else {
        return null;
      }

      ArchiveFile? tomb;
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final name = f.name.split('/').last.toLowerCase();
        if (name.contains('tombstone')) {
          tomb = f;
          break;
        }
      }

      if (tomb == null) {
        debugPrint('[ArchiveManager] 压缩包内无 tombstone 文件');
        return null;
      }

      final tombName = tomb.name.split('/').last;
      final dir = Directory(destDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await File('$destDir/$tombName').writeAsBytes(tomb.content as List<int>);
      return tombName;
    } catch (e) {
      debugPrint('[ArchiveManager] 提取 tombstone 失败: $e');
      return null;
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
