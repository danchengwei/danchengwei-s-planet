.trae/agents/skills/  # Trae固定Skill目录，必须放在此处
└─ skill-generator-main/  # 主Skill（静态，仅需一次搭建）
   ├─ skill.json          # Trae专属元数据（适配Trae触发字段）
   ├─ workflow.md         # 主Skill工作流（Trae可解析）
   ├─ scripts/            # 核心脚本（适配Trae路径规则）
   │  ├─ __init__.py
   │  ├─ dir_scanner.py   # 扫描项目模块目录
   │  ├─ skill_creator.py # 动态生成子Skill
   │  └─ utils.py         # Trae专属工具（刷新Skill、文件读写）
   ├─ templates/          # 子Skill模板（适配Trae规范）
   │  ├─ skill.json.tpl   # 子Skill元数据模板
   │  ├─ workflow.md.tpl  # 子Skill工作流模板
   │  └─ kb_mapping.json.tpl # 知识库映射模板
   └─ knowledge-base/     # 模块化知识库（按版本-模块分层）
      └─ project_v1.0/
         ├─ module-user-service/  # 业务模块知识库
         └─ module-order-service/