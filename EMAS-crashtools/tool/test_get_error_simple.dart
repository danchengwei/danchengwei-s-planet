// 测试 GetError API（获取单个错误详情）
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

  stdout.writeln('=== 测试 GetError API（获取错误详情）===\n');
  stdout.writeln('Region: ${cfg.region.trim()}');
  stdout.writeln('AppKey: $ak');
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
    // 第一步：调用 GetIssues 获取 DigestHash
    stdout.writeln('📋 步骤 1：调用 GetIssues 获取错误列表...');
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
      stderr.writeln('❌ 没有获取到错误列表');
      exitCode = 1;
      return;
    }

    stdout.writeln('✅ GetIssues 成功！获取到 ${issuesResult.items.length} 条记录\n');
    final firstIssue = issuesResult.items[0];
    final testDigestHash = firstIssue.digestHash;
    
    if (testDigestHash == null || testDigestHash.isEmpty) {
      stderr.writeln('❌ 第一个错误项没有 DigestHash');
      exitCode = 1;
      return;
    }

    stdout.writeln('📌 使用 DigestHash: $testDigestHash');
    stdout.writeln('   ErrorCount: ${firstIssue.errorCount}');
    stdout.writeln('');

    // 第二步：调用 GetErrors 获取错误实例列表
    stdout.writeln('📋 步骤 2：调用 GetErrors 获取错误实例列表...');
    final errorsResult = await client.getErrorsRaw(
      appKey: ak,
      bizModule: 'crash',
      startTimeMs: startMs,
      endTimeMs: endMs,
      pageIndex: 1,
      pageSize: 10,
      os: 'android',
      digestHash: testDigestHash,
    );

    final items = errorsResult['Model']?['Items'] as List<dynamic>?;
    if (items == null || items.isEmpty) {
      stderr.writeln('❌ 没有获取到错误实例');
      exitCode = 1;
      return;
    }

    stdout.writeln('✅ GetErrors 成功！获取到 ${items.length} 条错误实例\n');

    // 获取第一个错误实例的信息
    final firstError = items[0] as Map<String, dynamic>;
    final clientTime = firstError['ClientTime'] as int?;
    final uuid = firstError['Uuid']?.toString();
    final did = firstError['Did']?.toString();

    if (clientTime == null || uuid == null) {
      stderr.writeln('❌ 错误实例缺少 ClientTime 或 Uuid');
      exitCode = 1;
      return;
    }

    stdout.writeln('📌 使用错误实例信息：');
    stdout.writeln('   ClientTime: $clientTime');
    stdout.writeln('   Uuid: $uuid');
    stdout.writeln('   Did: ${did ?? "无"}');
    stdout.writeln('');

    // 第三步：打印 GetError 请求体
    stdout.writeln('📋 步骤 3：准备 GetError 请求...');
    final reqBody = EmasAppMonitorClient.buildGetErrorBody(
      appKey: ak,
      clientTime: clientTime,
      did: did,
      os: 'android',
      uuid: uuid,
      bizModule: 'crash',
      digestHash: testDigestHash,
    );

    stdout.writeln('📤 请求体参数：');
    const jsonEnc = JsonEncoder.withIndent('  ');
    stdout.writeln(jsonEnc.convert(reqBody));
    stdout.writeln('');

    // 第四步：调用 GetError API
    stdout.writeln('🔄 调用 GetError API...');
    final errorResult = await client.getErrorRaw(
      appKey: ak,
      clientTime: clientTime,
      did: did,
      os: 'android',
      uuid: uuid,
      bizModule: 'crash',
      digestHash: testDigestHash,
    );

    stdout.writeln('✅ GetError 成功！\n');
    stdout.writeln('完整响应：');
    const jsonEnc2 = JsonEncoder.withIndent('  ');
    stdout.writeln(jsonEnc2.convert(errorResult));

    // 尝试解析 Model
    if (errorResult.containsKey('Model')) {
      final model = errorResult['Model'];
      if (model is Map) {
        stdout.writeln('\n========================================');
        stdout.writeln('解析 Model 数据：');
        stdout.writeln('Uuid: ${model['Uuid']}');
        stdout.writeln('ClientTime: ${model['ClientTime']}');
        stdout.writeln('Did: ${model['Did']}');
        stdout.writeln('Os: ${model['Os']}');
        if (model.containsKey('Stack')) {
          final stack = model['Stack'] as String?;
          if (stack != null && stack.isNotEmpty) {
            stdout.writeln('\n堆栈信息（前 500 字符）：');
            stdout.writeln(stack.substring(0, stack.length > 500 ? 500 : stack.length));
          }
        }
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
