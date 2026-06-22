import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// 从壁纸资源取色并生成偏浅的 Material 主题种子色。
abstract final class WallpaperThemeSeeder {
  /// 无壁纸或解析失败时使用的默认种子（与 [AppTheme.defaultSeed] 一致）。
  static const Color fallbackSeed = Color(0xFF0F766E);

  static Future<Color> seedFromAssetPath(String assetPath) async {
    try {
      final gen = await PaletteGenerator.fromImageProvider(
        ResizeImage(
          AssetImage(assetPath),
          width: 100,
          height: 100,
        ),
        maximumColorCount: 14,
      );
      final swatch = gen.lightVibrantColor ??
          gen.vibrantColor ??
          gen.lightMutedColor ??
          gen.mutedColor ??
          gen.dominantColor;
      if (swatch == null) return fallbackSeed;
      return _softAccent(swatch.color);
    } catch (_) {
      return fallbackSeed;
    }
  }

  /// 与壁纸色相接近但整体偏浅，适合浅色界面大面积使用。
  static Color _softAccent(Color c) {
    final hsl = HSLColor.fromColor(c);
    final l = (0.5 + hsl.lightness * 0.28).clamp(0.42, 0.72);
    final s = (hsl.saturation * 0.48).clamp(0.14, 0.5);
    return hsl.withSaturation(s).withLightness(l).toColor();
  }
}
