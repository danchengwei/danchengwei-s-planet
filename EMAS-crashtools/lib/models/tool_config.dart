import 'dart:convert';

import 'gitlab_project_binding.dart';
import 'mcp_config_defaults.dart';

export 'gitlab_project_binding.dart';

/// 本地配置（敏感字段勿提交 Git）。兼容旧版 JSON 缺省字段。
class ToolConfig {
  ToolConfig({
    this.accessKeyId = '',
    this.accessKeySecret = '',
    this.region = 'cn-shanghai',
    this.appKey = '',
    this.os = 'android',
    this.bizModule = 'crash',
    this.emasListNameQuery = '',
    this.consoleBaseUrl = '',
    this.consoleIssueUrlTemplate = '',
    this.gitlabBaseUrl = '',
    this.gitlabToken = '',
    List<GitlabProjectBinding>? gitlabProjects,
    this.gitlabRef = 'main',
    this.llmBaseUrl = '',
    this.llmApiKey = '',
    this.llmModel = '',
    this.llmProviderPresetId = 'custom',
    this.llmChatCompletionsPath = 'v1/chat/completions',
    this.llmSystemPrompt = _defaultSystemPrompt,
    this.agentWorkDir = '',
    this.agentExecutable = '',
    this.agentMode = 'clipboard',
    this.agentFixedArgs = '[]',
    this.wallpaperId = '',
    this.uiPrimaryRailWidth,
    this.uiWorkbenchSidebarWidth,
    Map<String, dynamic>? mcpServers,
    Map<String, bool>? mcpExportIncludeById,
    this.mcpGitlabInstallAck = false,
    this.emasUseMockCrashData = false,
  })  : gitlabProjects = gitlabProjects ?? const [],
        mcpExportIncludeById = Map<String, bool>.from(mcpExportIncludeById ?? const {}),
        mcpServers = mcpServers != null
            ? McpConfigDefaults.normalizeStoredMcpServers(
                McpConfigDefaults.deepCopyMap(Map<dynamic, dynamic>.from(mcpServers)),
              )
            : McpConfigDefaults.defaultStoredMcpServers();

  static const _defaultSystemPrompt = '''
你是资深移动端崩溃分析工程师，擅长 Android/iOS 原生与跨端栈。回答使用简体中文。

若用户消息中的【分析要求】说明堆栈主要为系统/框架、无法定位业务源文件，则**禁止编造**具体业务源文件路径；改为给出排查方向、配置与容错类修改思路。

请严格按下面 Markdown 结构输出（二级标题必须保留且字面一致，便于界面分块展示；小节内可用列表、代码块）：

## 原因
（现象、堆栈指向、可疑根因与置信度）

## 分析
（结合业务/系统栈的进一步解读、关联模块、排查优先级）

## 如何处理
（分步骤的修复方案；文件/类/方法级修改思路与示例或伪代码；配置与发布策略；最后简述如何验证已修复、日志与监控要点）
''';

