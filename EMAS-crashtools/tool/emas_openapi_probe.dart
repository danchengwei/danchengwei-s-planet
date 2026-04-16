// 阿里云 EMAS **应用监控**（OpenAPI 产品 emas-appmonitor，控制台「应用监控」入口）探测脚本。
//
// 默认：GetIssues 分页，打印每页完整 JSON，并累加 Items[*].ErrorCount（近似「崩溃次数」）。
// 单条：--digest=<问题ID> 时走 GetIssue（控制台列表里的编号一般即 DigestHash），打印完整 JSON。
//
// 用法（在 EMAS-crashtools 目录下）：
//   dart run tool/emas_openapi_probe.dart
//   dart run tool/emas_openapi_probe.dart /path/to/crash-tools-test-config.json
//   dart run tool/emas_openapi_probe.dart config.json --no-package
//   dart run tool/emas_openapi_probe.dart config.json --digest=16BDPF82YWSZS
//   dart run tool/emas_openapi_probe.dart config.json --digest=16BDPF82YWSZS --calendar-days=30
//
// 默认读取顺序：命令行参数 → 环境变量 CRASH_TOOLS_TEST_CONFIG → 当前目录 crash-tools-test-config.json
//
// 与桌面端一致：使用 lib 内 newOutboundHttpClient()（IO 版 HttpClient，遵循 HTTPS_PROXY 等环境变量）。

import 'dart:convert';
import 'dart:io';

import 'package:crash_emas_tool/aliyun/emas_appmonitor_client.dart';
import 'package:crash_emas_tool/models/tool_config.dart';
import 'package:crash_emas_tool/services/http_retry_policy.dart';
import 'package:crash_emas_tool/services/outbound_http_client_for_config.dart';
import 'package:crash_emas_tool/services/security_redaction.dart';

