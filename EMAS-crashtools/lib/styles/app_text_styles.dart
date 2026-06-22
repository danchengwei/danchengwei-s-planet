/// Material 3 文本样式系统
/// 预定义 14 种标准文本样式组合
/// 遵循 Material Design 3 排版规范

import 'package:flutter/material.dart';

/// 文本样式扩展方法
extension TextStyleExtensions on TextTheme {
  /// 显示层级文本样式
  TextStyle get displayLargeSubtle => displayLarge?.copyWith(
        color: Color(0xFF1C1B1F).withValues(alpha: 0.87),
        height: 1.2,
      ) ?? const TextStyle();

  /// 标题层级 - 主标题
  TextStyle get headlineLargeEmphasis => headlineLarge?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.3,
      ) ?? const TextStyle();

  /// 标题层级 - 副标题
  TextStyle get headlineMediumSecondary => headlineMedium?.copyWith(
        fontWeight: FontWeight.w500,
        height: 1.3,
      ) ?? const TextStyle();

  /// 标题层级 - 小标题
  TextStyle get headlineSmallMuted => headlineSmall?.copyWith(
        fontWeight: FontWeight.w500,
        color: Color(0xFF1C1B1F).withValues(alpha: 0.60),
        height: 1.3,
      ) ?? const TextStyle();

  /// 标签层级 - 主要标签
  TextStyle get labelLargeBold => labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ) ?? const TextStyle();

  /// 标签层级 - 次要标签
  TextStyle get labelMediumRegular => labelMedium?.copyWith(
        fontWeight: FontWeight.w400,
        letterSpacing: 0.05,
      ) ?? const TextStyle();

  /// 标签层级 - 辅助标签
  TextStyle get labelSmallMuted => labelSmall?.copyWith(
        color: Color(0xFF1C1B1F).withValues(alpha: 0.60),
        fontWeight: FontWeight.w400,
      ) ?? const TextStyle();

  /// 正文层级 - 主文本
  TextStyle get bodyLargeRegular => bodyLarge?.copyWith(
        fontWeight: FontWeight.w400,
        height: 1.5,
      ) ?? const TextStyle();

  /// 正文层级 - 常规文本
  TextStyle get bodyMediumRegular => bodyMedium?.copyWith(
        fontWeight: FontWeight.w400,
        height: 1.5,
      ) ?? const TextStyle();

  /// 正文层级 - 副文本（灰化）
  TextStyle get bodySmallMuted => bodySmall?.copyWith(
        color: Color(0xFF1C1B1F).withValues(alpha: 0.60),
        fontWeight: FontWeight.w400,
        height: 1.5,
      ) ?? const TextStyle();

  /// 卡片标题 - 大
  TextStyle get titleLargeEmphasis => titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.4,
      ) ?? const TextStyle();

  /// 卡片标题 - 中
  TextStyle get titleMediumRegular => titleMedium?.copyWith(
        fontWeight: FontWeight.w500,
        height: 1.4,
      ) ?? const TextStyle();

  /// 卡片标题 - 小
  TextStyle get titleSmallMuted => titleSmall?.copyWith(
        color: Color(0xFF1C1B1F).withValues(alpha: 0.60),
        fontWeight: FontWeight.w500,
        height: 1.4,
      ) ?? const TextStyle();

  /// 代码文本（monospace）
  TextStyle get codeStyle => bodySmall?.copyWith(
        fontFamily: 'Courier New',
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: Color(0xFF1C1B1F).withValues(alpha: 0.87),
      ) ?? const TextStyle();
}

/// 快速获取文本样式的便利类
class AppTextStyle {
  AppTextStyle._();

  /// 创建所有文本样式快照
  static TextTheme createTheme(TextTheme base) {
    return base;
  }

  /// 应用文本样式到 Text widget 的快捷方式示例
  static const Map<String, String> styleNames = {
    'displayLarge': '显示大',
    'displayMedium': '显示中',
    'displaySmall': '显示小',
    'headlineLarge': '标题大',
    'headlineMedium': '标题中',
    'headlineSmall': '标题小',
    'labelLarge': '标签大',
    'labelMedium': '标签中',
    'labelSmall': '标签小',
    'bodyLarge': '正文大',
    'bodyMedium': '正文中',
    'bodySmall': '正文小',
    'titleLarge': '标题大',
    'titleMedium': '标题中',
    'titleSmall': '标题小',
  };
}

/// 颜色应用于文本的便利类
class TextColorVariant {
  TextColorVariant._();

  /// 主文本颜色
  static Color primary(ColorScheme cs) => cs.onSurface;

  /// 次级文本颜色（灰化 70%）
  static Color secondary(ColorScheme cs) => cs.onSurfaceVariant;

  /// 禁用文本颜色
  static Color disabled(ColorScheme cs) => cs.onSurface.withValues(alpha: 0.38);

  /// 提示文本颜色
  static Color hint(ColorScheme cs) => cs.onSurfaceVariant.withValues(alpha: 0.54);

  /// 强调文本颜色
  static Color emphasis(ColorScheme cs) => cs.primary;

  /// 错误文本颜色
  static Color error(ColorScheme cs) => cs.error;

  /// 成功文本颜色
  static Color success(ColorScheme cs) => cs.tertiary;

  /// 警告文本颜色
  static Color warning(ColorScheme cs) => cs.secondary;
}

/// 文本样式使用示例
class TextStyleExamples {
  static const String usage = '''
使用方法：

1. 直接使用 TextTheme（推荐）
   Text(
     'Hello World',
     style: Theme.of(context).textTheme.headlineLarge,
   )

2. 使用扩展方法
   Text(
     'Hello World',
     style: Theme.of(context).textTheme.headlineLargeEmphasis,
   )

3. 结合颜色变体
   Text(
     'Secondary Text',
     style: Theme.of(context).textTheme.bodyMedium?.copyWith(
       color: TextColorVariant.secondary(Theme.of(context).colorScheme),
     ),
   )

4. 快速创建样式组合
   Text(
     'Custom',
     style: Theme.of(context).textTheme.bodyMedium?.copyWith(
       fontWeight: FontWeight.w600,
       height: 1.5,
       color: Theme.of(context).colorScheme.primary,
     ),
   )
''';
}