  factory ToolConfig.fromJson(Map<String, dynamic> j) {
    final agent = _normalizeLegacyAgentFromJson(j);
    return ToolConfig(
      accessKeyId: j['accessKeyId']?.toString() ?? '',
      accessKeySecret: j['accessKeySecret']?.toString() ?? '',
      region: j['region']?.toString() ?? 'cn-shanghai',
      appKey: j['appKey']?.toString() ?? '',
      os: j['os']?.toString() ?? 'android',
      bizModule: j['bizModule']?.toString() ?? 'crash',
      emasListNameQuery: _emasListNameQueryFromJson(j),
      consoleBaseUrl: j['consoleBaseUrl']?.toString() ?? '',
      consoleIssueUrlTemplate: j['consoleIssueUrlTemplate']?.toString() ?? '',
      gitlabBaseUrl: j['gitlabBaseUrl']?.toString() ?? '',
      gitlabToken: j['gitlabToken']?.toString() ?? '',
      gitlabProjects: _gitlabProjectsFromJson(j),
      gitlabRef: j['gitlabRef']?.toString() ?? 'main',
      llmBaseUrl: j['llmBaseUrl']?.toString() ?? '',
      llmApiKey: j['llmApiKey']?.toString() ?? '',
      llmModel: j['llmModel']?.toString() ?? '',
      llmProviderPresetId: () {
        final s = j['llmProviderPresetId']?.toString().trim() ?? '';
        return s.isNotEmpty ? s : 'custom';
      }(),
      llmChatCompletionsPath: () {
        final s = j['llmChatCompletionsPath']?.toString().trim() ?? '';
        return s.isNotEmpty ? s : 'v1/chat/completions';
      }(),
      llmSystemPrompt: () {
        final s = j['llmSystemPrompt']?.toString().trim() ?? '';
        return s.isNotEmpty ? s : _defaultSystemPrompt;
      }(),
      agentWorkDir: j['agentWorkDir']?.toString() ?? '',
      agentExecutable: agent['agentExecutable']!,
      agentMode: agent['agentMode']!,
      agentFixedArgs: agent['agentFixedArgs']!,
      wallpaperId: j['wallpaperId']?.toString() ?? '',
      uiPrimaryRailWidth: _optDouble(j['uiPrimaryRailWidth']),
      uiWorkbenchSidebarWidth: _optDouble(j['uiWorkbenchSidebarWidth']),
      mcpServers: _mcpServersFromJson(j),
      mcpExportIncludeById: _mcpExportIncludeByIdFromJson(j),
      mcpGitlabInstallAck: _mcpGitlabInstallAckFromJson(j),
      emasUseMockCrashData: j['emasUseMockCrashData'] == true,
    );
  }

  /// 旧配置无字段时视为已确认（不锁 GitLab 编辑）。
  static bool _mcpGitlabInstallAckFromJson(Map<String, dynamic> j) {
    if (!j.containsKey('mcpGitlabInstallAck')) return true;
    return j['mcpGitlabInstallAck'] == true;
  }

  /// 仅持久化显式为 `false` 的项（省略表示默认导出）。
  static Map<String, bool> _mcpExportIncludeByIdFromJson(Map<String, dynamic> j) {
    final raw = j['mcpExportIncludeById'];
    if (raw is! Map) return {};
    final out = <String, bool>{};
    for (final e in raw.entries) {
      if (e.value == false) out[e.key.toString()] = false;
    }
    return out;
  }

  /// 旧配置中 Cursor CLI（args + cursor）已废弃，加载时改为 Claude Code（stdin + claude）。
  static Map<String, String> _normalizeLegacyAgentFromJson(Map<String, dynamic> j) {
    var mode = j['agentMode']?.toString() ?? 'clipboard';
    var exe = j['agentExecutable']?.toString() ?? '';
    var args = j['agentFixedArgs']?.toString() ?? '[]';
    if (mode.trim().toLowerCase() == 'args' && exe.trim().toLowerCase() == 'cursor') {
      return {
        'agentExecutable': 'claude',
        'agentMode': 'stdin',
        'agentFixedArgs': '[]',
      };
    }
    return {
      'agentExecutable': exe,
      'agentMode': mode,
      'agentFixedArgs': args,
    };
  }

  static double? _optDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// GetIssues 的 `Name` 筛选；JSON 可用 [emasListNameQuery]，或兼容 `packageName` / `androidPackageName`。
  static String _emasListNameQueryFromJson(Map<String, dynamic> j) {
    String pick(String key) => j[key]?.toString().trim() ?? '';
    final primary = pick('emasListNameQuery');
    if (primary.isNotEmpty) return primary;
    final pkg = pick('packageName');
    if (pkg.isNotEmpty) return pkg;
    return pick('androidPackageName');
  }

