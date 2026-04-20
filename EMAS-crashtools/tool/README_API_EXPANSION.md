# EMAS AppMonitor API 扩写说明

本文档说明了基于测试脚本对 EMAS API 进行的扩写和优化。

## 📋 扩写内容

### 1. BizModule 常量定义

在 `emas_appmonitor_client.dart` 中新增了 `EmasBizModule` 类，定义了所有支持的业务模块类型：

```dart
abstract class EmasBizModule {
  static const String crash = 'crash';           // 崩溃分析
  static const String anr = 'anr';               // ANR
  static const String startup = 'startup';       // 启动性能
  static const String exception = 'exception';   // 自定义异常
  static const String h5WhiteScreen = 'h5WhiteScreen'; // H5 白屏
  static const String lag = 'lag';               // 卡顿
  static const String h5JsError = 'h5JsError';   // H5 JS 错误
  static const String custom = 'custom';         // 自定义监控
}
```

**使用示例：**
```dart
// 之前
bizModule: 'crash',

// 现在（推荐使用常量）
bizModule: EmasBizModule.crash,
```

### 2. OsType 常量定义

新增了 `EmasOsType` 类，定义了所有支持的 OS 平台类型：

```dart
abstract class EmasOsType {
  static const String android = 'android';    // Android 平台（当前项目默认）
  static const String iphoneos = 'iphoneos';  // iOS 平台
  static const String harmony = 'harmony';    // HarmonyOS 平台
  static const String h5 = 'h5';              // H5/Web 平台
}
```

**使用示例：**
```dart
// 当前项目固定使用 Android
os: EmasOsType.android,
```

### 3. 可选参数扩写

为所有 API 方法添加了详细的注释，说明了所有可选参数的用途和取值范围。

#### GetIssues 可选参数

```dart
// 基本调用
final result = await client.getIssues(
  appKey: ak,
  bizModule: EmasBizModule.crash,
  os: EmasOsType.android,
  startTimeMs: startMs,
  endTimeMs: endMs,
  pageIndex: 1,
  pageSize: 10,
  orderBy: 'ErrorCount',
  orderType: 'desc',
);

// 可选参数（暂时不调用）
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
```

#### GetIssue 可选参数

```dart
// 基本调用
final result = await client.getIssue(
  appKey: ak,
  bizModule: EmasBizModule.crash,
  os: EmasOsType.android,
  digestHash: 'YOUR_DIGEST_HASH',
  startTimeMs: startMs,
  endTimeMs: endMs,
);

// 可选参数（暂时不调用）
// - packageName: 应用包名
//   packageName: 'com.example.app',
// 
// - extraBody: 额外的自定义参数
//   extraBody: {'CustomParam': 'value'},
```

#### GetErrors 可选参数

```dart
// 基本调用
final result = await client.getErrorsRaw(
  appKey: ak,
  bizModule: EmasBizModule.crash,
  os: EmasOsType.android,
  startTimeMs: startMs,
  endTimeMs: endMs,
  pageIndex: 1,
  pageSize: 10,
  digestHash: 'YOUR_DIGEST_HASH',
);

// 可选参数（暂时不调用）
// - utdid: 设备唯一标识符
//   utdid: 'device_utdid_123',
// 
// - extraBody: 额外的自定义参数
//   extraBody: {'CustomParam': 'value'},

// 注意：GetErrors 的 TimeRange 只包含 StartTime 和 EndTime 两个字段
// 不包含 Granularity 和 GranularityUnit
```

#### GetError 可选参数

```dart
// 基本调用
final result = await client.getErrorRaw(
  appKey: ak,
  clientTime: clientTime,
  os: EmasOsType.android,
  uuid: 'YOUR_UUID',
  did: 'YOUR_DID',
  bizModule: EmasBizModule.crash,
  digestHash: 'YOUR_DIGEST_HASH',
);

// 可选参数（暂时不调用）
// - force: 是否强制刷新
//   force: true,
// 
// - extraBody: 额外的自定义参数
//   extraBody: {'CustomParam': 'value'},

// 典型调用流程：
// 1. GetIssues -> 获取 DigestHash
// 2. GetErrors -> 获取 ClientTime 和 Uuid
// 3. GetError  -> 获取单个错误实例详情
```

## 📊 API 层级关系

```
GetIssues (聚合列表)
    ↓ 提取 DigestHash
GetIssue (单个聚合详情)
    ↓ 提取 DigestHash
GetErrors (实例列表)
    ↓ 提取 ClientTime 和 Uuid
GetError (单个实例详情)
```

## 🔧 关键差异点

### TimeRange 字段差异

| API | TimeRange 字段 |
|-----|---------------|
| GetIssues | StartTime, EndTime, **Granularity**, **GranularityUnit** |
| GetIssue | StartTime, EndTime, **Granularity**, **GranularityUnit** |
| GetErrors | StartTime, EndTime (只有两个字段) |
| GetError | 不需要 TimeRange，使用 ClientTime |

### 必填参数差异

| API | 必填参数 |
|-----|---------|
| GetIssues | AppKey, BizModule, TimeRange |
| GetIssue | AppKey, BizModule, **Os**, DigestHash, TimeRange |
| GetErrors | AppKey, BizModule, **Os**, TimeRange, **PageIndex**, **PageSize** |
| GetError | AppKey, **ClientTime** |

**注意：** Os 参数在某些 API 中虽然文档未标为必填，但实际需要传递。

## 📝 使用建议

1. **使用常量**：推荐使用 `EmasBizModule` 和 `EmasOsType` 常量，避免硬编码字符串
2. **Os 固定为 android**：当前项目固定使用 `EmasOsType.android`
3. **可选参数暂不调用**：已添加详细注释说明，后续可根据需要启用
4. **参考示例文件**：查看 `tool/example_api_usage.dart` 了解完整的使用方式

## ✅ 测试验证

所有 API 已通过测试验证：

```bash
# 运行综合测试
dart run tool/test_all_apis.dart

# 运行示例代码
dart run tool/example_api_usage.dart
```

测试结果：
- ✅ GetIssues - 成功
- ✅ GetIssue - 成功
- ✅ GetErrors - 成功
- ✅ GetError - 成功

## 📚 相关文档

- [阿里云 EMAS AppMonitor API 文档](https://api.aliyun.com/api/emas-appmonitor/2019-06-11/GetIssues)
- [EMAS 崩溃分析相关接口](https://help.aliyun.com/zh/document_detail/2880532.html)
