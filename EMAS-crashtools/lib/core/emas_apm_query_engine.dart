import 'dart:convert';
import 'dart:io';

/// EMAS APM 查询引擎
/// 使用 shell 脚本 (list_top_issues.sh, dig_issue.sh) 查询 EMAS API 数据
class EmasApmQueryEngine {
  /// Skill 目录路径 (包含 scripts/)
  final String skillDir;

  /// EMAS 应用 Key
  final String appKey;

  /// 操作系统类型 (android / iphoneos / harmony)
  final String osType;

  /// 阿里云 AccessKeyId (来自环境或配置文件)
  final String? accessKeyId;

  /// 阿里云 AccessKeySecret (来自环境或配置文件)
  final String? accessKeySecret;

  EmasApmQueryEngine({
    required this.skillDir,
    required this.appKey,
    required this.osType,
    this.accessKeyId,
    this.accessKeySecret,
  });

  /// 获取 Top N 问题
  ///
  /// 返回 JSON 格式的问题列表，每个问题包含:
  /// - digestHash: 问题唯一哈希
  /// - name: 问题名称
  /// - type: 问题类型 (crash / anr / lag / etc)
  /// - count: 错误次数
  /// - errorRate: 错误率
  /// - affectedDeviceCount: 影响的设备数
  /// - bm: 业务模块 (crash / anr / lag / custom / memory_leak / memory_alloc)
  Future<List<Map<String, dynamic>>> getTopIssues({
    required int topN,
    required DateTime startTime,
    required DateTime endTime,
    String orderBy = 'ErrorRate',
    String bizModules = 'crash,anr,lag,custom,memory_leak,memory_alloc',
    String? filterJson,
  }) async {
    final startMs = startTime.millisecondsSinceEpoch;
    final endMs = endTime.millisecondsSinceEpoch;

    final args = [
      '$skillDir/scripts/list_top_issues.sh',
      '--app-key', appKey,
      '--os', osType,
      '--start-time', startMs.toString(),
      '--end-time', endMs.toString(),
      '--top-n', topN.toString(),
      '--order-by', orderBy,
      '--biz-modules', bizModules,
      '--output', 'json',
    ];

    if (filterJson != null && filterJson.isNotEmpty) {
      args.addAll(['--filter-json', filterJson]);
    }

    final result = await Process.run('bash', args);

    if (result.exitCode != 0) {
      throw EmasQueryException(
        'Failed to query Top N issues',
        stderr: result.stderr.toString(),
        exitCode: result.exitCode,
      );
    }

    try {
      final json = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
      final items = json['items'] as List<dynamic>? ?? [];
      return items.cast<Map<String, dynamic>>();
    } catch (e) {
      throw EmasQueryException(
        'Failed to parse Top N response',
        stderr: result.stdout.toString(),
        originalError: e,
      );
    }
  }

  /// 获取单个问题的详情和样本
  ///
  /// 返回包含以下内容的目录路径:
  /// - 01-get-issue.json: 问题聚合数据
  /// - 02-get-errors.json: 样本列表
  /// - samples/: 完整样本数据 (包含堆栈、日志等)
  /// - report.md: 诊断报告
  Future<String> digIssue({
    required String digestHash,
    required String bizModule,
    required DateTime startTime,
    required DateTime endTime,
    int sampleSize = 3,
    String outputDir = '.',
  }) async {
    final startMs = startTime.millisecondsSinceEpoch;
    final endMs = endTime.millisecondsSinceEpoch;

    final args = [
      '$skillDir/scripts/dig_issue.sh',
      '--app-key', appKey,
      '--os', osType,
      '--biz-module', bizModule,
      '--digest-hash', digestHash,
      '--start-time', startMs.toString(),
      '--end-time', endMs.toString(),
      '--sample-size', sampleSize.toString(),
      '--output-dir', outputDir,
    ];

    final result = await Process.run('bash', args);

    if (result.exitCode != 0) {
      throw EmasQueryException(
        'Failed to dig issue: $digestHash',
        stderr: result.stderr.toString(),
        exitCode: result.exitCode,
      );
    }

    // 脚本输出目录路径到 stdout
    final output = result.stdout.toString().trim();
    if (output.isEmpty) {
      throw EmasQueryException(
        'dig_issue.sh did not return output directory path',
        stderr: result.stderr.toString(),
      );
    }

    return output;
  }

  /// 从问题详情目录读取完整堆栈数据
  /// 返回 JSON 格式的堆栈和样本信息
  Future<Map<String, dynamic>> readIssueDetails(String issueDir) async {
    final getIssueFile = File('$issueDir/01-get-issue.json');
    final getErrorsFile = File('$issueDir/02-get-errors.json');

    if (!getIssueFile.existsSync() || !getErrorsFile.existsSync()) {
      throw EmasQueryException(
        'Issue directory missing required files: $issueDir',
        exitCode: 1,
      );
    }

    try {
      final issueJson = jsonDecode(await getIssueFile.readAsString()) as Map<String, dynamic>;
      final errorsJson = jsonDecode(await getErrorsFile.readAsString()) as Map<String, dynamic>;

      return {
        'issue': issueJson,
        'errors': errorsJson,
      };
    } catch (e) {
      throw EmasQueryException(
        'Failed to read issue details from $issueDir',
        originalError: e,
      );
    }
  }

  /// 从样本目录读取单个样本的完整堆栈信息
  Future<Map<String, dynamic>> readSampleStack(String issueDir, String uuid) async {
    final sampleFile = File('$issueDir/samples/$uuid.json');

    if (!sampleFile.existsSync()) {
      throw EmasQueryException(
        'Sample file not found: ${sampleFile.path}',
        exitCode: 1,
      );
    }

    try {
      return jsonDecode(await sampleFile.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      throw EmasQueryException(
        'Failed to parse sample stack: $uuid',
        originalError: e,
      );
    }
  }
}

/// EMAS 查询异常
class EmasQueryException implements Exception {
  final String message;
  final String? stderr;
  final int? exitCode;
  final dynamic originalError;

  EmasQueryException(
    this.message, {
    this.stderr,
    this.exitCode,
    this.originalError,
  });

  @override
  String toString() => 'EmasQueryException: $message\nstderr: $stderr\nexit: $exitCode';
}
