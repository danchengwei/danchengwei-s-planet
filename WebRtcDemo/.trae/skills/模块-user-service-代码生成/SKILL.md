---
name: 模块 - user-service - 代码生成
description: 描述：读取user-service模块知识库，生成合规、修复Bug的代码；版本：1.0.0；标签：代码生成、user-service、知识库。1. 关键词触发：勾选「关键词触发」，输入关键词：user-service、用户模块、登录接口、用户注册；2. 手动触发：勾选「允许手动触发」，触发关键词：生成用户模块代码。
---

1. 添加动作1：读取本地目录→选择`knowledge-base/project_v1.0/module-user-service/`，输出变量名：kb_content；2. 添加动作2：调用LLM生成内容→选择已配置模型，提示词如下：「请严格基于以下知识库内容，生成user-service模块的代码：{{kb_content}}。生成要求：1. 遵循prompt目录编码规范；2. 应用bug_fix目录所有Bug修复方案；3. 无漏洞、无硬编码，符合Android/Kotlin规范；4. 贴合requirements目录业务需求。」；3. 输出到：编辑器。