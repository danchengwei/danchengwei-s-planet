# EMAS 崩溪分析工具 - Release 发行包

## 📦 发行版本

**版本**: 2026-06-26  
**大小**: 481 MB  
**文件**: `emas-crashtools-release-20260626.zip`

---

## 🚀 快速开始 (3 步 5 分钟)

### 第 1 步: 解压

```bash
unzip emas-crashtools-release-20260626.zip
cd release-package
```

### 第 2 步: 自动配置

```bash
bash setup.sh
```

自动配置脚本会：
- ✅ 检查 macOS 版本和 CPU 架构
- ✅ 配置 Aliyun CLI 环境
- ✅ 创建配置目录
- ✅ 设置所有文件权限

### 第 3 步: 配置凭证并启动

```bash
# 编辑配置文件（填入 EMAS 凭证）
vim config/emas-config.json

# 启动应用
open EMAS崩溪分析工具.app
```

---

## 📋 包内容清单

```
release-package/
├── EMAS崩溪分析工具.app           ✅ 完整应用（macOS universal）
├── cli/                           ✅ Aliyun CLI 工具集
│   └── aliyun/
│       ├── darwin-amd64/aliyun    ✅ Intel Mac
│       ├── darwin-arm64/aliyun    ✅ Apple Silicon Mac
│       └── VERSION
├── config/
│   └── emas-config.json           ✅ 配置模板
├── docs/
│   ├── QUICKSTART.md              ✅ 5 分钟快速开始
│   ├── CONFIG_GUIDE.md            ✅ 详细配置指南
│   ├── SKILLS_EXPORT.md           ✅ 龙虾 Skills 导出
│   └── README.md                  ✅ 整体说明
├── setup.sh                       ✅ 自动配置脚本
└── README.md                      ✅ 主文档
```

---

## 🎯 核心功能

### 📊 EMAS 数据查询
- Top 10 崩溪分析
- Top 10 ANR 卡顿统计
- Issue 详情和版本分布
- 设备影响范围分析

### 🔍 智能分析
- 堆栈轨迹自动分析
- 根本原因诊断
- 相似问题搜索
- 批量问题分析

### 📝 报告生成
- Markdown 格式报告
- HTML 格式报告
- 自动汇总统计
- 一键导出

### 🤖 AI Agent 助手
- 自由对话模式
- 多轮对话上下文
- 自动工具调用
- 完整日志记录

### 🦞 龙虾集成
- 一键导出 OpenClaw Skills
- MCP 标准完全兼容
- 龙虾直接调用
- 无需额外配置

---

## 🔧 系统要求

- **操作系统**: macOS 11.0 或更高版本
- **处理器**: Intel 或 Apple Silicon Mac
- **存储空间**: 至少 500 MB 可用空间
- **网络**: 连接阿里云 EMAS 服务

---

## ⚙️ 配置说明

### EMAS 凭证获取

1. 登录 [阿里云控制台](https://www.aliyun.com)
2. 进入 EMAS 产品
3. 创建应用并获取:
   - **appKey**: 应用标识
   - **appSecret**: 应用密钥（可选）
4. 在 RAM 控制台获取:
   - **accessKeyId**: Access Key ID
   - **accessKeySecret**: Access Key Secret
5. 选择服务区域:
   - **region**: cn-hangzhou / cn-beijing / cn-shanghai 等

### 配置文件模板

```json
{
  "accessKeyId": "LTAI4G...",
  "accessKeySecret": "qKkCp...",
  "region": "cn-hangzhou",
  "appKey": "xxxxx",
  "appSecret": "yyyyy"
}
```

---

## 💡 使用示例

### 例 1: 查询 Top 10 崩溪

```
1. 打开应用
2. 选择项目和时间范围
3. 点击"Top 10 崩溪"标签
4. 查看列表和统计
```

### 例 2: 分析单个问题

```
1. 点击任一 crash 进入详情
2. 查看堆栈信息
3. 获取修复建议
```

### 例 3: 在龙虾中使用

```
1. 打开应用 → Agent 标签
2. 点击"导出 Skills"
3. 将 ZIP 加载到龙虾
4. 龙虾中对话: "查一下 top10 crash"
5. 获取直接回复
```

---

## 🆘 常见问题

### Q: 无法连接 EMAS

**A**: 检查以下几点：
1. EMAS 凭证是否正确
2. 网络是否可以访问阿里云
3. 应用 Key 和区域是否匹配
4. 查看应用日志获取详细错误

### Q: setup.sh 执行失败

**A**: 
1. 确保 macOS 版本 >= 11.0
2. 尝试: `chmod +x setup.sh && bash setup.sh`
3. 检查磁盘空间是否充足

### Q: 应用启动后是白屏

**A**:
1. 等待 10 秒加载
2. 检查配置文件是否有效
3. 清空缓存: `rm -rf ~/.cache/emas-crashtools`
4. 重启应用

### Q: 如何更新应用

**A**: 下载新版 Release 包，解压后替换应用文件夹即可

---

## 📞 支持资源

### 包内文档
- `docs/QUICKSTART.md` - 5 分钟快速开始
- `docs/CONFIG_GUIDE.md` - 详细配置指南  
- `docs/SKILLS_EXPORT.md` - 龙虾 Skills 导出
- `README.md` - 完整说明

### 应用内帮助
- 右上角帮助按钮
- 各功能区域提示文字
- 错误时的诊断信息

---

## 🔐 安全说明

✅ **安全特性**:
- 应用已数字签名
- EMAS 凭证配置在本地
- 无需在线激活
- 可完全离线使用

⚠️ **安全建议**:
- 妥善保护 EMAS 凭证
- 不要分享配置文件
- 定期更新 Access Key
- 在不使用时禁用 Access Key

---

## 📈 版本历史

**v20260626** (当前)
- ✨ 新增: AI Agent 崩溪修复助手
- ✨ 新增: OpenClaw Skills 导出
- ✅ 完整: 9 个工具定义
- 🦞 支持: 龙虾 AI 直接调用

---

## 📝 许可证

MIT License

---

## ✨ 特别感谢

感谢使用 EMAS 崩溪分析工具！

如有问题或建议，欢迎反馈。

**祝你使用愉快！** 🎉
