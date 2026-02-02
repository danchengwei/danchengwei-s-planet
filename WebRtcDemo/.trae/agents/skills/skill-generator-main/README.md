# Skill Generator - 模块技能生成器

## 功能概述

Skill Generator 是一个 Trae IDE 专属的主 Skill，用于自动扫描 Android 项目中的业务模块，并为每个模块生成专属的 Skill，实现模块化的知识库管理和代码生成。

## 工作流程

```
A[Trae IDE打开Android项目] --> B[触发主Skill：模块扫描]
     B --> C[自动识别业务模块（user/order等）]
     C --> D[动态生成模块专属Skill]
     D --> E[用户发起开发需求（如"生成登录接口"）]
     E --> F[模块Skill加载对应知识库]
     F --> G[知识库内容：编码规范+业务规则+Bug修复+SDK说明]
     G --> H[大模型学习知识库后生成代码]
     H --> I[Trae内置Lint动态审查代码]
     I --> J[输出合规代码+审查报告]
     J --> K{有新Bug/需求文档?}
     K -->|是| L[上传文档→自动更新知识库]
     K -->|否| M[流程结束]
     L --> F[下次生成自动适配新内容]
```

## 目录结构

```
.trae/agents/skills/skill-generator-main/
├── knowledge-base/          # 知识库目录
│   └── project_v1.0/        # 项目版本
│       ├── module-user-service/   # 用户服务模块
│       │   ├── bug_fix/           # Bug 修复方案
│       │   ├── coding-standards/  # 编码规范
│       │   ├── business-rules/    # 业务规则
│       │   ├── sdk-docs/          # SDK 文档
│       │   └── requirements/      # 业务需求
│       └── module-order-service/  # 订单服务模块
│           ├── bug_fix/           # Bug 修复方案
│           ├── coding-standards/  # 编码规范
│           ├── business-rules/    # 业务规则
│           ├── sdk-docs/          # SDK 文档
│           └── requirements/      # 业务需求
├── scripts/                 # 核心脚本
│   ├── dir_scanner.py       # 扫描项目模块
│   ├── skill_creator.py     # 生成模块 Skill
│   ├── upload_doc.py        # 上传文档到知识库
│   └── utils.py             # 工具函数
├── templates/               # 模板文件
│   ├── skill.json.tpl       # Skill 配置模板
│   ├── workflow.md.tpl      # 工作流模板
│   └── kb_mapping.json.tpl  # 知识库映射模板
├── skill.json               # 主 Skill 配置
├── workflow.md              # 主 Skill 工作流
└── README.md                # 本说明文件
```

## 核心功能

### 1. 模块扫描
- 自动扫描 Android 项目中的业务模块
- 支持自定义模块根路径
- 排除指定的目录（如 build、test 等）

### 2. Skill 生成
- 根据扫描结果自动生成模块专属 Skill
- 使用模板文件生成标准化的 Skill 配置
- 为每个模块创建独立的知识库映射

### 3. 知识库管理
- 支持模块化的知识库结构
- 包含编码规范、业务规则、Bug 修复、SDK 文档等
- 自动更新知识库索引

### 4. 文档上传
- 支持上传新的 Bug 修复、需求文档等
- 自动更新知识库内容
- 下次生成代码时自动适配新内容

### 5. 代码生成
- 基于知识库内容生成合规的代码
- 自动应用 Bug 修复方案
- 遵循编码规范和业务规则

## 配置说明

### 主 Skill 配置

在 `skill.json` 文件中，可以配置以下参数：

- `project_version`：项目版本（默认 v1.0）
- `module_root`：模块根路径（默认 src/main/java/com/example/webrtctest/）
- `skip_dirs`：跳过的目录列表
- `skill_output_dir`：Skill 输出目录
- `kb_root`：知识库根目录

### 环境变量

无需特殊环境变量配置，Trae IDE 会自动识别和加载。

## 使用方法

### 1. 自动触发

当打开 Android 项目时，Trae IDE 会自动触发主 Skill，执行以下操作：

1. 扫描项目模块
2. 识别业务模块（如 user-service、order-service 等）
3. 为每个模块生成专属 Skill
4. 更新 Trae Skill 列表

