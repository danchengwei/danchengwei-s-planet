import 'dart:convert';
import 'emas_intelligent_analyzer.dart';
import 'distribution_analyzer.dart';

/// 多格式报告生成器
class ReportGenerator {
  /// 生成 Markdown 格式报告（参照 emas-intelligent-analysis2 样例格式）
  static String toMarkdown(AnalysisReport report) {
    final buffer = StringBuffer();

    // 标题
    buffer.writeln('# EMAS 智能分析报告');
    buffer.writeln();

    // 分析概览
    buffer.writeln('## 📋 分析概览');
    buffer.writeln('| 项目 | 内容 |');
    buffer.writeln('|------|------|');
    buffer.writeln('| 分析类型 | ${report.issueType} |');
    buffer.writeln('| Digest Hash | `${report.digestHash}` |');
    buffer.writeln('| 堆栈类型 | ${report.stackInfo.crashType} |');
    buffer.writeln('| 堆栈行数 | ${report.stackInfo.lineCount} |');
    buffer.writeln('| 分析时间 | ${report.createdAt.toIso8601String()} |');
    buffer.writeln();

    // 分布分析
    if (report.distribution.totalCount > 0) {
      buffer.writeln('## 📊 分布分析');
      buffer.writeln('| 类别 | 数值 |');
      buffer.writeln('|------|------|');
      buffer.writeln('| 总崩溃数 | ${report.distribution.totalCount} |');
      buffer.writeln('| 涉及版本 | ${report.distribution.versions.length} 个 |');
      buffer.writeln('| 涉及系统 | ${report.distribution.osVersions.length} 种 |');
      buffer.writeln('| 涉及品牌 | ${report.distribution.brands.length} 个 |');
      buffer.writeln();

      // 详细分布表
      buffer.write(DistributionAnalyzer.generateDistributionTable(report.distribution));
    }

    // 堆栈分析
    buffer.writeln('## 📍 堆栈分析');
    buffer.writeln();

    if (report.stackInfo.applicationCodeLocation != null) {
      final loc = report.stackInfo.applicationCodeLocation!;
      buffer.writeln('### 🏠 应用代码位置');
      buffer.writeln('- **类**: `${loc.className}`');
      buffer.writeln('- **方法**: `${loc.methodName}`');
      buffer.writeln('- **文件**: `${loc.fileName}`');
      buffer.writeln('- **行号**: `${loc.lineNumber}`');
      buffer.writeln();
    }

    if (report.stackInfo.javaClasses.isNotEmpty) {
      buffer.writeln('### ☕ 涉及的 Java 类');
      for (final cls in report.stackInfo.javaClasses.take(10)) {
        buffer.writeln('- `$cls`');
      }
      buffer.writeln();
    }

    // 源码分析
    if (report.sourceCode.isNotEmpty) {
      buffer.writeln('## 🔎 源码分析');
      buffer.writeln();

      for (final entry in report.sourceCode.entries) {
        buffer.writeln('### 📄 ${entry.key}');
        buffer.writeln('```java');
        buffer.writeln(entry.value);
        buffer.writeln('```');
        buffer.writeln();
      }
    }

    // Git 信息
    if (report.contributors.isNotEmpty) {
      buffer.writeln('## 👥 代码贡献者');
      buffer.writeln();

      for (final entry in report.contributors.entries) {
        buffer.writeln('### ${entry.key}');
        for (final contributor in entry.value) {
          buffer.writeln('- **${contributor.name}**: ${contributor.commitCount} 次提交');
          if (contributor.email != null) {
            buffer.writeln('  - 邮箱: ${contributor.email}');
          }
        }
      }
      buffer.writeln();
    }

    // AI 分析结果
    buffer.writeln('## 💡 AI 分析结果');
    buffer.writeln();
    buffer.writeln(report.analysisText);
    buffer.writeln();

    return buffer.toString();
  }

