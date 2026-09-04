import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/tool_config.dart';
import 'llm_client.dart';

typedef AgentToolHandler = Future<String> Function(Map<String, dynamic> params);

class AgentTool {
  AgentTool({required this.name, required this.description, required this.parameters, required this.handler});

  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final AgentToolHandler handler;

  LlmTool toLlmTool() => LlmTool(name: name, description: description, parameters: parameters);
}

class AgentToolRegistry {
  AgentToolRegistry({required this.config, required this.projectPath});

  final ToolConfig config;
  final String projectPath;
  final Map<String, AgentTool> _tools = {};

  void register(AgentTool tool) => _tools[tool.name] = tool;

  List<AgentTool> get all => _tools.values.toList();
  List<LlmTool> get llmTools => all.map((t) => t.toLlmTool()).toList();

  Future<String> execute(String name, Map<String, dynamic> params) {
    final tool = _tools[name];
    if (tool == null) return Future.value('未知工具: $name');
    return tool.handler(params);
  }

  /// 创建仅含源码分析所需的「只读检索」工具（grep/read_file/list_directory/search_files）。
  /// 不含 shell/write/claude/EMAS/GitLab 等工具，请求体更小、无副作用，专供源码智能分析。
  static AgentToolRegistry createReadOnlySourceTools({
    required ToolConfig config,
    required String projectPath,
  }) {
    final r = AgentToolRegistry(config: config, projectPath: projectPath);

    r.register(AgentTool(
      name: 'list_directory',
      description: '列出目录内容与子目录结构，用于了解项目布局',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': '目录路径，默认项目根目录'},
          'recursive': {'type': 'boolean', 'description': '是否递归'},
          'maxDepth': {'type': 'integer', 'description': '递归深度，默认 2'},
        },
      },
      handler: (p) => _listDirectory(
        p['path']?.toString(),
        projectPath,
        recursive: p['recursive'] == true,
        maxDepth: (p['maxDepth'] as num?)?.toInt() ?? 2,
      ),
    ));

    r.register(AgentTool(
      name: 'search_files',
      description: '按文件名/通配符搜索文件（如 *Activity*.kt、*.java）',
      parameters: {
        'type': 'object',
        'properties': {
          'pattern': {'type': 'string', 'description': '文件名通配符'},
          'directory': {'type': 'string', 'description': '搜索起始目录'},
        },
        'required': ['pattern'],
      },
      handler: (p) => _searchFiles(
        p['pattern']?.toString() ?? '*',
        p['directory']?.toString(),
        projectPath,
      ),
    ));

    r.register(AgentTool(
      name: 'grep',
      description: '在源码内容中搜索关键词/正则（基于 ripgrep，自动跳过 build/.git 等目录）',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '搜索关键词或正则'},
          'path': {'type': 'string', 'description': '搜索目录，默认项目根'},
          'fileTypes': {'type': 'string', 'description': '文件类型过滤，如 .kt,.java（逗号分隔）'},
          'maxResults': {'type': 'integer', 'description': '最大结果数，默认 30'},
        },
        'required': ['query'],
      },
      handler: (p) => _grep(
        p['query']?.toString() ?? '',
        p['path']?.toString(),
        projectPath,
        fileTypes: p['fileTypes']?.toString(),
        maxResults: (p['maxResults'] as num?)?.toInt() ?? 30,
      ),
    ));

    r.register(AgentTool(
      name: 'read_file',
      description: '读取指定文件内容（自动截断超大文件）',
      parameters: {
        'type': 'object',
        'properties': {'path': {'type': 'string', 'description': '文件绝对路径或相对项目根目录的路径'}},
        'required': ['path'],
      },
      handler: (p) => _readFile(p['path']?.toString() ?? '', projectPath),
    ));

    return r;
  }

  /// 创建包含全套通用工具 + EMAS/GitLab/华佗工具的注册表
  static AgentToolRegistry createStandard({
    required ToolConfig config,
    required String projectPath,
    Future<String> Function(String bizModule, int startTimeMs, int endTimeMs, {String? os, int? pageSize})? emasQuery,
    Future<String> Function(String bizModule, String digestHash, int startTimeMs, int endTimeMs, {String? os})? emasIssueDetail,
    Future<String> Function(String projectId, String query)? gitlabSearch,
    Future<String> Function(String userId, String date, String devid)? huatuoGetLogs,
  }) {
    final r = AgentToolRegistry(config: config, projectPath: projectPath);

    // === 通用系统工具 ===

    r.register(AgentTool(
      name: 'read_file',
      description: '读取指定文件的全部内容',
      parameters: {
        'type': 'object',
        'properties': {'path': {'type': 'string', 'description': '文件绝对路径或相对于项目根目录的路径'}},
        'required': ['path'],
      },
      handler: (p) => _readFile(p['path']?.toString() ?? '', projectPath),
    ));

    r.register(AgentTool(
      name: 'list_directory',
      description: '列出目录内容（可选递归）',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': '目录路径，默认项目根目录'},
          'recursive': {'type': 'boolean', 'description': '是否递归，默认 false'},
          'maxDepth': {'type': 'integer', 'description': '递归最大深度，默认 2'},
        },
      },
      handler: (p) => _listDirectory(
        p['path']?.toString(),
        projectPath,
        recursive: p['recursive'] == true,
        maxDepth: (p['maxDepth'] as num?)?.toInt() ?? 2,
      ),
    ));

    r.register(AgentTool(
      name: 'search_files',
      description: '在项目内按文件名/扩展名搜索文件',
      parameters: {
        'type': 'object',
        'properties': {
          'pattern': {'type': 'string', 'description': '文件名模式，如 *.dart、*Test*'},
          'directory': {'type': 'string', 'description': '搜索起始目录，默认项目根'},
        },
        'required': ['pattern'],
      },
      handler: (p) => _searchFiles(p['pattern']?.toString() ?? '*', p['directory']?.toString(), projectPath),
    ));

    r.register(AgentTool(
      name: 'grep',
      description: '在项目内搜索代码内容（支持正则）',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '搜索关键词或正则表达式'},
          'path': {'type': 'string', 'description': '搜索目录/文件，默认项目根'},
          'fileTypes': {'type': 'string', 'description': '文件扩展名过滤，如 .dart,.kt'},
          'maxResults': {'type': 'integer', 'description': '最大结果数，默认 30'},
        },
        'required': ['query'],
      },
      handler: (p) => _grep(
        p['query']?.toString() ?? '',
        p['path']?.toString(),
        projectPath,
        fileTypes: p['fileTypes']?.toString(),
        maxResults: (p['maxResults'] as num?)?.toInt() ?? 30,
      ),
    ));

    r.register(AgentTool(
      name: 'run_shell',
      description: '在项目目录中执行 shell 命令（只读命令：ls, cat, find, grep, git log, git diff, git show, git status, which, wc, head, tail, uname, ps）',
      parameters: {
        'type': 'object',
        'properties': {
          'command': {'type': 'string', 'description': '要执行的 shell 命令'},
          'timeout': {'type': 'integer', 'description': '超时秒数，默认 30'},
        },
        'required': ['command'],
      },
      handler: (p) => _runShell(
        p['command']?.toString() ?? '',
        projectPath,
        timeoutSec: (p['timeout'] as num?)?.toInt() ?? 30,
      ),
    ));

    r.register(AgentTool(
      name: 'write_file',
      description: '写入文件内容（仅在项目目录内）',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': '相对项目根目录的文件路径'},
          'content': {'type': 'string', 'description': '要写入的文件内容'},
        },
        'required': ['path', 'content'],
      },
      handler: (p) => _writeFile(
        p['path']?.toString() ?? '',
        p['content']?.toString() ?? '',
        projectPath,
      ),
    ));

    // === EMAS APM 工具 ===

    if (emasQuery != null) {
      r.register(AgentTool(
        name: 'emas_list_issues',
        description: '查询 EMAS APM 问题列表（崩溃/ANR等），支持时间范围和模块筛选',
        parameters: {
          'type': 'object',
          'properties': {
            'bizModule': {'type': 'string', 'description': '模块：crash/anr/lag/custom/memory_leak/memory_alloc', 'enum': ['crash', 'anr', 'lag', 'custom', 'memory_leak', 'memory_alloc']},
            'startTimeMs': {'type': 'integer', 'description': '开始时间戳（毫秒）'},
            'endTimeMs': {'type': 'integer', 'description': '结束时间戳（毫秒）'},
            'os': {'type': 'string', 'description': '系统：android/ios'},
            'pageSize': {'type': 'integer', 'description': '每页数量，默认 20'},
          },
          'required': ['bizModule', 'startTimeMs', 'endTimeMs'],
        },
        handler: (p) async {
          try {
            final result = await emasQuery(
              p['bizModule']!.toString(),
              (p['startTimeMs'] as num).toInt(),
              (p['endTimeMs'] as num).toInt(),
              os: p['os']?.toString(),
              pageSize: (p['pageSize'] as num?)?.toInt() ?? 20,
            );
            return _formatJson(result);
          } catch (e) {
            return 'EMAS 查询失败: $e';
          }
        },
      ));

      r.register(AgentTool(
        name: 'emas_issue_detail',
        description: '获取单个 EMAS 问题的详细信息（版本分布、设备分布等）',
        parameters: {
          'type': 'object',
          'properties': {
            'bizModule': {'type': 'string', 'description': '模块', 'enum': ['crash', 'anr', 'lag', 'custom', 'memory_leak', 'memory_alloc']},
            'digestHash': {'type': 'string', 'description': '问题的 Digest Hash'},
            'startTimeMs': {'type': 'integer', 'description': '开始时间戳'},
            'endTimeMs': {'type': 'integer', 'description': '结束时间戳'},
          },
          'required': ['bizModule', 'digestHash', 'startTimeMs', 'endTimeMs'],
        },
        handler: (p) async {
          try {
            final result = await emasIssueDetail!(
              p['bizModule']!.toString(),
              p['digestHash']!.toString(),
              (p['startTimeMs'] as num).toInt(),
              (p['endTimeMs'] as num).toInt(),
              os: p['os']?.toString(),
            );
            return _formatJson(result);
          } catch (e) {
            return '获取 Issue 详情失败: $e';
          }
        },
      ));
    }

    // === 华佗日志工具 ===

    if (huatuoGetLogs != null) {
      r.register(AgentTool(
        name: 'huatuo_get_logs',
        description: '查询华佗日志平台，获取指定用户在指定日期的崩溃日志（含 crashLogFile 的 tombstone 文本内容）。',
        parameters: {
          'type': 'object',
          'properties': {
            'userId': {'type': 'string', 'description': '用户 ID（从 EMAS 样本 latest_user_sample.user_id 获取）'},
            'date': {'type': 'string', 'description': '日期，格式 yyyyMMdd，如 20260902'},
            'devid': {'type': 'string', 'description': '设备标识，默认 8'},
          },
          'required': ['userId', 'date'],
        },
        handler: (p) async {
          try {
            return await huatuoGetLogs(
              p['userId']!.toString(),
              p['date']!.toString(),
              p['devid']?.toString() ?? '8',
            );
          } catch (e) {
            return '华佗日志查询失败: $e';
          }
        },
      ));
    }

    // === GitLab 工具 ===

    if (gitlabSearch != null) {
      final bindings = config.gitlabBindingsResolved;
      if (bindings.isNotEmpty) {
        r.register(AgentTool(
          name: 'gitlab_search',
          description: '在 GitLab 项目仓库中搜索代码（blob 级别）。可用项目: ${bindings.map((b) => '${b.repoName}(${b.projectId})').join(', ')}',
          parameters: {
            'type': 'object',
            'properties': {
              'projectId': {'type': 'string', 'description': 'GitLab 项目 ID，如 ${bindings.first.projectId}'},
              'query': {'type': 'string', 'description': '搜索关键词（类名、方法名等）'},
            },
            'required': ['projectId', 'query'],
          },
          handler: (p) async {
            try {
              return await gitlabSearch(p['projectId']!.toString(), p['query']!.toString());
            } catch (e) {
              return 'GitLab 搜索失败: $e';
            }
          },
        ));
      }
    }

    // === Claude Code 工具 ===

    r.register(AgentTool(
      name: 'launch_claude_code',
      description: '将分析任务通过 Claude Code CLI 在本机执行。提示词会通过 stdin 传给 claude 命令。',
      parameters: {
        'type': 'object',
        'properties': {
          'prompt': {'type': 'string', 'description': '发给 Claude Code 的完整提示词'},
          'workingDirectory': {'type': 'string', 'description': '工作目录，默认项目路径'},
        },
        'required': ['prompt'],
      },
      handler: (p) async {
        final wd = p['workingDirectory']?.toString() ?? projectPath;
        final prompt = p['prompt']!.toString();
        try {
          final proc = await Process.start('claude', ['-p', prompt],
              workingDirectory: wd, runInShell: Platform.isWindows);
          final out = await proc.stdout.transform(systemEncoding.decoder).join();
          final err = await proc.stderr.transform(systemEncoding.decoder).join();
          final code = await proc.exitCode;
          if (code != 0) return 'Claude Code 退出码 $code\n$err';
          return out;
        } catch (e) {
          return '启动 Claude Code 失败: $e';
        }
      },
    ));

    return r;
  }

  // === 工具实现 ===

  static String _resolvePath(String input, String base) {
    if (input.isEmpty) return base;
    if (p.isAbsolute(input)) return input;
    return p.normalize(p.join(base, input));
  }

  static Future<String> _readFile(String path, String base) async {
    final fp = _resolvePath(path, base);
    final f = File(fp);
    if (!await f.exists()) return '文件不存在: $fp';
    try {
      final content = await f.readAsString();
      if (content.length > 50000) return '${content.substring(0, 50000)}\n\n... (截断，共 ${content.length} 字符)';
      return content;
    } catch (e) {
      return '读取文件失败: $e';
    }
  }

  static Future<String> _listDirectory(String? path, String base, {bool recursive = false, int maxDepth = 2}) async {
    final dirPath = _resolvePath(path ?? '', base);
    final dir = Directory(dirPath);
    if (!await dir.exists()) return '目录不存在: $dirPath';
    try {
      return await _tree(dir, '', recursive ? maxDepth : 0);

    } catch (e) {
      return '列目录失败: $e';
    }
  }

  static Future<String> _tree(Directory dir, String prefix, int depth) async {
    final buf = StringBuffer();
    final entities = await dir.list().toList();
    entities.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir && !bIsDir) return -1;
      if (!aIsDir && bIsDir) return 1;
      return p.basename(a.path).compareTo(p.basename(b.path));
    });
    for (int i = 0; i < entities.length; i++) {
      final e = entities[i];
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      final isLast = i == entities.length - 1;
      buf.writeln('$prefix${isLast ? "└── " : "├── "}$name${e is Directory ? "/" : ""}');
      if (e is Directory && depth > 0) {
        buf.write(await _tree(e, '$prefix${isLast ? "    " : "│   "}', depth - 1));
      }
    }
    return buf.toString();
  }

  static Future<String> _searchFiles(String pattern, String? dir, String base) async {
    final sp = _resolvePath(dir ?? '', base);
    try {
      // 直接用 find 在项目内全量按文件名搜索（不遵循 .gitignore，适配多仓库多模块/子模块）。
      // 只在 .java / .kt 源码文件中查询，并排除明显的构建产物目录。
      final pruneDirs = const ['build', '.gradle', '.git', 'node_modules', 'Pods', 'target', '.dart_tool'];
      final args = <String>[
        sp, '-type', 'f',
        '(', '-iname', pattern, ')',
        '(', '-name', '*.java', '-o', '-name', '*.kt', ')',
        for (final d in pruneDirs) ...['-not', '-path', '*/$d/*'],
      ];
      final result = await Process.run('find', args, runInShell: false)
          .timeout(const Duration(seconds: 25));
      if (result.exitCode != 0 && (result.stderr?.toString().isNotEmpty ?? false)) {
        return '搜索失败: ${result.stderr}';
      }
      var out = (result.stdout as String).trim();
      if (out.isEmpty) {
        // 兜底：用 glob 通配符模糊匹配文件名包含关键词的文件
        final p2 = pattern.replaceAll(RegExp(r'\*'), '');
        if (p2.isNotEmpty) {
          final args2 = <String>[
            sp, '-type', 'f',
            '(', '-iname', '*$p2*', ')',
            '(', '-name', '*.java', '-o', '-name', '*.kt', ')',
          ];
          for (final d in const ['build', '.gradle', '.git', 'node_modules', 'Pods', 'target', '.dart_tool']) {
            args2.addAll(['-not', '-path', '*/$d/*']);
          }
          final r2 = await Process.run('find', args2, runInShell: false)
              .timeout(const Duration(seconds: 25));
          out = (r2.stdout as String).trim();
        }
      }
      if (out.isEmpty) return '未找到匹配 "$pattern" 的文件';
      final lines = out.split('\n');
      if (lines.length > 100) return '${lines.take(100).join('\n')}\n\n... (共 ${lines.length} 个结果)';
      return out;
    } on TimeoutException {
      return '文件搜索超时，请指定更具体的目录或文件名。';
    } catch (e) {
      return '搜索失败: $e';
    }
  }

  /// 搜索时应跳过的噪声目录（构建产物、版本控制、依赖、IDE 等）。
  static const _excludeDirs = [
    '.git', '.gradle', '.idea', '.vscode', 'build', 'node_modules',
    '.dart_tool', 'Pods', '.hg', '.svn', '.agents', '.claude',
  ];

  static Future<String> _grep(String query, String? path, String base, {String? fileTypes, int maxResults = 30}) async {
    final sp = _resolvePath(path ?? '', base);
    try {
      // 优先使用 ripgrep（rg）：默认跳过 .git/二进制/忽略文件，速度极快。
      final rgAvailable = await Process.run('which', ['rg']).then((r) => r.exitCode == 0).catchError((_) => false);
      if (rgAvailable) {
        // --no-ignore：不遵循 .gitignore，适配多仓库多模块/子模块（业务源码可能被忽略）。
        final args = <String>['rg', '-n', '--no-heading', '--no-ignore', '--color=never',
          '-m', maxResults.toString(),
          for (final d in _excludeDirs) ...['--glob', '!**/$d/**'],
        ];
        if (fileTypes != null && fileTypes.isNotEmpty) {
          for (final ext in fileTypes.split(',')) {
            args.addAll(['--glob', '*${ext.trim()}']);
          }
        }
        args.addAll([query, sp]);
        final result = await Process.run(args.first, args.sublist(1),
            runInShell: false).timeout(const Duration(seconds: 25));
        if (result.exitCode > 1) return '搜索异常: ${result.stderr}';
        final out = (result.stdout as String).trim();
        if (out.isEmpty) return '未找到匹配 "$query" 的内容';
        return out.length > 12000 ? '${out.substring(0, 12000)}\n...(结果截断)' : out;
      }

      // 回退：系统 grep，显式排除噪声目录并加超时，避免扫描大仓库卡死。
      final args = <String>['grep', '-rn', '-I', '--color=never',
        '-m', maxResults.toString(),
        for (final d in _excludeDirs) ...['--exclude-dir=$d'],
      ];
      if (fileTypes != null && fileTypes.isNotEmpty) {
        for (final ext in fileTypes.split(',')) {
          args.addAll(['--include', '*${ext.trim()}']);
        }
      }
      args.addAll([query, sp]);
      final result = await Process.run(args.first, args.sublist(1),
          runInShell: false).timeout(const Duration(seconds: 25));
      if (result.exitCode > 1) return '搜索异常: ${result.stderr}';
      final out = (result.stdout as String).trim();
      if (out.isEmpty) return '未找到匹配 "$query" 的内容';
      return out.length > 12000 ? '${out.substring(0, 12000)}\n...(结果截断)' : out;
    } on TimeoutException {
      return '搜索超时（仓库较大），请用更精确的关键词或指定子目录后重试。';
    } catch (e) {
      return 'grep 失败: $e';
    }
  }

  static Future<String> _runShell(String command, String base, {int timeoutSec = 30}) async {
    // 安全检查：拒绝危险命令
    final dangerous = RegExp(r'\b(rm\s+-rf|sudo|chmod\s+777|:(){|mkfs|dd\s+if=|>/dev/sd|wget\s+-O\s+/etc|curl.*\|.*sh)\b');
    if (dangerous.hasMatch(command)) {
      return '拒绝执行危险命令。只允许只读类操作和安全的读写操作。';
    }
    try {
      final result = await Process.run(
        Platform.isWindows ? 'cmd' : 'bash',
        [Platform.isWindows ? '/c' : '-c', command],
        workingDirectory: base,
        runInShell: false,
      ).timeout(Duration(seconds: timeoutSec));
      final out = (result.stdout as String).trim();
      final err = (result.stderr as String).trim();
      final buf = StringBuffer();
      if (out.isNotEmpty) buf.writeln(out);
      if (err.isNotEmpty) buf.writeln(err);
      if (result.exitCode != 0) buf.writeln('(exit code: ${result.exitCode})');
      return buf.toString().isEmpty ? '(无输出)' : buf.toString();
    } catch (e) {
      return '执行失败: $e';
    }
  }

  static Future<String> _writeFile(String path, String content, String base) async {
    final fp = _resolvePath(path, base);
    try {
      final f = File(fp);
      await f.parent.create(recursive: true);
      await f.writeAsString(content, flush: true);
      return '已写入: $fp (${content.length} 字符)';
    } catch (e) {
      return '写入失败: $e';
    }
  }

  static String _formatJson(dynamic data) {
    try {
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return data.toString();
    }
  }
}
