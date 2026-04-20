// 测试所有四个 API
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
  // 使用更广泛的时间范围，从90天前开始
  final startMs = todayStart.subtract(const Duration(days: 90)).millisecondsSinceEpoch;
  final endMs = todayStart.millisecondsSinceEpoch - 1;

  stdout.writeln('=== 测试所有四个 API ===\n');
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
    // 1. 测试 GetIssues API
    stdout.writeln('\n' + '=' * 80);
    stdout.writeln('1. 测试 GetIssues API');
    stdout.writeln('=' * 80);
    final issuesResult = await client.getIssues(
      appKey: ak,
      bizModule: 'crash',
      os: 'android',
      startTimeMs: startMs,
      endTimeMs: endMs,
      pageIndex: 1,
      pageSize: 5,
      orderBy: 'ErrorCount',
      orderType: 'desc',
    );
    stdout.writeln('✅ GetIssues 成功！');
    stdout.writeln('Total: ${issuesResult.total}');
    stdout.writeln('Items 数量: ${issuesResult.items.length}');
    if (issuesResult.items.isNotEmpty) {
      stdout.writeln('第一个项目: ${issuesResult.items[0].errorName}');
      stdout.writeln('DigestHash: ${issuesResult.items[0].digestHash}');
    }

    // 获取第一个 DigestHash 用于测试其他接口
    String? testDigestHash;
    if (issuesResult.items.isNotEmpty) {
      testDigestHash = issuesResult.items[0].digestHash;
      stdout.writeln('\n使用第一个 DigestHash 进行后续测试: $testDigestHash');
    }

    // 2. 测试 GetIssue API
    if (testDigestHash != null && testDigestHash.isNotEmpty) {
      stdout.writeln('\n' + '=' * 80);
      stdout.writeln('2. 测试 GetIssue API');
      stdout.writeln('=' * 80);
      final issueResult = await client.getIssue(
        appKey: ak,
        bizModule: 'crash',
        os: 'android',
        digestHash: testDigestHash,
        startTimeMs: startMs,
        endTimeMs: endMs,
      );
      stdout.writeln('✅ GetIssue 成功！');
      stdout.writeln('Response keys: ${issueResult.keys}');
    }

    // 3. 测试 GetErrors API（需要 DigestHash）
    if (testDigestHash != null && testDigestHash.isNotEmpty) {
      stdout.writeln('\n' + '=' * 80);
      stdout.writeln('3. 测试 GetErrors API');
      stdout.writeln('=' * 80);
      try {
        final errorsResult = await client.getErrorsRaw(
          appKey: ak,
          bizModule: 'crash',
          os: 'android',
          startTimeMs: startMs,
          endTimeMs: endMs,
          pageIndex: 1,
          pageSize: 10,
          digestHash: testDigestHash,
        );
        stdout.writeln('✅ GetErrors 成功！');
        if (errorsResult.containsKey('Model')) {
          final model = errorsResult['Model'];
          if (model is Map) {
            stdout.writeln('Total: ${model['Total'] ?? 0}');
            stdout.writeln('Pages: ${model['Pages'] ?? 0}');
            stdout.writeln('Items 数量: ${(model['Items'] as List?)?.length ?? 0}');
          }
        }
        stdout.writeln('Response keys: ${errorsResult.keys}');
      } catch (e) {
        stdout.writeln('⚠️ GetErrors 失败: $e');
      }
    } else {
      stdout.writeln('\n⚠️ 跳过 GetErrors 测试（缺少 DigestHash）');
    }

    // 4. 测试 GetError API（需要具体的 ClientTime 和 Uuid，这里使用 GetErrors 获取的测试值）
    stdout.writeln('\n' + '=' * 80);
    stdout.writeln('4. 测试 GetError API');
    stdout.writeln('=' * 80);
    final clientTime = DateTime.now().millisecondsSinceEpoch;
    try {
      final errorResult = await client.getErrorRaw(
        appKey: ak,
        clientTime: clientTime,
        os: 'android',
        uuid: 'test_uuid',
        did: 'test_did',
        bizModule: 'crash',
        digestHash: testDigestHash,
      );
      stdout.writeln('✅ GetError 成功！');
      if (errorResult.containsKey('Model')) {
        final model = errorResult['Model'];
        if (model is Map) {
          stdout.writeln('Uuid: ${model['Uuid']}');
          stdout.writeln('ClientTime: ${model['ClientTime']}');
          stdout.writeln('Os: ${model['Os']}');
        }
      }
      stdout.writeln('Response keys: ${errorResult.keys}');
    } catch (e) {
      stdout.writeln('⚠️ GetError 失败（需要有效的 ClientTime 和 Uuid）: $e');
    }

    stdout.writeln('\n' + '=' * 80);
    stdout.writeln('所有 API 测试完成！');
    stdout.writeln('=' * 80);

    exitCode = 0;
  } catch (e) {
    stderr.writeln('❌ 测试失败: $e');
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
