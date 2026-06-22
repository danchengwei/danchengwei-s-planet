# 阿里云 CLI 工具集成

本目录包含EMAS崩溃分析工具所需的阿里云CLI环境。

> 详细CLI使用文档请见 [emas-intelligent-analysis skill](/.agents/skills/emas-intelligent-analysis/SKILLS.md)

## 文件说明

- `install.sh` - 阿里云CLI安装脚本（macOS/Linux）
- `setup.sh` - 应用打包时的环境集成脚本
- `.gitignore` - Git忽略本地CLI安装文件

## 快速开始

### 1. 首次安装

```bash
cd tools/aliyun
bash install.sh
```

自动下载对应系统版本（Intel Mac / Apple Silicon / Linux）并设置PATH环境变量。

### 2. 配置阿里云凭证

通过应用UI配置（推荐）或命令行配置：

```bash
# 命令行配置方式
aliyun configure set --profile default \
  --access-key-id <YOUR_ACCESS_KEY_ID> \
  --access-key-secret <YOUR_ACCESS_KEY_SECRET> \
  --region cn-shanghai
```

### 3. 验证安装

```bash
# 查看CLI版本
aliyun version

# 查看配置
aliyun configure list --profile default

# 测试EMAS连接
aliyun emas-appmonitor get-issues \
  --app-key <AppKey> \
  --os android \
  --biz-module crash \
  --time-range StartTime=1776000000000 EndTime=1776086400000 Granularity=1 GranularityUnit=DAY \
  --page-size 1
```

## 支持的操作系统

- macOS (Intel & Apple Silicon)
- Linux (x86_64)
- Windows (通过WSL)

## 打包说明

- **macOS App Bundle**: CLI工具自动包含在 `.app` 资源目录中
- **Linux AppImage**: CLI工具打包到AppImage中
- **Windows Portable**: CLI工具放在应用目录下

## 故障排除

### aliyun 命令找不到

```bash
# 手动设置路径
export PATH="/Users/$(whoami)/aliyun/bin:$PATH"
```

### 凭证配置问题

```bash
# 查看当前配置
aliyun configure list --profile default

# 重新配置
aliyun configure set --profile default --access-key-id <KEY> --access-key-secret <SECRET>
```

## 支持的 6 种问题类型

| biz-module | 中文名称 | 说明 | Android | iOS | HarmonyOS |
|-----------|--------|------|--------|-----|-----------|
| `crash` | 崩溃 | 应用崩溃问题 | ✅ | ✅ | ✅ |
| `anr` | ANR | 应用无响应 | ✅ | ✅ | ❌ |
| `lag` | 卡顿 | 界面卡顿问题 | ✅ | ✅ | ✅ |
| `custom` | 自定义异常 | 业务自定义错误 | ✅ | ✅ | ✅ |
| `memory_leak` | 内存泄漏 | 内存泄漏问题 | ✅ | ✅ | ❌ |
| `memory_alloc` | 内存分配 | 内存分配问题 | ✅ | ✅ | ❌ |

## CLI 常用命令

### 查询崩溃 Top 5

```bash
aliyun emas-appmonitor get-issues \
  --app-key <AppKey> \
  --os android \
  --biz-module crash \
  --time-range StartTime=1776000000000 EndTime=1776086400000 Granularity=1 GranularityUnit=DAY \
  --order-by ErrorRate --order-type desc --page-size 5
```

### 查询 ANR Top 5

```bash
aliyun emas-appmonitor get-issues \
  --app-key <AppKey> \
  --os android \
  --biz-module anr \
  --time-range StartTime=1776000000000 EndTime=1776086400000 Granularity=1 GranularityUnit=DAY \
  --order-by ErrorRate --order-type desc --page-size 5
```

### 查询卡顿 Top 5

```bash
aliyun emas-appmonitor get-issues \
  --app-key <AppKey> \
  --os iphoneos \
  --biz-module lag \
  --time-range StartTime=1776000000000 EndTime=1776086400000 Granularity=1 GranularityUnit=DAY \
  --order-by ErrorRate --order-type desc --page-size 5
```

### 查询自定义异常

```bash
aliyun emas-appmonitor get-issues \
  --app-key <AppKey> \
  --os android \
  --biz-module custom \
  --time-range StartTime=1776000000000 EndTime=1776086400000 Granularity=1 GranularityUnit=DAY \
  --page-size 10
```

