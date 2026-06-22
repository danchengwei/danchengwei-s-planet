// 测试 GetIssues API（简化版本，只使用基本参数）
import 'dart:convert';
import 'dart:io';

import 'package:crash_emas_tool/aliyun/emas_appmonitor_client.dart';
import 'package:crash_emas_tool/models/tool_config.dart';
import 'package:crash_emas_tool/services/outbound_http_client_for_config.dart';

Future<void> main() async {
  final configFile = File('crash-tools-test-config.json');
  if (!await configFile.exists()) {
    stderr.writeln('❌ 配置文件不存在');
    exit(1);
  }

  final configText = await configFile.readAsString();
  final configJson = jsonDecode(configText) as Map<String, dynamic>;
  final cfg = ToolConfig.fromJson(configJson);

  final ak = cfg.appKeyAsInt;
  if (ak == null) {
    stderr.writeln('❌ appKey 无效');
    exit(1);
  }

  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final startMs = todayStart.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
  final endMs = todayStart.millisecondsSinceEpoch - 1;

  stdout.writeln('=== 测试 GetIssues API（简化版）===\n');
  stdout.writeln('Region: ${cfg.region.trim()}');
  stdout.writeln('AppKey: $ak');
  stdout.writeln('OS: android');
  stdout.writeln('时间范围: ${_ymdLocal(startMs)} ~ ${_ymdLocal(endMs)}');
  stdout.writeln('');

  final httpClient = newOutboundHttpClient();
  final client = EmasAppMonitorClient(
    accessKeyId: cfg.accessKeyId.trim(),
    accessKeySecret: cfg.accessKeySecret.trim(),
    regionId: cfg.region.trim(),
    httpClient: httpClient,
  );

  try {
    // 先打印请求体，看看参数格式
    final reqBody = EmasAppMonitorClient.buildGetIssuesBody(
      appKey: ak,
      bizModule: 'crash',
      os: 'android',
      startTimeMs: startMs,
      endTimeMs: endMs,
      pageIndex: 1,
      pageSize: 10,
      orderBy: 'ErrorCount',
      orderType: 'desc',
    );
    
    stdout.writeln('📤 请求体参数：');
    const jsonEnc = JsonEncoder.withIndent('  ');
    stdout.writeln(jsonEnc.convert(reqBody));
    stdout.writeln('');
    
    // 调用 API（使用必填参数 + 常用可选参数）
    stdout.writeln('🔄 调用 GetIssues API...');
    final result = await client.getIssuesRaw(
      appKey: ak,
      bizModule: 'crash',
      os: 'android',
      startTimeMs: startMs,
      endTimeMs: endMs,
      pageIndex: 1,
      pageSize: 10,
      orderBy: 'ErrorCount',
      orderType: 'desc',
    );

    stdout.writeln('✅ 成功！\n');
    stdout.writeln('完整响应：');
    stdout.writeln(jsonEnc.convert(result));

    // 尝试解析结果
    stdout.writeln('\n========================================');
    stdout.writeln('解析后的结果：');
    final parsed = GetIssuesResult.fromJson(result);
    stdout.writeln('Total: ${parsed.total}');
    stdout.writeln('Items 数量: ${parsed.items.length}');
    if (parsed.items.isNotEmpty) {
      stdout.writeln('\n前3个错误项：');
      for (var i = 0; i < parsed.items.length && i < 3; i++) {
        final item = parsed.items[i];
        stdout.writeln('  ${i + 1}. ${item.errorName ?? '无名称'}');
        stdout.writeln('     DigestHash: ${item.digestHash ?? '无'}');
        stdout.writeln('     ErrorCount: ${item.errorCount}');
      }
    }

    exitCode = 0;
  } catch (e, stackTrace) {
    stderr.writeln('❌ 失败: $e');
    stderr.writeln('堆栈跟踪:');
    stderr.writeln(stackTrace);
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