  static List<GitlabProjectBinding> _gitlabProjectsFromJson(Map<String, dynamic> j) {
    final raw = j['gitlabProjects'];
    if (raw is List<dynamic>) {
      final out = <GitlabProjectBinding>[];
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          final b = GitlabProjectBinding.fromJson(e);
          if (b.projectId.trim().isNotEmpty) out.add(b);
        }
      }
      if (out.isNotEmpty) return out;
    }
    final legacy = j['gitlabProjectId']?.toString().trim() ?? '';
    if (legacy.isNotEmpty) {
      return [GitlabProjectBinding(projectId: legacy, repoName: '')];
    }
    return const [];
  }

  static Map<String, dynamic> _mcpServersFromJson(Map<String, dynamic> j) {
    if (!j.containsKey('mcpServers')) {
      return McpConfigDefaults.deepCopyMap(
        Map<dynamic, dynamic>.from(McpConfigDefaults.defaultStoredMcpServers()),
      );
    }
    final v = j['mcpServers'];
    if (v is! Map) {
      return McpConfigDefaults.deepCopyMap(
        Map<dynamic, dynamic>.from(McpConfigDefaults.defaultStoredMcpServers()),
      );
    }
    return McpConfigDefaults.normalizeStoredMcpServers(
      McpConfigDefaults.deepCopyMap(Map<dynamic, dynamic>.from(v)),
    );
  }

  String accessKeyId;
  String accessKeySecret;
  String region;
  String appKey;
  String os;
  String bizModule;
  /// 对应 GetIssues 请求体中的 `Name`（可选），**应用版本 / 包名** 等筛选与控制台一致。
  String emasListNameQuery;
  String consoleBaseUrl;
  /// 单条问题链接模板，可含 `{digest}`；空则仅用控制台总入口。
  String consoleIssueUrlTemplate;
  String gitlabBaseUrl;
  String gitlabToken;
  /// 多个仓库：每条为 Project Id + 仓库名（展示用）；搜索时会依次在各仓库中查关键词并合并命中。
  List<GitlabProjectBinding> gitlabProjects;
  String gitlabRef;
  String llmBaseUrl;
  String llmApiKey;
  String llmModel;
  /// 大模型厂商预设 id，见 [LlmProviderPreset]（`custom` 表示完全自定义）。
  String llmProviderPresetId;
  /// 相对 Base 的 Chat 路径，默认 `v1/chat/completions`；智谱等为 `chat/completions`。
  String llmChatCompletionsPath;
  String llmSystemPrompt;
  String agentWorkDir;
  /// 可执行文件路径，如 `claude`（Claude Code CLI）或绝对路径。
  String agentExecutable;
  /// clipboard：仅复制；stdin：标准输入写入 prompt；args：prompt 作为最后一参数。
  String agentMode;
  /// JSON 数组字符串，如 `["--print"]`，在 stdin/args 模式下作为固定前置参数。
  String agentFixedArgs;
  /// 主界面背景壁纸 id，空为无壁纸；与 `wallpaper_catalog.dart` 中内置 id 一致。
  String wallpaperId;

  /// 主导航栏（工作台 / 配置）像素宽度；null 表示使用界面默认约 88。
  double? uiPrimaryRailWidth;

  /// 工作台内「功能」侧栏像素宽度；null 表示使用界面默认约 200。
  double? uiWorkbenchSidebarWidth;

  /// 工作区持久化的 MCP（默认仅 `gitlab`；写入 Cursor 时会与内置 claude-code / cursor 合并）。
  Map<String, dynamic> mcpServers;

  /// 写入 Cursor / 完整导出时是否包含对应 id；仅当值为 `false` 时排除，未出现视为包含。
  Map<String, bool> mcpExportIncludeById;

  /// 用户已确认完成 GitLab MCP 本机安装（npx / brew）；为 `false` 时 MCP 页锁定编辑直至确认。
  bool mcpGitlabInstallAck;

  /// 为 true 且当前 Biz 为 `crash` 时，列表用本地 Mock，不请求 GetIssues；`mock_digest_*` 详情走 Mock GetIssue。
  bool emasUseMockCrashData;

  /// 是否将 [id] 写入导出的 `mcpServers`（`cursor`、`claude-code`、`gitlab` 等）。
  bool isMcpIdIncludedInExport(String id) => mcpExportIncludeById[id] != false;

  /// 已填写 Project Id 的绑定（用于 API）。
  List<GitlabProjectBinding> get gitlabBindingsResolved =>
      gitlabProjects.where((e) => e.projectId.trim().isNotEmpty).toList();

  List<String> get agentFixedArgsList {
    try {
      final v = jsonDecode(agentFixedArgs);
      if (v is List) return v.map((e) => e.toString()).toList();
    } catch (_) {}
    return const [];
  }

  Map<String, dynamic> toJson() => {
        'accessKeyId': accessKeyId,
        'accessKeySecret': accessKeySecret,
        'region': region,
        'appKey': appKey,
        'os': os,
        'bizModule': bizModule,
        'emasListNameQuery': emasListNameQuery,
        'consoleBaseUrl': consoleBaseUrl,
        'consoleIssueUrlTemplate': consoleIssueUrlTemplate,
        'gitlabBaseUrl': gitlabBaseUrl,
        'gitlabToken': gitlabToken,
        'gitlabProjects': gitlabProjects.map((e) => e.toJson()).toList(),
        if (gitlabProjects.isNotEmpty) 'gitlabProjectId': gitlabProjects.first.projectId,
        'gitlabRef': gitlabRef,
        'llmBaseUrl': llmBaseUrl,
        'llmApiKey': llmApiKey,
        'llmModel': llmModel,
        'llmProviderPresetId': llmProviderPresetId,
        'llmChatCompletionsPath': llmChatCompletionsPath,
        'llmSystemPrompt': llmSystemPrompt,
        'agentWorkDir': agentWorkDir,
        'agentExecutable': agentExecutable,
        'agentMode': agentMode,
        'agentFixedArgs': agentFixedArgs,
        'wallpaperId': wallpaperId,
        if (uiPrimaryRailWidth != null) 'uiPrimaryRailWidth': uiPrimaryRailWidth,
        if (uiWorkbenchSidebarWidth != null) 'uiWorkbenchSidebarWidth': uiWorkbenchSidebarWidth,
        'mcpServers': mcpServers,
        if (mcpExportIncludeById.isNotEmpty) 'mcpExportIncludeById': mcpExportIncludeById,
        'mcpGitlabInstallAck': mcpGitlabInstallAck,
        if (emasUseMockCrashData) 'emasUseMockCrashData': true,
      };

  List<String> validateEmas() {
    final miss = <String>[];
    if (accessKeyId.trim().isEmpty) miss.add('AccessKey ID');
    if (accessKeySecret.trim().isEmpty) miss.add('AccessKey Secret');
    if (region.trim().isEmpty) miss.add('Region');
    if (appKey.trim().isEmpty) miss.add('AppKey');
    if (os.trim().isEmpty) miss.add('平台 Os');
    if (bizModule.trim().isEmpty) miss.add('BizModule');
    return miss;
  }

  List<String> validateGitlab() {
    final miss = <String>[];
    if (gitlabBaseUrl.trim().isEmpty) miss.add('GitLab URL');
    if (gitlabToken.trim().isEmpty) miss.add('GitLab Token');
    if (gitlabBindingsResolved.isEmpty) miss.add('至少一个 GitLab Project Id');
    return miss;
  }

  List<String> validateLlm() {
    final miss = <String>[];
    if (llmBaseUrl.trim().isEmpty) miss.add('LLM Base URL');
    if (llmApiKey.trim().isEmpty) miss.add('LLM API Key');
    if (llmModel.trim().isEmpty) miss.add('LLM 模型名');
    return miss;
  }

  /// 已填写的大模型 / GitLab 接口地址须为 HTTPS，保存前校验。
  List<String> validateSecretEndpointsUseHttps() {
    final miss = <String>[];
    final llm = llmBaseUrl.trim();
    if (llm.isNotEmpty) {
      final u = Uri.tryParse(llm);
      if (u == null || !u.hasScheme || u.host.isEmpty) {
        miss.add('LLM Base URL 格式无效（需完整 https 地址）');
      } else if (u.scheme != 'https') {
        miss.add('LLM Base URL 须使用 https，避免 API Key 明文传输');
      }
    }
    final gl = gitlabBaseUrl.trim();
    if (gl.isNotEmpty) {
      final u = Uri.tryParse(gl);
      if (u == null || !u.hasScheme || u.host.isEmpty) {
        miss.add('GitLab URL 格式无效（需完整 https 地址）');
      } else if (u.scheme != 'https') {
        miss.add('GitLab URL 须使用 https，避免 Token 明文传输');
      }
    }
    return miss;
  }

  /// 非 clipboard 时启动本地 Agent（stdin/args）需要可执行文件与项目工作目录。
  String? validateAgentCliLaunch() {
    final mode = agentMode.trim().isEmpty ? 'clipboard' : agentMode.trim();
    if (mode == 'clipboard') return null;
    if (agentExecutable.trim().isEmpty) {
      return '请在「配置」中填写 Agent 可执行文件（一般为 claude 或绝对路径）';
    }
    if (agentWorkDir.trim().isEmpty) {
      return '请在「配置」中填写本地项目目录（Agent 工作目录，一般为工程根路径）';
    }
    return null;
  }

  int? get appKeyAsInt => int.tryParse(appKey.trim());

  /// 调用 LLM 时使用的 Chat 路径（非空）。
  String get effectiveLlmChatPath {
    final p = llmChatCompletionsPath.trim();
    return p.isEmpty ? 'v1/chat/completions' : p;
  }

  /// 附在每次 Chat 请求 system 末尾：引导模型**优先**通过用户本机 **GitLab MCP** 取证（与侧栏 MCP 导出配置一致）。
  static const String _llmMcpGitlabCoachingSuffix = '''

----------
【GitLab：优先本机 MCP】
用户可在 Cursor、Claude Desktop 等环境启用 **GitLab MCP**（本工具侧栏「MCP」可导出同款 `mcpServers`）。**若当前对话中你可以使用 GitLab 相关 MCP 工具，查仓库、读文件、搜代码时请优先走 MCP**，结果通常比单次 HTTP 摘录更完整、更接近线上代码。

若用户消息中出现「GitLab 内置检索」等段落，来自本工具内嵌的 GitLab REST 搜索，**仅作快速补充**；与 MCP 结果不一致或不足以定责时，**以 MCP 工具结果为准**。
''';

  /// 侧栏「对话」页专用：较详情页分析提示更通用，仍附带 GitLab MCP 说明（与 [effectiveLlmSystemPrompt] 共用同一 MCP 段）。
  static const String _freeChatSystemPromptBase = '''
你是资深移动端研发与崩溃分析助手，回答使用简体中文。
可讨论 EMAS、Android/iOS、堆栈解读、性能与发布流程等；用户未提供具体堆栈或仓库上下文时，不要编造具体业务源文件路径。
''';

  /// 发往 OpenAI 兼容 Chat API 的 system 字段：用户配置的 [llmSystemPrompt]（空则用内置默认），并自动附带 GitLab MCP 优先说明。
  String get effectiveLlmSystemPrompt {
    final base = llmSystemPrompt.trim().isEmpty ? _defaultSystemPrompt : llmSystemPrompt.trim();
    return '$base$_llmMcpGitlabCoachingSuffix';
  }

  /// 自由多轮对话页使用的 system（不含用户可在配置里改的崩溃分析模板，避免强套「原因/分析/如何处理」结构）。
  String get effectiveLlmFreeChatSystemPrompt =>
      '${_freeChatSystemPromptBase.trim()}$_llmMcpGitlabCoachingSuffix';
}
