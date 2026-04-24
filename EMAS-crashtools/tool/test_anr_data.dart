// 测试获取 ANR 数据
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

  stdout.writeln('=== 测试获取 ANR 数据 ===\n');
  stdout.writeln('Region: ${cfg.region.trim()}');
  stdout.writeln('AppKey: $ak');
  stdout.writeln('BizModule: ${EmasBizModule.anr} (ANR)');
  stdout.writeln('Os: ${EmasOsType.android}');
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
    // 调用 GetIssues API 获取 ANR 聚合列表
    stdout.writeln('🔄 正在获取 ANR 数据...\n');
    
    final issuesResult = await client.getIssues(
      appKey: ak,
      bizModule: EmasBizModule.anr,  // 使用 ANR 常量
      os: EmasOsType.android,
      startTimeMs: startMs,
      endTimeMs: endMs,
      pageIndex: 1,
      pageSize: 10,
      orderBy: 'ErrorCount',
      orderType: 'desc',
    );

    stdout.writeln('✅ 成功获取 ANR 数据！\n');
    stdout.writeln('=' * 80);
    stdout.writeln('统计信息：');
    stdout.writeln('=' * 80);
    stdout.writeln('总聚合数: ${issuesResult.total}');
    stdout.writeln('返回条目数: ${issuesResult.items.length}');
    stdout.writeln('页码: ${issuesResult.pageNum ?? "N/A"}');
    stdout.writeln('每页大小: ${issuesResult.pageSize ?? "N/A"}');
    stdout.writeln('总页数: ${issuesResult.pages ?? "N/A"}');
    stdout.writeln('');

    if (issuesResult.items.isEmpty) {
      stdout.writeln('⚠️  在指定时间范围内没有找到 ANR 数据');
      stdout.writeln('   可能原因：');
      stdout.writeln('   1. 该应用在最近 7 天内没有 ANR 问题');
      stdout.writeln('   2. 时间范围需要调整');
      stdout.writeln('   3. AppKey 对应的应用可能没有开启 ANR 监控');
    } else {
      stdout.writeln('=' * 80);
      stdout.writeln('ANR 列表（前 ${issuesResult.items.length} 条）：');
      stdout.writeln('=' * 80);
      
      for (var i = 0; i < issuesResult.items.length; i++) {
        final item = issuesResult.items[i];
        stdout.writeln('\n${i + 1}. ${item.errorName ?? "无名称"}');
        stdout.writeln('   DigestHash: ${item.digestHash ?? "无"}');
        stdout.writeln('   发生次数: ${item.errorCount ?? 0}');
        stdout.writeln('   影响设备数: ${item.errorDeviceCount ?? 0}');
        if (item.errorRate != null) {
          stdout.writeln('   错误率: ${item.errorRate!.toStringAsFixed(2)}%');
        }
        if (item.errorDeviceRate != null) {
          stdout.writeln('   影响设备率: ${item.errorDeviceRate!.toStringAsFixed(2)}%');
        }
        
        // 显示堆栈预览（如果有）
        if (item.stack != null && item.stack!.isNotEmpty) {
          final stackLines = item.stack!.split('\n');
          final previewLines = stackLines.take(3).toList();
          stdout.writeln('   堆栈预览:');
          for (final line in previewLines) {
            stdout.writeln('     $line');
          }
          if (stackLines.length > 3) {
            stdout.writeln('     ... (${stackLines.length - 3} 更多行)');
          }
        }
      }

      stdout.writeln('\n' + '=' * 80);
      stdout.writeln('💡 提示：');
      stdout.writeln('=' * 80);
      stdout.writeln('- 可以使用 DigestHash 调用 GetIssue API 获取单个 ANR 聚合的详情');
      stdout.writeln('- 可以使用 GetErrors API 获取 ANR 实例列表');
      stdout.writeln('- 可以调整时间范围获取更多历史数据');
    }

    exitCode = 0;
  } catch (e, stackTrace) {
    stderr.writeln('❌ 获取 ANR 数据失败: $e');
    stderr.writeln('\n堆栈跟踪:');
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
