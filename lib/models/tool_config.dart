import 'dart:convert';

import 'gitlab_project_binding.dart';

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
    this.appPackageName = '',
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
    this.localProjectPath = '',
    this.sourceAnalysisPrompt = '',
    this.uiPrimaryRailWidth,
    this.uiWorkbenchSidebarWidth,
    Map<String, dynamic>? mcpServers,
    Map<String, bool>? mcpExportIncludeById,
    this.mcpGitlabInstallAck = false,
    this.emasUseMockCrashData = false,
    List<Map<String, dynamic>>? grayTestTasks,
    this.grayTestMonitoringEnabled = false,
    this.grayTestCheckIntervalSeconds = 30,
  })  : gitlabProjects = gitlabProjects ?? const [],
        mcpExportIncludeById = Map<String, bool>.from(mcpExportIncludeById ?? const {}),
        mcpServers = mcpServers != null
            ? Map<String, dynamic>.from(mcpServers)
            : const {},
        grayTestTasks = grayTestTasks ?? const [];

  /// 源码分析项目说明默认提示词（学而思网校 Android 项目）。
  static const defaultSourceAnalysisPrompt = '''
学而思网校 Android 项目架构与业务说明（供源码检索参考）

一、项目基本信息
- 项目路径根目录：xueersiwangxiao
- 主包名：com.xueersi.parentsmeeting（另含素质、高中、创新、科技、在线、素养 6 个变体包）
- 语言：Java + Kotlin 混合开发；跨端集成 React Native、Flutter（可配置混编）、Unity
- 架构：多仓库多模块 + 壳工程 AAR 聚合的巨型单体；核心模块由独立 Git 仓库维护（repo_projects.xml 动态 include）

二、整体分层（自上而下）
1. 壳工程 app/：7 类变体打包配置，启动初始化 Sophix 热修复、ARouter 路由、RN/Flutter 混编、华为 HMS
2. businessinterface/：业务协议层（接口/实体/路由；含 captureview 拍照裁剪、share 跨业务事件总线、practice 练习问答、quickhandwriting、pschat、publiclive、home tab 协议）
3. common/：公共基础层（网络/工具/配置；含 BLE 蓝牙、Cocos 课件下载、CPS 代理、FLog 监控、HD 大屏适配、手写组件）
4. business-base/：基础业务仓（contentcommon 内容社区、unitybridge Unity 桥接、xesprivacy 隐私合规；以及 home 首页、browser 浏览器、login 登录、player 播放器、cloud 云、livebasics/liveframework 直播框架、advertmanager 广告、addressmanager 地址、sharedresources 共享资源、unityframework、verticalresource、publiclive 等 AAR）
5. business/：业务子仓（40+，直播/点播/学习/商城等，见下）
6. library/：基础库仓（40+ AAR：framework、uicomponent、xesrouter 路由、network、xcrash/bytehook 崩溃、xrsbury/analytics 埋点、psijkplayer 播放器、libpag 动画、agora/webrtc 音视频、aiteacher/aipartner/aitalk AI 等）

三、核心业务模块与检索线索
- 直播 Live：livevideo、publiclive(公域)、livebusiness、liveexperience、liverecord；连麦 pschat/webrtc/agora，弹幕 danmaku；基础框架 livebasics/liveframework
- 点播/录播 VOD：instantvideo、newinstantvideo；统一播放器 player（ExoPlayer/IJKPlayer），下载 download
- AI 互动教学：aiteacher（AI 老师）、aipartner（AI 伙伴）、aitalk（口语对话）；MediaPipe + STMobile + ByteDance CV 手势/表情识别；语音 speechrecognizer 系列 + texttospeech
- 语言学习：englishmorningread(晨读)、englishdailyreading(日常阅读)、englishbook(英语书)、endictation(听写)、listenread(听说)、chineserecite(语文背诵)、reader/legadoread/readpartner(读书房)
- 练习/作业/考试：exercise(题库)、answer(答题)、homeworkpapertest(纸质拍照测)、examquestion(考题)、quickhandwriting(手写识别)、captureview(拍照多拍裁剪)
- 首页/个性化：home（Tab 切换、年级/地区选择）、personals(个人中心)、studycenter(学习中心)、discover(发现)、creative(创作社区)
- 电商：xesmall(学而思商城)、goldshop(金币商城)、addressmanager(地址)
- 内容社区：contentcommon（评论/表情/图文/语音评论/点赞 PK/Lottie 动画表情）
- 多端适配：手机 + 平板 Pad/XPad（common/customxpad 定制登录态同步）；HD 大屏（common/base/hd）

四、检索建议
- 堆栈中类名形如 com.xueersi.parentsmeeting.module.xxx.yyy.ZzzBinder/Activity/Fragment，可按模块名/类名用 grep 搜索（如 StreakFlameCalendarBinder 搜 CalendarBinder）
- 系统/第三方库帧（java.*/android.*/org.libpag 等）应结合业务调用栈定位到对应的 module 目录
- 崩溃相关基础库：XrsCrashReport + xcrash + bytehook；埋点 xrsbury/analytics；热修复 Sophix(HotFixApplication)
- 先 list_directory 看顶层模块布局，再按业务域到对应 business/business-base 子仓 grep 类名或关键词，最后 read_file 读关键方法
''';

  static const _defaultSystemPrompt = '''
你是资深移动端崩溃分析工程师，擅长 Android/iOS 原生与跨端栈。回答使用简体中文。

**重要原则**：
1. **只基于提供的事实分析，严禁编造**。不确定的地方明确标注「待确认」，不要猜测具体业务类名或文件路径。
2. **对于 native/so 崩溃**（堆栈中是 `libxxx.so`、`#xx pc` 格式），不要强行对应到业务代码，应从「信号类型、崩溃地址分布、.so 库作用」角度分析可能原因。
3. **对于 Java/Kotlin 异常**（有明确异常类型和类方法栈），可以结合堆栈中的包名/类名推断责任模块，但不要编造未出现在堆栈中的类。
4. **若提供了 GitLab 命中片段**，请对照片段内容分析，不要超出片段范围下结论。

请严格按下面 Markdown 结构输出（二级标题必须保留且字面一致，便于界面分块展示；小节内可用列表、代码块）：

## 原因
- 现象：一句话描述崩溃类型和特征
- 堆栈指向：最顶层的关键帧是什么，属于系统库还是业务代码
- 可疑根因：基于现有信息推断 2-3 个最可能的原因，按可能性排序
- 置信度：高 / 中 / 低，并说明为什么

## 分析
- 堆栈解读：逐段说明堆栈在做什么（从顶到底，只说确定的部分）
- 关联模块：可能涉及的系统组件或业务模块（仅基于堆栈中出现的包名/类名）
- 排查优先级：建议先查什么、后查什么，以及为什么

## 如何处理
- 修复方向：分点给出可操作的排查和修复建议
- 验证方法：如何验证修复是否有效
- 监控与防护：建议增加的日志、监控或容错机制
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
      appPackageName: _appPackageNameFromJson(j),
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
      localProjectPath: j['localProjectPath']?.toString() ?? '',
      sourceAnalysisPrompt: j['sourceAnalysisPrompt']?.toString() ?? '',
      uiPrimaryRailWidth: _optDouble(j['uiPrimaryRailWidth']),
      uiWorkbenchSidebarWidth: _optDouble(j['uiWorkbenchSidebarWidth']),
      mcpServers: _mcpServersFromJson(j),
      mcpExportIncludeById: _mcpExportIncludeByIdFromJson(j),
      mcpGitlabInstallAck: _mcpGitlabInstallAckFromJson(j),
      emasUseMockCrashData: j['emasUseMockCrashData'] == true,
      grayTestTasks: _grayTestTasksFromJson(j),
      grayTestMonitoringEnabled: j['grayTestMonitoringEnabled'] == true,
      grayTestCheckIntervalSeconds: j['grayTestCheckIntervalSeconds'] as int? ?? 30,
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

  /// 应用包名（Android `applicationId` 等）。
  ///
  /// JSON 读取顺序：`appPackageName` → `packageName` → `androidPackageName` → `emasListNameQuery`。
  /// 其中 `emasListNameQuery` 为部分测试/扁平配置沿用键名（**表示包名**，与 GetIssues 的 `Name`、工作台「应用版本」无关）。
  static String _appPackageNameFromJson(Map<String, dynamic> j) {
    String pick(String k) => j[k]?.toString().trim() ?? '';
    final a = pick('appPackageName');
    if (a.isNotEmpty) return a;
    final b = pick('packageName');
    if (b.isNotEmpty) return b;
    final c = pick('androidPackageName');
    if (c.isNotEmpty) return c;
    return pick('emasListNameQuery');
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
      return const {};
    }
    final v = j['mcpServers'];
    if (v is! Map) {
      return const {};
    }
    return Map<String, dynamic>.from(v);
  }

  static List<Map<String, dynamic>> _grayTestTasksFromJson(Map<String, dynamic> j) {
    final raw = j['grayTestTasks'];
    if (raw is List<dynamic>) {
      final out = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          out.add(Map<String, dynamic>.from(e));
        }
      }
      return out;
    }
    return const [];
  }

  String accessKeyId;
  String accessKeySecret;
  String region;
  String appKey;
  String os;
  String bizModule;
  /// 应用包名（如 `com.xxx.app`）。**可选**：`AppKey` 已绑定应用时多数场景可不填；若需随 OpenAPI 传 `PackageName` 再填写。
  String appPackageName;
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

  /// 本地项目路径（Git 仓库根目录），用于本地项目配置替代 GitLab API。
  String localProjectPath;

  /// 源码分析项目说明提示词：告诉模型当前项目类型、目录结构、业务模块与检索方式。
  String sourceAnalysisPrompt;

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

  /// 灰度监听任务列表（每项为灰度任务 JSON）
  List<Map<String, dynamic>> grayTestTasks;

  /// 灰度监听全局启用开关
  bool grayTestMonitoringEnabled;

  /// 灰度监听检查间隔（秒）
  int grayTestCheckIntervalSeconds;

  /// 是否将 [id] 写入导出的 `mcpServers`（`cursor`、`claude-code`、`gitlab` 等）。
  bool isMcpIdIncludedInExport(String id) => mcpExportIncludeById[id] != false;

  /// 已填写 Project Id 的绑定（用于 API）。
  List<GitlabProjectBinding> get gitlabBindingsResolved =>
      gitlabProjects.where((e) => e.projectId.trim().isNotEmpty).toList();

  /// 非空时写入 GetIssues/GetIssue 请求体的 `PackageName`（与控制台「应用版本」筛选 `Name` 无关）。
  String? get appPackageNameForOpenApi {
    final t = appPackageName.trim();
    return t.isEmpty ? null : t;
  }

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
        'appPackageName': appPackageName,
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
        if (localProjectPath.isNotEmpty) 'localProjectPath': localProjectPath,
        if (sourceAnalysisPrompt.trim().isNotEmpty) 'sourceAnalysisPrompt': sourceAnalysisPrompt,
        if (uiPrimaryRailWidth != null) 'uiPrimaryRailWidth': uiPrimaryRailWidth,
        if (uiWorkbenchSidebarWidth != null) 'uiWorkbenchSidebarWidth': uiWorkbenchSidebarWidth,
        'mcpServers': mcpServers,
        if (mcpExportIncludeById.isNotEmpty) 'mcpExportIncludeById': mcpExportIncludeById,
        'mcpGitlabInstallAck': mcpGitlabInstallAck,
        if (emasUseMockCrashData) 'emasUseMockCrashData': true,
        if (grayTestTasks.isNotEmpty) 'grayTestTasks': grayTestTasks,
        if (grayTestMonitoringEnabled) 'grayTestMonitoringEnabled': true,
        if (grayTestCheckIntervalSeconds != 30) 'grayTestCheckIntervalSeconds': grayTestCheckIntervalSeconds,
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