Future<void> main(List<String> args) async {
  final flags = args.where((a) => a.startsWith('--')).map((a) => a.trim()).toSet();
  final pos = args.where((a) => !a.startsWith('--')).toList();
  final omitPackage = flags.contains('--no-package');
  final omitName = flags.contains('--no-name');
  final digestHash = _flagValue(flags, 'digest').trim();
  final calendarDays = _parseCalendarDays(flags);
  final path = _resolveConfigPath(pos);
  final file = File(path);
  if (!await file.exists()) {
    stderr.writeln('未找到配置文件：$path');
    stderr.writeln(_usage);
    exitCode = 2;
    return;
  }

  Map<String, dynamic> root;
  try {
    final text = await file.readAsString();
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      stderr.writeln('配置须为 JSON 对象');
      exitCode = 2;
      return;
    }
    root = Map<String, dynamic>.from(decoded);
    root.remove('__comment');
  } catch (e) {
    stderr.writeln('读取或解析 JSON 失败：$e');
    exitCode = 2;
    return;
  }

  final cfg = ToolConfig.fromJson(root);
  final miss = cfg.validateEmas();
  if (miss.isNotEmpty) {
    stderr.writeln('EMAS 配置不完整，缺少：${miss.join('、')}');
    exitCode = 2;
    return;
  }
  final ak = cfg.appKeyAsInt;
  if (ak == null) {
    stderr.writeln('appKey 须为数字');
    exitCode = 2;
    return;
  }

  // 自然日窗口：最新完整日为昨天（与 AppController.calendarInclusiveRangeBounds 同源）；天数由 --calendar-days 指定，默认 7。
  final bounds = _calendarInclusiveRangeBounds(calendarDaysInclusive: calendarDays);
  final startMs = bounds.$1;
  final endMs = bounds.$2;
  final nameQ = () {
    if (omitName) return null;
    final n = _optionalLegacyAppVersionFromImportRoot(root);
    if (n == null || n.isEmpty) return null;
    return n;
  }();

  stdout.writeln(
    '时间范围（本地自然日，共 $calendarDays 天，不含今天）：${_ymdLocal(startMs)} ～ ${_ymdLocal(endMs)}',
  );
  stdout.writeln('目标主机：emas-appmonitor.${cfg.region.trim()}.aliyuncs.com');
  if (digestHash.isNotEmpty) {
    stdout.writeln('模式：GetIssue（DigestHash=$digestHash）');
  } else {
    stdout.writeln('模式：GetIssues');
  }
  stdout.writeln('AppKey=$ak BizModule=${cfg.bizModule.trim()} Os=${cfg.os.trim()}');
  if (omitName) stdout.writeln('应用版本（GetIssues Name）：已用 --no-name 跳过');
  if (nameQ != null) stdout.writeln('应用版本（GetIssues Name）：$nameQ');
  final pkgQ = cfg.appPackageNameForOpenApi;
  if (omitPackage) {
    stdout.writeln('应用包名（GetIssues PackageName）：已用 --no-package 跳过');
  } else if (pkgQ != null) {
    stdout.writeln('应用包名（GetIssues PackageName）：$pkgQ');
  }

  final httpClient = newOutboundHttpClient();
  final client = EmasAppMonitorClient(
    accessKeyId: cfg.accessKeyId.trim(),
    accessKeySecret: cfg.accessKeySecret.trim(),
    regionId: cfg.region.trim(),
    httpClient: httpClient,
  );
  const jsonEnc = JsonEncoder.withIndent('  ');
  try {
    if (digestHash.isNotEmpty) {
      final issueJson = await client.getIssue(
        appKey: ak,
        bizModule: cfg.bizModule.trim(),
        os: cfg.os.trim(),
        digestHash: digestHash,
        startTimeMs: startMs,
        endTimeMs: endMs,
        packageName: omitPackage ? null : pkgQ,
      );
      stdout.writeln('');
      stdout.writeln('========== GetIssue 原始响应 ==========');
      stdout.writeln(jsonEnc.convert(issueJson));
      exitCode = 0;
      return;
    }

    const probePageSize = 100;
    const maxPages = 500;
    var sumErrorCount = 0;
    var totalPagesToFetch = 1;
    for (var page = 1; page <= totalPagesToFetch && page <= maxPages; page++) {
      final raw = await client.getIssuesRaw(
        appKey: ak,
        bizModule: cfg.bizModule.trim(),
        os: cfg.os.trim(),
        startTimeMs: startMs,
        endTimeMs: endMs,
        pageIndex: page,
        pageSize: probePageSize,
        name: nameQ,
        packageName: omitPackage ? null : pkgQ,
      );
      stdout.writeln('');
      stdout.writeln('========== GetIssues 原始响应（第 $page 页 / 每页 $probePageSize 条）==========');
      stdout.writeln(jsonEnc.convert(raw));

      final parsed = GetIssuesResult.fromJson(raw);
      for (final row in parsed.items) {
        sumErrorCount += row.errorCount ?? 0;
      }
      if (page == 1) {
        totalPagesToFetch = _inferTotalPages(parsed, probePageSize);
        stdout.writeln('');
        stdout.writeln(
          '解析摘要：聚合问题总数 Model.Total=${parsed.total}；'
          '服务端分页数 Model.Pages=${parsed.pages ?? '(缺省，已按 Total 推算 $totalPagesToFetch 页)'}',
        );
      }
    }
    if (totalPagesToFetch > maxPages) {
      stderr.writeln(
        '警告：推算总页数 $totalPagesToFetch 超过上限 $maxPages，仅拉取前 $maxPages 页；'
        'ErrorCount 累加可能小于真实值。可在脚本中调高 maxPages。',
      );
    }
    stdout.writeln('');
    stdout.writeln(
      '---------- 汇总（用于对齐控制台「崩溃次数」类指标）----------\n'
      '本时间窗内，GetIssues 各页 Items[*].ErrorCount 累加 = $sumErrorCount\n'
      '说明：该值为接口返回的各聚合行次数之和，一般可近似崩溃/异常上报次数；'
      '若与控制台 707 等数字仍有偏差，多为时间范围、包名/版本筛选或大盘统计口径差异。',
    );
    exitCode = 0;
  } on EmasApiException catch (e) {
    stderr.writeln('EMAS 业务错误：${e.code ?? ''} ${e.message}');
    if (e.requestId != null) stderr.writeln('RequestId：${e.requestId}');
    exitCode = 1;
  } on ApiRetryExhaustedException catch (e) {
    stderr.writeln(
      '请求失败（已重试 ${e.attempts} 次）：${userFacingNetworkError(e.cause)}',
    );
    exitCode = 1;
  } catch (e) {
    stderr.writeln('请求失败：${userFacingNetworkError(e)}');
    exitCode = 1;
  } finally {
    client.close();
  }
}

String _ymdLocal(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: false);
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

