# HTML 报告分析与 CLI 服务集成指南

## 概述

HTML 报告分析功能负责：
1. 解析用户上传的 HTML 报告，提取崩溃堆栈
2. 查询 EMAS API 获取样本信息
3. 下载华佗平台的诊断日志
4. 生成最终的分析报告

当前状态：**已支持 CLI 服务调用**

## 架构

### 当前实现（混合模式）

```
HTML 报告分析流程
├── Step 1: parse_html_fast.py → 解析 HTML 提取崩溃
│   └── 保存到 JSON 中间文件
├── Step 2: 查询用户样本（**已支持 CLI 服务**）
│   ├── 方式 A: batch_get_samples.py（旧）- 调用 Python 脚本
│   └── 方式 B: AliyunCliService（新）- 直接使用 Dart CLI 服务
├── Step 3: huatuo_analyzer.py → 查询华佗日志
│   └── 下载诊断日志文件
└── Step 4: generate_report.py → 生成最终报告
    └── 整合所有数据生成报告
```

## CLI 服务集成点

### 方式 A：通过 Python 脚本调用（当前）

```dart
// 在 HtmlAnalysisPipelineService._step2_getUnfortunatelySamples()
final result = await Process.run(
  'python3',
  [scriptPath, '--app-key', config.appKey, '--digest-hash', hash],
  runInShell: true,
);
```

Python 脚本 `batch_get_samples.py` 内部使用 Aliyun CLI。

### 方式 B：直接使用 CLI 服务（推荐）

```dart
// 在 HtmlAnalysisPipelineService 中已实现
final result = await _queryErrorSamplesViaCli(
  digestHash: hash,
  bizModule: 'crash',
  startTimeMs: startTime,
  endTimeMs: endTime,
  os: 'android',
  sampleSize: 2,
);
```

**优点：**
- 避免 Python 脚本调用开销
- 直接使用类型安全的 Dart API
- 错误处理更清晰
- 无需外部依赖

## 使用场景

### 场景 1：用户上传崩溃报告

```
用户 → 上传 HTML 报告
  ↓
Step 1: 解析 HTML
  - 提取崩溃堆栈
  - 识别 digest hash
  ↓
Step 2: 查询样本（**CLI 服务**）
  - 调用 getErrors() 获取样本列表
  - 提取 clientTime、uuid、did
  ↓
Step 3: 查询华佗日志
  - 下载诊断日志
  ↓
Step 4: 生成报告
  - 整合所有信息
  ↓
用户 ← 获取分析报告
```

## 迁移指南

### 从 Python 脚本迁移到 CLI 服务

如果要完全去除 Python 脚本依赖，修改 `_step2_getUnfortunatelySamples()` 如下：

**旧代码（使用 Python 脚本）：**

```dart
Future<void> _step2_getUnfortunatelySamples(AnalysisSession session) async {
  // ...
  
  for (int i = 0; i < session.selectedDigestHashes.length; i++) {
    final hash = session.selectedDigestHashes[i];
    
    // 调用 Python 脚本
    final result = await Process.run(
      'python3',
      [scriptPath, '--app-key', config.appKey, '--digest-hash', hash],
      runInShell: true,
    );
    
    // 处理结果...
  }
}
```

**新代码（使用 CLI 服务）：**

```dart
Future<void> _step2_getUnfortunatelySamples(AnalysisSession session) async {
  // ...
  
  for (int i = 0; i < session.selectedDigestHashes.length; i++) {
    final hash = session.selectedDigestHashes[i];
    
    try {
      // 使用 CLI 服务直接查询
      final result = await _queryErrorSamplesViaCli(
        digestHash: hash,
        bizModule: session.bizModule ?? 'crash',
        startTimeMs: session.startTimeMs,
        endTimeMs: session.endTimeMs,
        sampleSize: 2,
      );
      
      if (result['status'] == 'success') {
        samples.add({
          'hash': hash,
          'status': 'success',
          'samples': result['samples'],
          'sample_count': result['sample_count'],
        });
      } else {
        samples.add({
          'hash': hash,
          'status': 'error',
          'error': result['error'],
        });
      }
    } catch (e) {
      samples.add({
        'hash': hash,
        'status': 'error',
        'error': e.toString(),
      });
    }
    
    await Future.delayed(const Duration(milliseconds: 500));
  }
}
```

## CLI 服务方法

### _queryErrorSamplesViaCli()

查询错误样本列表。

**参数：**
- `digestHash` - 问题 ID
- `bizModule` - 问题类型（crash/anr/lag 等）
- `startTimeMs` - 开始时间戳
- `endTimeMs` - 结束时间戳
- `os` - 平台（可选）
- `sampleSize` - 样本数量（默认 2）

**返回值：**

```dart
{
  'digest_hash': '3JE6F43KCQ1SV',
  'status': 'success',              // 或 'error'
  'sample_count': 2,                // 获取到的样本数
  'samples': [                      // 样本列表
    {
      'clientTime': 1682064128000,
      'uuid': 'uuid-string',
      'did': 'device-id',
      'utdid': 'utdid-string',
    },
    // ...
  ],
  'raw_response': {...},            // 原始 API 响应
  'error': 'error message',         // 仅当 status == 'error'
}
```

## 完整链路示例

### 获取完整样本详情

```dart
// 使用 CLI 服务获取样本列表
final errorsList = await _queryErrorSamplesViaCli(
  digestHash: '3JE6F43KCQ1SV',
  bizModule: 'crash',
  startTimeMs: 1682000000000,
  endTimeMs: 1682086400000,
);

// 如果查询成功，获取每个样本的详细信息
if (errorsList['status'] == 'success') {
  for (final sample in errorsList['samples']) {
    // 使用 getError() 获取完整样本信息
    final errorDetail = await _cliService.getError(
      bizModule: 'crash',
      digestHash: '3JE6F43KCQ1SV',
      clientTime: sample['clientTime'],
      uuid: sample['uuid'],
      did: sample['did'],
    );
    
    // 处理样本详情...
    print('异常: ${errorDetail['ExceptionMsg']}');
    print('堆栈: ${errorDetail['Backtrace']}');
  }
}
```

## 配置要求

### 必需配置

HTML 报告分析需要以下配置才能使用 CLI 服务查询样本：

1. **AppKey** - EMAS 应用密钥
2. **Region** - 阿里云地域（通常 cn-shanghai）
3. **OS** - 平台（android/iphoneos/harmony）

这些配置应存储在 `ToolConfig` 中。

### 验证配置

```dart
final miss = config.validateEmas();
if (miss.isNotEmpty) {
  print('缺少配置：${miss.join(', ')}');
  // 配置不完整，无法查询
}
```

## 故障排查

### 问题：查询失败，显示 "AppKey 未配置"

**原因：** `ToolConfig.appKey` 为空

**解决方案：**
1. 确保用户已在设置中配置 AppKey
2. 检查配置是否正确保存
3. 重新启动应用

### 问题：查询超时

**原因：** CLI 命令执行超时

**解决方案：**
1. 检查网络连接
2. 检查 Aliyun CLI 是否正常工作
3. 增加超时时间（目前为 30 秒）

### 问题：样本列表为空

**原因：** EMAS 中该问题没有样本数据

**解决方案：**
1. 检查时间范围是否正确
2. 确保 digest hash 有效
3. 检查平台（OS）是否正确

## 参考文档

- [CLI 服务使用指南](CLI_SERVICE_GUIDE.md)
- [阿里云 CLI 参考手册](aliyun-emas-apm-cli-reference.md)
