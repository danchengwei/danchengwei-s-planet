import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import 'emas_intelligent_analyzer.dart';
import 'stack_parser.dart';

/// HTML 报告解析器（解析 Baymax 格式的 HTML 报告）
class HtmlReportAnalyzer {
  HtmlReportAnalyzer(this.htmlContent);

  final String htmlContent;

  /// 解析 HTML 报告并提取分析数据
  Map<String, dynamic> parseReport() {
    final doc = _parseHtml(htmlContent);

    return {
      'digestHash': _extractDigestHash(doc),
      'issueType': _extractIssueType(doc),
      'stackTrace': _extractStackTrace(doc),
      'distribution': _extractDistribution(doc),
      'analysisText': _extractAnalysisText(doc),
      'metadata': _extractMetadata(doc),
    };
  }

  /// 内部 HTML 解析包装
  Document _parseHtml(String html) {
    return parse(html);
  }

  /// 从 HTML 中提取 Digest Hash
  String _extractDigestHash(Document doc) {
    final digestEl = doc.querySelector('[data-digest]');
    if (digestEl != null) {
      return digestEl.attributes['data-digest'] ?? '';
    }

    // 备选：从标题中提取
    final h1 = doc.querySelector('h1');
    if (h1 != null) {
      final text = h1.text;
      final match = RegExp(r'([a-f0-9]{32,})').firstMatch(text);
      if (match != null) {
        return match.group(1) ?? '';
      }
    }

    return '';
  }

  /// 从 HTML 中提取问题类型
  String _extractIssueType(Document doc) {
    // 查找问题类型标签
    final typeEl = doc.querySelector('[data-issue-type]');
    if (typeEl != null) {
      return typeEl.attributes['data-issue-type'] ?? 'Unknown';
    }

    // 查找 meta 标签
    final metaIssueType = doc.querySelector('meta[name="issue-type"]');
    if (metaIssueType != null) {
      return metaIssueType.attributes['content'] ?? 'Unknown';
    }

    // 从标题中推断
    final title = doc.querySelector('title')?.text ?? '';
    if (title.contains('Crash')) return 'Crash';
    if (title.contains('ANR')) return 'ANR';
    if (title.contains('Lag')) return 'Lag';

    return 'Unknown';
  }

  /// 从 HTML 中提取堆栈跟踪
  String _extractStackTrace(Document doc) {
    // 查找 <pre> 标签内的堆栈跟踪
    final preElements = doc.querySelectorAll('pre');
    for (final pre in preElements) {
      final text = pre.text;
      if (text.contains('at ') || text.contains('Exception') || text.contains('Error')) {
        return text;
      }
    }

    // 查找 data 属性
    final stackEl = doc.querySelector('[data-stack]');
    if (stackEl != null) {
      return stackEl.attributes['data-stack'] ?? '';
    }

    // 查找特定 ID
    final stackDiv = doc.getElementById('stack-trace');
    if (stackDiv != null) {
      return stackDiv.text;
    }

    return '';
  }

  /// 从 HTML 中提取分布数据
  Map<String, dynamic> _extractDistribution(Document doc) {
    final dist = <String, dynamic>{};

    // 提取总崩溃数
    final countEl = doc.querySelector('[data-error-count]');
    dist['ErrorCount'] = int.tryParse(countEl?.attributes['data-error-count'] ?? '0') ?? 0;

    // 提取版本分布表
    dist['VersionDistribution'] = _extractTableData(doc, 'version-distribution');
    dist['SystemVersionDistribution'] = _extractTableData(doc, 'system-distribution');
    dist['DeviceDistribution'] = _extractTableData(doc, 'device-distribution');
    dist['BrandDistribution'] = _extractTableData(doc, 'brand-distribution');

    return dist;
  }

