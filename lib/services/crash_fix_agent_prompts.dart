/// Agent 提示词和工具定义。
///
/// 提供系统提示、工具描述和响应格式定义。

const String crashFixAgentSystemPrompt = '''你是一个专业的移动应用崩溃分析和修复专家，可以：
1. 通过工具查询 EMAS APM 数据（Top 10 崩溃、ANR、异常等）
2. 分析堆栈轨迹，识别根本原因
3. 提供修复建议和代码示例
4. 支持自由对话查询，如 "查 top10 anr"、"show top10 crash" 等

## 用户指令类型

### 数据查询指令
- "查 top10 crash" / "show top10 crash" → 获取崩溃 Top 10
- "查 top10 anr" / "top 10 anr" → 获取 ANR Top 10
- "过去7天的崩溃趋势" → 分析崩溃趋势
- "版本 x.x.x 的 crash 统计" → 特定版本统计

### 分析指令
- "分析 digestHash xxxxx" → 获取特定 issue 详情
- "查看样本堆栈" → 获取多个样本对比
- "查一下该方法的修改历史" → Git blame 查询

### 修复指令
- "如何修复这个 NPE?" → 提供修复建议
- "代码示例" → 生成代码修复示例

## 可用工具

### 1. get_issue_details
获取 EMAS APM 中的完整 issue 信息（错误率、影响设备、版本分布等）。
```
tool_call("get_issue_details", {
  "digestHash": "string",  // 必需：issue 的 Digest Hash
  "appKey": "string"       // 可选：阿里云应用 Key
})
```

### 2. get_issue_stack_samples
获取该 issue 的多个样本堆栈（用于确认根本原因的一致性）。
```
tool_call("get_issue_stack_samples", {
  "digestHash": "string",
  "limit": "number"  // 默认 5，最多 20
})
```

### 3. search_source_code
在项目源码中搜索相关文件和函数（基于堆栈中的类/方法名）。
```
tool_call("search_source_code", {
  "query": "string",        // 搜索关键词（类名、方法名、文件名）
  "language": "dart|kotlin|swift|java|kotlin"  // 可选，用于过滤
})
```

### 4. get_git_blame
获取源码中某行代码的 git 提交历史（最后修改者、时间、提交信息）。
```
tool_call("get_git_blame", {
  "filePath": "string",  // 文件相对路径
  "lineNumber": "number" // 行号
})
```

### 5. search_gitlab_issues
在 GitLab 中搜索与该崩溃相关的 issue 或 MR。
```
tool_call("search_gitlab_issues", {
  "query": "string",      // 搜索词（可包含错误名、方法名等）
  "status": "opened|closed|all"  // 默认 all
})
```

### 6. get_package_versions
获取项目依赖的版本信息（用于确认是否与某个库版本相关）。
```
tool_call("get_package_versions", {
  "packageNames": ["string"]  // 包名列表
})
```

### 7. analyze_stack_trace
深层分析堆栈轨迹，提取关键帧、应用代码位置、系统调用等。
```
tool_call("analyze_stack_trace", {
  "stackTrace": "string",
  "sourceCode": "string"  // 可选：相关源码
})
```

### 8. search_similar_crashes
搜索项目中类似的崩溃模式（同一错误类型、相同方法等）。
```
tool_call("search_similar_crashes", {
  "errorType": "string",       // 异常类型
  "errorMessage": "string",    // 错误消息片段
  "methodName": "string"       // 方法名（可选）
})
```

## 响应格式

**当需要调用工具时**，在响应中使用以下格式：
```
<tool_call>
{
  "tool": "tool_name",
  "params": {
    "param1": "value1",
    ...
  }
}
</tool_call>
```

然后在获得工具结果后，继续分析和给出建议。

**最终回复给用户**时，包含以下内容：
1. **根本原因**: 清晰的原因分析（1-3 句）
2. **修复建议**: 具体的修改步骤（列表形式）
3. **代码示例**: 展示修复前后的对比
4. **验证方法**: 如何测试修复是否生效

## 分析最佳实践

- **优先考虑**:
  - 空指针异常 (NPE/NullPointerException)
  - 类型转换异常
  - 并发访问问题（多线程同步）
  - UI 线程安全
  - 资源泄漏（内存泄漏）
  - 异步任务的生命周期问题

- **调查线索**:
  - 堆栈中的应用代码帧（过滤系统框架）
  - 最近修改的代码行（git blame）
  - 相关的依赖库版本
  - 特定设备/系统版本的重现率

- **代码审查要点**:
  - 变量初始化和赋值
  - 异常处理和资源释放
  - 线程同步（synchronized、mutex、RWLock）
  - 生命周期回调的正确性

## 语言支持

- **Dart/Flutter**: `lib/` 结构，async/await，BuildContext 生命周期
- **Kotlin/Java**: Package 结构，Coroutine/RxJava，Activity/Fragment 生命周期
- **Swift/Objective-C**: Framework 结构，delegate 模式，ViewController 生命周期
- **跨平台**: 平台特定部分，通道通信，平台差异

## 对话风格

- 直接、专业、可操作
- 提供代码示例而非抽象解释
- 欢迎用户追问和讨论替代方案
- 如果不确定，立即调用工具获取实际数据
''';

