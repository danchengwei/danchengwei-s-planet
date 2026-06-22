import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';

/// 解析 Baymax HTML 报告，提取崩溃和 ANR 数据
class HtmlReportParser {
  /// 从 HTML 内容解析报告数据
  Map<String, dynamic> parseReport(String htmlContent) {
    final document = html.parse(htmlContent);

    return {
      'summary': _parseSummary(document),
      'crashes': _parseCrashes(document),
      'anrs': _parseAnrs(document),
    };
  }

  /// 解析报告摘要信息（时间、应用名等）
  Map<String, dynamic> _parseSummary(Document document) {
    try {
      final title = document.querySelector('title')?.text ?? 'Unknown';

      // 尝试从 meta 标签或页面内容提取应用名和时间
      final appNameElement = document.querySelector('[data-app-name]') ??
                             document.querySelector('.app-name');
      final appName = appNameElement?.text ?? 'Unknown App';

      final timeElement = document.querySelector('[data-time]') ??
                         document.querySelector('.generate-time');
      final timestamp = timeElement?.text ?? DateTime.now().toString();

      return {
        'title': title,
        'appName': appName,
        'timestamp': timestamp,
      };
    } catch (e) {
      return {
        'title': 'Unknown',
        'appName': 'Unknown App',
        'timestamp': DateTime.now().toString(),
      };
    }
  }

  /// 解析崩溃数据（Java/Native Top 10）
  List<Map<String, dynamic>> _parseCrashes(Document document) {
    final crashes = <Map<String, dynamic>>[];

    try {
      // 查找包含崩溃数据的表格或列表
      final crashSections = document.querySelectorAll('[data-type="crash"], .crash-section, table[data-crash]');

      for (final section in crashSections) {
        final rows = section.querySelectorAll('tr, .crash-item, [data-crash-item]');
        for (final row in rows) {
          final crash = _parseCrashRow(row);
          if (crash != null) {
            crashes.add(crash);
          }
        }
      }

      // 如果没找到，尝试通用的表格解析
      if (crashes.isEmpty) {
        crashes.addAll(_parseGenericTables(document, 'crash'));
      }

      return crashes.take(10).toList();
    } catch (e) {
      return [];
    }
  }

  /// 解析单个崩溃行
  Map<String, dynamic>? _parseCrashRow(Element row) {
    try {
      final cells = row.querySelectorAll('td, .cell, [data-cell]');
      if (cells.length < 2) return null;

      // 通常格式：[异常名, 次数, 设备数, 其他信息]
      final name = cells.isNotEmpty ? cells[0].text.trim() : null;
      final countStr = cells.length > 1 ? cells[1].text.trim().replaceAll(RegExp(r'[^\d]'), '') : '0';
      final devicesStr = cells.length > 2 ? cells[2].text.trim().replaceAll(RegExp(r'[^\d]'), '') : '0';

      if (name == null || name.isEmpty) return null;

      // 尝试找到堆栈信息
      final stackElement = row.querySelector('[data-stack], .stack, pre');
      final topStack = stackElement?.text;

      return {
        'name': name,
        'count': int.tryParse(countStr) ?? 0,
        'devices': int.tryParse(devicesStr) ?? 0,
        'topStack': topStack,
      };
    } catch (e) {
      return null;
    }
  }

  /// 解析 ANR 数据
  List<Map<String, dynamic>> _parseAnrs(Document document) {
    final anrs = <Map<String, dynamic>>[];

    try {
      final anrSections = document.querySelectorAll('[data-type="anr"], .anr-section, table[data-anr]');

      for (final section in anrSections) {
        final rows = section.querySelectorAll('tr, .anr-item, [data-anr-item]');
        for (final row in rows) {
          final anr = _parseAnrRow(row);
          if (anr != null) {
            anrs.add(anr);
          }
        }
      }

      if (anrs.isEmpty) {
        anrs.addAll(_parseGenericTables(document, 'anr'));
      }

      return anrs.take(10).toList();
    } catch (e) {
      return [];
    }
  }

  /// 解析单个 ANR 行
  Map<String, dynamic>? _parseAnrRow(Element row) {
    try {
      final cells = row.querySelectorAll('td, .cell, [data-cell]');
      if (cells.length < 2) return null;

      final name = cells.isNotEmpty ? cells[0].text.trim() : null;
      final countStr = cells.length > 1 ? cells[1].text.trim().replaceAll(RegExp(r'[^\d]'), '') : '0';
      final devicesStr = cells.length > 2 ? cells[2].text.trim().replaceAll(RegExp(r'[^\d]'), '') : '0';

      if (name == null || name.isEmpty) return null;

      return {
        'name': name,
        'count': int.tryParse(countStr) ?? 0,
        'devices': int.tryParse(devicesStr) ?? 0,
      };
    } catch (e) {
      return null;
    }
  }

  /// 通用表格解析（后备方案）
  List<Map<String, dynamic>> _parseGenericTables(Document document, String type) {
    final items = <Map<String, dynamic>>[];

    try {
      final tables = document.querySelectorAll('table');
      for (final table in tables) {
        final rows = table.querySelectorAll('tbody tr');
        for (final row in rows) {
          final cells = row.querySelectorAll('td');
          if (cells.length >= 2) {
            final item = {
              'name': cells[0].text.trim(),
              'count': int.tryParse(cells.length > 1
                ? cells[1].text.replaceAll(RegExp(r'[^\d]'), '')
                : '0') ?? 0,
              'devices': int.tryParse(cells.length > 2
                ? cells[2].text.replaceAll(RegExp(r'[^\d]'), '')
                : '0') ?? 0,
            };
            if ((item['name'] as String).isNotEmpty) {
              items.add(item);
            }
          }
        }
      }
    } catch (e) {
      // Fallback: 不返回任何内容
    }

    return items.take(10).toList();
  }
}