  /// 从 HTML 表格中提取数据
  List<Map<String, dynamic>> _extractTableData(Document doc, String tableId) {
    final result = <Map<String, dynamic>>[];
    final table = doc.getElementById(tableId) ?? doc.querySelector('table[data-type="$tableId"]');

    if (table == null) return result;

    final rows = table.querySelectorAll('tbody tr');
    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.length >= 2) {
        final percentage = cells.length > 2 ? double.tryParse(cells[2].text.trim()) ?? 0.0 : 0.0;
        result.add({
          'name': cells[0].text.trim(),
          'count': int.tryParse(cells[1].text.trim()) ?? 0,
          'percentage': percentage,
        });
      }
    }

    return result;
  }

  /// 从 HTML 中提取分析文本
  String _extractAnalysisText(Document doc) {
    // 查找分析结果部分
    final analysisEl = doc.querySelector('[data-analysis]');
    if (analysisEl != null) {
      return analysisEl.innerHtml;
    }

    // 查找特定 ID 的 div
    final analysisDiv = doc.getElementById('analysis-result');
    if (analysisDiv != null) {
      return analysisDiv.text;
    }

    // 查找最后一个 section 或 article
    final sections = doc.querySelectorAll('section, article');
    if (sections.isNotEmpty) {
      return sections.last.text;
    }

    return '';
  }

  /// 从 HTML 中提取元数据
  Map<String, String> _extractMetadata(Document doc) {
    final metadata = <String, String>{};

    // 查找所有 meta 标签
    final metaTags = doc.querySelectorAll('meta');
    for (final meta in metaTags) {
      final name = meta.attributes['name'];
      final content = meta.attributes['content'];
      if (name != null && content != null) {
        metadata[name] = content;
      }
    }

    // 查找 data-* 属性
    final rootEl = doc.documentElement;
    if (rootEl != null) {
      for (final entry in rootEl.attributes.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (key.startsWith('data-')) {
          metadata[key] = value.toString();
        }
      }
    }

    return metadata;
  }

  /// 将解析结果转换为 issueData 格式（兼容 EmasIntelligentAnalyzer）
  Map<String, dynamic> toIssueData() {
    final parsed = parseReport();

    // 构造与 EMAS API 兼容的数据结构
    final stackTrace = parsed['stackTrace'] as String;
    final stackInfo = StackParser.parse(stackTrace);

    return {
      'Name': parsed['issueType'],
      'Stack': stackTrace,
      'ErrorCount': parsed['distribution']['ErrorCount'],
      'SystemVersionDistribution': parsed['distribution']['SystemVersionDistribution'],
      'VersionDistribution': parsed['distribution']['VersionDistribution'],
      'DeviceDistribution': parsed['distribution']['DeviceDistribution'],
      'BrandDistribution': parsed['distribution']['BrandDistribution'],
      'CrashType': stackInfo.crashType,
      'ExceptionName': stackInfo.exceptionName,
    };
  }
}

/// HTML 报告构建器 - 生成 Baymax 格式的 HTML 报告
class HtmlReportBuilder {
  /// 从 AnalysisReport 生成 Baymax 格式 HTML
  static String buildBaymax(AnalysisReport report) {
    final buffer = StringBuffer();

    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="zh-CN">');
    buffer.writeln('<head>');
    buffer.writeln('<meta charset="UTF-8">');
    buffer.writeln('<meta name="viewport" content="width=device-width, initial-scale=1.0">');
    buffer.writeln('<meta name="issue-type" content="${report.issueType}">');
    buffer.writeln('<meta name="created-at" content="${report.createdAt.toIso8601String()}">');
    buffer.writeln('<title>EMAS 智能分析报告 - ${report.issueType}</title>');
    buffer.writeln('<style>');
    buffer.writeln(_getBayamaxStyles());
    buffer.writeln('</style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');

    // 头部
    buffer.writeln('<header class="report-header">');
    buffer.writeln('<h1 class="report-title">${report.issueType} 分析报告</h1>');
    buffer.writeln('<div class="digest-hash" data-digest="${report.digestHash}">');
    buffer.writeln('Digest: <code>${report.digestHash}</code>');
    buffer.writeln('</div>');
    buffer.writeln('</header>');

    // 概览卡片
    buffer.writeln('<section class="overview-section">');
    buffer.writeln('<h2>基本信息</h2>');
    buffer.writeln('<table class="overview-table">');
    buffer.writeln('<tr><th>项目</th><th>值</th></tr>');
    buffer.writeln('<tr><td>问题类型</td><td>${report.issueType}</td></tr>');
    buffer.writeln('<tr><td>堆栈类型</td><td>${report.stackInfo.crashType}</td></tr>');
    buffer.writeln('<tr><td>堆栈行数</td><td>${report.stackInfo.lineCount}</td></tr>');
    buffer.writeln('<tr><td>分析时间</td><td>${report.createdAt}</td></tr>');
    buffer.writeln('</table>');
    buffer.writeln('</section>');

    // 分布分析
    if (report.distribution.totalCount > 0) {
      buffer.writeln('<section class="distribution-section" data-error-count="${report.distribution.totalCount}">');
      buffer.writeln('<h2>分布分析</h2>');

      // 版本分布表
      if (report.distribution.versions.isNotEmpty) {
        buffer.writeln('<div class="table-wrapper" id="version-distribution">');
        buffer.writeln('<h3>版本分布</h3>');
        buffer.writeln('<table>');
        buffer.writeln('<thead><tr><th>版本</th><th>崩溃数</th><th>占比</th></tr></thead>');
        buffer.writeln('<tbody>');
        for (final v in report.distribution.versions) {
          buffer.writeln('<tr><td>${v.version}</td><td>${v.count}</td><td>${v.percentage.toStringAsFixed(2)}%</td></tr>');
        }
        buffer.writeln('</tbody></table>');
        buffer.writeln('</div>');
      }

      // 系统分布表
      if (report.distribution.osVersions.isNotEmpty) {
        buffer.writeln('<div class="table-wrapper" id="system-distribution">');
        buffer.writeln('<h3>系统版本分布</h3>');
        buffer.writeln('<table>');
        buffer.writeln('<thead><tr><th>系统版本</th><th>崩溃数</th><th>占比</th></tr></thead>');
        buffer.writeln('<tbody>');
        for (final os in report.distribution.osVersions) {
          buffer.writeln('<tr><td>${os.osVersion}</td><td>${os.count}</td><td>${os.percentage.toStringAsFixed(2)}%</td></tr>');
        }
        buffer.writeln('</tbody></table>');
        buffer.writeln('</div>');
      }

      buffer.writeln('</section>');
    }

    // 代码位置
    if (report.stackInfo.applicationCodeLocation != null) {
      final loc = report.stackInfo.applicationCodeLocation!;
      buffer.writeln('<section class="code-location-section">');
      buffer.writeln('<h2>应用代码位置</h2>');
      buffer.writeln('<div class="code-location-card">');
      buffer.writeln('<p><strong>类:</strong> <code>${loc.className}</code></p>');
      buffer.writeln('<p><strong>方法:</strong> <code>${loc.methodName}</code></p>');
      buffer.writeln('<p><strong>文件:</strong> <code>${loc.fileName}</code></p>');
      buffer.writeln('<p><strong>行号:</strong> ${loc.lineNumber}</p>');
      buffer.writeln('</div>');
      buffer.writeln('</section>');
    }

    // 分析结果
    buffer.writeln('<section class="analysis-section" id="analysis-result">');
    buffer.writeln('<h2>AI 分析结果</h2>');
    buffer.writeln('<div class="analysis-content">');
    buffer.write(_markdownToHtml(report.analysisText));
    buffer.writeln('</div>');
    buffer.writeln('</section>');

    // 底部
    buffer.writeln('<footer class="report-footer">');
    buffer.writeln('<p>报告生成时间: ${report.createdAt}</p>');
    buffer.writeln('</footer>');

    buffer.writeln('</body>');
    buffer.writeln('</html>');

    return buffer.toString();
  }

