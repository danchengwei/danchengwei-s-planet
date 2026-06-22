import 'dart:io';
import 'dart:convert';

/// Baymax HTML 报告中单个崩溃项（对齐 skills 中 parse_html_fast.py 的输出格式）
class BaymaxCrashItem {
  final String digestHash;
  final String title;
  final int affectedDevices;
  final int errorCount;
  final double errorRate;
  final String appVersion;
  final List<String> stackTop; // Top 3 stack frames
  final String crashType; // 'java' or 'native'

  BaymaxCrashItem({
    required this.digestHash,
    required this.title,
    required this.affectedDevices,
    required this.errorCount,
    required this.errorRate,
    required this.appVersion,
    required this.stackTop,
    required this.crashType,
  });

  Map<String, dynamic> toJson() => {
    'digest_hash': digestHash,
    'title': title,
    'affected_devices': affectedDevices,
    'error_count': errorCount,
    'error_rate': errorRate,
    'version': appVersion,
    'stack_top': stackTop,
    'type': crashType,
  };

  @override
  String toString() => 'BaymaxCrashItem($digestHash, type=$crashType, count=$errorCount)';
}

/// Baymax HTML 报告整体统计（对齐 skills 中 parse_html_fast.py 的输出格式）
class BaymaxReportSummary {
  final List<BaymaxCrashItem> javaCrashes;
  final List<BaymaxCrashItem> nativeCrashes;
  final String sourceFilePath;

  BaymaxReportSummary({
    required this.javaCrashes,
    required this.nativeCrashes,
    this.sourceFilePath = '',
  });

  int get totalCrashItems => javaCrashes.length + nativeCrashes.length;

  double get javaCrashPercent {
    final total = totalCrashItems;
    if (total == 0) return 0;
    return (javaCrashes.length / total) * 100;
  }

  double get nativeCrashPercent {
    final total = totalCrashItems;
    if (total == 0) return 0;
    return (nativeCrashes.length / total) * 100;
  }

  Map<String, dynamic> toJson() => {
    'java_crashes': javaCrashes.map((c) => c.toJson()).toList(),
    'native_crashes': nativeCrashes.map((c) => c.toJson()).toList(),
    'total': totalCrashItems,
    'java_percent': javaCrashPercent,
    'native_percent': nativeCrashPercent,
    'source_file_path': sourceFilePath,
  };

  @override
  String toString() => 'BaymaxReportSummary(java=$javaCrashPercent%, native=$nativeCrashPercent%, items=$totalCrashItems)';
}

/// Baymax HTML 报告解析器 - 严格遵循 skills 中 parse_html_fast.py 的规范
class BaymaxReportParser {
  /// 通过调用 skills 中的 parse_html_fast.py 脚本来解析 HTML（第一步：快速解析）
  /// 输出：crash_list.json 结构化数据
  /// 注：仅做快速预览，不调用 API，完整分析需要后续调用 batch_full_analysis.py
  static Future<BaymaxReportSummary> parseFile(String filePath) async {
    try {
      // 获取 skills 目录（严格按照 skills SKILL.md 规范：emas-tools-upgrade）
      final skillsDir = '.claude/skills/emas-tools-upgrade';
      final scriptPath = '$skillsDir/scripts/parse_html_fast.py';

      // 验证脚本存在
      final scriptFile = File(scriptPath);
      if (!scriptFile.existsSync()) {
        throw Exception('脚本不存在: $scriptPath（应在 $skillsDir 目录下）');
      }

      // 临时输出文件（存放 crash_list.json）
      final tmpDir = Directory.systemTemp;
      final outputJson = '${tmpDir.path}/crash_list_${DateTime.now().millisecondsSinceEpoch}.json';

      // 执行 Python 脚本（parse_html_fast.py）— 严格遵循 skills SKILL.md 8.1 节规范
      final result = await Process.run(
        'python3',
        [scriptPath, filePath, outputJson],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        throw Exception('脚本执行失败: ${result.stderr}');
      }

      // 读取脚本输出的 JSON 文件
      final outputFile = File(outputJson);
      if (!outputFile.existsSync()) {
        throw Exception('脚本未生成输出文件: $outputJson');
      }

      final jsonContent = await outputFile.readAsString();
      final parsed = jsonDecode(jsonContent) as Map<String, dynamic>;

      // 解析 JSON 为 BaymaxCrashItem 列表（与 parse_html_fast.py 输出格式对齐）
      final javaCrashes = _parseCrashesFromJson(parsed['java'] ?? [], 'java');
      final nativeCrashes = _parseCrashesFromJson(parsed['native'] ?? [], 'native');

      // 清理临时文件
      await outputFile.delete();

      return BaymaxReportSummary(
        javaCrashes: javaCrashes,
        nativeCrashes: nativeCrashes,
        sourceFilePath: filePath,
      );
    } catch (e) {
      throw Exception('HTML 报告解析失败（对齐 skills 规范）: $e');
    }
  }

  /// 从 JSON 格式解析崩溃项列表（对齐 parse_html_fast.py 输出格式）
  static List<BaymaxCrashItem> _parseCrashesFromJson(List<dynamic> crashes, String type) {
    return crashes.map((item) {
      final map = item as Map<String, dynamic>;

      // stack_top 可能是字符串（多行）或已分割的列表，统一转为 List<String>
      List<String> stackTopList = [];
      final stackTop = map['stack_top'];
      if (stackTop != null) {
        if (stackTop is String) {
          stackTopList = stackTop.split('\n').where((s) => s.isNotEmpty).toList();
        } else if (stackTop is List) {
          stackTopList = List<String>.from(stackTop);
        }
      }

      // error_rate 可能是字符串（如 "5.2%"），需要提取数字
      double errorRate = 0.0;
      final rateValue = map['error_rate'];
      if (rateValue != null) {
        if (rateValue is num) {
          errorRate = rateValue.toDouble();
        } else if (rateValue is String) {
          final numStr = rateValue.replaceAll('%', '').trim();
          errorRate = double.tryParse(numStr) ?? 0.0;
        }
      }

      return BaymaxCrashItem(
        digestHash: map['digest_hash'] ?? 'unknown',
        title: map['title'] ?? 'Unknown',
        affectedDevices: (map['affected_devices'] as num?)?.toInt() ?? 0,
        errorCount: (map['error_count'] as num?)?.toInt() ?? 0,
        errorRate: errorRate,
        appVersion: map['version'] ?? 'unknown',
        stackTop: stackTopList,
        crashType: type,
      );
    }).toList();
  }
}
