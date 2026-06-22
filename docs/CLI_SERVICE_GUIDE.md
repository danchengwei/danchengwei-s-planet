# Aliyun CLI 服务使用指南

## 概述

`AliyunCliService` 是对阿里云 EMAS APM CLI 的完整包装，支持所有 4 个核心 API 调用，并提供筛选条件构建工具。

## 核心方法

### 1. getIssues - 获取问题列表

查询指定时间范围内的聚合问题列表。

**特点：**
- 支持按版本筛选（`firstVersion` 参数）
- 支持按名称模糊搜索（`name` 参数）
- 支持分页查询
- 支持多种排序方式

**示例：**

```dart
final service = AliyunCliService(config: toolConfig);

// 基础查询
final result = await service.getIssues(
  bizModule: 'crash',
  startTimeMs: startTime,
  endTimeMs: endTime,
  os: 'android',
);

// 带版本筛选的查询
final filtered = await service.getIssues(
  bizModule: 'crash',
  startTimeMs: startTime,
  endTimeMs: endTime,
  os: 'android',
  firstVersion: '3.5.0',  // 只查询版本 3.5.0 的问题
  pageSize: 10,
  orderBy: 'ErrorCount',  // 按错误数排序
);
```

**参数说明：**

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| bizModule | String | ✅ | 问题类型：crash/anr/lag/custom/memory_leak/memory_alloc |
| startTimeMs | int | ✅ | 开始时间戳（毫秒） |
| endTimeMs | int | ✅ | 结束时间戳（毫秒） |
| os | String? | ❌ | 平台：android/iphoneos/harmony（**强烈建议传值**） |
| pageIndex | int | ❌ | 页码（默认 1） |
| pageSize | int | ❌ | 每页条数（默认 500） |
| orderBy | String | ❌ | 排序字段：ErrorRate/ErrorCount/ErrorDeviceCount/ErrorDeviceRate |
| orderType | String? | ❌ | 排序方向：asc/desc（默认 desc） |
| name | String? | ❌ | 问题名称模糊搜索 |
| status | int? | ❌ | 状态：1=未处理/2=处理中/3=已关闭/4=已处理 |
| firstVersion | String? | ❌ | 首次出现版本（版本筛选） |

**返回：** `GetIssuesResult` 对象，包含：
- `items`: 问题列表
- `pages`: 总页数
- `total`: 总问题数

---

### 2. getIssue - 获取单个问题详情

查询某个聚合问题的详细信息，包括受影响版本列表、环比增长率等。

**特点：**
- 返回完整的问题信息
- 包含受影响版本列表
- 包含增长率数据

**示例：**

```dart
// 获取问题详情
final issue = await service.getIssue(
  bizModule: 'crash',
  digestHash: '3JE6F43KCQ1SV',
  startTimeMs: startTime,
  endTimeMs: endTime,
  os: 'android',
);

// 访问关键字段
print('问题标题: ${issue['Name']}');
print('受影响版本: ${issue['AffectedVersions']}');
print('错误率增长: ${issue['ErrorRateGrowthRate']}');
```

**参数说明：**

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| bizModule | String | ✅ | 问题类型 |
| digestHash | String | ✅ | 问题唯一 ID（来自 getIssues） |
| startTimeMs | int | ✅ | 开始时间戳 |
| endTimeMs | int | ✅ | 结束时间戳 |
| os | String? | ❌ | 平台 |
| filter | Map? | ❌ | 可选筛选条件 |

---

### 3. getErrors - 获取错误样本列表

查询某个问题下的错误样本列表，返回用于调用 `getError` 的必需参数。

**特点：**
- 返回样本的 ClientTime、Uuid、Did
- 这些参数是调用 `getError` 的必需条件
- 支持 UTDID 筛选

**示例：**

```dart
// 获取样本列表
final errors = await service.getErrors(
  bizModule: 'crash',
  digestHash: '3JE6F43KCQ1SV',
  startTimeMs: startTime,
  endTimeMs: endTime,
  os: 'android',
  pageSize: 5,
);

// 提取第一个样本的关键信息
final items = errors['Model']['Items'] as List;
if (items.isNotEmpty) {
  final sample = items[0];
  final clientTime = sample['ClientTime'];  // 必需
  final uuid = sample['Uuid'];              // 必需
  final did = sample['Did'];                // 必需
}
```

**参数说明：**

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| bizModule | String | ✅ | 问题类型 |
| digestHash | String | ✅ | 问题 ID |
| startTimeMs | int | ✅ | 开始时间戳 |
| endTimeMs | int | ✅ | 结束时间戳 |
| os | String? | ❌ | 平台 |
| pageIndex | int | ❌ | 页码 |
| pageSize | int | ❌ | 每页条数 |
| orderBy | String? | ❌ | 排序字段 |
| name | String? | ❌ | 名称筛选 |
| utdid | String? | ❌ | 脱敏设备 ID |
| filter | Map? | ❌ | 筛选条件 |

---

### 4. getError - 获取单个错误样本详情

查询单个错误样本的完整详情，返回约 65 个字段的信息。

**特点：**
- 返回完整的堆栈信息
- 返回业务日志和事件日志
- 返回内存、文件描述符等信息

**示例：**

```dart
// 获取样本详情
final error = await service.getError(
  bizModule: 'crash',
  digestHash: '3JE6F43KCQ1SV',
  clientTime: 1682064128000,
  uuid: 'b8f3a5c2-1234-5678-9abc-def012345678',
  did: 'device_id_123',
  os: 'android',
);

// 访问关键字段
print('堆栈: ${error['Backtrace']}');
print('异常类型: ${error['ExceptionType']}');
print('异常消息: ${error['ExceptionMsg']}');
print('设备型号: ${error['DeviceModel']}');
print('系统版本: ${error['OsVersion']}');
print('应用版本: ${error['AppVersion']}');
```