  /// 生成 HTML 表格格式
  static String toHtml(AnalysisReport report) {
    final buffer = StringBuffer();

    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="zh-CN">');
    buffer.writeln('<head>');
    buffer.writeln('<meta charset="UTF-8">');
    buffer.writeln('<meta name="viewport" content="width=device-width, initial-scale=1.0">');
    buffer.writeln('<title>EMAS 智能分析报告</title>');
    buffer.writeln('<style>');
    buffer.writeln('body { font-family: Arial, sans-serif; margin: 20px; color: #333; }');
    buffer.writeln('h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }');
    buffer.writeln('h2 { color: #34495e; margin-top: 20px; }');
    buffer.writeln('table { border-collapse: collapse; width: 100%; margin-top: 10px; }');
    buffer.writeln('th { background-color: #3498db; color: white; padding: 12px; text-align: left; }');
    buffer.writeln('td { border: 1px solid #bdc3c7; padding: 10px; }');
    buffer.writeln('tr:nth-child(even) { background-color: #ecf0f1; }');
    buffer.writeln('code { background-color: #f4f4f4; padding: 2px 5px; border-radius: 3px; }');
    buffer.writeln('pre { background-color: #f4f4f4; padding: 10px; border-radius: 5px; overflow-x: auto; }');
    buffer.writeln('</style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');

    // 标题
    buffer.writeln('<h1>📊 EMAS 智能分析报告</h1>');

    // 概览表
    buffer.writeln('<h2>分析概览</h2>');
    buffer.writeln('<table>');
    buffer.writeln('<tr><th>项目</th><th>内容</th></tr>');
    buffer.writeln('<tr><td>分析类型</td><td>${report.issueType}</td></tr>');
    buffer.writeln('<tr><td>Digest Hash</td><td><code>${report.digestHash}</code></td></tr>');
    buffer.writeln('<tr><td>堆栈类型</td><td>${report.stackInfo.crashType}</td></tr>');
    buffer.writeln('<tr><td>堆栈行数</td><td>${report.stackInfo.lineCount}</td></tr>');
    buffer.writeln('</table>');

    // 分布分析表
    if (report.distribution.totalCount > 0) {
      buffer.writeln('<h2>分布分析</h2>');
      buffer.writeln('<table>');
      buffer.writeln('<tr><th>类别</th><th>数值</th></tr>');
      buffer.writeln('<tr><td>总崩溃数</td><td>${report.distribution.totalCount}</td></tr>');
      buffer.writeln('<tr><td>涉及版本</td><td>${report.distribution.versions.length}</td></tr>');
      buffer.writeln('<tr><td>涉及系统</td><td>${report.distribution.osVersions.length}</td></tr>');
      buffer.writeln('</table>');
    }

    // 代码位置
    if (report.stackInfo.applicationCodeLocation != null) {
      final loc = report.stackInfo.applicationCodeLocation!;
      buffer.writeln('<h2>应用代码位置</h2>');
      buffer.writeln('<table>');
      buffer.writeln('<tr><th>属性</th><th>值</th></tr>');
      buffer.writeln('<tr><td>类</td><td><code>${loc.className}</code></td></tr>');
      buffer.writeln('<tr><td>方法</td><td><code>${loc.methodName}</code></td></tr>');
      buffer.writeln('<tr><td>文件</td><td>${loc.fileName}</td></tr>');
      buffer.writeln('<tr><td>行号</td><td>${loc.lineNumber}</td></tr>');
      buffer.writeln('</table>');
    }

    // AI 分析结果
    buffer.writeln('<h2>AI 分析结果</h2>');
    buffer.writeln('<pre>${_escapeHtml(report.analysisText)}</pre>');

    buffer.writeln('</body>');
    buffer.writeln('</html>');

    return buffer.toString();
  }

  /// 生成 JSON 格式
  static String toJson(AnalysisReport report) {
    final json = {
      'digestHash': report.digestHash,
      'issueType': report.issueType,
      'stackInfo': report.stackInfo.toJson(),
      'distribution': report.distribution.toJson(),
      'sourceCodeFiles': report.sourceCode.keys.toList(),
      'sourceCode': report.sourceCode,
      'contributorsCount': report.contributors.length,
      'analysisText': report.analysisText,
      'createdAt': report.createdAt.toIso8601String(),
    };

    return jsonEncode(json);
  }

  /// 生成 TSV（表格格式）
  static String toTsv(AnalysisReport report) {
    final buffer = StringBuffer();

    // 标题
    buffer.writeln('EMAS 智能分析报告（TSV 格式）');
    buffer.writeln();

    // 基本信息
    buffer.writeln('# 基本信息');
    buffer.writeln('属性\t值');
    buffer.writeln('分析类型\t${report.issueType}');
    buffer.writeln('Digest Hash\t${report.digestHash}');
    buffer.writeln('堆栈类型\t${report.stackInfo.crashType}');
    buffer.writeln('堆栈行数\t${report.stackInfo.lineCount}');
    buffer.writeln('分析时间\t${report.createdAt.toIso8601String()}');
    buffer.writeln();

    // 分布统计
    if (report.distribution.totalCount > 0) {
      buffer.writeln('# 分布统计');
      buffer.writeln('类别\t数值');
      buffer.writeln('总崩溃数\t${report.distribution.totalCount}');
      buffer.writeln('涉及版本\t${report.distribution.versions.length}');
      buffer.writeln('涉及系统\t${report.distribution.osVersions.length}');
      buffer.writeln('涉及品牌\t${report.distribution.brands.length}');
      buffer.writeln();

      // 版本分布
      if (report.distribution.versions.isNotEmpty) {
        buffer.writeln('# 版本分布');
        buffer.writeln('版本\t崩溃数\t占比(%)');
        for (final v in report.distribution.versions) {
          buffer.writeln('${v.version}\t${v.count}\t${v.percentage.toStringAsFixed(2)}');
        }
        buffer.writeln();
      }

      // 系统版本分布
      if (report.distribution.osVersions.isNotEmpty) {
        buffer.writeln('# 系统版本分布');
        buffer.writeln('系统版本\t崩溃数\t占比(%)');
        for (final os in report.distribution.osVersions) {
          buffer.writeln('${os.osVersion}\t${os.count}\t${os.percentage.toStringAsFixed(2)}');
        }
        buffer.writeln();
      }
    }

    // 代码位置
    if (report.stackInfo.applicationCodeLocation != null) {
      final loc = report.stackInfo.applicationCodeLocation!;
      buffer.writeln('# 应用代码位置');
      buffer.writeln('属性\t值');
      buffer.writeln('类\t${loc.className}');
      buffer.writeln('方法\t${loc.methodName}');
      buffer.writeln('文件\t${loc.fileName}');
      buffer.writeln('行号\t${loc.lineNumber}');
      buffer.writeln();
    }

    // 分析结果
    buffer.writeln('# AI 分析结果');
    buffer.writeln(report.analysisText);

    return buffer.toString();
  }

  /// HTML 转义
  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}
