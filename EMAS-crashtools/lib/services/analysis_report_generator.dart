import 'dart:io';
import 'package:intl/intl.dart';

/// 生成聚合分析报告
class AnalysisReportGenerator {
  Future<String> generateReport({
    required String title,
    required String description,
    required bool includeTopCrashes,
    required bool includeTopAnrs,
    required bool includeStackAnalysis,
    required bool includeSuggestions,
    required int topItemsCount,
  }) async {
    // 获取文档目录
    final now = DateTime.now();
    final formatter = DateFormat('yyyyMMdd_HHmmss');
    final filename = 'emas_report_${formatter.format(now)}.html';

    // 尝试保存到桌面或文档目录
    final homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final reportsDir = Directory('$homeDir/Desktop/EMAS-Reports');
    if (!await reportsDir.exists()) {
      await reportsDir.create(recursive: true);
    }

    final reportFile = File('${reportsDir.path}/$filename');

    // 生成 HTML 报告
    final html = _generateHtmlReport(
      title: title,
      description: description,
      timestamp: now,
      includeTopCrashes: includeTopCrashes,
      includeTopAnrs: includeTopAnrs,
      includeStackAnalysis: includeStackAnalysis,
      includeSuggestions: includeSuggestions,
      topItemsCount: topItemsCount,
    );

    await reportFile.writeAsString(html);
    return reportFile.path;
  }

