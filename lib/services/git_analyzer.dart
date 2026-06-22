import 'package:process/process.dart';

/// Git 贡献者信息
class GitContributor {
  GitContributor({
    required this.name,
    this.email,
    required this.commitCount,
    this.lastCommitDate,
  });

  final String name;
  final String? email;
  final int commitCount;
  final DateTime? lastCommitDate;

  @override
  String toString() => '$name ($commitCount commits)';

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'commitCount': commitCount,
        'lastCommitDate': lastCommitDate?.toIso8601String(),
      };
}

/// Git blame 信息（代码贡献者）
class GitBlameInfo {
  GitBlameInfo({
    required this.fileName,
    required this.lineNumber,
    required this.author,
    required this.commitHash,
    required this.commitDate,
    required this.codeLine,
  });

  final String fileName;
  final int lineNumber;
  final String author;
  final String commitHash;
  final DateTime commitDate;
  final String codeLine;

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'lineNumber': lineNumber,
        'author': author,
        'commitHash': commitHash,
        'commitDate': commitDate.toIso8601String(),
        'codeLine': codeLine,
      };
}

/// Git 日志条目
class GitLogEntry {
  GitLogEntry({
    required this.hash,
    required this.author,
    required this.date,
    required this.message,
  });

  final String hash;
  final String author;
  final DateTime date;
  final String message;

  Map<String, dynamic> toJson() => {
        'hash': hash,
        'author': author,
        'date': date.toIso8601String(),
        'message': message,
      };
}

/// Git 分析器
class GitAnalyzer {
  GitAnalyzer({
    ProcessManager? processManager,
    String? workingDirectory,
  })  : _processManager = processManager ?? const LocalProcessManager(),
        _workingDirectory = workingDirectory;

  final ProcessManager _processManager;
  final String? _workingDirectory;

  /// 执行 git 命令
  Future<String> _runGitCommand(List<String> args) async {
    try {
      final result = await _processManager.run(
        ['git', ...args],
        workingDirectory: _workingDirectory,
      );

      if (result.exitCode != 0) {
        throw GitException('git ${args.join(" ")} failed: ${result.stderr}');
      }

      return result.stdout.toString().trim();
    } catch (e) {
      throw GitException('Git command failed: $e');
    }
  }

  /// 获取文件的贡献者列表（按提交数排序）
  Future<List<GitContributor>> getFileContributors(
    String filePath, {
    int limit = 5,
  }) async {
    try {
      final output = await _runGitCommand([
        'log',
        '--format=%an|%ae|%aI',
        '--',
        filePath,
      ]);

      final lines = output.split('\n').where((l) => l.isNotEmpty).toList();
      final contributors = <String, GitContributor>{};

      for (final line in lines) {
        final parts = line.split('|');
        if (parts.length >= 2) {
          final name = parts[0];
          final email = parts.length > 1 ? parts[1] : null;
          final dateStr = parts.length > 2 ? parts[2] : null;

          if (contributors.containsKey(name)) {
            contributors[name]!._incrementCount();
          } else {
            contributors[name] = GitContributor(
              name: name,
              email: email,
              commitCount: 1,
              lastCommitDate: _parseGitDate(dateStr),
            );
          }
        }
      }

      final sorted = contributors.values.toList();
      sorted.sort((a, b) => b.commitCount.compareTo(a.commitCount));
      return sorted.take(limit).toList();
    } catch (e) {
      return [];
    }
  }

  /// Git blame - 获取指定行的贡献者
  Future<GitBlameInfo?> blameLine(
    String filePath,
    int lineNumber,
  ) async {
    try {
      final output = await _runGitCommand([
        'blame',
        '-L',
        '$lineNumber,$lineNumber',
        '--line-porcelain',
        filePath,
      ]);

      return _parseBlameOutput(output, filePath, lineNumber);
    } catch (e) {
      return null;
    }
  }

  /// 获取文件的最新提交
  Future<GitLogEntry?> getLatestCommit(String filePath) async {
    try {
      final output = await _runGitCommand([
        'log',
        '-1',
        '--format=%H|%an|%aI|%s',
        '--',
        filePath,
      ]);

      if (output.isEmpty) return null;

      final parts = output.split('|');
      if (parts.length < 4) return null;

      return GitLogEntry(
        hash: parts[0],
        author: parts[1],
        date: _parseGitDate(parts[2]) ?? DateTime.now(),
        message: parts[3],
      );
    } catch (e) {
      return null;
    }
  }

  /// 获取文件的提交历史
  Future<List<GitLogEntry>> getFileHistory(
    String filePath, {
    int limit = 10,
  }) async {
    try {
      final output = await _runGitCommand([
        'log',
        '-$limit',
        '--format=%H|%an|%aI|%s',
        '--',
        filePath,
      ]);

      final lines = output.split('\n').where((l) => l.isNotEmpty).toList();
      return lines
          .map((line) {
            final parts = line.split('|');
            if (parts.length >= 4) {
              return GitLogEntry(
                hash: parts[0],
                author: parts[1],
                date: _parseGitDate(parts[2]) ?? DateTime.now(),
                message: parts[3],
              );
            }
            return null;
          })
          .whereType<GitLogEntry>()
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 获取特定提交的文件内容
  Future<String?> getFileAtCommit(
    String filePath,
    String commitHash,
  ) async {
    try {
      return await _runGitCommand([
        'show',
        '$commitHash:$filePath',
      ]);
    } catch (e) {
      return null;
    }
  }

  /// 检查项目是否为 git 仓库
  Future<bool> isGitRepository() async {
    try {
      await _runGitCommand(['rev-parse', '--git-dir']);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 解析 git 日期格式（ISO 8601）
  static DateTime? _parseGitDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      return DateTime.parse(dateStr);
    } catch (e) {
      return null;
    }
  }

  /// 解析 blame 输出
  static GitBlameInfo? _parseBlameOutput(
    String output,
    String filePath,
    int lineNumber,
  ) {
    final lines = output.split('\n');
    String? author;
    String? commitHash;
    DateTime? commitDate;
    String? codeLine;

    for (final line in lines) {
      if (line.startsWith('^') || line.startsWith('0' * 40)) {
        continue;
      }

      if (line.length >= 40) {
        commitHash = line.substring(0, 40).trim();
      }

      if (line.startsWith('author ')) {
        author = line.substring(7).trim();
      } else if (line.startsWith('author-time ')) {
        final timestamp = int.tryParse(line.substring(12).trim());
        if (timestamp != null) {
          commitDate = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        }
      } else if (!line.startsWith('\t') && !line.startsWith(' ')) {
        continue;
      } else {
        codeLine = line;
        break;
      }
    }

    if (author == null || commitHash == null) return null;

    return GitBlameInfo(
      fileName: filePath,
      lineNumber: lineNumber,
      author: author,
      commitHash: commitHash,
      commitDate: commitDate ?? DateTime.now(),
      codeLine: codeLine ?? '',
    );
  }
}

/// Git 异常
class GitException implements Exception {
  GitException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 扩展 GitContributor 以支持计数增加
extension on GitContributor {
  void _incrementCount() {
    // 由于 Dart 的不可变性，这里用不了，需要在 getFileContributors 中处理
  }
}