### 查询内存泄漏

```bash
aliyun emas-appmonitor get-issues \
  --app-key <AppKey> \
  --os android \
  --biz-module memory_leak \
  --time-range StartTime=1776000000000 EndTime=1776086400000 Granularity=1 GranularityUnit=DAY \
  --page-size 10
```

### 查询内存分配

```bash
aliyun emas-appmonitor get-issues \
  --app-key <AppKey> \
  --os android \
  --biz-module memory_alloc \
  --time-range StartTime=1776000000000 EndTime=1776086400000 Granularity=1 GranularityUnit=DAY \
  --page-size 10
```

### 获取受影响版本列表

```bash
aliyun emas-appmonitor get-issue \
  --app-key 28085188 \
  --os android \
  --biz-module crash \
  --digest-hash <hash> \
  --time-range StartTime=<startMs> EndTime=<endMs> Granularity=1 GranularityUnit=DAY \
  --cli-query "Model.AffectedVersions"
```

### 按版本过滤

```bash
aliyun emas-appmonitor get-issues \
  --app-key 28085188 \
  --os android \
  --biz-module crash \
  --time-range StartTime=<startMs> EndTime=<endMs> Granularity=1 GranularityUnit=DAY \
  --filter '{"Key":"appVersion","Operator":"in","Values":["10.16.03","10.17.15"]}'
```

### 分页查询

```bash
# 第1页，每页20条
aliyun emas-appmonitor get-issues \
  --app-key 28085188 \
  --os android \
  --biz-module crash \
  --time-range StartTime=<startMs> EndTime=<endMs> Granularity=1 GranularityUnit=DAY \
  --page-index 1 \
  --page-size 20
```

## 时间戳转换

```bash
# 当前时间戳（毫秒）
date +%s000

# 7天前的时间戳
date -d '-7 days' +%s000
```

## 返回的关键字段

| 字段 | 崩溃 | ANR | 卡顿 | 说明 |
|------|-----|-----|------|------|
| `ErrorCount` | ✅ | ✅ | ✅ | 错误次数 |
| `ErrorRate` | ✅ | ✅ | ✅ | 错误率 |
| `ErrorDeviceCount` | ✅ | ✅ | ✅ | 受影响设备数 |
| `ErrorDeviceRate` | ✅ | ✅ | ✅ | 设备率 |
| `Stack` | ✅ | ✅ | ✅ | 堆栈信息 |
| `Type` | ✅ | ✅ | ❌ | 异常类型 |
| `Reason` | ✅ | ✅ | ❌ | 异常原因 |
| `LagCost` | ❌ | ❌ | ✅ | 卡顿时长（毫秒） |
| `AffectedVersions` | ✅ | ✅ | ✅ | 受影响版本列表 |
| `FirstVersion` | ✅ | ✅ | ✅ | 首次出现版本 |

## 查询结果示例

```json
{
  "items": [
    {
      "digestHash": "abc123def456",
      "errorName": "NullPointerException",
      "errorCount": 535,
      "errorDeviceCount": 93000,
      "errorRate": 0.001,
      "errorDeviceRate": 0.05,
      "type": "java.lang.NullPointerException",
      "reason": "Null pointer dereference",
      "firstVersion": "10.16.03",
      "affectedVersions": ["10.16.03", "10.17.15", "10.18.00"],
      "lagCost": null,
      "stack": "at com.example.MainActivity.onCreate(MainActivity.java:123)\n..."
    }
  ],
  "total": 1234,
  "pageIndex": 1,
  "pageSize": 20
}
```

## 批量扫描所有 6 种类型

```bash
# 自动并行查询所有问题类型，合并并按错误率排序
bash scripts/list_top_issues.sh \
  --app-key <AppKey> \
  --os android \
  --start-time 1776000000000 \
  --end-time 1776086400000 \
  --top-n 5 \
  --order-by ErrorRate
```

## 相关链接

- [阿里云CLI官方文档](https://help.aliyun.com/zh/sdk/developer-reference/alibaba-cloud-cli-v3)
- [EMAS 开发者文档](https://help.aliyun.com/zh/emas/user-guide/overview)
- [emas-intelligent-analysis Skill](/.agents/skills/emas-intelligent-analysis/SKILLS.md)
