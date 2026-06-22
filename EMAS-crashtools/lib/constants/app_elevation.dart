/// Material 3 高程系统
/// 遵循 Material Design 3 标准高程规范

import 'package:flutter/material.dart';

const double kElevationNone = 0;
const double kElevationLevel1 = 1;
const double kElevationLevel2 = 3;
const double kElevationLevel3 = 6;
const double kElevationLevel4 = 8;
const double kElevationLevel5 = 12;

/// 高程预设
class AppElevation {
  AppElevation._();

  static const double none = kElevationNone;
  static const double veryLight = kElevationLevel1;
  static const double light = kElevationLevel2;
  static const double standard = kElevationLevel3;
  static const double strong = kElevationLevel4;
  static const double strongest = kElevationLevel5;

  // 组件特定高程
  static const double appBar = kElevationNone;
  static const double card = kElevationLevel3;
  static const double fab = kElevationLevel4;
  static const double navigationBar = kElevationLevel2;
  static const double dialog = kElevationLevel4;
  static const double bottomSheet = kElevationLevel3;
  static const double snackBar = kElevationLevel3;
  static const double popup = kElevationLevel4;
  static const double tooltip = kElevationLevel5;
  static const double drawer = kElevationLevel4;
  static const double searchBar = kElevationLevel1;
  static const double listItem = kElevationNone;
  static const double listItemHover = kElevationLevel1;
  static const double button = kElevationNone;
  static const double buttonPressed = kElevationLevel2;
}

/// Material 3 标准阴影生成器
class AppShadow {
  AppShadow._();

  static List<BoxShadow> get(double elevation, {Color? color}) {
    final shadowColor = color ?? Colors.black;

    switch (elevation) {
      case 0:
        return const [];
      case 1:
        return [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.05),
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
        ];
      case 3:
        return [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.12),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.08),
            blurRadius: 2,
            offset: const Offset(0, 2),
          ),
        ];
      case 6:
        return [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.12),
            blurRadius: 3,
            offset: const Offset(0, 4),
          ),
        ];
      case 8:
        return [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 8),
          ),
        ];
      case 12:
        return [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 12),
          ),
        ];
      default:
        return [];
    }
  }

  static List<BoxShadow> card({Color? color}) {
    final shadowColor = color ?? Colors.black;
    return [
      BoxShadow(
        color: shadowColor.withValues(alpha: 0.08),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
      BoxShadow(
        color: shadowColor.withValues(alpha: 0.06),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ];
  }

  static List<BoxShadow> buttonPressed({Color? color}) {
    final shadowColor = color ?? Colors.black;
    return [
      BoxShadow(
        color: shadowColor.withValues(alpha: 0.05),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ];
  }

  static List<BoxShadow> dialog({Color? color}) {
    final shadowColor = color ?? Colors.black;
    return [
      BoxShadow(
        color: shadowColor.withValues(alpha: 0.20),
        blurRadius: 12,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: shadowColor.withValues(alpha: 0.15),
        blurRadius: 8,
        offset: const Offset(0, 12),
      ),
    ];
  }

  static List<BoxShadow> fab({Color? color}) {
    final shadowColor = color ?? Colors.black;
    return [
      BoxShadow(
        color: shadowColor.withValues(alpha: 0.15),
        blurRadius: 8,
        offset: const Offset(0, 4),
      ),
      BoxShadow(
        color: shadowColor.withValues(alpha: 0.12),
        blurRadius: 4,
        offset: const Offset(0, 8),
      ),
    ];
  }

  static List<BoxShadow> hover({Color? color}) {
    final shadowColor = color ?? Colors.black;
    return [
      BoxShadow(
        color: shadowColor.withValues(alpha: 0.08),
        blurRadius: 2,
        offset: const Offset(0, 2),
      ),
    ];
  }
}
