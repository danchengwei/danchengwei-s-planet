// EMAS AppMonitor OpenAPI 连通性探测（GetIssues 最小请求）。
//
// 用法（在 EMAS-crashtools 目录下）：
//   dart run tool/emas_openapi_probe.dart
//   dart run tool/emas_openapi_probe.dart /path/to/crash-tools-test-config.json
//
// 默认读取顺序：命令行参数 → 环境变量 CRASH_TOOLS_TEST_CONFIG → 当前目录 crash-tools-test-config.json
//
// 与桌面端一致：使用 lib 内 newOutboundHttpClient()（IO 版 HttpClient，遵循 HTTPS_PROXY 等环境变量）。

import 'dart:convert';
import 'dart:io';

import 'package:crash_emas_tool/aliyun/emas_appmonitor_client.dart';
import 'package:crash_emas_tool/app_controller.dart';
import 'package:crash_emas_tool/models/tool_config.dart';
import 'package:crash_emas_tool/services/http_retry_policy.dart';
import 'package:crash_emas_tool/services/outbound_http_client_for_config.dart';
import 'package:crash_emas_tool/services/security_redaction.dart';

Future<void> main(List<String> args) async {
  final path = _resolveConfigPath(args);
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

  // 与 App 内「7 天」芯片一致：自然日、最新一天为昨天（见 AppController.calendarInclusiveRangeBounds）。
  final bounds = AppController.calendarInclusiveRangeBounds(calendarDaysInclusive: 7);
  final startMs = bounds.$1;
  final endMs = bounds.$2;
  final nameQ = cfg.emasListNameQuery.trim().isEmpty ? null : cfg.emasListNameQuery.trim();

  stdout.writeln('目标主机：emas-appmonitor.${cfg.region.trim()}.aliyuncs.com');
  stdout.writeln('GetIssues：AppKey=$ak BizModule=${cfg.bizModule.trim()} Os=${cfg.os.trim()}');
  if (nameQ != null) stdout.writeln('Name：$nameQ');

  final httpClient = newOutboundHttpClient();
  final client = EmasAppMonitorClient(
    accessKeyId: cfg.accessKeyId.trim(),
    accessKeySecret: cfg.accessKeySecret.trim(),
    regionId: cfg.region.trim(),
    httpClient: httpClient,
  );
  try {
    final r = await client.getIssues(
      appKey: ak,
      bizModule: cfg.bizModule.trim(),
      os: cfg.os.trim(),
      startTimeMs: startMs,
      endTimeMs: endMs,
      pageIndex: 1,
      pageSize: 1,
      name: nameQ,
    );
    stdout.writeln('成功：时间范围内聚合总数 total=${r.total}（本次仅拉取 1 条用于探测）');
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
''';
