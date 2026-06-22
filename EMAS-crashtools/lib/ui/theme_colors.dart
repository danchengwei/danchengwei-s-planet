import 'package:flutter/material.dart';

/// EMAS 应用统一主题色配置
/// 设计方案：低饱和草绿色边框/导航/Tab + 浅灰色页面背景 + 黑白色文字
class ThemeColors {
  // 主色
  static const int _primaryGreenValue = 0xFF7B9E89;
  static const int _lightGrayValue = 0xFFF5F5F5;
  static const int _borderGrayValue = 0xFFE8E8E8;
  static const int _textBlackValue = 0xFF1F1F1F;
  static const int _textGrayValue = 0xFF666666;

  /// 低饱和草绿色 - 用于边框、导航栏、Tab 指示线、按钮
  static const Color primaryGreen = Color(_primaryGreenValue);

  /// 浅灰色 - 页面背景色
  static const Color lightGray = Color(_lightGrayValue);

  /// 边框灰色 - 卡片边框、表格线
  static const Color borderGray = Color(_borderGrayValue);

  /// 黑色文字 - 主标题、标签
  static const Color textBlack = Color(_textBlackValue);

  /// 灰色文字 - 副文本、占位符
  static const Color textGray = Color(_textGrayValue);

  /// 白色
  static const Color white = Color(0xFFFFFFFF);

  /// 获取 AppBar 主题
  static AppBarTheme get appBarTheme {
    return AppBarTheme(
      backgroundColor: white,
      foregroundColor: textBlack,
      elevation: 2,
      shadowColor: Color.fromARGB(13, 0, 0, 0),
      centerTitle: false,
      titleTextStyle: const TextStyle(
        color: textBlack,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// 获取卡片主题
  static CardThemeData get cardTheme {
    return CardThemeData(
      color: white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: borderGray, width: 1),
      ),
      margin: const EdgeInsets.all(0),
    );
  }

  /// 获取 ElevatedButton 主题
  static ElevatedButtonThemeData get elevatedButtonTheme {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryGreen,
        foregroundColor: white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 2,
      ),
    );
  }

  /// 获取文字主题
  static TextTheme get textTheme {
    return TextTheme(
      displayLarge: const TextStyle(
        color: textBlack,
        fontSize: 32,
        fontWeight: FontWeight.bold,
      ),
      displayMedium: const TextStyle(
        color: textBlack,
        fontSize: 28,
        fontWeight: FontWeight.bold,
      ),
      displaySmall: const TextStyle(
        color: textBlack,
        fontSize: 24,
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: const TextStyle(
        color: textBlack,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: const TextStyle(
        color: textBlack,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: const TextStyle(
        color: textBlack,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: const TextStyle(
        color: textBlack,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      titleSmall: const TextStyle(
        color: textGray,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: const TextStyle(
        color: textBlack,
        fontSize: 16,
        height: 1.5,
      ),
      bodyMedium: const TextStyle(
        color: textBlack,
        fontSize: 14,
        height: 1.5,
      ),
      bodySmall: const TextStyle(
        color: textGray,
        fontSize: 12,
        height: 1.5,
      ),
      labelLarge: const TextStyle(
        color: primaryGreen,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: const TextStyle(
        color: textGray,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: const TextStyle(
        color: textGray,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  /// 获取完整 ThemeData
  static ThemeData getThemeData() {
    return ThemeData(
      useMaterial3: true,
      primaryColor: primaryGreen,
      scaffoldBackgroundColor: lightGray,
      appBarTheme: appBarTheme,
      cardTheme: cardTheme,
      elevatedButtonTheme: elevatedButtonTheme,
      textTheme: textTheme,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderGray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderGray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryGreen, width: 2),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorColor: primaryGreen,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: primaryGreen,
        unselectedLabelColor: textGray,
      ),
    );
  }
}
