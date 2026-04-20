# EMAS API 快速参考

## 🎯 常量使用

### BizModule（业务模块）
```dart
import 'package:crash_emas_tool/aliyun/emas_appmonitor_client.dart';

EmasBizModule.crash           // 崩溃分析
EmasBizModule.anr             // ANR
EmasBizModule.startup         // 启动性能
EmasBizModule.exception       // 自定义异常
EmasBizModule.h5WhiteScreen   // H5 白屏
EmasBizModule.lag             // 卡顿
EmasBizModule.h5JsError       // H5 JS 错误
EmasBizModule.custom          // 自定义监控
```

### OsType（OS 平台）
```dart
EmasOsType.android    // Android（当前项目固定使用）
EmasOsType.iphoneos   // iOS
EmasOsType.harmony    // HarmonyOS
EmasOsType.h5         // H5/Web
```

## 📡 API 调用示例

### GetIssues - 获取聚合列表
```dart
final result = await client.getIssues(
  appKey: ak,
  bizModule: EmasBizModule.crash,      // ✅ 使用常量
  os: EmasOsType.android,              // ✅ 固定使用 android
  startTimeMs: startMs,
  endTimeMs: endMs,
  pageIndex: 1,
  pageSize: 10,
  orderBy: 'ErrorCount',
  orderType: 'desc',
);

// 可选参数（暂不调用）
// name: '1.0.0',                    // 应用版本筛选
// status: 1,                        // 错误状态
// granularity: 1,                   // 时间粒度值
// granularityUnit: 'day',           // 时间粒度单位
// packageName: 'com.example.app',   // 应用包名
// extraBody: {'CustomParam': 'value'},
```

### GetIssue - 获取单个聚合详情
```dart
final result = await client.getIssue(
  appKey: ak,
  bizModule: EmasBizModule.crash,      // ✅ 使用常量
  os: EmasOsType.android,              // ✅ 固定使用 android
  digestHash: 'YOUR_DIGEST_HASH',
  startTimeMs: startMs,
  endTimeMs: endMs,
);

// 可选参数（暂不调用）
// packageName: 'com.example.app',
// extraBody: {'CustomParam': 'value'},
```

### GetErrors - 获取实例列表
```dart
final result = await client.getErrorsRaw(
  appKey: ak,
  bizModule: EmasBizModule.crash,      // ✅ 使用常量
  os: EmasOsType.android,              // ✅ 固定使用 android
  startTimeMs: startMs,
  endTimeMs: endMs,
  pageIndex: 1,                        // ⚠️ 必填
  pageSize: 10,                        // ⚠️ 必填
  digestHash: 'YOUR_DIGEST_HASH',
);

// 可选参数（暂不调用）
// utdid: 'device_utdid_123',
// extraBody: {'CustomParam': 'value'},

// ⚠️ 注意：TimeRange 只包含 StartTime 和 EndTime 两个字段
```

### GetError - 获取单个实例详情
```dart
final result = await client.getErrorRaw(
  appKey: ak,
  clientTime: clientTime,              // ⚠️ 必填（从 GetErrors 获取）
  os: EmasOsType.android,              // ✅ 固定使用 android
  uuid: 'YOUR_UUID',                   // 从 GetErrors 获取
  did: 'YOUR_DID',
  bizModule: EmasBizModule.crash,      // ✅ 使用常量
  digestHash: 'YOUR_DIGEST_HASH',
);

// 可选参数（暂不调用）
// force: true,
// extraBody: {'CustomParam': 'value'},
```

## 🔗 API 调用流程

```
GetIssues (聚合列表)
    ↓ 提取 DigestHash
GetIssue (单个聚合详情)
    ↓ 提取 DigestHash
GetErrors (实例列表)
    ↓ 提取 ClientTime 和 Uuid
GetError (单个实例详情)
```

## ⚠️ 关键注意事项

### 1. TimeRange 字段差异
| API | TimeRange 字段 |
|-----|---------------|
| GetIssues | StartTime, EndTime, **Granularity**, **GranularityUnit** |
| GetIssue | StartTime, EndTime, **Granularity**, **GranularityUnit** |
| GetErrors | StartTime, EndTime (只有两个字段) |
| GetError | 不需要 TimeRange，使用 ClientTime |

### 2. 必填参数
| API | 必填参数 |
|-----|---------|
| GetIssues | AppKey, BizModule, TimeRange |
| GetIssue | AppKey, BizModule, **Os**, DigestHash, TimeRange |
| GetErrors | AppKey, BizModule, **Os**, TimeRange, **PageIndex**, **PageSize** |
| GetError | AppKey, **ClientTime** |

### 3. Os 参数
- 虽然某些 API 文档中 Os 未标为必填，但实际调用时需要传递
- 当前项目固定使用 `EmasOsType.android`

## 🧪 测试命令

```bash
# 运行综合测试
dart run tool/test_all_apis.dart

# 运行示例代码
dart run tool/example_api_usage.dart

# 代码分析
dart analyze lib/aliyun/emas_appmonitor_client.dart
```

## 📚 相关文档

- [详细扩写说明](README_API_EXPANSION.md)
- [扩写总结](API_EXPANSION_SUMMARY.md)
- [使用示例](example_api_usage.dart)
- [阿里云官方文档](https://api.aliyun.com/api/emas-appmonitor/2019-06-11/GetIssues)
