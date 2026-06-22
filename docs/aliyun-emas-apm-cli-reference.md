# 阿里云 EMAS APM CLI 完整参考手册

> 汇总自 `alibabacloud-emas-apm-query` Skill 全部文档、脚本和资源文件
> 更新时间：2026-06-22

---

## 目录

1. [环境准备](#1-环境准备)
2. [4个核心 API](#2-4个核心-api)
3. [问题类型（biz-module）](#3-问题类型biz-module)
4. [平台支持矩阵](#4-平台支持矩阵)
5. [筛选参数（--filter）](#5-筛选参数filter)
6. [完整筛选字段清单](#6-完整筛选字段清单)
7. [API 返回字段](#7-api-返回字段)
8. [脚本工具](#8-脚本工具)
9. [常用查询场景](#9-常用查询场景)
10. [参数获取与自动推断](#10-参数获取与自动推断)
11. [RAM 权限](#11-ram-权限)
12. [踩坑与注意事项](#12-踩坑与注意事项)
13. [故障排查](#13-故障排查)
14. [清理](#14-清理)

---

## 1. 环境准备

### 1.1 安装阿里云 CLI

```bash
# macOS / Linux（推荐）
/bin/bash -c "$(curl -fsSL --connect-timeout 10 --max-time 120 https://aliyuncli.alicdn.com/setup.sh)"

# macOS Homebrew
brew install aliyun-cli

# 验证版本（需要 >= 3.3.3）
aliyun version
```

### 1.2 安装 emas-appmonitor 插件

```bash
# 开启自动安装插件
aliyun configure set --auto-plugin-install true
aliyun plugin update

# 或手动安装
aliyun plugin install --names emas-appmonitor

# 验证
aliyun emas-appmonitor --help | head -40
```

### 1.3 配置凭证

```bash
# AK 模式（最常用）
aliyun configure set \
  --mode AK \
  --access-key-id <your-access-key-id> \
  --access-key-secret <your-access-key-secret> \
  --region cn-hangzhou

# 检查当前配置（不要打印 AK/SK 值）
aliyun configure list

# 其他模式：OAuth / StsToken / RamRoleArn / EcsRamRole / RsaKeyPair / RamRoleArnWithEcs
```

### 1.4 AI 模式生命周期

```bash
# 开始前启用
aliyun configure ai-mode enable
aliyun configure ai-mode set-user-agent --user-agent "AlibabaCloud-Agent-Skills/alibabacloud-emas-apm-query"

# 结束后关闭
aliyun configure ai-mode disable
```

### 1.5 依赖检查

```bash
aliyun version    # >= 3.3.3
jq --version      # 任意版本
```

---

## 2. 4个核心 API

所有 API 版本：`2019-06-11`，方法：`POST RPC`，Region：`cn-shanghai`。

### 2.1 `get-issues` — 聚合问题列表

查询指定 AppKey + OS + BizModule + TimeRange 下的聚合 Issue 列表。

```bash
aliyun emas-appmonitor get-issues \
  --app-key <AppKey> \
  --os <android|iphoneos|harmony> \
  --biz-module <crash|anr|lag|custom|memory_leak|memory_alloc> \
  --time-range StartTime=<ms> EndTime=<ms> Granularity=1 GranularityUnit=DAY \
  [--filter '<JSON>'] \
  [--name '<关键词>'] \
  [--order-by ErrorCount|ErrorRate|ErrorDeviceCount|ErrorDeviceRate] \
  [--order-type asc|desc] \
  [--status 1|2|3|4] \
  [--page-index <int>] \
  [--page-size <int>]
```

**参数说明：**

| 参数 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `--app-key` | 是 | int64 | EMAS APP Key（通常9位以上数字） |
| `--os` | 强烈建议 | enum | `android` / `iphoneos` / `harmony`，不传会返回空结果 |
| `--biz-module` | 是 | enum | 问题类型 |
| `--time-range` | 是 | object | `StartTime=<ms> EndTime=<ms> Granularity=<int> GranularityUnit=<HOUR\|DAY>` |
| `--filter` | 否 | JSON | 筛选条件，JSON 字符串 |
| `--name` | 否 | string | 按 Name 模糊搜索 |
| `--order-by` | 否 | string | 排序字段：ErrorCount / ErrorRate / ErrorDeviceCount / ErrorDeviceRate |
| `--order-type` | 否 | string | `asc` / `desc`，默认 `desc` |
| `--status` | 否 | int | `1=未处理` / `2=处理中` / `3=已关闭` / `4=已处理` |
| `--page-index` | 否 | int | 页码，默认 1 |
| `--page-size` | 否 | int | 每页条数，建议 10~50，**最小2** |

**返回字段（Model.Items[*]）：**

| 字段 | 类型 | 说明 |
|------|------|------|
| DigestHash | string | 问题唯一 ID（Base36，13位） |
| Name | string | 问题标题 |
| Status | int32 | 1=未处理 / 2=处理中 / 3=已关闭 / 4=已处理 |
| FirstVersion | string | 首次出现版本 |
| ErrorCount | int32 | 错误次数 |
| ErrorRate | double | 错误率 |
| ErrorDeviceCount | int32 | 受影响设备数 |
| ErrorDeviceRate | double | 受影响设备率 |
| AffectedUserCount | int32 | 受影响用户数 |
| Stack | string | 截断堆栈 |
| Type | string | 异常类型 |
| Reason | string | 异常原因 |
| LagCost | int64 | 卡顿时长（仅 lag） |
| EventTime | string | 最近事件时间 |
| Tags | array | 标签 |

---

### 2.2 `get-issue` — 单个问题详情

查询某个聚合问题（DigestHash）的详细统计信息。

```bash
aliyun emas-appmonitor get-issue \
  --app-key <AppKey> \
  --os <android|iphoneos|harmony> \
  --biz-module <crash|anr|lag|custom|memory_leak|memory_alloc> \
  --digest-hash <13位Base36> \
  --time-range StartTime=<ms> EndTime=<ms> Granularity=1 GranularityUnit=DAY \
  [--filter '<JSON>']
```

**返回字段（Model）：**

| 字段 | 类型 | 说明 |
|------|------|------|
| DigestHash | string | 回显输入 |
| Name | string | 问题标题 |
| Status | int32 | 状态 |
| FirstVersion | string | 首次出现版本 |
| **AffectedVersions** | array\<string\> | **受影响版本列表** |
| GmtCreate | int64 | 首次创建时间（ms） |
| GmtLatest | int64 | 最近发生时间（ms） |
| ErrorCount / ErrorRate | int32 / double | 绝对数量和比率 |
| ErrorCountGrowthRate | double | 错误数环比增长率 |
| ErrorRateGrowthRate | double | 错误率环比增长率 |
| ErrorDeviceCount / ErrorDeviceRate | int32 / double | 受影响设备 |
| Stack | string | 完整堆栈 |
| CruxStack / KeyLine | string / int32 | 关键堆栈和关键行 |
| Summary | string | 机器摘要 |
| SymbolicStatus | boolean | 是否已符号化（iOS） |
| Type / Reason | string | 异常类型和原因 |

---

### 2.3 `get-errors` — 样本列表

查询某个 Issue 下的错误样本列表。

```bash
aliyun emas-appmonitor get-errors \
  --app-key <AppKey> \
  --os <android|iphoneos|harmony> \
  --biz-module <crash|anr|lag|custom|memory_leak|memory_alloc> \
  --digest-hash <13位Base36> \
  --time-range StartTime=<ms> EndTime=<ms> \
  --page-index 1 --page-size 5 \
  [--filter '<JSON>'] \
  [--utdid '<utdid>']
```

> ⚠️ `--time-range` 只接受 `StartTime` + `EndTime`，**不支持 Granularity**

**返回字段（Model.Items[*]）— 仅5个字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| ClientTime | int64 | 客户端时间（ms）— get-error 必需 |
| Uuid | string | 事件唯一 ID — get-error 强烈建议 |
| Did | string | 设备 ID — get-error 需要 |
| Utdid | string | UTDID（脱敏设备 ID） |
| DigestHash | string | 所属 Issue 的 Hash |

---

### 2.4 `get-error` — 样本详情

查询单个错误样本的完整详情。

```bash
aliyun emas-appmonitor get-error \
  --app-key <AppKey> \
  --os <android|iphoneos|harmony> \
  --biz-module <crash|anr|lag|custom|memory_leak|memory_alloc> \
  --client-time <ms> \
  --uuid <Uuid> \
  --did <Did> \
  --digest-hash <13位Base36> \
  [--biz-force false]
```

> ⚠️ 没有此 API 的 `--time-range` 参数，用 `--client-time` 定位样本

**返回字段（Model）— 约65个字段，按用途分组：**

#### A. 基础维度

| 字段 | 类型 | 说明 |
|------|------|------|
| AppVersion | string | 应用版本 |
| Build | string | 构建号 |
| Os | string | 操作系统 |
| OsVersion | string | 系统版本 |
| Brand | string | 品牌 |
| DeviceModel | string | 设备型号 |
| Resolution | string | 屏幕分辨率 |
| Channel | string | 渠道 |
| Language | string | 语言 |
| Country / Province / City | string | 地域 |
| Carrier / Isp / Access / AccessSubType | string | 运营商/网络 |
| CpuModel | string | CPU 型号 |
| InMainProcess | int | 是否主进程 |
| ForeGround | int | 是否前台 |
| IsJailbroken / IsSimulator | int | 设备状态 |
| SdkVersion | string | SDK 版本 |
| UserId / UserNick | string | 业务用户 |
| ProcessName | string | 进程名 |

#### B. 异常描述

| 字段 | 类型 | 说明 |
|------|------|------|
| ExceptionType | string | 异常类型 |
| ExceptionSubtype | string | 子类型 |
| ExceptionCodes | string | 信号/KERN 代码 |
| ExceptionMsg | string | 异常原因描述 |
| ExceptionDetail | string | 详细信息 |
| Summary | string | 机器摘要 |
| Digest | string | 堆栈摘要 |
| ReportType | string | 报告类型（MOTU_IOS_CRASH 等） |
| ReportContent | string | 原始崩溃报告 |
| LagCost | int64 | 卡顿时长（仅 lag） |

#### C. 堆栈与线程

| 字段 | 类型 | 说明 |
|------|------|------|
| **Backtrace** | string | 崩溃线程堆栈（最重要） |
| ThreadName | string | 崩溃线程名 |
| Threads | array\<object\> | 所有线程（ThreadId / ThreadName / Stack / IsMain） |
| SymbolicFileType | string | 符号文件类型 |

#### D. 业务日志与扩展

| 字段 | 类型 | 说明 |
|------|------|------|
| EventLog | string | 事件日志（页面导航/生命周期/面包屑） |
| MainLog | string | 主线程日志 |
| CustomInfo | string | 开发者注入的键值对 |
| Controllers | string | 页面路径（VC/Activity 栈） |
| View | string | 当前视图路径 |

#### E. 内存与 IO

| 字段 | 类型 | 说明 |
|------|------|------|
| MemInfo | string | 内存使用摘要 |
| MemoryMap | string | 内存映射 |
| FileDescriptor | string | FD 使用情况 |

---

## 3. 问题类型（biz-module）

| biz-module | 中文名 | 适用场景 | 典型根因 |
|-----------|--------|---------|---------|
| `crash` | 崩溃 | 进程异常终止 | 空指针、越界、竞态、Native 内存损坏 |
| `anr` | ANR（应用无响应） | 主线程阻塞超时 | 主线程 IO、锁竞争、慢广播 |
| `lag` | 卡顿 | 低 FPS / 主线程执行超阈值 | 大图解码、过度布局、同步网络、JSON 解析 |
| `custom` | 自定义异常 | 业务错误上报 | 业务校验失败、接口异常 |
| `memory_leak` | 内存泄漏 | 不可释放的引用链 | 静态持有 Activity、单例持有 Context |
| `memory_alloc` | 内存分配 | 大额分配/批量增长 | Bitmap 未采样、无界缓存 |

---

## 4. 平台支持矩阵

| 问题类型 | Android | iOS | HarmonyOS |
|---------|---------|-----|-----------|
| `crash` | ✅ | ✅ | ✅ |
| `anr` | ✅ | ✅ | ❌ |
| `lag` | ✅ | ✅ | ✅ |
| `custom` | ✅ | ✅ | ✅ |
| `memory_leak` | ✅ | ✅ | ❌ |
| `memory_alloc` | ✅ | ✅ | ❌ |

> HarmonyOS 不支持 `anr` / `memory_leak` / `memory_alloc`，查询会返回空结果但不报错

---

## 5. 筛选参数（--filter）

### 5.1 基本格式

`--filter` 接收一个 **JSON 字符串**（不是 flat 格式）：

```bash
--filter '{"Key":"appVersion","Operator":"in","Values":["3.5.0","3.5.1"]}'
```

### 5.2 完整操作符

| 操作符 | 含义 | 适用字段 |
|--------|------|---------|
| `=` / `!=` | 等于/不等于 | 单值字段 |
| `in` / `not in` | 属于/不属于集合 | 枚举/字符串字段 |
| `>` / `<` / `>=` / `<=` | 数值比较 | 数值字段（如 lagCost） |
| `and` | 逻辑与 | 组合节点，用 SubFilters |
| `or` | 逻辑或 | 组合节点，用 SubFilters |
| `not` | 逻辑非 | 组合节点 |

### 5.3 组合筛选

```bash
# 用 jq 构建嵌套 JSON，避免手写转义
SUB1='{"Key":"appVersion","Operator":"in","Values":["3.5.0","3.5.1"]}'
SUB2='{"Key":"brand","Operator":"=","Values":["Apple"]}'
SUB3='{"Key":"province","Operator":"=","Values":["浙江"]}'

FILTER=$(jq -cn --arg s1 "$SUB1" --arg s2 "$SUB2" --arg s3 "$s3" \
  '{Key:"",Operator:"and",Values:[],SubFilters:[$s1,$s2,$s3]}')

aliyun emas-appmonitor get-issues \
  --app-key 335695934 --os iphoneos --biz-module crash \
  --time-range StartTime=$START EndTime=$END Granularity=1 GranularityUnit=DAY \
  --filter "$FILTER"
```

### 5.4 常用筛选示例

```bash
# 指定版本
--filter '{"Key":"appVersion","Operator":"=","Values":["3.5.0"]}'

# 多版本
--filter '{"Key":"appVersion","Operator":"in","Values":["3.5.0","3.5.1","3.5.2"]}'

# 排除版本
--filter '{"Key":"appVersion","Operator":"not in","Values":["3.5.0-beta"]}'

# 首次出现版本
--filter '{"Key":"firstVersion","Operator":"=","Values":["3.5.0"]}'

# 指定设备型号
--filter '{"Key":"deviceModel","Operator":"in","Values":["iPhone14,5","iPhone14,2"]}'

# 指定系统版本
--filter '{"Key":"osVersion","Operator":"in","Values":["17.0","17.1","17.2"]}'

# 指定品牌
--filter '{"Key":"brand","Operator":"=","Values":["Apple"]}'

# 卡顿 >= 500ms
--filter '{"Key":"lagCost","Operator":">=","Values":["500"]}'

# 是否 OOM
--filter '{"Key":"isOom","Operator":"=","Values":["1"]}'

# 仅前台
--filter '{"Key":"isForeground","Operator":"=","Values":["1"]}'

# 仅主进程
--filter '{"Key":"inMainProcess","Operator":"=","Values":["True"]}'

# 问题状态
--filter '{"Key":"issueStatus","Operator":"in","Values":["1","2"]}'

# 崩溃类型
--filter '{"Key":"crashType","Operator":"=","Values":["MOTU_ANDROID_CRASH"]}'
```

---

## 6. 完整筛选字段清单

### 6.1 静态筛选字段（预定义枚举值）

| filterCode | 中文名 | 类型 | 可选值 |
|-----------|--------|------|--------|
| `crashType` | 崩溃类型 | checkbox | Android: `MOTU_ANDROID_CRASH`(Java), `MOTU_ANDROID_NATIVE_CRASH`(Native); iOS: `MOTU_IOS_CRASH`, `MOTU_IOS_MACH_EXCEPTION`, `MOTU_IOS_NATIVE_CRASH` |
| `isOom` | 是否 OOM | radio | `1`(是), `0`(否) |
| `shadow_launchedCrashDuration` | 启动状态 | radio | `1`(启动阶段), `0`(非启动阶段) |
| `isForeground` | 是否前台 | radio | `1`(是), `0`(否), `2`(未知) |
| `isJailbroken` | 是否 root | radio | `1`(是), `0`(否), `2`(未知) |
| `inMainProcess` | 是否主进程 | radio | `True`(是), `False`(否) |
| `isSimulator` | 运行环境 | radio | `0`(真机), `1`(模拟器) |
| `issueStatus` | 问题状态 | checkbox | `1`(未处理), `2`(处理中), `3`(已关闭), `4`(已处理), `5`(已忽略) |
| `componentType` | 组件类型（iOS） | checkbox | APP / Extension / Watch |
| `customErrorLanguage` | 自定义错误语言 | checkbox | Java / OC / Swift / JavaScript / ArkTS / Dart / C# |
| `isCustomErrorFlag` | 自定义错误标记 | checkbox | - |
| `digestHash` | 问题 ID | text | 13位 Base36 |
| `utdid` | 设备 ID | text | - |
| `clientIp` | 客户端 IP | text | - |
| `userNick` | 用户昵称 | text | - |
| `userId` | 用户 ID | text | - |

### 6.2 动态筛选字段（需自行提供值）

| filterCode | 中文名 | 类型 | 说明 |
|-----------|--------|------|------|
| `appVersion` | 应用版本 | checkbox | SDK 自动上报，随发版动态产生 |
| `build` | 构建号 | checkbox | SDK 自动上报 |
| `firstVersion` | 首现版本 | checkbox | 问题首次出现的版本 |
| `osVersion` | 系统版本 | checkbox | 如 "17.0", "14" |
| `brand` | 品牌 | checkbox | 如 "Apple", "Xiaomi" |
| `deviceModel` | 机型 | checkbox | 如 "iPhone14,5" |
| `channel` | 渠道 | checkbox | 如 "AppStore", "HuaWei" |
| `language` | 语言 | checkbox | 如 "zh-Hans" |
| `view` | 页面 | checkbox | 当前视图路径 |
| `access` | 网络 | checkbox | WIFI / 4G / 5G 等 |
| `country` | 国家/地区 | checkbox | - |
| `province` | 省份 | checkbox | - |
| `city` | 城市 | checkbox | - |
| `resolution` | 分辨率 | checkbox | - |
| `processName` | 进程 | checkbox | 如 ":background" |
| `carrier` | 运营商 | checkbox | - |
| `cpuModel` | CPU 架构 | checkbox | - |
| `tag` | 标签 | checkbox | 自定义标签 |
| `additionalCustomInfo` | 自定义维度 | custom | - |

### 6.3 筛选字段 vs 平台 vs 问题类型对照

**crash × android（32个筛选字段）：**

| 类型 | 字段 |
|------|------|
| 静态 | crashType, isOom, shadow_launchedCrashDuration, utdid, clientIp, userNick, userId, isForeground, isJailbroken, inMainProcess, digestHash, isSimulator, issueStatus |
| 动态 | appVersion, build, firstVersion, osVersion, brand, deviceModel, channel, language, view, access, country, province, city, resolution, processName, carrier, cpuModel, tag, additionalCustomInfo |

**crash × iphoneos（31个筛选字段）：**

| 类型 | 字段 |
|------|------|
| 静态 | componentType, crashType, shadow_launchedCrashDuration, utdid, clientIp, userNick, userId, isForeground, isJailbroken, inMainProcess, digestHash, issueStatus |
| 动态 | 同 android（19个） |

**crash × harmony（27个筛选字段）：**

| 类型 | 字段 |
|------|------|
| 静态 | crashType, utdid, clientIp, userNick, userId, isForeground, inMainProcess, digestHash, issueStatus |
| 动态 | appVersion, build, firstVersion, osVersion, brand, deviceModel, channel, language, view, access, country, province, city, resolution, processName, carrier, cpuModel, tag |

**anr × android（29个筛选字段）：**

| 类型 | 字段 |
|------|------|
| 静态 | utdid, clientIp, userNick, userId, isForeground, isJailbroken, inMainProcess, digestHash, isSimulator, issueStatus |
| 动态 | 同 crash × android（19个） |

**lag × android（29个筛选字段）：**

| 类型 | 字段 |
|------|------|
| 静态 | 同 anr × android |
| 动态 | 同 crash × android（19个） |

**lag × iphoneos（28个筛选字段）：** 同 lag × android（减去 isSimulator）

**lag × harmony（26个筛选字段）：** 同 crash × harmony 的动态字段

**custom × android（31个筛选字段）：** crash × android 的静态字段 + customErrorLanguage + isCustomErrorFlag（减去 isOom、shadow_launchedCrashDuration）

**custom × iphoneos（30个筛选字段）：** 同 custom × android（减去 isSimulator）

**custom × harmony（26个筛选字段）：** 同 crash × harmony 静态字段

**memory_leak / memory_alloc × android（26个筛选字段）：**

| 类型 | 字段 |
|------|------|
| 静态 | deviceId, clientIp, userNick, userId, isForeground, isJailbroken, digestHash, isSimulator, issueStatus |
| 动态 | appVersion, build, firstVersion, osVersion, brand, deviceModel, channel, language, access, country, province, city, resolution, carrier, cpuModel, tag, additionalCustomInfo |

**memory_leak / memory_alloc × iphoneos（25个筛选字段）：** 同 android（减去 isSimulator）

> 完整 JSON 定义在 `assets/system-filters/<biz-module>-<platform>.json`

---

## 7. API 返回字段

### 7.1 你提到的字段 vs 官方字段对照

| 你的字段 | 官方字段 | 所在 API | 说明 |
|---------|---------|---------|------|
| digestHash | DigestHash | get-issues / get-issue | 问题唯一哈希 |
| errorName | Name | get-issues / get-issue | 错误名称 |
| errorCount | ErrorCount | get-issues / get-issue | 错误次数 |
| errorDeviceCount | ErrorDeviceCount | get-issues / get-issue | 受影响设备数 |
| errorRatePercent | ErrorRate | get-issues / get-issue | 错误率 |
| deviceRatePercent | ErrorDeviceRate | get-issues / get-issue | 设备率 |
| firstVersion | FirstVersion | get-issues / get-issue | 首次出现版本 |
| issueStatus | Status | get-issues / get-issue | 问题状态 |
| stack | Stack | get-issues / get-issue | 堆栈信息 |
| errorType | Type | get-issues / get-issue | 错误类型 |
| eventTime | EventTime | get-issues | 事件时间 |

### 7.2 字段分类：维度 vs 指标

| 类型 | 特征 | 是否可筛选 | 处理方式 |
|------|------|-----------|---------|
| **维度字段** | 谁/什么设备/什么版本/什么地域 | ✅ 可 `--filter` | 直接筛选 |
| **指标字段** | 多少次/多高率/什么时候 | ❌ 不可筛选 | 排序（`--order-by`）或时间范围（`--time-range`） |

---

## 8. 脚本工具

### 8.1 `list_top_issues.sh` — 批量扫描 Top N

并行查询6种问题类型，合并排序取 Top N。

```bash
bash "$SKILL_DIR/scripts/list_top_issues.sh" \
  --app-key <AppKey> \
  --os <android|iphoneos|harmony> \
  --start-time <ms> \
  --end-time <ms> \
  --top-n 5 \
  --order-by ErrorRate \
  [--biz-modules crash,anr,lag,custom,memory_leak,memory_alloc] \
  [--filter-json '<JSON>'] \
  [--granularity 1] \
  [--granularity-unit DAY] \
  [--output table|json]
```

**输出格式（table）：**
```
#    bm      digestHash      ec        er          edc      name
1    crash   3JE6F43KCQ1SV   150       0.023       89       NullPointerException
2    anr     7AB2K91PXN3RT   80        0.015       45       MainActivity.onCreate
```

**输出格式（json）：**
```json
[{"bm":"crash","dh":"3JE6F43KCQ1SV","name":"...","ec":150,"er":0.023,"edc":89,...}]
```

### 8.2 `dig_issue.sh` — 下钻单个问题

对单个 DigestHash 执行 get-issue → get-errors → get-error 全链路查询。

```bash
bash "$SKILL_DIR/scripts/dig_issue.sh" \
  --app-key <AppKey> \
  --os <android|iphoneos|harmony> \
  --biz-module <crash|anr|lag|custom|memory_leak|memory_alloc> \
  --digest-hash <13位Base36> \
  --start-time <ms> \
  --end-time <ms> \
  --sample-size 3 \
  [--out-dir <dir>] \
  [--granularity 1] \
  [--granularity-unit DAY]
```

**输出目录结构：**
```
emas-apm-dig-<AppKey>-<DigestHash>-<epoch>/
  01-get-issue.json          # get-issue 原始响应
  02-get-errors.json         # get-errors 样本列表
  02-get-errors.tsv          # ClientTime/Uuid/Did 三元组
  samples/<Uuid>.json        # 每个样本的完整 get-error 响应
  report.md                  # 结构化 Markdown 报告
```

---

## 9. 常用查询场景

### 9.1 查崩溃 Top 5

```bash
NOW_MS=$(($(date +%s) * 1000)); START_MS=$(($NOW_MS - 7*86400000))

aliyun emas-appmonitor get-issues \
  --app-key 335695934 --os android --biz-module crash \
  --time-range StartTime=$START_MS EndTime=$NOW_MS Granularity=1 GranularityUnit=DAY \
  --order-by ErrorRate --order-type desc --page-size 5 \
  --cli-query "Model.Items[*].{dh:DigestHash,name:Name,er:ErrorRate,ec:ErrorCount}"
```

### 9.2 查 ANR Top 5

```bash
aliyun emas-appmonitor get-issues \
  --app-key 335695934 --os android --biz-module anr \
  --time-range StartTime=$START_MS EndTime=$NOW_MS Granularity=1 GranularityUnit=DAY \
  --order-by ErrorRate --order-type desc --page-size 5
```

### 9.3 查卡顿 Top 5

```bash
aliyun emas-appmonitor get-issues \
  --app-key 335695934 --os iphoneos --biz-module lag \
  --time-range StartTime=$START_MS EndTime=$NOW_MS Granularity=1 GranularityUnit=DAY \
  --order-by ErrorRate --order-type desc --page-size 5
```

### 9.4 按版本筛选崩溃

```bash
aliyun emas-appmonitor get-issues \
  --app-key 335695934 --os android --biz-module crash \
  --time-range StartTime=$START_MS EndTime=$NOW_MS Granularity=1 GranularityUnit=DAY \
  --filter '{"Key":"appVersion","Operator":"in","Values":["3.5.0","3.5.1"]}'
```

### 9.5 查新版本引入的问题

```bash
aliyun emas-appmonitor get-issues \
  --app-key 335695934 --os android --biz-module crash \
  --time-range StartTime=$START_MS EndTime=$NOW_MS Granularity=1 GranularityUnit=DAY \
  --filter '{"Key":"firstVersion","Operator":"=","Values":["3.5.0"]}'
```

### 9.6 全类型扫描 Top N（脚本）

```bash
NOW_MS=$(($(date +%s) * 1000)); START_MS=$(($NOW_MS - 24*3600000))

bash scripts/list_top_issues.sh \
  --app-key 335695934 --os android \
  --start-time $START_MS --end-time $NOW_MS \
  --top-n 5 --order-by ErrorRate
```

### 9.7 下钻单个问题（脚本）

```bash
bash scripts/dig_issue.sh \
  --app-key 335695934 --os iphoneos --biz-module crash \
  --digest-hash 3JE6F43KCQ1SV \
  --start-time $START_MS --end-time $NOW_MS \
  --sample-size 3
```

### 9.8 全链路手动调用

```bash
# Step 1: 获取 Top 1 的 DigestHash
DH=$(aliyun emas-appmonitor get-issues \
  --app-key 335695934 --os iphoneos --biz-module crash \
  --time-range StartTime=$START_MS EndTime=$NOW_MS Granularity=1 GranularityUnit=DAY \
  --order-by ErrorCount --order-type desc --page-index 1 --page-size 1 \
  --cli-query 'Model.Items[0].DigestHash' | jq -r .)

# Step 2: 获取 Issue 详情
aliyun emas-appmonitor get-issue \
  --app-key 335695934 --os iphoneos --biz-module crash \
  --digest-hash "$DH" \
  --time-range StartTime=$START_MS EndTime=$NOW_MS Granularity=1 GranularityUnit=DAY

# Step 3: 获取样本列表
SAMPLE=$(aliyun emas-appmonitor get-errors \
  --app-key 335695934 --os iphoneos --biz-module crash \
  --digest-hash "$DH" \
  --time-range StartTime=$START_MS EndTime=$NOW_MS \
  --page-index 1 --page-size 1 \
  --cli-query 'Model.Items[0].{CT:ClientTime,UUID:Uuid,DID:Did}')
CT=$(echo "$SAMPLE" | jq -r .CT)
UUID=$(echo "$SAMPLE" | jq -r .UUID)
DID=$(echo "$SAMPLE" | jq -r .DID)

# Step 4: 获取样本详情
aliyun emas-appmonitor get-error \
  --app-key 335695934 --os iphoneos --biz-module crash \
  --digest-hash "$DH" \
  --client-time "$CT" --uuid "$UUID" --did "$DID" > /tmp/sample.json

# 提取堆栈
jq '.Model | {type:.ExceptionType,msg:.ExceptionMsg,stack:.Backtrace}' /tmp/sample.json
```

### 9.9 并行扫描6种问题类型

```bash
NOW_MS=$(($(date +%s) * 1000)); START_MS=$(($NOW_MS - 7*86400000))

for MOD in crash anr lag custom memory_leak memory_alloc; do
  aliyun emas-appmonitor get-issues \
    --app-key "$APP_KEY" --os "$OS" --biz-module "$MOD" \
    --time-range StartTime=$START_MS EndTime=$NOW_MS Granularity=1 GranularityUnit=DAY \
    --order-by ErrorCount --order-type desc --page-index 1 --page-size 5 \
    --cli-query 'Model.Items[*].{Module:`'"$MOD"'`,DigestHash:DigestHash,Type:Type,ErrorCount:ErrorCount,ErrorDeviceCount:ErrorDeviceCount,FirstVersion:FirstVersion}' > /tmp/top_${MOD}.json
done

# 合并排序取 Top 5
jq -s 'flatten | sort_by(-(.ErrorCount // 0)) | .[0:5]' /tmp/top_*.json
```

---

## 10. 参数获取与自动推断

### 10.1 appVersion 来源

`appVersion` 由 **App 端 SDK 上报**，不是 API 查询出来的：

| 平台 | 来源 |
|------|------|
| Android | SDK 自动读取 `BuildConfig.VERSION_NAME` |
| iOS | SDK 自动读取 `CFBundleShortVersionString` |
| HarmonyOS | SDK 自动读取应用版本信息 |
| H5 | 手动传入 `appVersion: '1.0.0'` |
| Flutter | 自动从平台获取 |
| Unity | 自动获取 |

### 10.2 AppKey 自动推断

从 workspace 的 SDK 初始化代码中自动探测：

| 平台 | 检测文件 | grep 规则 |
|------|---------|----------|
| Android | build.gradle / AndroidManifest.xml | `setAppKey("...")` / `APP_KEY="..."` |
| iOS | *.m / *.swift | `initWithAppKey:@"..."` / `appKey: "..."` |
| HarmonyOS | *.ets / *.ts | `appKey: '...'` + `from '@aliyun/apm'` |
| Flutter | *.dart | `ApmOptions(appKey: '...')` |
| Unity | *.cs | `new ApmOptions("...")` |

### 10.3 OS 推断

| 项目特征 | 推断 OS |
|---------|---------|
| build.gradle / AndroidManifest.xml | `android` |
| *.xcodeproj / Podfile | `iphoneos` |
| module.json5 + ets/ | `harmony` |
| pubspec.yaml (Flutter) | 需用户选择 android 或 iphoneos |
| Assets/ + ProjectSettings/ + *.cs (Unity) | 需用户选择 |

### 10.4 时间戳

所有 API 使用 **Unix 毫秒**。如果传入值 < 1e12（秒级），脚本会自动 ×1000。

```bash
# 最近24小时
NOW_MS=$(($(date +%s) * 1000))
START_MS=$(($NOW_MS - 24*3600000))

# 最近7天
START_MS=$(($NOW_MS - 7*86400000))
```

---

## 11. RAM 权限

### 11.1 最小权限

| CLI 命令 | RAM Action | 用途 |
|---------|-----------|------|
| get-issues | `emasha:ViewIssues` | 聚合问题列表 |
| get-issue | `emasha:ViewIssue` | 单个问题详情 |
| get-errors | `emasha:ViewErrors` | 样本列表 |
| get-error | `emasha:ViewError` | 样本详情 |

### 11.2 自定义策略

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "emasha:ViewIssues",
        "emasha:ViewIssue",
        "emasha:ViewErrors",
        "emasha:ViewError"
      ],
      "Resource": "*"
    }
  ]
}
```

### 11.3 系统策略

| 策略 | 范围 |
|------|------|
| `AliyunEMASAppMonitorReadOnlyAccess` | emasha:View* + Resource:"*"（够用） |
| `AliyunEMASAppMonitorFullAccess` | emasha:* + Resource:"*"（不需要） |

---

## 12. 踩坑与注意事项

### 12.1 必须传 `--os`

CLI `--help` 标记为可选，但**不传会返回空结果**。所有4个 API 都必须显式指定 `android` / `iphoneos` / `harmony`。

### 12.2 `--page-size` 最小为 2

`--page-size 1` 会触发后端 `unknown error`，建议最小2，常用10~50。

### 12.3 `get-error` 必须传 `--did`

`--did` 在 `--help` 中标记为可选，但后端隐式必需，不传会返回 `Parameter Not Enough`。从 `get-errors` 的 `Items[*].Did` 获取。

### 12.4 `get-errors` 不支持 Granularity

`--time-range` 只接受 `StartTime` + `EndTime`，混入 `Granularity` 会报 `Error: unknown field: Granularity`。

### 12.5 Granularity 组合陷阱

`Granularity=60 GranularityUnit=MINUTE` 可能被后端拒绝，推荐用 `Granularity=1 GranularityUnit=DAY` 或 `GranularityUnit=HOUR`。

### 12.6 DigestHash 双重语义

`get-errors` 返回的 `Items[*].DigestHash` 是单个事件的 hash，与聚合的 `--digest-hash` 不同。`get-error` 仍使用**聚合** hash。

### 12.7 复用 biz-module

从 `get-issues` 获取 Top Issue 时使用的 `bizModule`，后续 `get-issue` / `get-errors` / `get-error` 必须复用同一个，否则返回空。

### 12.8 filter 必须是 JSON 字符串

`--filter` 只接受 JSON 字符串形式，flat 格式（`Key=appVersion Operator=in Values.1=...`）不生效。

### 12.9 SubFilters 需要多层转义

嵌套 `SubFilters` 中的每个子条件需要 `JSON.stringify` 后放入数组，用 `jq -cn` 构建最可靠。

### 12.10 Values 中数字要写字符串

`Values:["200"]` 而不是 `Values:[200]`，后端会自动转换类型。

### 12.11 get-error 响应可能很大

单次响应可达数百 KB 到数 MB，不要用 `head`/`tail` 截断，先保存到文件再用 `jq` 处理：

```bash
aliyun emas-appmonitor get-error ... > /tmp/emas-error-$(date +%s).json
jq '.Model | {type:.ExceptionType,stack:.Backtrace}' /tmp/emas-error-*.json
```

### 12.12 Android 混淆堆栈

看到类名如 `a.a.a.b.c` 时，需用户提供 `mapping.txt` 才能还原。

### 12.13 iOS 未符号化

`SymbolicStatus=false` 时 Stack 含大量十六进制地址，需上传 dSYM 后重新拉取。

### 12.14 时间窗口建议

先宽后窄：24h + DAY → 定位版本/设备后缩到 1~4h + HOUR。

### 12.15 避免的操作符

`eq` / `neq` / `not_in` 在 `--filter` 中观察到不工作，使用 `in` 或 `or` 替代。

---

## 13. 故障排查

### 13.1 CLI 自检步骤

```bash
# 1. 检查当前配置
aliyun configure list

# 2. 更新插件
aliyun plugin update

# 3. 参数序列化检查（不发真实请求）
aliyun emas-appmonitor get-issues ... --cli-dry-run

# 4. 调试模式（含 HTTP body + RequestId）
aliyun emas-appmonitor get-issues ... --log-level debug
```

### 13.2 常见错误

| HTTP | ErrorCode | 含义 | 处理 |
|------|-----------|------|------|
| 400 | InvalidAppId | AppKey 不存在 | 确认 AppKey |
| 400 | InvalidParameters | 参数无效（时间/粒度组合等） | 检查时间戳单位和粒度 |
| 400 | InvalidRequest | 请求结构无效 | 检查 body 字段名 |
| 403 | Forbidden.NoRAMPermission | 缺少 RAM 权限 | 见 RAM 权限章节 |
| 403 | Forbidden.NoPermission | 账号不拥有此 AppKey | 找 AppKey 所属账号 |
| 406 | UnexpectedAppStatus | 应用状态异常 | 在控制台激活子服务 |
| 500 | InternalError | 后端错误 | 重试，附 RequestId 报告 |

### 13.3 验证筛选是否生效

```bash
# 1. 不带 filter 查一次，记录 Model.Total
# 2. 带 filter 查一次，新的 Model.Total 应明显小于步骤1
# 3. 用 --cli-dry-run + --log-level debug 确认 Filter 字段
```

---

## 14. 清理

此 Skill 只读，不创建云资源。清理仅限本地：

```bash
# 关闭 AI 模式
aliyun configure ai-mode disable

# 删除 dig_issue.sh 产生的本地 JSON 目录
rm -rf ./emas-apm-dig-*
```

---

## 附录：JMESPath 查询模板

| 场景 | JMESPath |
|------|----------|
| Top Hash | `Model.Items[0].DigestHash` |
| Flatten Top N | `Model.Items[*].{Hash:DigestHash,Count:ErrorCount}` |
| Issue 概览 | `Model.{Hash:DigestHash,Type:Type,Versions:AffectedVersions,Stack:Stack}` |
| 样本三元组 | `Model.Items[*].{CT:ClientTime,UUID:Uuid,DID:Did}` |
| 样本维度 | `Model.{App:AppVersion,Os:OsVersion,Brand:Brand,Model:DeviceModel}` |
| 堆栈+原因 | `Model.{type:ExceptionType,subType:ExceptionSubtype,msg:ExceptionMsg,stack:Backtrace}` |
| 事件日志+页面 | `Model.{eventLog:EventLog,mainLog:MainLog,controllers:Controllers,custom:CustomInfo}` |
| 多线程状态 | `Model.Threads[*].{name:ThreadName,isMain:IsMain,stack:Stack}` |
| 增长率 | `Model.{ec:ErrorCount,ecGrowth:ErrorCountGrowthRate,er:ErrorRate,erGrowth:ErrorRateGrowthRate}` |
