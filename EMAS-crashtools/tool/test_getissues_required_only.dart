// 测试 GetIssues API（只使用必填参数）
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
  // 使用最近 7 天的数据
  final startMs = todayStart.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
  final endMs = todayStart.millisecondsSinceEpoch - 1;

  stdout.writeln('=== 测试 GetIssues API（仅使用必填参数）===\n');
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
    // 仅使用必填参数调用 GetIssues
    stdout.writeln('🔄 正在调用 GetIssues（仅必填参数）...\n');

    final issuesResult = await client.getIssues(
      appKey: ak,
      bizModule: EmasBizModule.crash,
      os: EmasOsType.android,
      startTimeMs: startMs,
      endTimeMs: endMs,
      pageIndex: 1,
      pageSize: 10,
    );

    stdout.writeln('✅ 成功！\n');
    stdout.writeln('=' * 80);
    stdout.writeln('统计结果：');
    stdout.writeln('=' * 80);
    stdout.writeln('总聚合数: ${issuesResult.total}');
    stdout.writeln('返回条目数: ${issuesResult.items.length}');
    stdout.writeln('页码: ${issuesResult.pageNum ?? "N/A"}');
    stdout.writeln('每页大小: ${issuesResult.pageSize ?? "N/A"}');
    stdout.writeln('总页数: ${issuesResult.pages ?? "N/A"}');
    stdout.writeln('');

    if (issuesResult.items.isEmpty) {
      stdout.writeln('⚠️  未找到任何聚合问题');
    } else {
      stdout.writeln('=' * 80);
      stdout.writeln('问题列表（前 ${issuesResult.items.length} 条）：');
      stdout.writeln('=' * 80);

      for (var i = 0; i < issuesResult.items.length; i++) {
        final item = issuesResult.items[i];
        stdout.writeln('\n${i + 1}. ${item.errorName ?? "无名称"}');
        stdout.writeln('   DigestHash: ${item.digestHash ?? "无"}');
        stdout.writeln('   发生次数: ${item.errorCount ?? 0}');
      }
    }
  } catch (e) {
    stderr.writeln('❌ 错误：$e');
    exit(1);
  }
}

String _ymdLocal(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
