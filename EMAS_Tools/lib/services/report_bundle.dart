import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../aliyun/emas_appmonitor_client.dart';
import '../models/tool_config.dart';
import 'agent_launcher.dart';
import 'console_links.dart';

/// 导出完整报告目录：index.html、manifest.json、payloads/*.json（供 crash-tools:// 打开）。
Future<String> exportReportBundle({
  required ToolConfig config,
  required List<IssueListItem> items,
  required int startMs,
  required int endMs,
  required Directory parentDir,
  String? bizModuleShown,
  String? nameFilterShown,
}) async {
  final bizLabel = bizModuleShown ?? config.bizModule;
  if (items.isEmpty) return 'err:没有可导出的问题';
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final dir = Directory(p.join(parentDir.path, 'emas_report_$stamp'));
  await dir.create(recursive: true);
  final payloadsDir = Directory(p.join(dir.path, 'payloads'));
  await payloadsDir.create();

  final manifest = <String, dynamic>{
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'rangeStartMs': startMs,
    'rangeEndMs': endMs,
    'appKey': config.appKey,
    'bizModule': bizLabel,
    if (nameFilterShown != null && nameFilterShown.trim().isNotEmpty) 'nameFilter': nameFilterShown.trim(),
    'issues': <Map<String, dynamic>>[],
  };

  final rows = StringBuffer();
  const esc = HtmlEscape();

  for (final it in items) {
    final digest = it.digestHash ?? '';
    if (digest.isEmpty) continue;
    final safeName = digest.replaceAll(RegExp(r'[^\w.-]+'), '_');

    final prompt = AgentLauncher.buildPromptFromIssue(
      digestHash: digest,
      getIssueBody: null,
      listTitle: it.errorName,
      listStack: it.stack,
    );
    final payload = AgentLauncher.payloadFromConfig(config: config, digestHash: digest, prompt: prompt);
    final payloadFile = File(p.join(payloadsDir.path, '$safeName.json'));
    await payloadFile.writeAsString(const JsonEncoder.withIndent('  ').convert(payload.toJson()), encoding: utf8);

    final relPayload = 'payloads/$safeName.json';
    (manifest['issues'] as List).add({
      'digestHash': digest,
      'payload': relPayload,
      'title': it.errorName,
    });

    final openUri = 'crash-tools://open?path=${Uri.encodeComponent(payloadFile.absolute.path)}';
    final consoleLink = consoleLinkForIssue(config, digest, bizModuleForConsole: bizLabel);

    final name = esc.convert(it.errorName ?? '');
    final d = esc.convert(digest);
    final stack = esc.convert(it.stack ?? '').replaceAll('\n', '<br/>');

    rows.writeln('''
<tr>
  <td>$name</td>
  <td><code>$d</code></td>
  <td>${it.errorCount ?? ''}</td>
  <td>
    <details><summary>查看堆栈</summary><div class="stack">$stack</div></details>
  </td>
  <td>${consoleLink == null ? '-' : '<a href="${esc.convert(consoleLink)}" target="_blank">阿里云</a>'}</td>
  <td><a href="$openUri">去处理</a></td>
</tr>''');
  }

  await File(p.join(dir.path, 'manifest.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
    encoding: utf8,
  );

  final html = _htmlShell(
    config: config,
    startMs: startMs,
    endMs: endMs,
    tableRows: rows.toString(),
    bizModuleShown: bizLabel,
    nameFilterShown: nameFilterShown,
  );
  await File(p.join(dir.path, 'index.html')).writeAsString(html, encoding: utf8);

  return 'ok:${dir.absolute.path}';
}

String _htmlShell({
  required ToolConfig config,
  required int startMs,
  required int endMs,
  required String tableRows,
  String? bizModuleShown,
  String? nameFilterShown,
}) {
  const esc = HtmlEscape();
  final console = config.consoleBaseUrl.trim();
  final topLink = console.isEmpty ? '#' : esc.convert(console);
  final bizLabel = bizModuleShown ?? config.bizModule;
  final filterNote = (nameFilterShown != null && nameFilterShown.trim().isNotEmpty)
      ? ' · Name筛选：${esc.convert(nameFilterShown.trim())}'
      : '';
  return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<title>EMAS 完整报告</title>
<style>
body { font-family: system-ui, sans-serif; margin: 16px; }
table { border-collapse: collapse; width: 100%; table-layout: fixed; }
th, td { border: 1px solid #ccc; padding: 8px; vertical-align: top; word-break: break-word; }
th { background: #f5f5f5; }
code { font-size: 11px; }
.stack { max-height: 240px; overflow: auto; background: #fafafa; padding: 8px; margin-top: 8px; }
.note { color: #666; font-size: 13px; margin: 12px 0; }
</style>
</head>
<body>
<h1>EMAS 聚合问题报告</h1>
<p class="note">时间(ms)：$startMs ~ $endMs · AppKey：${esc.convert(config.appKey)} · BizModule：${esc.convert(bizLabel)}$filterNote</p>
<p><a href="$topLink" target="_blank">控制台总入口</a> · 同目录含 <code>manifest.json</code> 与 <code>payloads/*.json</code></p>
<p class="note">「去处理」需本机已安装本应用并注册 <code>crash-tools://</code> 协议；点击后将打开对应 payload 并执行配置中的 Agent。</p>
<table>
<thead>
<tr>
<th>错误名</th><th>Digest</th><th>次数</th><th>堆栈</th><th>控制台</th><th>去处理</th>
</tr>
</thead>
<tbody>
$tableRows
</tbody>
</table>
</body>
</html>
''';
}
