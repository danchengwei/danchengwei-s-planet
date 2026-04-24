import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 应用级视觉：现代、克制配色 + Noto Sans SC（中英文可读性好）。
abstract final class AppTheme {
  /// 默认主题种子（无壁纸或与壁纸取色失败时）。
  static const Color defaultSeed = Color(0xFF0F766E);

  /// [seedColor] 通常来自当前壁纸主色（已做偏浅处理）；整体仍为浅色 Material3。
  static ThemeData light({Color? seedColor}) {
    final seed = seedColor ?? defaultSeed;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: Color.lerp(const Color(0xFFFCFCFD), seed, 0.04)!,
      surfaceContainerLow: Color.lerp(const Color(0xFFF7F8FA), seed, 0.065)!,
      surfaceContainerHigh: Color.lerp(const Color(0xFFEEF0F3), seed, 0.085)!,
      surfaceContainerHighest: Color.lerp(const Color(0xFFE2E5EA), seed, 0.095)!,
    );

    final baseText = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
    ).textTheme;

    final textTheme = GoogleFonts.notoSansScTextTheme(baseText).apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: colorScheme.surface,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surface,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        indicatorColor: colorScheme.primaryContainer.withValues(alpha: 0.65),
        elevation: 0,
        labelType: NavigationRailLabelType.all,
        minWidth: 88,
        minExtendedWidth: 200,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.45)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        floatingLabelStyle: textTheme.labelLarge?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        labelStyle: textTheme.labelLarge!,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: colorScheme.onInverseSurface),
      ),
      dialogTheme: DialogThemeData(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        backgroundColor: colorScheme.surfaceContainerHigh,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        iconColor: colorScheme.onSurfaceVariant,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }
}