  /// 获取 Baymax 样式
  static String _getBayamaxStyles() {
    return '''
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
  line-height: 1.6;
  color: #333;
  background-color: #f5f7fa;
}

.report-header {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  padding: 40px 20px;
  text-align: center;
}

.report-title {
  font-size: 32px;
  margin-bottom: 15px;
}

.digest-hash {
  font-size: 14px;
  opacity: 0.9;
}

.digest-hash code {
  background-color: rgba(255,255,255,0.2);
  padding: 4px 8px;
  border-radius: 4px;
  font-family: monospace;
}

section {
  background: white;
  margin: 20px;
  padding: 20px;
  border-radius: 8px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
}

h2 {
  font-size: 24px;
  margin-bottom: 15px;
  color: #2c3e50;
  border-bottom: 2px solid #667eea;
  padding-bottom: 10px;
}

h3 {
  font-size: 18px;
  margin-top: 15px;
  margin-bottom: 10px;
  color: #34495e;
}

table {
  width: 100%;
  border-collapse: collapse;
  margin-top: 10px;
}

th {
  background-color: #667eea;
  color: white;
  padding: 12px;
  text-align: left;
}

td {
  border: 1px solid #ecf0f1;
  padding: 10px;
}

tr:nth-child(even) {
  background-color: #f9f9f9;
}

code {
  background-color: #f4f4f4;
  padding: 2px 6px;
  border-radius: 3px;
  font-family: 'Monaco', 'Courier New', monospace;
}

.code-location-card {
  background-color: #f9f9f9;
  padding: 15px;
  border-left: 4px solid #667eea;
  border-radius: 4px;
}

.code-location-card p {
  margin: 8px 0;
}

.analysis-content {
  padding: 15px;
  background-color: #f9f9f9;
  border-radius: 4px;
}

.report-footer {
  text-align: center;
  color: #7f8c8d;
  font-size: 12px;
  margin-top: 40px;
  padding: 20px;
  border-top: 1px solid #ecf0f1;
}

@media (max-width: 768px) {
  section {
    margin: 10px;
    padding: 15px;
  }

  .report-title {
    font-size: 24px;
  }
}
''';
  }

  /// Markdown 转 HTML（简易转换）
  static String _markdownToHtml(String markdown) {
    var html = markdown;

    // 标题
    html = html.replaceAll(RegExp(r'^## (.+)$', multiLine: true), '<h2>\$1</h2>');
    html = html.replaceAll(RegExp(r'^### (.+)$', multiLine: true), '<h3>\$1</h3>');

    // 加粗
    html = html.replaceAll(RegExp(r'\*\*(.+?)\*\*'), '<strong>\$1</strong>');

    // 代码块
    html = html.replaceAll(RegExp(r'```(.+?)```', dotAll: true), '<pre><code>\$1</code></pre>');

    // 行内代码
    html = html.replaceAll(RegExp(r'`([^`]+)`'), '<code>\$1</code>');

    // 列表项
    html = html.replaceAll(RegExp(r'^- (.+)$', multiLine: true), '<li>\$1</li>');
    html = html.replaceAll(RegExp(r'(<li>.+</li>)', dotAll: true), '<ul>\$1</ul>');

    // 换行
    html = html.replaceAll(RegExp(r'\n\n'), '</p><p>');
    html = '<p>\$html</p>';

    return html;
  }
}
