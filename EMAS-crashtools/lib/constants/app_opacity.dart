/// Material 3 透明度系统
/// 遵循 Material Design 3 不透明度规范

import 'package:flutter/material.dart';

const double kOpacityDisabled = 0.38;
const double kOpacityVerySubtle = 0.05;
const double kOpacityVeryLight = 0.08;
const double kOpacitySubtle = 0.08;
const double kOpacityLight = 0.12;
const double kOpacityMedium = 0.38;
const double kOpacitySemiTransparent = 0.45;
const double kOpacityStrong = 0.88;
const double kOpacityHeavy = 0.65;
const double kOpacityEmphasis = 1.0;

/// 常用透明度组合
class AppOpacity {
  AppOpacity._();

  static const double disabled = kOpacityDisabled;
  static const double verySubtle = kOpacityVerySubtle;
  static const double subtle = kOpacitySubtle;
  static const double light = kOpacityLight;
  static const double medium = kOpacityMedium;
  static const double semiTransparent = kOpacitySemiTransparent;
  static const double heavy = kOpacityHeavy;
  static const double emphasis = kOpacityEmphasis;

  // 文本透明度
  static const double textPrimary = 1.0;
  static const double textSecondary = 0.70;
  static const double textDisabled = 0.38;
  static const double textHint = 0.54;

  // 背景颜色透明度
  static const double bgSolid = 1.0;
  static const double bgVeryLight = 0.05;
  static const double bgLight = 0.08;
  static const double bgMedium = 0.12;
  static const double bgDark = 0.25;
  static const double bgVeryDark = 0.45;

  // 边框和分割线
  static const double borderHairline = 0.25;
  static const double borderLight = 0.38;
  static const double borderStandard = 0.45;
  static const double borderEmphasis = 0.65;
  static const double borderStrongest = 1.0;

  // 图标透明度
  static const double iconPrimary = 1.0;
  static const double iconSecondary = 0.70;
  static const double iconDisabled = 0.38;
  static const double iconHover = 0.08;

  // 覆盖层
  static const double overlaySubtle = 0.05;
  static const double overlayLight = 0.12;
  static const double overlayStandard = 0.32;
  static const double overlayDeep = 0.54;
  static const double overlayDeepest = 0.65;
}

/// 快速应用透明度的扩展方法
extension OpacityExtension on Color {
  Color withDisabledOpacity() => withValues(alpha: kOpacityDisabled);
  Color withSubtleOpacity() => withValues(alpha: kOpacitySubtle);
  Color withMediumOpacity() => withValues(alpha: kOpacityMedium);
  Color withSemiTransparentOpacity() => withValues(alpha: kOpacitySemiTransparent);
  Color withCustomOpacity(double opacity) => withValues(alpha: opacity.clamp(0, 1));
  Color asSecondaryText() => withValues(alpha: AppOpacity.textSecondary);
  Color asDivider() => withValues(alpha: AppOpacity.borderLight);
  Color asDisabledBg() => withValues(alpha: AppOpacity.bgLight);
  Color asHoverBg() => withValues(alpha: AppOpacity.bgVeryLight);
}
