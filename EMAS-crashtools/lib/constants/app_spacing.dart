/// Material 3 间距系统
/// 8 级标准间距，用于内边距、外边距、组件间距
/// 遵循 Material Design 3 规范，提升代码复用性和视觉一致性

import 'package:flutter/material.dart';

// 极微小间距（精细调整）
const double kSpacing2 = 2;

// 极小间距（元素微调）
const double kSpacing4 = 4;

// 超紧凑间距（微调间距）
const double kSpacing6 = 6;

// 紧凑间距（组件内部）
const double kSpacing8 = 8;

// 微型间距（图标与文字间隔）
const double kSpacing10 = 10;

// 通用间距（组件间距）
const double kSpacing12 = 12;

// 小大间距
const double kSpacing14 = 14;

// 主要间距（卡片、容器内边距）
const double kSpacing16 = 16;

// 大间距（模块分隔）
const double kSpacing20 = 20;

// 微调大间距
const double kSpacing18 = 18;

// 特大间距（导航、侧边栏）
const double kSpacing26 = 26;

// 页面间距（大模块分隔）
const double kSpacing24 = 24;

// 大留白（区块分隔）
const double kSpacing28 = 28;

// 超大留白（页面外边距、主要分区）
const double kSpacing32 = 32;

// 常用组合（EdgeInsets）
class AppSpacingInsets {
  // 极小内边距
  static const EdgeInsets xs = EdgeInsets.all(kSpacing4);

  // 小内边距（紧凑组件）
  static const EdgeInsets sm = EdgeInsets.all(kSpacing8);

  // 基础内边距（标准组件）
  static const EdgeInsets md = EdgeInsets.all(kSpacing12);

  // 主要内边距（卡片、容器）
  static const EdgeInsets lg = EdgeInsets.all(kSpacing16);

  // 大内边距
  static const EdgeInsets xl = EdgeInsets.all(kSpacing20);

  // 超大内边距
  static const EdgeInsets xxl = EdgeInsets.all(kSpacing24);

  // 水平间距组合
  static const EdgeInsets horizontalMd = EdgeInsets.symmetric(horizontal: kSpacing16);
  static const EdgeInsets horizontalSm = EdgeInsets.symmetric(horizontal: kSpacing12);
  static const EdgeInsets horizontalLg = EdgeInsets.symmetric(horizontal: kSpacing20);

  // 竖直间距组合
  static const EdgeInsets verticalMd = EdgeInsets.symmetric(vertical: kSpacing16);
  static const EdgeInsets verticalSm = EdgeInsets.symmetric(vertical: kSpacing12);
  static const EdgeInsets verticalLg = EdgeInsets.symmetric(vertical: kSpacing20);

  // 对称组合（常见的水平紧凑、竖直宽松）
  static const EdgeInsets compactHorizontal = EdgeInsets.symmetric(
    horizontal: kSpacing16,
    vertical: kSpacing12,
  );

  static const EdgeInsets compactVertical = EdgeInsets.symmetric(
    horizontal: kSpacing12,
    vertical: kSpacing16,
  );

  // 页面外边距
  static const EdgeInsets pageMargin = EdgeInsets.all(kSpacing24);

  // 页面内边距
  static const EdgeInsets pagePadding = EdgeInsets.all(kSpacing24);
}

/// 快速访问助手
extension SpacingExtension on BuildContext {
  /// 获取标准间距值
  double spacing(int level) => const [
    kSpacing4,
    kSpacing8,
    kSpacing12,
    kSpacing16,
    kSpacing20,
    kSpacing24,
    kSpacing28,
    kSpacing32,
  ][level.clamp(0, 7)];
}
