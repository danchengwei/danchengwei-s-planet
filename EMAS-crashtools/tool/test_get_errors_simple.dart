// 测试 GetErrors API（简化版本）
import 'dart:convert';
import 'dart:io';

import 'package:crash_emas_tool/aliyun/emas_appmonitor_client.dart';
import 'package:crash_emas_tool/aliyun/form_flatten.dart';
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

  stdout.writeln('=== 测试 GetErrors API（简化版）===\n');
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
    // 第一步：先调用 GetIssues 获取一个 DigestHash
    stdout.writeln('📋 步骤 1：调用 GetIssues 获取错误列表和 DigestHash...');
    final issuesResult = await client.getIssues(
      appKey: ak,
      bizModule: 'crash',
      startTimeMs: startMs,
      endTimeMs: endMs,
      pageIndex: 1,
      pageSize: 5,
      orderBy: 'ErrorCount',
      orderType: 'desc',
      os: 'android',
    );

    if (issuesResult.items.isEmpty) {
      stderr.writeln('❌ 没有获取到错误列表，无法测试 GetErrors');
      exitCode = 1;
      return;
    }

    stdout.writeln('✅ GetIssues 成功！获取到 ${issuesResult.items.length} 条记录\n');

    // 获取第一个 DigestHash
    final firstItem = issuesResult.items[0];
    final testDigestHash = firstItem.digestHash;
    
    if (testDigestHash == null || testDigestHash.isEmpty) {
      stderr.writeln('❌ 第一个错误项没有 DigestHash');
      exitCode = 1;
      return;
    }

    stdout.writeln('📌 使用 DigestHash: $testDigestHash');
    stdout.writeln('   ErrorType: ${firstItem.errorType}');
    stdout.writeln('   ErrorCount: ${firstItem.errorCount}');
    stdout.writeln('');

    // 第二步：打印 GetErrors 请求体
    stdout.writeln('📋 步骤 2：准备 GetErrors 请求...');
    final reqBody = EmasAppMonitorClient.buildGetErrorsBody(
      appKey: ak,
      bizModule: 'crash',
      startTimeMs: startMs,
      endTimeMs: endMs,
      pageIndex: 1,
      pageSize: 10,
      os: 'android',
      digestHash: testDigestHash,
    );
    
    stdout.writeln('📤 请求体参数：');
    const jsonEnc = JsonEncoder.withIndent('  ');
    stdout.writeln(jsonEnc.convert(reqBody));
    stdout.writeln('');
    
    // 打印扁平化后的表单参数
    final flatMap = <String, String>{};
    flattenToStringMap(flatMap, reqBody);
    stdout.writeln('📤 扁平化后的表单参数：');
    final keys = flatMap.keys.toList()..sort();
    for (final k in keys) {
      stdout.writeln('  $k = ${flatMap[k]}');
    }
    stdout.writeln('');
    
    // 第三步：调用 GetErrors API
    stdout.writeln('🔄 调用 GetErrors API...');
    final result = await client.getErrorsRaw(
      appKey: ak,
      bizModule: 'crash',
      startTimeMs: startMs,
      endTimeMs: endMs,
      pageIndex: 1,
      pageSize: 10,
      os: 'android',
      digestHash: testDigestHash,
    );

    stdout.writeln('✅ 成功！\n');
    stdout.writeln('完整响应：');
    const jsonEnc2 = JsonEncoder.withIndent('  ');
    stdout.writeln(jsonEnc2.convert(result));

    exitCode = 0;
  } catch (e) {
    stderr.writeln('❌ 失败: $e');
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