  String _generateHtmlReport({
    required String title,
    required String description,
    required DateTime timestamp,
    required bool includeTopCrashes,
    required bool includeTopAnrs,
    required bool includeStackAnalysis,
    required bool includeSuggestions,
    required int topItemsCount,
  }) {
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    final dateStr = formatter.format(timestamp);

    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$title</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            background: #f5f5f5;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 40px 20px;
        }

        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            border-radius: 12px;
            margin-bottom: 40px;
        }

        .header h1 {
            font-size: 32px;
            margin-bottom: 10px;
        }

        .header p {
            font-size: 14px;
            opacity: 0.9;
        }

        .meta-info {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 16px;
            margin-bottom: 40px;
        }

        .meta-card {
            background: white;
            padding: 16px;
            border-radius: 8px;
            box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
        }

        .meta-card strong {
            display: block;
            margin-bottom: 4px;
            color: #667eea;
            font-size: 12px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .meta-card p {
            font-size: 16px;
            color: #333;
        }

        section {
            background: white;
            padding: 24px;
            margin-bottom: 24px;
            border-radius: 8px;
            box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
        }

        h2 {
            font-size: 24px;
            margin-bottom: 16px;
            padding-bottom: 12px;
            border-bottom: 2px solid #667eea;
            color: #333;
        }

        h3 {
            font-size: 18px;
            margin-top: 16px;
            margin-bottom: 12px;
            color: #555;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 12px;
        }

        th {
            background: #f5f5f5;
            padding: 12px;
            text-align: left;
            font-weight: 600;
            color: #333;
            border-bottom: 2px solid #e0e0e0;
        }

        td {
            padding: 12px;
            border-bottom: 1px solid #e0e0e0;
        }

        tr:hover {
            background: #fafafa;
        }

        .stat-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 16px;
            margin-bottom: 24px;
        }

        .stat-box {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 8px;
            text-align: center;
        }

        .stat-box .number {
            font-size: 32px;
            font-weight: bold;
            margin-bottom: 8px;
        }

        .stat-box .label {
            font-size: 12px;
            opacity: 0.9;
        }

        .stack-trace {
            background: #f5f5f5;
            border-left: 4px solid #667eea;
            padding: 12px;
            margin: 12px 0;
            font-family: 'Monaco', 'Courier New', monospace;
            font-size: 12px;
            color: #333;
            overflow-x: auto;
            white-space: pre-wrap;
            word-break: break-word;
        }

        .suggestion {
            background: #e8f5e9;
            border-left: 4px solid #4caf50;
            padding: 12px;
            margin: 12px 0;
            border-radius: 4px;
        }

        .suggestion strong {
            color: #2e7d32;
        }

        .empty {
            text-align: center;
            color: #999;
            padding: 40px;
            font-size: 14px;
        }

        .footer {
            text-align: center;
            padding: 20px;
            color: #999;
            font-size: 12px;
            margin-top: 40px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>$title</h1>
            <p>$description</p>
        </div>

        <div class="meta-info">
            <div class="meta-card">
                <strong>生成时间</strong>
                <p>$dateStr</p>
            </div>
            <div class="meta-card">
                <strong>报告版本</strong>
                <p>1.0</p>
            </div>
            <div class="meta-card">
                <strong>数据来源</strong>
                <p>EMAS AppMonitor</p>
            </div>
        </div>

        ${includeTopCrashes ? _buildCrashesSection(topItemsCount) : ''}

        ${includeTopAnrs ? _buildAnrsSection(topItemsCount) : ''}

        ${includeStackAnalysis ? _buildStackAnalysisSection() : ''}

        ${includeSuggestions ? _buildSuggestionsSection() : ''}

        <section>
            <h2>总结</h2>
            <p>本报告基于 EMAS AppMonitor 收集的真实用户数据生成。建议按优先级修复排名前 3-5 的问题。</p>
        </section>
    </div>

    <div class="footer">
        <p>由 EMAS 小助手生成 • Generated by EMAS Assistant</p>
    </div>
</body>
</html>
''';
  }

  String _buildCrashesSection(int count) {
    return '''
        <section>
            <h2>Top $count 崩溃</h2>
            <div class="stat-grid">
                <div class="stat-box">
                    <div class="number">0</div>
                    <div class="label">总崩溃数</div>
                </div>
                <div class="stat-box">
                    <div class="number">0</div>
                    <div class="label">受影响设备</div>
                </div>
                <div class="stat-box">
                    <div class="number">0%</div>
                    <div class="label">崩溃率</div>
                </div>
            </div>
            <table>
                <thead>
                    <tr>
                        <th>排名</th>
                        <th>异常类型</th>
                        <th>发生次数</th>
                        <th>受影响设备</th>
                        <th>错误率</th>
                    </tr>
                </thead>
                <tbody>
                    <tr><td colspan="5" class="empty">暂无数据 - 请配置 EMAS 凭证并拉取数据</td></tr>
                </tbody>
            </table>
        </section>
''';
  }

  String _buildAnrsSection(int count) {
    return '''
        <section>
            <h2>Top $count ANR</h2>
            <div class="stat-grid">
                <div class="stat-box">
                    <div class="number">0</div>
                    <div class="label">总 ANR 数</div>
                </div>
                <div class="stat-box">
                    <div class="number">0</div>
                    <div class="label">受影响设备</div>
                </div>
            </div>
            <table>
                <thead>
                    <tr>
                        <th>排名</th>
                        <th>ANR 类型</th>
                        <th>发生次数</th>
                        <th>受影响设备</th>
                    </tr>
                </thead>
                <tbody>
                    <tr><td colspan="4" class="empty">暂无数据 - 请配置 EMAS 凭证并拉取数据</td></tr>
                </tbody>
            </table>
        </section>
''';
  }

  String _buildStackAnalysisSection() {
    return '''
        <section>
            <h2>堆栈分析</h2>
            <h3>关键异常点识别</h3>
            <p>对排名前 5 的崩溃进行代码级分析，结合源代码识别问题根源：</p>
            <ul style="margin-left: 20px; margin-top: 12px;">
                <li>异常发生位置的代码逻辑审查</li>
                <li>相关调用链路的并发安全性检查</li>
                <li>资源泄漏和内存问题诊断</li>
                <li>与已知 Android/iOS 系统问题的关联性</li>
            </ul>
        </section>
''';
  }

  String _buildSuggestionsSection() {
    return '''
        <section>
            <h2>修复建议</h2>
            <div class="suggestion">
                <strong>1. 崩溃修复优先级：</strong><br>
                按错误率降序修复，优先处理影响用户最多的问题。
            </div>
            <div class="suggestion">
                <strong>2. 回归测试策略：</strong><br>
                修复后需在多个 Android/iOS 版本上进行充分测试，特别是涉及系统 API 的修改。
            </div>
            <div class="suggestion">
                <strong>3. 灰度发布：</strong><br>
                建议先在小范围用户中灰度发布，监控修复效果后再全量发布。
            </div>
            <div class="suggestion">
                <strong>4. 监控告警：</strong><br>
                在修复版本发布后持续监控该类崩溃的发生率，设置告警阈值防止回归。
            </div>
        </section>
''';
  }
}
