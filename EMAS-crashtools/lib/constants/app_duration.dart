/// Material 3 动画时长系统
/// 遵循 Material Design 3 动效规范

import 'package:flutter/material.dart';

// 快速动画（100ms）
const Duration kDurationFast = Duration(milliseconds: 100);

// 标准动画（200ms）
const Duration kDurationStandard = Duration(milliseconds: 200);

// 缓慢动画（300ms）
const Duration kDurationSlow = Duration(milliseconds: 300);

// 超慢动画（500ms）
const Duration kDurationVerySlow = Duration(milliseconds: 500);

/// 动画时长预设
class AppDuration {
  AppDuration._();

  static const Duration superFast = Duration(milliseconds: 50);
  static const Duration fast = kDurationFast;
  static const Duration standard = kDurationStandard;
  static const Duration slow = kDurationSlow;
  static const Duration verySlow = kDurationVerySlow;
  static const Duration extraslow = Duration(milliseconds: 800);

  // 按钮
  static const Duration buttonClick = kDurationFast;
  static const Duration buttonHover = Duration(milliseconds: 75);

  // 输入框
  static const Duration inputFocus = kDurationFast;

  // 卡片
  static const Duration cardTransition = kDurationStandard;

  // 对话框
  static const Duration dialogAppear = kDurationStandard;
  static const Duration dialogOverlay = kDurationStandard;

  // 页面
  static const Duration pageTransition = kDurationStandard;

  // 列表
  static const Duration listItemLoad = kDurationSlow;
  static const Duration listItemDelete = kDurationStandard;

  // 标签
  static const Duration chipSwitch = kDurationFast;

  // 导航
  static const Duration navigationSwitch = kDurationStandard;

  // 浮按钮
  static const Duration fabAppear = kDurationStandard;

  // 菜单
  static const Duration menuAppear = Duration(milliseconds: 120);
  static const Duration menuItemTransition = Duration(milliseconds: 100);

  // SnackBar
  static const Duration snackBarTransition = kDurationStandard;

  // 抽屉
  static const Duration bottomSheetSlide = kDurationStandard;

  // 加载动画
  static const Duration skeletonShimmer = Duration(milliseconds: 1500);
  static const Duration loadingRotate = Duration(milliseconds: 1000);
  static const Duration pulse = Duration(milliseconds: 800);
}

/// Material 3 动画曲线
class AppCurves {
  AppCurves._();

  static const Curve easeOut = Curves.easeOut;
  static const Curve easeInOut = Curves.easeInOut;
  static const Curve linear = Curves.linear;
  static const Curve fastOutSlowIn = Curves.fastOutSlowIn;
  static const Curve elasticOut = Curves.elasticOut;
  static const Curve elasticInOut = Curves.elasticInOut;

  // 标准曲线
  static const Curve entrance = Curves.easeOut;
  static const Curve exit = Curves.easeIn;
  static const Curve standard = Curves.easeInOut;
  static const Curve quickFeedback = Curves.easeOut;
  static const Curve emphasis = Curves.fastOutSlowIn;
}

/// 动画延迟
class AnimationDelay {
  AnimationDelay._();

  static const Duration none = Duration.zero;
  static const Duration xs = Duration(milliseconds: 25);
  static const Duration sm = Duration(milliseconds: 50);
  static const Duration md = Duration(milliseconds: 75);
  static const Duration lg = Duration(milliseconds: 100);
  static const Duration xl = Duration(milliseconds: 150);

  static Duration staggered(int index, {Duration baseDelay = const Duration(milliseconds: 50)}) {
    return Duration(milliseconds: (baseDelay.inMilliseconds * index));
  }
}

/// 动画值预设
class AnimationValues {
  AnimationValues._();

  static const double scaleNormal = 1.0;
  static const double scaleSmall = 0.98;
  static const double scalePressed = 0.96;
  static const double opacityMin = 0.0;
  static const double opacityMax = 1.0;
  static const double offsetSmall = 4.0;
  static const double offsetMedium = 8.0;
  static const double offsetLarge = 12.0;
  static const double rotationNone = 0.0;
  static const double rotationSmall = 90.0;
}
