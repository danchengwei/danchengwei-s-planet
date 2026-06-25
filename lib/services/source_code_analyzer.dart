import 'dart:io';

import 'package:path/path.dart' as p;

/// 单条 blame 记录：行号、作者、提交、原始内容。
class SourceCodeBlameLine {
  SourceCodeBlameLine({
    required this.lineNumber,
    required this.content,
    this.author = '',
    this.authorEmail = '',
    this.commit = '',
    this.commitSummary = '',
    this.authorTimeText = '',
  });

  final int lineNumber;
  final String content;
  final String author;
  final String authorEmail;
  final String commit;
  /// 提交信息第一行（来自 `git blame` 的 `summary` 字段）。
  final String commitSummary;
  /// 作者时间（来自 `git blame` 的 `author-time`），格式 `YYYY-MM-DD`。
  final String authorTimeText;
}

/// 源码分析结果：解析堆栈、定位文件、读取代码片段、获取作者。
class SourceCodeLookup {
  SourceCodeLookup({
    required this.sourceFile,
    required this.centerLine,
    required this.snippet,
    required this.authorStats,
    this.isGitIgnored = false,
    this.submodule = '',
    this.gitRoot = '',
    this.error,
  });

  /// 命中的源码文件绝对路径；未命中时为 null。
  final String? sourceFile;
  final int centerLine;
  /// 以 [centerLine] 为中心，前后各 [context] 行的代码片段（已带 `>>>` 标记）。
  final List<SourceCodeBlameLine> snippet;
  /// 出现行数（去重作者）→ 贡献行数。
  final Map<String, int> authorStats;
  /// 文件是否被 `.gitignore` 忽略。
  final bool isGitIgnored;
  /// 若文件在子模块/子仓库中，记录相对 [projectPath] 的子模块路径。
  final String submodule;
  /// 实际执行 `git` 命令的仓库根（可能与 projectPath 不同：子模块场景）。
  final String gitRoot;
  /// 命中失败或异常时的原因；null 表示成功。
  final String? error;
}

/// 本地源码分析：定位 + 读取 + git blame（支持子模块/子仓库）。
///
/// 依赖：
/// - `localProjectPath`（[ToolConfig.localProjectPath]）作为仓库根。
/// - 仓库下需存在 `.git`（否则 blame 静默跳过）。
class SourceCodeAnalyzer {
  SourceCodeAnalyzer({required this.projectPath});

  final String projectPath;

  static const _systemPrefixes = <String>[
    'android.', 'androidx.', 'java.', 'javax.', 'dalvik.', 'com.android.',
    'libcore.', 'org.apache.', 'org.xml', 'org.w3c.', 'kotlin.',
    'com.google.android.', 'com.google.firebase.', 'com.facebook.',
  ];

  /// 从堆栈解析首个**业务帧**（非系统/框架），作为源码定位目标。
  static ({String? className, String? method, String? file, int line}) parseAppFrame(
    String stack,
  ) {
    if (stack.trim().isEmpty) return (className: null, method: null, file: null, line: 0);
    final causedBy = stack.indexOf('Caused by:');
    final effective = causedBy >= 0 ? stack.substring(causedBy) : stack;
    final re = RegExp(r'at\s+([^\s(]+)\.([^\s(]+)\(([^:)]+):(\d+)\)');
    for (final m in re.allMatches(effective)) {
      final cls = m.group(1) ?? '';
      if (_systemPrefixes.any(cls.startsWith)) continue;
      return (
        className: cls,
        method: m.group(2),
        file: m.group(3),
        line: int.tryParse(m.group(4) ?? '0') ?? 0,
      );
    }
    return (className: null, method: null, file: null, line: 0);
  }

  /// 按类名在 [projectPath] 中查找源码文件。
  ///
  /// 命中顺序：
  /// 1. `com.xx.Yy` → `com/xx/Yy.java` 直接拼路径（含 `src/main/java` 前缀尝试）
  /// 2. `find ... -name 'Yy.java' | xargs grep 'class Yy'` 模糊匹配（10s 超时）
  Future<String?> findSourceFile(String className) async {
    final root = _rootDir;
    if (root == null) return null;
    final simple = className.split('.').last;
    final directRel = '${className.replaceAll('.', '/')}.java';
    final candidates = <String>[
      directRel,
      'src/main/java/$directRel',
      'app/src/main/java/$directRel',
    ];
    for (final rel in candidates) {
      final f = File(p.join(root.path, rel));
      if (f.existsSync()) return f.path;
    }
    try {
      final r = await Process.run(
        '/bin/sh',
        [
          '-c',
          "find '${root.path}' -name '$simple.java' -type f 2>/dev/null | xargs grep -l 'class $simple\\b' 2>/dev/null | head -1",
        ],
      ).timeout(const Duration(seconds: 10));
      final out = r.stdout.toString().trim();
      if (out.isNotEmpty) return out;
    } catch (_) {}
    return null;
  }