String _resolveConfigPath(List<String> args) {
  if (args.isNotEmpty && args.first.trim().isNotEmpty) {
    return args.first.trim();
  }
  final env = Platform.environment['CRASH_TOOLS_TEST_CONFIG']?.trim();
  if (env != null && env.isNotEmpty) return env;
  return 'crash-tools-test-config.json';
}

const _usage = '''
请提供与 ToolConfig 字段一致的 JSON（至少含 accessKeyId、accessKeySecret、region、appKey、os、bizModule）。

示例：
  dart run tool/emas_openapi_probe.dart ./crash-tools-test-config.json
  dart run tool/emas_openapi_probe.dart ./crash-tools-test-config.json --no-package
  dart run tool/emas_openapi_probe.dart ./crash-tools-test-config.json --digest=16BDPF82YWSZS
  dart run tool/emas_openapi_probe.dart ./crash-tools-test-config.json --digest=16BDPF82YWSZS --calendar-days=30 --no-package
''';

String _flagValue(Set<String> flags, String name) {
  final prefix = '--$name=';
  for (final f in flags) {
    if (f.startsWith(prefix)) return f.substring(prefix.length);
  }
  return '';
}

int _parseCalendarDays(Set<String> flags) {
  final raw = _flagValue(flags, 'calendar-days');
  final alt = raw.isNotEmpty ? raw : _flagValue(flags, 'days');
  if (alt.isEmpty) return 7;
  final n = int.tryParse(alt.trim());
  if (n == null || n < 1) return 7;
  if (n > 365) return 365;
  return n;
}

/// 推算 GetIssues 总页数（优先 Model.Pages，否则用 Total 与 pageSize）。
int _inferTotalPages(GetIssuesResult r, int pageSize) {
  if (pageSize < 1) return 1;
  final p = r.pages;
  if (p != null && p > 0) return p;
  final t = r.total;
  if (t <= 0) return 1;
  return (t + pageSize - 1) ~/ pageSize;
}

/// 自然日窗口（共 [calendarDaysInclusive] 天）：最新一天为「昨天」（本地时区）。
/// 与桌面端 `AppController.calendarInclusiveRangeBounds` 保持一致，供纯 VM 下 `dart run` 使用。
(int startMs, int endMs) _calendarInclusiveRangeBounds({
  required int calendarDaysInclusive,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final todayStart = DateTime(clock.year, clock.month, clock.day);
  final yesterdayStart = todayStart.subtract(const Duration(days: 1));
  if (calendarDaysInclusive < 1) {
    final e = DateTime(yesterdayStart.year, yesterdayStart.month, yesterdayStart.day, 23, 59, 59, 999);
    final t = e.millisecondsSinceEpoch;
    return (t, t);
  }
  final rangeStart = yesterdayStart.subtract(Duration(days: calendarDaysInclusive - 1));
  final rangeEnd = DateTime(yesterdayStart.year, yesterdayStart.month, yesterdayStart.day, 23, 59, 59, 999);
  return (rangeStart.millisecondsSinceEpoch, rangeEnd.millisecondsSinceEpoch);
}

/// 从导入 JSON 读取应用版本（GetIssues `Name`），与 `TestLocalConfigLoader.optionalLegacyAppVersionFromImportRoot` 一致。
String? _optionalLegacyAppVersionFromImportRoot(Map<String, dynamic> root) {
  String? pickVersion(Map<String, dynamic> m) {
    for (final k in const ['emasAppVersion', 'appVersion', 'applicationVersion', 'versionName']) {
      final v = m[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  final direct = pickVersion(root);
  if (direct != null) return direct;

  final projects = root['projects'];
  if (projects is! List<dynamic>) return null;
  final activeId = root['activeProjectId']?.toString();
  Map<String, dynamic>? configActive;
  Map<String, dynamic>? configFirst;
  for (final e in projects) {
    if (e is! Map) continue;
    final em = Map<String, dynamic>.from(e);
    final rawCfg = em['config'];
    Map<String, dynamic>? cfg;
    if (rawCfg is Map<String, dynamic>) {
      cfg = rawCfg;
    } else if (rawCfg is Map) {
      cfg = Map<String, dynamic>.from(rawCfg);
    }
    if (cfg == null) continue;
    configFirst ??= cfg;
    if (activeId != null && em['id']?.toString() == activeId) {
      configActive = cfg;
      break;
    }
  }
  final use = configActive ?? configFirst;
  if (use == null) return null;
  return pickVersion(use);
}
