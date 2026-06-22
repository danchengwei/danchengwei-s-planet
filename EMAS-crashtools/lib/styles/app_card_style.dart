/// Material 3 卡片样式系统
/// 提供标准卡片样式和装饰

import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// 卡片样式快速生成器
class AppCardStyle {
  AppCardStyle._();

  /// 标准卡片 BoxDecoration
  static BoxDecoration standard(ColorScheme cs) {
    return BoxDecoration(
      color: cs.surfaceContainer.withValues(alpha: 0.5),
      borderRadius: AppBorderRadius.lg,
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: kOpacitySubtle),
        width: 1,
      ),
      boxShadow: AppShadow.card(),
    );
  }

  /// 浮起卡片（更强阴影）
  static BoxDecoration elevated(ColorScheme cs) {
    return BoxDecoration(
      color: cs.surfaceContainer,
      borderRadius: AppBorderRadius.lg,
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: kOpacityLight),
        width: 1,
      ),
      boxShadow: AppShadow.get(6),
    );
  }

  /// 极简卡片（无背景色变化）
  static BoxDecoration minimal(ColorScheme cs) {
    return BoxDecoration(
      color: cs.surface,
      borderRadius: AppBorderRadius.lg,
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: kOpacitySubtle),
        width: 1,
      ),
    );
  }

  /// 填充卡片（强调背景）
  static BoxDecoration filled(ColorScheme cs) {
    return BoxDecoration(
      color: cs.surfaceContainerLow.withValues(alpha: 0.8),
      borderRadius: AppBorderRadius.lg,
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: kOpacityLight),
        width: 1,
      ),
      boxShadow: AppShadow.card(),
    );
  }

  /// 悬停卡片（交互反馈）
  static BoxDecoration hover(ColorScheme cs) {
    return BoxDecoration(
      color: cs.surfaceContainer.withValues(alpha: 0.7),
      borderRadius: AppBorderRadius.lg,
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: kOpacityLight),
        width: 1,
      ),
      boxShadow: AppShadow.hover(),
    );
  }

  /// 强调卡片（主色系）
  static BoxDecoration accent(ColorScheme cs) {
    return BoxDecoration(
      color: cs.primaryContainer.withValues(alpha: 0.4),
      borderRadius: AppBorderRadius.lg,
      border: Border.all(
        color: cs.primary.withValues(alpha: kOpacityLight),
        width: 1,
      ),
      boxShadow: AppShadow.card(),
    );
  }

  /// 错误卡片（错误提示）
  static BoxDecoration error(ColorScheme cs) {
    return BoxDecoration(
      color: cs.errorContainer.withValues(alpha: 0.4),
      borderRadius: AppBorderRadius.lg,
      border: Border.all(
        color: cs.error.withValues(alpha: kOpacityLight),
        width: 1,
      ),
      boxShadow: AppShadow.card(),
    );
  }

  /// 成功卡片
  static BoxDecoration success(ColorScheme cs) {
    return BoxDecoration(
      color: cs.tertiaryContainer.withValues(alpha: 0.4),
      borderRadius: AppBorderRadius.lg,
      border: Border.all(
        color: cs.tertiary.withValues(alpha: kOpacityLight),
        width: 1,
      ),
      boxShadow: AppShadow.card(),
    );
  }
}

/// 标准卡片 Widget 包装器
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.style = AppCardStyleEnum.standard,
    this.padding = const EdgeInsets.all(kSpacing16),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.borderRadius = kRadius16,
  });

  final Widget child;
  final AppCardStyleEnum style;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    BoxDecoration decoration = switch (style) {
      AppCardStyleEnum.standard => AppCardStyle.standard(cs),
      AppCardStyleEnum.elevated => AppCardStyle.elevated(cs),
      AppCardStyleEnum.minimal => AppCardStyle.minimal(cs),
      AppCardStyleEnum.filled => AppCardStyle.filled(cs),
      AppCardStyleEnum.hover => AppCardStyle.hover(cs),
      AppCardStyleEnum.accent => AppCardStyle.accent(cs),
      AppCardStyleEnum.error => AppCardStyle.error(cs),
      AppCardStyleEnum.success => AppCardStyle.success(cs),
    };

    Widget content = Container(
      margin: margin,
      decoration: decoration,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );

    if (onTap != null) {
      content = GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: content,
        ),
      );
    }

    return content;
  }
}

/// 卡片样式枚举
enum AppCardStyleEnum {
  standard,  // 标准卡片
  elevated,  // 浮起卡片
  minimal,   // 极简卡片
  filled,    // 填充卡片
  hover,     // 悬停卡片
  accent,    // 强调卡片
  error,     // 错误卡片
  success,   // 成功卡片
}

/// 卡片内容分割线
class CardDivider extends StatelessWidget {
  const CardDivider({
    super.key,
    this.height = 1,
    this.margin = const EdgeInsets.symmetric(vertical: kSpacing12),
  });

  final double height;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      height: height,
      color: cs.outlineVariant.withValues(alpha: kOpacitySubtle),
    );
  }
}

/// 卡片标题 + 内容快速组件
class CardSection extends StatelessWidget {
  const CardSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.showDivider = true,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: kSpacing8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        if (showDivider)
          CardDivider(
            margin: const EdgeInsets.only(bottom: kSpacing12),
          ),
        child,
      ],
    );
  }
}