**参数说明：**

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| bizModule | String | ✅ | 问题类型 |
| digestHash | String | ✅ | 问题 ID |
| clientTime | int | ✅ | 客户端时间戳（来自 getErrors） |
| uuid | String | ✅ | 事件 UUID（来自 getErrors） |
| did | String | ✅ | 设备 ID（来自 getErrors） |
| os | String? | ❌ | 平台 |
| bizForce | bool | ❌ | 是否强制获取 |

---

## 筛选条件构建工具

### buildSimpleFilter - 构建简单筛选条件

用于构建单个筛选条件。

**示例：**

```dart
// 按版本筛选
final versionFilter = AliyunCliService.buildSimpleFilter(
  'appVersion',
  '=',
  ['3.5.0'],
);

// 按多个版本筛选
final multiVersionFilter = AliyunCliService.buildSimpleFilter(
  'appVersion',
  'in',
  ['3.5.0', '3.5.1', '3.5.2'],
);

// 按品牌筛选
final brandFilter = AliyunCliService.buildSimpleFilter(
  'brand',
  '=',
  ['Apple'],
);

// 使用筛选条件
final issues = await service.getIssues(
  bizModule: 'crash',
  startTimeMs: startTime,
  endTimeMs: endTime,
  os: 'iphoneos',
  // filter: brandFilter,  // 注：getIssues 通过 firstVersion 参数筛选版本
);
```

**支持的操作符：**
- `=` : 等于
- `!=` : 不等于
- `in` : 属于
- `not in` : 不属于
- `>`, `<`, `>=`, `<=` : 数值比较

---

### buildCompositeFilter - 构建组合筛选条件

用于构建 AND/OR 组合筛选条件。

**示例：**

```dart
// 构建 AND 条件：版本为 3.5.0 或 3.5.1，且品牌为 Apple
final compositeFilter = AliyunCliService.buildCompositeFilter(
  'and',
  [
    AliyunCliService.buildSimpleFilter('appVersion', 'in', ['3.5.0', '3.5.1']),
    AliyunCliService.buildSimpleFilter('brand', '=', ['Apple']),
  ],
);

// 获取单个问题详情时使用复杂筛选
final issue = await service.getIssue(
  bizModule: 'crash',
  digestHash: '3JE6F43KCQ1SV',
  startTimeMs: startTime,
  endTimeMs: endTime,
  filter: compositeFilter,
);
```

---

## 常见使用场景

### 场景 1：查询 Top 5 崩溃

```dart
final topCrashes = await service.getIssues(
  bizModule: 'crash',
  startTimeMs: startTime,
  endTimeMs: endTime,
  os: 'android',
  pageSize: 5,
  orderBy: 'ErrorRate',
  orderType: 'desc',
);
```

### 场景 2：查询新版本引入的问题

```dart
final newIssues = await service.getIssues(
  bizModule: 'crash',
  startTimeMs: startTime,
  endTimeMs: endTime,
  os: 'android',
  firstVersion: '3.5.0',  // 首次出现在这个版本
);
```

### 场景 3：全链路获取崩溃样本信息

```dart
// Step 1: 获取问题列表
final issues = await service.getIssues(
  bizModule: 'crash',
  startTimeMs: startTime,
  endTimeMs: endTime,
  os: 'android',
  pageSize: 1,
);

final digestHash = issues.items.first.digestHash;

// Step 2: 获取问题详情
final issueDetail = await service.getIssue(
  bizModule: 'crash',
  digestHash: digestHash,
  startTimeMs: startTime,
  endTimeMs: endTime,
);

// Step 3: 获取错误样本列表
final errorsList = await service.getErrors(
  bizModule: 'crash',
  digestHash: digestHash,
  startTimeMs: startTime,
  endTimeMs: endTime,
  pageSize: 3,
);

// Step 4: 获取单个错误详情
final items = errorsList['Model']['Items'] as List;
if (items.isNotEmpty) {
  final sample = items[0];
  final errorDetail = await service.getError(
    bizModule: 'crash',
    digestHash: digestHash,
    clientTime: sample['ClientTime'],
    uuid: sample['Uuid'],
    did: sample['Did'],
  );
  
  print('堆栈: ${errorDetail['Backtrace']}');
  print('设备型号: ${errorDetail['DeviceModel']}');
}
```

---

## 错误处理

所有方法都会抛出异常，需要使用 try-catch 处理：

```dart
try {
  final issues = await service.getIssues(
    bizModule: 'crash',
    startTimeMs: startTime,
    endTimeMs: endTime,
  );
} catch (e) {
  print('查询失败: $e');
  // 处理错误
}
```

**常见错误：**
- `AppKey 未配置或为空` - 检查 toolConfig.appKey
- `Region 未配置或为空` - 检查 toolConfig.region
- `CLI 执行失败` - 检查 aliyun CLI 是否安装并配置
- `API 失败` - 检查 API 参数和权限

---

## 调试技巧

服务会输出详细的日志信息，包括：
- CLI 命令执行过程
- 配置检查信息
- 应用的筛选条件
- 响应数据大小

查看控制台输出可以快速定位问题。

---

## 参考文档

详见 [aliyun-emas-apm-cli-reference.md](aliyun-emas-apm-cli-reference.md)
