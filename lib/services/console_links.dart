import '../models/tool_config.dart';

/// 控制台路径中与 OpenAPI [ToolConfig.bizModule] 对应的最后一段（如 crash、anr）。
/// 若控制台实际路径不同，请在模板里写死路径，勿用 `{bizConsole}`。
String bizConsoleSegment(String bizModule) {
  final b = bizModule.trim().toLowerCase();
  if (b.isEmpty) return 'crash';
  return b;
}

/// 根据 bizModule 获取控制台中的分析路径段
/// 如 crash → crashAnalysis/crash, anr → lagAnalysis/anr, lag → lagAnalysis/lag
String consoleAnalysisPath(String bizModule) {
  final b = bizModule.trim().toLowerCase();
  switch (b) {
    case 'crash':
      return 'crashAnalysis/crash';
    case 'anr':
    case 'lag':
      return 'lagAnalysis/$b';
    case 'exception':
      return 'exceptionAnalysis/exception';
    default:
      return '$b/$b';
  }
}

/// EMAS 控制台 URL 常见平台段：Android 多为 `2`，iOS 多为 `1`（以你控制台地址栏为准）。
String osCodeForEmasConsole(String os) {
  final o = os.trim().toLowerCase();
  if (o == 'android' || o == '2') return '2';
  if (o == 'ios' || o == 'iphone' || o == 'ipad' || o == '1') return '1';
  return o;
}

/// 替换模板中的 `{digest}`、`{osCode}`、`{bizConsole}`（URL 编码仅作用于 digest）。
/// [bizModuleForConsole] 非空时用于 `{bizConsole}`（如工作台当前子模块为 anr）。
String applyConsolePlaceholders(
  ToolConfig config,
  String digest,
  String template, {
  String? bizModuleForConsole,
}) {
  final encDigest = Uri.encodeComponent(digest);
  final biz = bizModuleForConsole ?? config.bizModule;
  return template
      .replaceAll('{digest}', encDigest)
      .replaceAll('{osCode}', osCodeForEmasConsole(config.os))
      .replaceAll('{bizConsole}', bizConsoleSegment(biz));
}

/// 单条问题控制台链接；模板可含 `{digest}`、`{osCode}`、`{bizConsole}`。
///
/// 示例（与控制台地址栏形态一致，需替换为你的空间 ID、应用 ID；查询参数名以控制台为准）：
/// `https://emas.console.aliyun.com/apm/3711937/28085188/{osCode}/crashAnalysis/{bizConsole}?digestHash={digest}`
String? consoleLinkForIssue(ToolConfig config, String digest, {String? bizModuleForConsole}) {
  final t = config.consoleIssueUrlTemplate.trim();
  if (t.isNotEmpty) {
    if (t.contains('{digest}') || t.contains('{osCode}') || t.contains('{bizConsole}')) {
      return applyConsolePlaceholders(config, digest, t, bizModuleForConsole: bizModuleForConsole);
    }
    return '$t${t.contains('?') ? '&' : '?'}digest=$digest';
  }
  final base = config.consoleBaseUrl.trim();
  if (base.isEmpty) return null;
  if (base.contains('{digest}') || base.contains('{osCode}') || base.contains('{bizConsole}')) {
    return applyConsolePlaceholders(config, digest, base, bizModuleForConsole: bizModuleForConsole);
  }
  return base.contains('{digest}') ? base.replaceAll('{digest}', Uri.encodeComponent(digest)) : base;
}

/// 根据请求参数生成具体的崩溃详情地址
/// 格式: https://emas.console.aliyun.com/apm/{spaceId}/{appId}/{osCode}/{analysisPath}/detail?fromType={fromType}&digestId={digest}&pageNum=1
String? buildCrashConsoleUrl({
  required ToolConfig config,
  required String digest,
  String? bizModule,
}) {
  final baseUrl = config.consoleBaseUrl.trim();
  if (baseUrl.isEmpty) return null;

  final biz = (bizModule ?? config.bizModule).trim().toLowerCase();
  final osCode = osCodeForEmasConsole(config.os);
  final analysisPath = consoleAnalysisPath(biz);
  final fromType = biz == 'lag' || biz == 'anr' ? 'lag' : biz;

  // 从 consoleBaseUrl 提取 spaceId 和 appId (格式: .../apm/{spaceId}/{appId}/...)
  final regex = RegExp(r'/apm/(\d+)/(\d+)');
  final match = regex.firstMatch(baseUrl);

  if (match != null && match.groupCount >= 2) {
    final spaceId = match.group(1)!;
    final appId = match.group(2)!;

    final url = 'https://emas.console.aliyun.com/apm/$spaceId/$appId/$osCode/$analysisPath/detail?fromType=$fromType&digestId=$digest&pageNum=1';
    return url;
  }

  return null;
}
