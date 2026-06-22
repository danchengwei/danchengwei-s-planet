import 'dart:convert';

import '../aliyun/emas_appmonitor_client.dart';
import '../models/tool_config.dart';
import 'console_links.dart';

/// 生成本地可打开的简易 HTML（含单条控制台链接列）。
String buildIssuesHtml({
  required ToolConfig config,
  required List<IssueListItem> items,
  required int startMs,
  required int endMs,
  String? bizModuleShown,
  String? nameFilterShown,
  String? packageNameShown,
}) {
  const esc = HtmlEscape();
  final bizLabel = bizModuleShown ?? config.bizModule;
  final filterNote = (nameFilterShown != null && nameFilterShown.trim().isNotEmpty)
      ? ' · 应用版本：${esc.convert(nameFilterShown.trim())}'
      : '';
  final pkgSrc = packageNameShown?.trim();
  final pkgNote = (pkgSrc != null && pkgSrc.isNotEmpty)
      ? ' · 包名：${esc.convert(pkgSrc)}'
      : '';
  final rows = StringBuffer();
  for (final it in items) {
    final name = esc.convert(it.errorName ?? '');
    final digestRaw = it.digestHash ?? '';
    final digest = esc.convert(digestRaw);
    final stack = esc.convert(it.stack ?? '').replaceAll('\n', '<br/>');
    final clink =
        digestRaw.isEmpty ? null : consoleLinkForIssue(config, digestRaw, bizModuleForConsole: bizLabel);
    final ccell = clink == null ? '-' : '<a href="${esc.convert(clink)}" target="_blank">控制台</a>';
    rows.writeln(
      '<tr><td>$name</td><td><code>$digest</code></td><td>${it.errorCount ?? ''}</td>'
      '<td><details><summary>查看</summary><div>$stack</div></details></td><td>$ccell</td></tr>',
    );
  }
  final console = config.consoleBaseUrl.trim();
  final consoleLink = console.isEmpty ? '#' : esc.convert(console);
  return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<title>EMAS 问题简报</title>
<style>
body { font-family: system-ui, sans-serif; margin: 16px; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #ccc; padding: 8px; vertical-align: top; }
th { background: #f5f5f5; }
code { font-size: 12px; word-break: break-all; }
</style>
</head>
<body>
<h1>EMAS 聚合问题简报</h1>
<p>时间范围(ms)：$startMs ~ $endMs | AppKey：${esc.convert(config.appKey)} | BizModule：${esc.convert(bizLabel)}$filterNote$pkgNote</p>
<p><a href="$consoleLink" target="_blank">打开控制台（需在配置中填写前缀）</a></p>
<table>
<thead><tr><th>错误名</th><th>DigestHash</th><th>次数</th><th>堆栈</th><th>控制台</th></tr></thead>
<tbody>
$rows
</tbody>
</table>
</body>
</html>
''';
}
