// EMAS AppMonitor API 使用示例
// 
// 本文件展示了如何使用扩写后的 EMAS API，包括：
// 1. BizModule 常量的使用
// 2. OsType 常量的使用（当前项目固定使用 android）
// 3. 所有可选参数的说明（暂时不调用）

import 'dart:convert';
import 'dart:io';

import 'package:crash_emas_tool/aliyun/emas_appmonitor_client.dart';
import 'package:crash_emas_tool/models/tool_config.dart';
import 'package:crash_emas_tool/services/outbound_http_client_for_config.dart';

Future<void> main() async {
  // 加载配置
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

  stdout.writeln('=== EMAS API 使用示例 ===\n');
  stdout.writeln('Region: ${cfg.region.trim()}');
  stdout.writeln('AppKey: $ak');
  stdout.writeln('Os: ${EmasOsType.android} (固定使用)');
  stdout.writeln('');

  final httpClient = newOutboundHttpClient();
  final client = EmasAppMonitorClient(
    accessKeyId: cfg.accessKeyId.trim(),
    accessKeySecret: cfg.accessKeySecret.trim(),
    regionId: cfg.region.trim(),
    httpClient: httpClient,
  );

  try {
    // ========================================
    // 示例 1: 使用 BizModule 常量
    // ========================================
    stdout.writeln('\n' + '=' * 80);
    stdout.writeln('示例 1: 使用 BizModule 常量');
    stdout.writeln('=' * 80);
    
    // 支持的 BizModule 类型：
    // - EmasBizModule.crash         : 崩溃分析
    // - EmasBizModule.anr           : ANR
    // - EmasBizModule.startup       : 启动性能
    // - EmasBizModule.exception     : 自定义异常
    // - EmasBizModule.h5WhiteScreen : H5 白屏
    // - EmasBizModule.lag           : 卡顿
    // - EmasBizModule.h5JsError     : H5 JS 错误
    // - EmasBizModule.custom        : 自定义监控
    
    final bizModules = [
      EmasBizModule.crash,
      EmasBizModule.anr,
      EmasBizModule.startup,
      EmasBizModule.exception,
    ];
    
    for (final biz in bizModules) {
      stdout.writeln('  - $biz');
    }

    // ========================================
    // 示例 2: 使用 OsType 常量（当前项目固定使用 android）
    // ========================================
    stdout.writeln('\n' + '=' * 80);
    stdout.writeln('示例 2: 使用 OsType 常量');
    stdout.writeln('=' * 80);
    
    // 支持的 OS 类型：
    // - EmasOsType.android   : Android 平台（当前项目默认）
    // - EmasOsType.iphoneos  : iOS 平台
    // - EmasOsType.harmony   : HarmonyOS 平台
    // - EmasOsType.h5        : H5/Web 平台
    
    stdout.writeln('  当前项目固定使用: ${EmasOsType.android}');
    stdout.writeln('  其他支持的平台:');
    stdout.writeln('    - ${EmasOsType.iphoneos}');
    stdout.writeln('    - ${EmasOsType.harmony}');
    stdout.writeln('    - ${EmasOsType.h5}');

    // ========================================
    // 示例 3: GetIssues - 使用所有可选参数（演示用途，暂不调用）
    // ========================================
    stdout.writeln('\n' + '=' * 80);
    stdout.writeln('示例 3: GetIssues - 可选参数说明');
    stdout.writeln('=' * 80);
    
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final startMs = todayStart.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final endMs = todayStart.millisecondsSinceEpoch - 1;
    
    stdout.writeln('''
  // 基本调用（当前使用的方式）
  final result = await client.getIssues(
    appKey: $ak,
    bizModule: EmasBizModule.crash,  // 使用常量
    os: EmasOsType.android,          // 固定使用 android
    startTimeMs: $startMs,
    endTimeMs: $endMs,
    pageIndex: 1,
    pageSize: 10,
    orderBy: 'ErrorCount',
    orderType: 'desc',
  );

  // 可选参数说明：
  // - name: 应用版本筛选（模糊搜索）
  //   name: '1.0.0',
  // 
  // - status: 错误状态（1/2/3/4）
  //   status: 1,
  // 
  // - granularity: 时间粒度值
  //   granularity: 1,
  // 
  // - granularityUnit: 时间粒度单位（hour/day/minute）
  //   granularityUnit: 'day',
  // 
  // - packageName: 应用包名
  //   packageName: 'com.example.app',
  // 
  // - extraBody: 额外的自定义参数
  //   extraBody: {'CustomParam': 'value'},
''');

    // ========================================
    // 示例 4: GetIssue - 使用所有可选参数（演示用途，暂不调用）
    // ========================================
    stdout.writeln('\n' + '=' * 80);
    stdout.writeln('示例 4: GetIssue - 可选参数说明');
    stdout.writeln('=' * 80);
    
    stdout.writeln('''
  // 基本调用（当前使用的方式）
  final result = await client.getIssue(
    appKey: $ak,
    bizModule: EmasBizModule.crash,  // 使用常量
    os: EmasOsType.android,          // 固定使用 android
    digestHash: 'YOUR_DIGEST_HASH',
    startTimeMs: $startMs,
    endTimeMs: $endMs,
  );

  // 可选参数说明：
  // - packageName: 应用包名
  //   packageName: 'com.example.app',
  // 
  // - extraBody: 额外的自定义参数
  //   extraBody: {'CustomParam': 'value'},
''');

    // ========================================
    // 示例 5: GetErrors - 使用所有可选参数（演示用途，暂不调用）
    // ========================================
    stdout.writeln('\n' + '=' * 80);
    stdout.writeln('示例 5: GetErrors - 可选参数说明');
    stdout.writeln('=' * 80);
    
    stdout.writeln('''
  // 基本调用（当前使用的方式）
  final result = await client.getErrorsRaw(
    appKey: $ak,
    bizModule: EmasBizModule.crash,  // 使用常量
    os: EmasOsType.android,          // 固定使用 android
    startTimeMs: $startMs,
    endTimeMs: $endMs,
    pageIndex: 1,
    pageSize: 10,
    digestHash: 'YOUR_DIGEST_HASH',
  );

  // 可选参数说明：
  // - utdid: 设备唯一标识符
  //   utdid: 'device_utdid_123',
  // 
  // - extraBody: 额外的自定义参数
  //   extraBody: {'CustomParam': 'value'},
  
  // 注意：GetErrors 的 TimeRange 只包含 StartTime 和 EndTime 两个字段
  // 不包含 Granularity 和 GranularityUnit
''');

    // ========================================
    // 示例 6: GetError - 使用所有可选参数（演示用途，暂不调用）
    // ========================================
    stdout.writeln('\n' + '=' * 80);
    stdout.writeln('示例 6: GetError - 可选参数说明');
    stdout.writeln('=' * 80);
    
    final clientTime = DateTime.now().millisecondsSinceEpoch;
    
    stdout.writeln('''
  // 基本调用（当前使用的方式）
  final result = await client.getErrorRaw(
    appKey: $ak,
    clientTime: $clientTime,
    os: EmasOsType.android,          // 固定使用 android
    uuid: 'YOUR_UUID',
    did: 'YOUR_DID',
    bizModule: EmasBizModule.crash,  // 使用常量
    digestHash: 'YOUR_DIGEST_HASH',
  );

  // 可选参数说明：
  // - force: 是否强制刷新
  //   force: true,
  // 
  // - extraBody: 额外的自定义参数
  //   extraBody: {'CustomParam': 'value'},
  
  // 典型调用流程：
  // 1. GetIssues -> 获取 DigestHash
  // 2. GetErrors -> 获取 ClientTime 和 Uuid
  // 3. GetError  -> 获取单个错误实例详情
''');

    // ========================================
    // 示例 7: 实际调用演示（仅调用 GetIssues）
    // ========================================
    stdout.writeln('\n' + '=' * 80);
    stdout.writeln('示例 7: 实际调用演示（GetIssues）');
    stdout.writeln('=' * 80);
    
    final issuesResult = await client.getIssues(
      appKey: ak,
      bizModule: EmasBizModule.crash,  // 使用常量
      os: EmasOsType.android,          // 固定使用 android
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
      stdout.writeln('\n前 3 个错误项：');
      for (var i = 0; i < issuesResult.items.length && i < 3; i++) {
        final item = issuesResult.items[i];
        stdout.writeln('  ${i + 1}. ${item.errorName ?? '无名称'}');
        stdout.writeln('     DigestHash: ${item.digestHash ?? '无'}');
        stdout.writeln('     ErrorCount: ${item.errorCount}');
      }
    }

    stdout.writeln('\n' + '=' * 80);
    stdout.writeln('所有示例完成！');
    stdout.writeln('=' * 80);

    exitCode = 0;
  } catch (e) {
    stderr.writeln('❌ 测试失败: $e');
    exitCode = 1;
  } finally {
    client.close();
  }
}