  /// 读取中心行前后 [context] 行的代码片段，并按 `git blame` 标记作者/时间/提交。
  ///
  /// 支持子模块/子仓库：若文件所在目录或其父目录存在 `.git`，就在那个根目录跑 `git blame`。
  Future<SourceCodeLookup> readSnippet({
    required String? className,
    int line = 0,
    int context = 6,
  }) async {
    final root = _rootDir;
    if (root == null) {
      return SourceCodeLookup(
        sourceFile: null,
        centerLine: line,
        snippet: const [],
        authorStats: const {},
        error: '本地项目路径未配置',
      );
    }
    if (className == null || className.isEmpty) {
      return SourceCodeLookup(
        sourceFile: null,
        centerLine: line,
        snippet: const [],
        authorStats: const {},
        error: '堆栈中未定位到业务类',
      );
    }
    final file = await findSourceFile(className);
    if (file == null) {
      return SourceCodeLookup(
        sourceFile: null,
        centerLine: line,
        snippet: const [],
        authorStats: const {},
        error: '未在项目中找到源码：$className',
      );
    }
    final lines = await _safeRead(file);
    if (lines.isEmpty) {
      return SourceCodeLookup(
        sourceFile: file,
        centerLine: line,
        snippet: const [],
        authorStats: const {},
        error: '源码文件为空或读取失败',
      );
    }
    final center = line <= 0 ? 1 : line.clamp(1, lines.length);
    final start = (center - context - 1).clamp(0, lines.length - 1);
    final end = (center + context).clamp(0, lines.length);
    final slice = <String>[];
    for (var i = start; i < end; i++) {
      slice.add(lines[i]);
    }

    // 1) 从文件向上找最近的 .git（子模块支持）
    final gitRoot = _findGitRoot(file, root.path);
    final submodule = gitRoot != root.path ? p.relative(gitRoot, from: root.path) : '';
    final isSubmodule = submodule.isNotEmpty;

    // 2) 在主仓库根下做 git check-ignore（子模块内不再做此检查）
    if (!isSubmodule) {
      final ignored = await _isGitIgnored(file, root.path);
      if (ignored) {
        // 即便被忽略，也尝试给出代码片段（无 blame 信息）
        final result = <SourceCodeBlameLine>[];
        for (var i = 0; i < slice.length; i++) {
          final lineNo = start + i + 1;
          result.add(SourceCodeBlameLine(
            lineNumber: lineNo,
            content: slice[i],
            author: '-',
            commit: '-',
            authorTimeText: '-',
            commitSummary: '-',
          ));
        }
        return SourceCodeLookup(
          sourceFile: file,
          centerLine: center,
          snippet: result,
          authorStats: const {},
          isGitIgnored: true,
          submodule: '',
          gitRoot: root.path,
        );
      }
    }

    // 3) git blame（porcelain），在子模块/主仓库的根目录下执行
    final relativePath = p.relative(file, from: gitRoot);
    final blame = await _gitBlameRange(gitRoot, relativePath, start + 1, end);
    final result = <SourceCodeBlameLine>[];
    final authorStats = <String, int>{};
    for (var i = 0; i < slice.length; i++) {
      final lineNo = start + i + 1;
      final info = blame[lineNo];
      final author = (info?.author ?? '').trim();
      if (author.isNotEmpty && author != 'Not Committed Yet' && author != '-') {
        authorStats[author] = (authorStats[author] ?? 0) + 1;
      }
      result.add(SourceCodeBlameLine(
        lineNumber: lineNo,
        content: slice[i],
        author: author,
        authorEmail: info?.authorEmail ?? '',
        commit: info?.commit ?? '',
        commitSummary: info?.commitSummary ?? '',
        authorTimeText: info?.authorTimeText ?? '',
      ));
    }
    return SourceCodeLookup(
      sourceFile: file,
      centerLine: center,
      snippet: result,
      authorStats: authorStats,
      isGitIgnored: false,
      submodule: isSubmodule ? submodule : '',
      gitRoot: gitRoot,
    );
  }