### 2. 手动触发

可以通过以下关键词手动触发：

- "生成用户模块代码"
- "扫描项目模块"
- "刷新 Skill 配置"

### 3. 生成代码

1. 在 Trae IDE 中输入需求，如 "生成登录接口"
2. 系统会自动触发对应的模块 Skill
3. 模块 Skill 加载对应知识库
4. 大模型学习知识库后生成代码
5. Trae 内置 Lint 动态审查代码
6. 输出合规代码和审查报告

### 4. 上传文档

1. 准备新的 Bug 修复或需求文档
2. 使用 "模块知识库-文档上传" Skill
3. 选择文档和目标模块
4. 系统自动更新知识库
5. 下次生成代码时自动适配新内容

## 知识库文档格式

### 1. Bug 修复文档

文件路径：`knowledge-base/{project_version}/module-{module_name}/bug_fix/{bug_name}.md`

格式：

```markdown
# Bug 修复标题

1. Bug 描述：详细描述 Bug 的现象和影响
2. 修复方案：详细描述修复方法和代码变更
3. 编码规范：相关的编码规范
4. 输出要求：生成代码的要求
```

### 2. 编码规范文档

文件路径：`knowledge-base/{project_version}/module-{module_name}/coding-standards/{standard_name}.md`

格式：

```markdown
# 编码规范标题

## 1. 命名规范
## 2. 代码结构
## 3. 异常处理
## 4. 性能优化
## 5. 安全规范
## 6. 注释规范
```

### 3. 业务规则文档

文件路径：`knowledge-base/{project_version}/module-{module_name}/business-rules/{rule_name}.md`

格式：

```markdown
# 业务规则标题

## 1. 核心业务功能
## 2. 数据模型
## 3. API 接口
## 4. 业务流程
## 5. 安全规则
## 6. 错误处理
```

### 4. SDK 文档

文件路径：`knowledge-base/{project_version}/module-{module_name}/sdk-docs/{doc_name}.md`

格式：

```markdown
# SDK 文档标题

## 1. SDK 概述
## 2. 环境搭建
## 3. 核心功能
## 4. 数据模型
## 5. 错误处理
## 6. 最佳实践
```

### 5. 需求文档

文件路径：`knowledge-base/{project_version}/module-{module_name}/requirements/{requirement_name}.md`

格式：

```markdown
# 需求标题

## 1. 功能需求
## 2. 非功能需求
## 3. 技术需求
## 4. 数据需求
## 5. 范围限定
## 6. 验收标准
```

## 技术依赖

- **Python 3.7+**：运行核心脚本
- **Jinja2**：渲染模板文件
- **Kotlin**：Android 项目开发
- **Trae IDE**：运行环境

## 故障排查

### 1. 模块扫描失败

- 检查 `module_root` 配置是否正确
- 检查项目结构是否符合标准 Android 项目结构
- 查看 Trae IDE 日志获取详细错误信息

### 2. Skill 生成失败

- 检查模板文件是否存在且格式正确
- 检查输出目录权限是否足够
- 查看 Trae IDE 日志获取详细错误信息

### 3. 知识库加载失败

- 检查知识库目录结构是否正确
- 检查文档格式是否符合要求
- 查看 Trae IDE 日志获取详细错误信息

### 4. 代码生成失败

- 检查知识库内容是否完整
- 检查网络连接是否正常
- 查看 Trae IDE 日志获取详细错误信息

## 版本历史

### v1.0.0 (2026-01-26)
- 初始版本
- 支持模块扫描和 Skill 生成
- 支持知识库管理和文档上传
- 支持基于知识库的代码生成

## 贡献指南

欢迎贡献代码和文档，遵循以下流程：

1. Fork 本项目
2. 创建功能分支
3. 提交更改
4. 推送到分支
5. 开启 Pull Request

## 联系方式

- **开发者**：Trae AI
- **邮箱**：support@trae.ai
- **文档**：https://docs.trae.ai/skill-generator

## 许可证

本项目采用 MIT 许可证，详见 LICENSE 文件。