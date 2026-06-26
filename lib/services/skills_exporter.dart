/// Skills 导出器 - 生成 OpenClaw Skills 规范的压缩包。
///
/// 为已安装当前应用的用户导出一份完整的 Skills 压缩包，
/// 包含所有 API 能力、文档、示例代码，可直接在其他 AI 工具中使用。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../models/tool_config.dart';

/// Skills 导出器
class SkillsExporter {
  SkillsExporter({
    required this.config,
    required this.appVersion,
  });

  final ToolConfig config;
  final String appVersion;

  /// 导出 Skills 包
  ///
  /// 返回本地文件路径
  Future<String> exportSkillsPackage({
    required String outputDir,
  }) async {
    try {
      final archive = Archive();

      // 1. 创建 SKILLS.md 文档
      final skillsMd = _generateSkillsMd();
      archive.addFile(
        ArchiveFile('SKILLS.md', skillsMd.length, utf8.encode(skillsMd)),
      );

      // 2. 创建 package.json
      final packageJson = _generatePackageJson();
      archive.addFile(
        ArchiveFile('package.json', packageJson.length, utf8.encode(packageJson)),
      );

      // 3. 创建 README.md
      final readmeMd = _generateReadmeMd();
      archive.addFile(
        ArchiveFile('README.md', readmeMd.length, utf8.encode(readmeMd)),
      );

      // 4. 创建 index.ts (MCP 标准实现)
      final indexTs = _generateIndexTs();
      archive.addFile(
        ArchiveFile('index.ts', indexTs.length, utf8.encode(indexTs)),
      );

      // 5. 创建 examples 目录
      final examples = _generateExamples();
      for (final (fileName, content) in examples) {
        archive.addFile(
          ArchiveFile(
            'examples/$fileName',
            content.length,
            utf8.encode(content),
          ),
        );
      }

      // 6. 创建 .gitignore
      const gitignore = '''node_modules/
.env
.env.local
*.log
dist/
build/
.DS_Store
''';
      archive.addFile(
        ArchiveFile('.gitignore', gitignore.length, utf8.encode(gitignore)),
      );

      // 7. 创建 tsconfig.json
      final tsconfig = _generateTsconfig();
      archive.addFile(
        ArchiveFile('tsconfig.json', tsconfig.length, utf8.encode(tsconfig)),
      );

      // 导出为 ZIP 文件
      final now = DateTime.now();
      final timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final fileName = 'emas-crashtools-skills-$timestamp.zip';
      final filePath = p.join(outputDir, fileName);

      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) {
        throw Exception('Failed to encode ZIP');
      }

      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(zipData);

      return filePath;
    } catch (e) {
      throw Exception('导出 Skills 包失败: $e');
    }
  }

  /// 生成 SKILLS.md
  String _generateSkillsMd() {
    return '''---
name: emas-crashtools
description: EMAS 崩溃修复 Agent Skills。通过集成当前应用的 API 能力，提供崩溃查询、ANR 分析、报告生成等功能。Keywords: EMAS, 崩溃分析, ANR分析, 报告生成, 源码分析, 自动修复.
---

# EMAS 崩溪修复 Agent Skills

基于 EMAS 应用性能监控平台，提供智能崩溃分析和修复建议。

## 🎯 功能概述

本 Skills 包集成了 EMAS-crashtools 应用的所有 API 能力，支持：

- ✅ **查询能力**: Top 10 崩溃/ANR、Issue 详情、版本统计
- ✅ **分析能力**: 堆栈分析、相似崩溃搜索、根因诊断
- ✅ **报告能力**: 生成汇总报告、导出 HTML/Markdown、批量分析
- ✅ **代码能力**: 源码搜索、Git Blame、版本依赖查询

## 📋 支持的工具

### 核心工具 (MCP Tools)

| 工具名 | 功能描述 |
|--------|---------|
| \`get_top10_crash\` | 获取 Top 10 崩溃问题 |
| \`get_top10_anr\` | 获取 Top 10 ANR 卡顿问题 |
| \`get_issue_detail\` | 获取单个 issue 详情 |
| \`batch_analyze\` | 批量分析多个 issues |
| \`analyze_stack_trace\` | 分析堆栈轨迹 |
| \`search_similar_crashes\` | 搜索相似崩溃 |
| \`generate_report\` | 生成完整分析报告 |
| \`get_versions\` | 获取应用版本列表 |
| \`refresh_data\` | 刷新 EMAS 数据 |

## 🚀 快速开始

### 1. 安装

\`\`\`bash
npm install
\`\`\`

### 2. 配置环境

创建 \`.env.local\` 文件:

\`\`\`env
# EMAS APM 配置
EMAS_BASE_URL=http://localhost:8080
EMAS_APP_KEY=your_app_key
EMAS_APP_SECRET=your_app_secret

# LLM 配置（可选）
LLM_API_KEY=your_api_key
LLM_BASE_URL=https://api.openai.com/v1
LLM_MODEL=gpt-4
\`\`\`

### 3. 在龙虾中使用

1. 将本 Skills 包加载到龙虾
2. 龙虾将自动发现所有工具
3. 直接在对话中使用，如:
   - "查一下 top10 crash"
   - "分析这个 digestHash"
   - "生成一份分析报告"

### 4. 在 Claude Code MCP 中使用

配置 \`claude_desktop_config.json\`:

\`\`\`json
{
  "mcpServers": {
    "emas-crashtools": {
      "command": "node",
      "args": ["./dist/index.js"]
    }
  }
}
\`\`\`

## 📚 工具使用示例

### 获取 Top 10 崩溃

参数:
- limit (可选): 返回数量，默认 10
- days (可选): 时间范围（天），默认 7

响应示例:
\`\`\`
Top 10 崩溪列表 (最近 7 天):

1. [NullPointerException] - 次数: 1523, 设备: 456, 率: 12.5%
   Hash: abc123def456
2. [ArrayIndexOutOfBoundsException] - 次数: 892, 设备: 234, 率: 8.2%
   Hash: xyz789...
\`\`\`

### 获取单个 Issue 详情

参数:
- digestHash (必需): Issue 的哈希值

响应示例:
\`\`\`
Issue 详情: NullPointerException

- 类型: crash
- 崩溪数: 1523
- 影响设备: 456
- 错误率: 12.5%
- 首现版本: 1.0.0

版本分布:
  - 1.2.0: 456 次
  - 1.1.9: 389 次
  - 1.1.8: 234 次
\`\`\`

### 批量分析

参数:
- digestHashes (必需): Issue Hash 数组

### 生成报告

参数:
- type: 报告类型 (top10|top20|summary)
- days: 分析周期（天）
- format: 输出格式 (markdown|html|json)

## 💡 使用场景

### 场景 1: 定期崩溪分析

\`\`\`
用户: "帮我分析一下最近一周的 top10 crash"
↓
龙虾: 调用 get_top10_crash 工具
↓
返回: Top 10 列表和各项统计
\`\`\`

### 场景 2: 快速问题诊断

\`\`\`
用户: "这个 hash 是什么问题? xxxxx"
↓
龙虾: 调用 get_issue_detail 工具
↓
返回: Issue 详情、堆栈、影响范围
\`\`\`

### 场景 3: 批量问题修复

\`\`\`
用户: "帮我分析这几个问题"
↓
龙虾: 调用 batch_analyze 工具
↓
返回: 逐个问题的详情和分析建议
\`\`\`

## 🔧 技术细节

### MCP 协议兼容性

✅ 完全支持 MCP (Model Context Protocol) 标准
✅ 所有工具遵循 MCP 工具定义规范
✅ 支持龙虾、Claude Code 等多个 AI 平台

### 错误处理

所有工具都提供结构化的错误响应:
\`\`\`
❌ 工具调用失败: Connection refused
\`\`\`

## 📄 许可

MIT

## 🆘 支持

遇到问题? 查看 [README.md](./README.md) 获取更多帮助。
''';
  }

  /// 生成 package.json
  String _generatePackageJson() {
    final json = {
      'name': 'emas-crashtools-skills',
      'version': appVersion,
      'description': 'EMAS 崩溪修复 Agent Skills - 集成 EMAS 应用性能监控平台的所有 API 能力',
      'type': 'module',
      'main': 'dist/index.js',
      'types': 'dist/index.d.ts',
      'scripts': {
        'build': 'tsc',
        'dev': 'tsc --watch',
        'test': 'node --test',
      },
      'dependencies': {
        'axios': '^1.6.0',
        'dotenv': '^16.0.0',
      },
      'devDependencies': {
        'typescript': '^5.0.0',
        '@types/node': '^20.0.0',
      },
      'keywords': [
        'EMAS',
        'crash-analysis',
        'ANR',
        'performance-monitoring',
        'mobile-app',
        'intelligent-analysis',
        'skills',
        'MCP',
      ],
      'author': 'EMAS-crashtools Team',
      'license': 'MIT',
    };

    return jsonEncode(json);
  }

  /// 生成 README.md
  String _generateReadmeMd() {
    return '''# EMAS 崩溃修复 Agent Skills

快速集成 EMAS 应用性能监控平台的所有 API 能力。

## 📦 安装

本 Skills 包已集成到 EMAS-crashtools 应用中。如果您已安装该应用，可以：

1. 打开 EMAS-crashtools 应用
2. 进入"Agent"标签页
3. 点击"导出 Skills"按钮
4. 获取本压缩包

## 🎯 用途

本 Skills 包适用于以下场景：

- **龙虾 (Lobster AI)**: 在龙虾中直接加载，快速分析崩溃问题
- **Claude Code MCP**: 在 Claude Code 中作为自定义 MCP Server 使用
- **其他 AI 工具**: 与支持 OpenClaw Skills 规范和 MCP 的任何 AI 工具集成

## ✨ 核心特性

| 特性 | 说明 |
|------|------|
| 🔍 **智能查询** | Top 10 崩溃、ANR 统计、Issue 详情 |
| 📊 **深度分析** | 堆栈分析、根因诊断、相似问题搜索 |
| 📝 **报告生成** | 自动生成完整分析报告（Markdown/HTML）|
| 💻 **代码检查** | 源码搜索、Git Blame、版本依赖 |
| 🚀 **快速集成** | 开箱即用，MCP 标准，无需额外配置 |
| 🦞 **龙虾支持** | 完全兼容龙虾 AI 工具调用 |

## 🚀 在龙虾中使用

### 第 1 步: 添加 Skills 包

1. 打开龙虾应用
2. 进入设置或 Skills 管理
3. 点击"添加 Skills"
4. 选择本压缩包或提取的目录
5. 龙虾将自动加载所有工具

### 第 2 步: 开始使用

在龙虾的对话框中输入命令，龙虾将自动调用相应工具：

\`\`\`
你: "查一下最近的 top10 crash"
龙虾: 调用 get_top10_crash 工具 → 返回结果
```

支持的对话方式:
- "查一下 top10 crash"
- "最近一周的 ANR 统计"
- "分析这个 digestHash: abc123"
- "生成一份完整报告"
- "这些问题的根本原因是什么?"

## 🚀 在 Claude Code 中使用

### 配置 MCP Server

1. 复制本文件夹到 Claude Code 的 MCP Server 目录
2. 编辑 \`claude_desktop_config.json\`:

\`\`\`json
{
  "mcpServers": {
    "emas-crashtools": {
      "command": "node",
      "args": ["./dist/index.js"],
      "env": {
        "EMAS_BASE_URL": "http://localhost:8080",
        "EMAS_APP_KEY": "your_app_key",
        "EMAS_APP_SECRET": "your_app_secret"
      }
    }
  }
}
\`\`\`

3. 重启 Claude Code
4. 在对话中使用 EMAS 工具

## 📚 API 列表

### 查询接口

| 工具 | 参数 | 功能 |
|------|------|------|
| get_top10_crash | limit, days | 获取 Top 10 崩溃 |
| get_top10_anr | limit, days | 获取 Top 10 ANR |
| get_issue_detail | digestHash | 获取 issue 详情 |
| get_versions | - | 获取版本列表 |

### 分析接口

| 工具 | 参数 | 功能 |
|------|------|------|
| batch_analyze | digestHashes | 批量分析 |
| analyze_stack_trace | stackTrace | 分析堆栈 |
| search_similar_crashes | errorType | 搜索相似问题 |

### 报告接口

| 工具 | 参数 | 功能 |
|------|------|------|
| generate_report | type, days, format | 生成报告 |
| refresh_data | - | 刷新数据 |

## 🔧 配置

### 环境变量 (.env.local)

\`\`\`env
# 必需
EMAS_BASE_URL=http://localhost:8080
EMAS_APP_KEY=your_app_key
EMAS_APP_SECRET=your_app_secret

# 可选
LLM_API_KEY=your_api_key
LLM_BASE_URL=https://api.openai.com/v1
LLM_MODEL=gpt-4

# 日志级别
LOG_LEVEL=info
\`\`\`

## 💡 示例

### 龙虾对话示例

\`\`\`
用户: 查一下最近的 crash 问题
龙虾: 调用 get_top10_crash 工具

响应:
Top 10 崩溪列表 (最近 7 天):

1. [NullPointerException] - 次数: 1523, 设备: 456, 率: 12.5%
   Hash: abc123def456
2. [ArrayIndexOutOfBoundsException] - 次数: 892, 设备: 234, 率: 8.2%
   Hash: xyz789...

用户: 分析第一个问题
龙虾: 调用 get_issue_detail 工具，获取详细信息
```

## 🆘 故障排除

### 连接问题

如果龙虾无法连接到 EMAS 服务：

1. 检查 \`EMAS_BASE_URL\` 是否正确
2. 验证 \`EMAS_APP_KEY\` 和 \`EMAS_APP_SECRET\` 有效
3. 确保网络连接正常

### 工具不可用

如果工具显示"未知工具"：

1. 检查 Skills 包是否正确加载
2. 重启龙虾应用
3. 查看龙虾的日志输出

## 📞 获取帮助

- 查看 [SKILLS.md](./SKILLS.md) 获取详细 API 文档
- 查看 examples/ 目录下的使用示例
- 访问 EMAS-crashtools 应用内的帮助文档

## 📄 许可

MIT License - 自由使用和修改

---

**最后更新**: $appVersion | **应用版本**: $appVersion
''';
  }

  /// 生成 index.ts (MCP 标准实现，龙虾兼容)
  String _generateIndexTs() {
    return '''// EMAS Crashtools Skills - MCP Server Implementation (Lobster Compatible)
// 符合 MCP (Model Context Protocol) 标准，支持龙虾和其他 AI 工具调用

import axios, { AxiosInstance } from 'axios';
import * as fs from 'fs';
import * as path from 'path';

require('dotenv').config({ path: '.env.local' });

// ============= MCP 接口定义 =============

interface Tool {
  name: string;
  description: string;
  inputSchema: {
    type: 'object';
    properties: Record<string, any>;
    required?: string[];
  };
}

interface ToolResult {
  type: 'text' | 'image' | 'resource';
  text?: string;
  mimeType?: string;
  data?: string;
  uri?: string;
}

// ============= EMAS API 客户端 =============

class EmasApiClient {
  private client: AxiosInstance;
  private baseUrl: string;

  constructor() {
    this.baseUrl = process.env.EMAS_BASE_URL || 'http://localhost:8080';
    this.client = axios.create({
      baseURL: this.baseUrl,
      timeout: 30000,
      headers: {
        'X-App-Key': process.env.EMAS_APP_KEY,
        'X-App-Secret': process.env.EMAS_APP_SECRET,
        'Content-Type': 'application/json',
      },
    });
  }

  async request(url: string, method: string = 'GET', data?: any) {
    try {
      const response = await this.client.request({ url, method, data });
      return response.data;
    } catch (error: any) {
      throw new Error(`EMAS API Error: \${error.message}`);
    }
  }
}

const emasClient = new EmasApiClient();

// ============= 工具定义 (MCP Tools Definition) =============

const TOOLS: Record<string, Tool> = {
  get_top10_crash: {
    name: 'get_top10_crash',
    description: '获取 Top 10 崩溪问题列表，包含发生次数、影响设备数、错误率等统计信息',
    inputSchema: {
      type: 'object',
      properties: {
        limit: {
          type: 'number',
          description: '返回数量，默认 10',
          default: 10,
        },
        days: {
          type: 'number',
          description: '时间范围（天），默认 7',
          default: 7,
        },
      },
    },
  },

  get_top10_anr: {
    name: 'get_top10_anr',
    description: '获取 Top 10 ANR 卡顿问题，包含时间段分布和影响统计',
    inputSchema: {
      type: 'object',
      properties: {
        limit: {
          type: 'number',
          description: '返回数量，默认 10',
          default: 10,
        },
        days: {
          type: 'number',
          description: '时间范围（天），默认 7',
          default: 7,
        },
      },
    },
  },

  get_issue_detail: {
    name: 'get_issue_detail',
    description: '获取单个 issue 的完整详情，包含堆栈、版本分布、设备分布等信息',
    inputSchema: {
      type: 'object',
      properties: {
        digestHash: {
          type: 'string',
          description: 'Issue 的唯一哈希标识符',
        },
      },
      required: ['digestHash'],
    },
  },

  batch_analyze: {
    name: 'batch_analyze',
    description: '批量分析多个 issues，逐个获取详情并进行初步分析',
    inputSchema: {
      type: 'object',
      properties: {
        digestHashes: {
          type: 'array',
          items: { type: 'string' },
          description: '要分析的 Issue Hash 列表',
        },
      },
      required: ['digestHashes'],
    },
  },

  analyze_stack_trace: {
    name: 'analyze_stack_trace',
    description: '深层分析崩溪堆栈轨迹，提取关键帧和代码位置',
    inputSchema: {
      type: 'object',
      properties: {
        stackTrace: {
          type: 'string',
          description: '堆栈轨迹文本',
        },
        sourceCode: {
          type: 'string',
          description: '相关源码（可选）',
        },
      },
      required: ['stackTrace'],
    },
  },

  search_similar_crashes: {
    name: 'search_similar_crashes',
    description: '搜索项目中类似的崩溪模式和根本原因',
    inputSchema: {
      type: 'object',
      properties: {
        errorType: {
          type: 'string',
          description: '异常类型，如 NullPointerException',
        },
        errorMessage: {
          type: 'string',
          description: '错误消息片段（可选）',
        },
      },
      required: ['errorType'],
    },
  },

  generate_report: {
    name: 'generate_report',
    description: '生成完整的分析报告，可导出为 Markdown 或 HTML 格式',
    inputSchema: {
      type: 'object',
      properties: {
        type: {
          type: 'string',
          enum: ['top10', 'top20', 'summary'],
          description: '报告类型',
          default: 'top10',
        },
        days: {
          type: 'number',
          description: '分析周期（天）',
          default: 7,
        },
        format: {
          type: 'string',
          enum: ['markdown', 'html', 'json'],
          description: '报告格式',
          default: 'markdown',
        },
      },
    },
  },

  get_versions: {
    name: 'get_versions',
    description: '获取应用的所有版本列表',
    inputSchema: {
      type: 'object',
      properties: {},
    },
  },

  refresh_data: {
    name: 'refresh_data',
    description: '刷新 EMAS 的数据，同步最新的崩溪和卡顿信息',
    inputSchema: {
      type: 'object',
      properties: {},
    },
  },
};

// ============= 工具实现 (Tool Implementations) =============

async function handleGetTop10Crash(params: any): Promise<string> {
  try {
    const limit = params.limit || 10;
    const days = params.days || 7;

    const data = await emasClient.request('/api/issues');
    const crashes = (data.issues || []).slice(0, limit);

    const result = crashes
      .map(
        (c: any, i: number) =>
          \`\${i + 1}. [\${c.errorName}] - 次数: \${c.count}, 设备: \${c.affectedDevices}, 率: \${c.errorRate}\\n   Hash: \${c.digestHash}\`,
      )
      .join('\\n');

    return \`**Top \${Math.min(limit, crashes.length)} 崩溪列表** (最近 \${days} 天):\\n\\n\${result}\`;
  } catch (error) {
    return \`❌ 获取 Top 10 崩溪失败: \${error instanceof Error ? error.message : 'Unknown error'}\`;
  }
}

async function handleGetTop10Anr(params: any): Promise<string> {
  try {
    const limit = params.limit || 10;
    const days = params.days || 7;

    const data = await emasClient.request('/api/anr');
    const anrs = (data.anrs || []).slice(0, limit);

    const result = anrs
      .map(
        (a: any, i: number) =>
          \`\${i + 1}. [\${a.errorName}] - 次数: \${a.count}, 设备: \${a.affectedDevices}\\n   Hash: \${a.digestHash}\`,
      )
      .join('\\n');

    return \`**Top \${Math.min(limit, anrs.length)} ANR 列表** (最近 \${days} 天):\\n\\n\${result}\`;
  } catch (error) {
    return \`❌ 获取 ANR 统计失败: \${error instanceof Error ? error.message : 'Unknown error'}\`;
  }
}

async function handleGetIssueDetail(params: any): Promise<string> {
  try {
    const { digestHash } = params;
    if (!digestHash) throw new Error('digestHash 参数必需');

    const data = await emasClient.request(\`/api/issue/\${digestHash}\`);

    let result = \`**Issue 详情**: \${data.errorName}\\n\\n\`;
    result += \`- 类型: \${data.errorType}\\n\`;
    result += \`- 崩溪数: \${data.count}\\n\`;
    result += \`- 影响设备: \${data.affectedDevices}\\n\`;
    result += \`- 错误率: \${data.errorRate}\\n\`;
    result += \`- 首现版本: \${data.firstVersion || 'N/A'}\\n\\n\`;

    if (data.versionDistribution && data.versionDistribution.length > 0) {
      result += \`**版本分布**:\\n\`;
      data.versionDistribution.slice(0, 5).forEach((v: any) => {
        result += \`  - \${v.version}: \${v.count} 次\\n\`;
      });
    }

    return result;
  } catch (error) {
    return \`❌ 获取 Issue 详情失败: \${error instanceof Error ? error.message : 'Unknown error'}\`;
  }
}

async function handleBatchAnalyze(params: any): Promise<string> {
  try {
    const { digestHashes } = params;
    if (!digestHashes || !Array.isArray(digestHashes)) {
      throw new Error('digestHashes 必须是数组');
    }

    let result = \`**批量分析 \${digestHashes.length} 个 Issues**\\n\\n\`;
    let successCount = 0;
    let failedCount = 0;

    for (const hash of digestHashes.slice(0, 10)) {
      try {
        const data = await emasClient.request(\`/api/issue/\${hash}\`);
        result += \`✅ \${data.errorName} (\${data.count} 次)\\n\`;
        successCount++;
      } catch {
        result += \`❌ \${hash} 分析失败\\n\`;
        failedCount++;
      }
    }

    result += \`\\n统计: 成功 \${successCount}, 失败 \${failedCount}\`;
    return result;
  } catch (error) {
    return \`❌ 批量分析失败: \${error instanceof Error ? error.message : 'Unknown error'}\`;
  }
}

async function handleAnalyzeStackTrace(params: any): Promise<string> {
  try {
    const { stackTrace } = params;
    if (!stackTrace) throw new Error('stackTrace 参数必需');

    const lines = stackTrace.split('\\n').filter((l: string) => l.trim());
    const appFrames = lines.filter((l: string) => !l.includes('android') && !l.includes('java.lang'));

    let result = \`**堆栈分析结果**\\n\\n\`;
    result += \`- 总行数: \${lines.length}\\n\`;
    result += \`- 应用代码帧: \${appFrames.length}\\n\`;
    result += \`- 系统帧: \${lines.length - appFrames.length}\\n\\n\`;

    if (appFrames.length > 0) {
      result += \`**关键应用代码帧** (前 5):\\n\`;
      appFrames.slice(0, 5).forEach((frame: string, i: number) => {
        result += \`  \${i + 1}. \${frame.substring(0, 100)}\\n\`;
      });
    }

    return result;
  } catch (error) {
    return \`❌ 堆栈分析失败: \${error instanceof Error ? error.message : 'Unknown error'}\`;
  }
}

async function handleSearchSimilarCrashes(params: any): Promise<string> {
  try {
    const { errorType } = params;
    if (!errorType) throw new Error('errorType 参数必需');

    const data = await emasClient.request('/api/search', 'GET');
    const crashes = (data.crashes || []).slice(0, 10);

    let result = \`**搜索相似崩溪**: \${errorType}\\n\\n\`;
    result += \`找到 \${crashes.length} 个相似崩溪:\\n\`;

    crashes.forEach((c: any, i: number) => {
      result += \`  \${i + 1}. \${c.errorName || '未知'} (\${c.count} 次)\\n\`;
    });

    return result;
  } catch (error) {
    return \`❌ 搜索相似崩溪失败: \${error instanceof Error ? error.message : 'Unknown error'}\`;
  }
}

async function handleGenerateReport(params: any): Promise<string> {
  try {
    const type = params.type || 'top10';
    const days = params.days || 7;
    const format = params.format || 'markdown';

    const data = await emasClient.request('/api/issues');
    const crashes = (data.issues || []).slice(0, 20);

    let result = \`# EMAS 崩溪分析报告\\n\\n\`;
    result += \`- 类型: \${type}\\n\`;
    result += \`- 周期: 最近 \${days} 天\\n\`;
    result += \`- 生成时间: \${new Date().toISOString()}\\n\\n\`;

    result += \`## Top \${crashes.length} 崩溪列表\\n\\n\`;
    result += \`| # | 错误名 | 次数 | 设备 | 错误率 |\\n\`;
    result += \`|---|--------|------|------|--------|\\n\`;

    crashes.forEach((c: any, i: number) => {
      result += \`| \${i + 1} | \${c.errorName} | \${c.count} | \${c.affectedDevices} | \${c.errorRate} |\\n\`;
    });

    return result;
  } catch (error) {
    return \`❌ 生成报告失败: \${error instanceof Error ? error.message : 'Unknown error'}\`;
  }
}

async function handleGetVersions(params: any): Promise<string> {
  try {
    const data = await emasClient.request('/api/versions');
    const versions = (data.versions || []).slice(0, 20);

    let result = \`**应用版本列表** (共 \${versions.length} 个):\\n\\n\`;
    versions.forEach((v: any) => {
      result += \`- \${v.version}\\n\`;
    });

    return result;
  } catch (error) {
    return \`❌ 获取版本失败: \${error instanceof Error ? error.message : 'Unknown error'}\`;
  }
}

async function handleRefreshData(params: any): Promise<string> {
  try {
    await emasClient.request('/api/refresh', 'POST');
    return '✅ 数据已刷新，同步最新的崩溪和卡顿信息';
  } catch (error) {
    return \`❌ 数据刷新失败: \${error instanceof Error ? error.message : 'Unknown error'}\`;
  }
}

// ============= MCP 工具调用分发器 =============

export async function callTool(toolName: string, params: any): Promise<ToolResult> {
  try {
    let text = '';

    switch (toolName) {
      case 'get_top10_crash':
        text = await handleGetTop10Crash(params);
        break;
      case 'get_top10_anr':
        text = await handleGetTop10Anr(params);
        break;
      case 'get_issue_detail':
        text = await handleGetIssueDetail(params);
        break;
      case 'batch_analyze':
        text = await handleBatchAnalyze(params);
        break;
      case 'analyze_stack_trace':
        text = await handleAnalyzeStackTrace(params);
        break;
      case 'search_similar_crashes':
        text = await handleSearchSimilarCrashes(params);
        break;
      case 'generate_report':
        text = await handleGenerateReport(params);
        break;
      case 'get_versions':
        text = await handleGetVersions(params);
        break;
      case 'refresh_data':
        text = await handleRefreshData(params);
        break;
      default:
        text = \`❌ 未知工具: \${toolName}\`;
    }

    return { type: 'text', text };
  } catch (error) {
    return {
      type: 'text',
      text: \`❌ 工具调用异常: \${error instanceof Error ? error.message : 'Unknown error'}\`,
    };
  }
}

// ============= MCP 协议接口 (Lobster Compatible) =============

export function listTools(): Tool[] {
  return Object.values(TOOLS);
}

export async function handleToolCall(toolName: string, toolInput: any): Promise<ToolResult> {
  return callTool(toolName, toolInput);
}

// 龙虾兼容接口
export async function executeToolCall(toolName: string, toolInput: Record<string, any>): Promise<string> {
  const result = await callTool(toolName, toolInput);
  return result.text || '';
}

// 导出为默认模块
export default {
  callTool,
  listTools,
  handleToolCall,
  executeToolCall,
  TOOLS,
};
''';
  }

  /// 生成 tsconfig.json
  String _generateTsconfig() {
    return '''{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "moduleResolution": "node",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": [
    "*.ts",
    "examples/**/*.ts"
  ],
  "exclude": [
    "node_modules",
    "dist"
  ]
}''';
  }

  /// 生成示例文件
  List<(String, String)> _generateExamples() {
    return [
      (
        'query-top10.ts',
        '''import { callTool } from '../index'

async function main() {
  console.log('🔍 查询 Top 10 崩溪...')
  const crashResult = await callTool('get_top10_crash', { limit: 10, days: 7 })
  console.log(crashResult.text)

  console.log('\\n🔍 查询 Top 10 ANR...')
  const anrResult = await callTool('get_top10_anr', { limit: 10 })
  console.log(anrResult.text)
}

main().catch(console.error)
'''
      ),
      (
        'analyze-issue.ts',
        '''import { callTool } from '../index'

async function main() {
  const digestHash = process.argv[2] || 'abc123'

  console.log(\`📋 获取 Issue 详情: \${digestHash}\`)
  const result = await callTool('get_issue_detail', { digestHash })
  console.log(result.text)
}

main().catch(console.error)
'''
      ),
      (
        'batch-analysis.ts',
        '''import { callTool } from '../index'

async function main() {
  const hashes = ['hash1', 'hash2', 'hash3']

  console.log(\`📊 批量分析 \${hashes.length} 个 Issues...\`)
  const result = await callTool('batch_analyze', { digestHashes: hashes })
  console.log(result.text)
}

main().catch(console.error)
'''
      ),
      (
        'generate-report.ts',
        '''import { callTool } from '../index'

async function main() {
  console.log('📝 生成分析报告...')

  const result = await callTool('generate_report', {
    type: 'top10',
    days: 7,
    format: 'markdown'
  })
  console.log(result.text)
}

main().catch(console.error)
'''
      ),
    ];
  }
}