  Directory? get _rootDir {
    if (projectPath.trim().isEmpty) return null;
    final d = Directory(projectPath);
    return d.existsSync() ? d : null;
  }

  Future<List<String>> _safeRead(String path) async {
    try {
      return await File(path).readAsLines();
    } catch (_) {
      return const [];
    }
  }

  /// 从文件目录向上找最近的 `.git`，找到返回其所在目录；找不到回退到 projectRoot。
  String _findGitRoot(String filePath, String projectRoot) {
    try {
      final absFile = p.canonicalize(filePath);
      final absRoot = p.canonicalize(projectRoot);
      var dir = p.dirname(absFile);
      while (true) {
        if (Directory(p.join(dir, '.git')).existsSync()) {
          return dir;
        }
        if (dir == absRoot) break;
        final parent = p.dirname(dir);
        if (parent == dir || parent == '/' || parent.isEmpty) break;
        // 不要跳出 projectRoot 以上：避免命中用户家目录里的其他 repo
        if (!p.isWithin(absRoot, parent) && parent != absRoot) break;
        dir = parent;
      }
    } catch (_) {}
    return projectRoot;
  }

  /// `git check-ignore -v <path>` 检查文件是否被 .gitignore 忽略。
  Future<bool> _isGitIgnored(String filePath, String repoRoot) async {
    try {
      final rel = p.relative(filePath, from: repoRoot);
      final r = await Process.run(
        'git',
        ['check-ignore', '-v', rel],
        workingDirectory: repoRoot,
        runInShell: true,
      ).timeout(const Duration(seconds: 5));
      // 退出码 0 = 被忽略，1 = 未忽略
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 调 `git blame -L start,end --line-porcelain` 拿行号→作者/时间/提交映射。
  Future<Map<int, _BlameRow>> _gitBlameRange(
    String repoRoot,
    String relativePath,
    int start,
    int end,
  ) async {
    try {
      final r = await Process.run(
        'git',
        [
          'blame',
          '-L',
          '$start,$end',
          '--line-porcelain',
          '--',
          relativePath,
        ],
        workingDirectory: repoRoot,
        runInShell: true,
      ).timeout(const Duration(seconds: 15));
      if (r.exitCode != 0) return const {};
      final out = r.stdout.toString();
      final map = <int, _BlameRow>{};
      String commit = '';
      String author = '';
      String email = '';
      int authorTime = 0;
      String commitSummary = '';
      final blocks = out.split('\n');
      int idx = 0;
      while (idx < blocks.length) {
        final header = blocks[idx];
        if (header.isEmpty) {
          idx++;
          continue;
        }
        final firstSpace = header.indexOf(' ');
        if (firstSpace <= 0) {
          idx++;
          continue;
        }
        final head = header.substring(0, firstSpace);
        final rest = header.substring(firstSpace + 1);
        if (head.length != 40) {
          idx++;
          continue;
        }
        commit = head;
        final parts = rest.split(' ');
        final finalLine = int.tryParse(parts.isNotEmpty ? parts.last : '0') ?? 0;
        if (finalLine <= 0) {
          idx++;
          continue;
        }
        author = '';
        email = '';
        authorTime = 0;
        commitSummary = '';
        idx++;
        while (idx < blocks.length && blocks[idx].isNotEmpty) {
          final line = blocks[idx];
          if (line.startsWith('author ')) {
            author = line.substring('author '.length);
          } else if (line.startsWith('author-mail ')) {
            email = line.substring('author-mail '.length).trim();
            if (email.startsWith('<') && email.endsWith('>')) {
              email = email.substring(1, email.length - 1);
            }
          } else if (line.startsWith('author-time ')) {
            authorTime = int.tryParse(line.substring('author-time '.length)) ?? 0;
          } else if (line.startsWith('summary ')) {
            commitSummary = line.substring('summary '.length);
          }
          idx++;
        }
        map[finalLine] = _BlameRow(
          author: author,
          authorEmail: email,
          commit: commit,
          authorTime: authorTime,
          commitSummary: commitSummary,
        );
        idx++;
      }
      return map;
    } catch (_) {
      return const {};
    }
  }
}

class _BlameRow {
  _BlameRow({
    required this.author,
    required this.authorEmail,
    required this.commit,
    required this.authorTime,
    required this.commitSummary,
  });
  final String author;
  final String authorEmail;
  final String commit;
  final int authorTime;
  final String commitSummary;
  String get authorTimeText {
    if (authorTime <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(authorTime * 1000);
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
