/// Material 3 圆角系统
/// 遵循 Material Design 3 标准圆角尺度
/// 用于卡片、按钮、输入框、对话框等组件

import 'package:flutter/material.dart';

// 微细圆角（代码块、嵌套细节）
const double kRadius8 = 8;

// 小圆角（Chip、标签、小组件）
const double kRadius10 = 10;

// 按钮/输入框圆角
const double kRadius12 = 12;

// 标准卡片圆角（按钮、导航项）
const double kRadius14 = 14;

// 主卡片圆角（浮层、模块容器）
const double kRadius16 = 16;

// 大容器圆角
const double kRadius20 = 20;

// 对话框圆角（Material 3 标准）
const double kRadius28 = 28;

// 预定义的 BorderRadius 对象（提高复用性）
class AppBorderRadius {
  // 微细
  static const BorderRadius xs = BorderRadius.all(Radius.circular(kRadius8));

  // 小
  static const BorderRadius sm = BorderRadius.all(Radius.circular(kRadius10));

  // 中小（按钮、输入框）
  static const BorderRadius md = BorderRadius.all(Radius.circular(kRadius12));

  // 中（导航、卡片）
  static const BorderRadius lg = BorderRadius.all(Radius.circular(kRadius14));

  // 大（主卡片、浮层）
  static const BorderRadius xl = BorderRadius.all(Radius.circular(kRadius16));

  // 超大（容器）
  static const BorderRadius xxl = BorderRadius.all(Radius.circular(kRadius20));

  // 对话框（Material 3 标准）
  static const BorderRadius dialog = BorderRadius.all(Radius.circular(kRadius28));

  // 仅顶部圆角
  static const BorderRadius topOnly = BorderRadius.only(
    topLeft: Radius.circular(kRadius16),
    topRight: Radius.circular(kRadius16),
  );

  // 仅底部圆角
  static const BorderRadius bottomOnly = BorderRadius.only(
    bottomLeft: Radius.circular(kRadius16),
    bottomRight: Radius.circular(kRadius16),
  );

  // 底部抽屉样式（顶部圆角）
  static const BorderRadius bottomSheetTop = BorderRadius.only(
    topLeft: Radius.circular(kRadius28),
    topRight: Radius.circular(kRadius28),
  );
}

/// 快速创建圆角函数
BorderRadius kRadius(double radius) => BorderRadius.all(Radius.circular(radius));

/// 创建圆角矩形边框
RoundedRectangleBorder kRoundedRectangleBorder({
  required double radius,
  Color? borderColor,
  double borderWidth = 1.0,
}) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
      side: borderColor != null
          ? BorderSide(color: borderColor, width: borderWidth)
          : BorderSide.none,
    );