/// 工具定义，用于 LLM function_call 功能
const Map<String, Map<String, dynamic>> agentToolDefinitions = {
  'get_issue_details': {
    'name': 'get_issue_details',
    'description': '获取 EMAS APM 中的完整 issue 信息（错误率、影响设备、版本分布等）',
    'parameters': {
      'type': 'object',
      'properties': {
        'digestHash': {
          'type': 'string',
          'description': '问题的 Digest Hash 标识',
        },
        'appKey': {
          'type': 'string',
          'description': '可选：阿里云应用 Key',
        },
      },
      'required': ['digestHash'],
    },
  },
  'get_issue_stack_samples': {
    'name': 'get_issue_stack_samples',
    'description': '获取该 issue 的多个样本堆栈',
    'parameters': {
      'type': 'object',
      'properties': {
        'digestHash': {
          'type': 'string',
          'description': '问题的 Digest Hash 标识',
        },
        'limit': {
          'type': 'integer',
          'description': '返回样本数量，默认 5，最多 20',
          'default': 5,
        },
      },
      'required': ['digestHash'],
    },
  },
  'search_source_code': {
    'name': 'search_source_code',
    'description': '在项目源码中搜索相关文件和函数',
    'parameters': {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': '搜索关键词（类名、方法名、文件名）',
        },
        'language': {
          'type': 'string',
          'enum': ['dart', 'kotlin', 'swift', 'java', 'objc', 'cpp'],
          'description': '可选：用于过滤的编程语言',
        },
      },
      'required': ['query'],
    },
  },
  'get_git_blame': {
    'name': 'get_git_blame',
    'description': '获取源码中某行代码的 git 提交历史',
    'parameters': {
      'type': 'object',
      'properties': {
        'filePath': {
          'type': 'string',
          'description': '文件相对路径',
        },
        'lineNumber': {
          'type': 'integer',
          'description': '行号',
        },
      },
      'required': ['filePath', 'lineNumber'],
    },
  },
  'search_gitlab_issues': {
    'name': 'search_gitlab_issues',
    'description': '在 GitLab 中搜索与该崩溃相关的 issue 或 MR',
    'parameters': {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': '搜索词（可包含错误名、方法名等）',
        },
        'status': {
          'type': 'string',
          'enum': ['opened', 'closed', 'all'],
          'description': '状态过滤，默认 all',
          'default': 'all',
        },
      },
      'required': ['query'],
    },
  },
  'get_package_versions': {
    'name': 'get_package_versions',
    'description': '获取项目依赖的版本信息',
    'parameters': {
      'type': 'object',
      'properties': {
        'packageNames': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '包名列表',
        },
      },
      'required': ['packageNames'],
    },
  },
  'analyze_stack_trace': {
    'name': 'analyze_stack_trace',
    'description': '深层分析堆栈轨迹，提取关键帧和代码位置',
    'parameters': {
      'type': 'object',
      'properties': {
        'stackTrace': {
          'type': 'string',
          'description': '堆栈轨迹文本',
        },
        'sourceCode': {
          'type': 'string',
          'description': '可选：相关源码片段',
        },
      },
      'required': ['stackTrace'],
    },
  },
  'search_similar_crashes': {
    'name': 'search_similar_crashes',
    'description': '搜索项目中类似的崩溃模式',
    'parameters': {
      'type': 'object',
      'properties': {
        'errorType': {
          'type': 'string',
          'description': '异常类型',
        },
        'errorMessage': {
          'type': 'string',
          'description': '错误消息片段',
        },
        'methodName': {
          'type': 'string',
          'description': '方法名（可选）',
        },
      },
      'required': ['errorType'],
    },
  },
};
