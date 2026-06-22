/// Material 3 设计系统常量导出中心
/// 统一导出所有设计常量，便于全局使用

// 间距系统
export 'app_spacing.dart';

// 圆角系统
export 'app_radius.dart';

// 尺寸系统
export 'app_dimensions.dart';

// 透明度系统
export 'app_opacity.dart';

// 高程系统
export 'app_elevation.dart';

// 动画系统
export 'app_duration.dart';

/// 快速访问所有常量的便利类
/// 统一导出 Material 3 设计系统所有常量
///
/// 使用示例：
/// ```dart
/// import 'package:crash_emas_tool/constants/app_constants.dart';
///
/// // 使用间距
/// padding: EdgeInsets.all(kSpacing16),
///
/// // 使用圆角
/// borderRadius: AppBorderRadius.lg,
///
/// // 使用尺寸
/// width: IconDimensions.medium,
///
/// // 使用透明度
/// color: cs.primary.withCustomOpacity(kOpacitySubtle),
///
/// // 使用高程
/// boxShadow: AppShadow.card(),
///
/// // 使用动画
/// duration: AppDuration.standard,
/// ```
class AppConstants {
  // 禁用默认构造函数
  AppConstants._();

  /// 间距快速参考
  static const Map<String, double> spacingsReference = {
    'xs': 4,
    'sm': 8,
    'md': 12,
    'lg': 16,
    'xl': 20,
    'xxl': 24,
    'huge': 28,
    'mega': 32,
  };

  /// 圆角快速参考
  static const Map<String, double> radiusReference = {
    'xs': 8,
    'sm': 10,
    'md': 12,
    'lg': 14,
    'xl': 16,
    'xxl': 20,
    'dialog': 28,
  };

  /// 高程快速参考
  static const Map<String, double> elevationReference = {
    'none': 0,
    'level1': 1,
    'level2': 3,
    'level3': 6,
    'level4': 8,
    'level5': 12,
  };

  /// 快速参考指南
  static const String guide = '''
Material 3 Design System Constants Guide
========================================

SPACING (间距系统)
├── kSpacing4 = 4dp      (极小)
├── kSpacing8 = 8dp      (紧凑)
├── kSpacing12 = 12dp    (标准)
├── kSpacing16 = 16dp    (主要)
├── kSpacing20 = 20dp    (大)
├── kSpacing24 = 24dp    (页面)
├── kSpacing28 = 28dp    (大块)
└── kSpacing32 = 32dp    (超大)

RADIUS (圆角系统)
├── kRadius8 = 8dp       (细节)
├── kRadius10 = 10dp     (小)
├── kRadius12 = 12dp     (按钮)
├── kRadius14 = 14dp     (标准卡片)
├── kRadius16 = 16dp     (主卡片)
├── kRadius20 = 20dp     (大容器)
└── kRadius28 = 28dp     (对话框)

OPACITY (透明度系统)
├── kOpacityDisabled = 0.38     (禁用)
├── kOpacitySubtle = 0.08       (极淡)
├── kOpacityLight = 0.12        (轻微)
├── kOpacityMedium = 0.38       (中等)
├── kOpacitySemiTransparent = 0.45 (半透)
└── kOpacityHeavy = 0.65        (重)

ELEVATION (高程系统)
├── kElevationNone = 0          (平面)
├── kElevationLevel1 = 1        (极微)
├── kElevationLevel2 = 3        (轻)
├── kElevationLevel3 = 6        (标准)
├── kElevationLevel4 = 8        (强)
└── kElevationLevel5 = 12       (最强)

DURATION (动画时长)
├── kDurationFast = 100ms       (快速)
├── kDurationStandard = 200ms   (标准)
└── kDurationSlow = 300ms       (缓慢)

USAGE EXAMPLES (使用示例)
=======================

// 卡片样式
Card(
  margin: EdgeInsets.all(kSpacing16),
  shape: RoundedRectangleBorder(borderRadius: AppBorderRadius.lg),
  child: Padding(
    padding: AppSpacingInsets.md,
    child: // 内容
  ),
)

// 按钮样式
FilledButton(
  onPressed: () {},
  style: ButtonStyle(
    padding: WidgetStateProperty.all(
      EdgeInsets.symmetric(horizontal: kSpacing20, vertical: kSpacing12),
    ),
  ),
  child: const Text('按钮'),
)

// 颜色透明度
Container(
  color: cs.primary.withCustomOpacity(kOpacitySubtle),
  child: // 内容
)

// 阴影效果
Container(
  decoration: BoxDecoration(
    boxShadow: AppShadow.card(),
    borderRadius: AppBorderRadius.lg,
  ),
)

// 动画过渡
AnimatedContainer(
  duration: AppDuration.standard,
  curve: AppCurves.easeOut,
  padding: EdgeInsets.all(kSpacing16),
)
''';
}
