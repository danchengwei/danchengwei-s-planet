/// Material 3 组件装饰库
/// 可复用的装饰效果和样式组件

import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// 快速生成按钮样式
class AppButtonStyle {
  AppButtonStyle._();

  /// 填充按钮样式
  static ButtonStyle filled(ColorScheme cs) {
    return FilledButton.styleFrom(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      padding: const EdgeInsets.symmetric(horizontal: kSpacing20, vertical: kSpacing12),
      shape: RoundedRectangleBorder(borderRadius: AppBorderRadius.md),
      elevation: 0,
    );
  }

  /// 描边按钮样式
  static ButtonStyle outlined(ColorScheme cs) {
    return OutlinedButton.styleFrom(
      foregroundColor: cs.primary,
      padding: const EdgeInsets.symmetric(horizontal: kSpacing20, vertical: kSpacing12),
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.md,
        side: BorderSide(
          color: cs.outline.withValues(alpha: kOpacitySubtle),
          width: 1,
        ),
      ),
      side: BorderSide(
        color: cs.outline.withValues(alpha: kOpacitySubtle),
        width: 1,
      ),
    );
  }

  /// 文字按钮样式
  static ButtonStyle text(ColorScheme cs) {
    return TextButton.styleFrom(
      foregroundColor: cs.primary,
      padding: const EdgeInsets.symmetric(horizontal: kSpacing12, vertical: kSpacing8),
      shape: RoundedRectangleBorder(borderRadius: AppBorderRadius.md),
    );
  }
}

/// 快速生成输入框装饰
class AppInputDecoration {
  AppInputDecoration._();

  /// 标准输入框
  static InputDecoration standard(
    BuildContext context, {
    required String label,
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: cs.surfaceContainer.withValues(alpha: 0.3),
      border: OutlineInputBorder(
        borderRadius: AppBorderRadius.md,
        borderSide: BorderSide(
          color: cs.outline.withValues(alpha: kOpacitySubtle),
          width: 1,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppBorderRadius.md,
        borderSide: BorderSide(
          color: cs.outline.withValues(alpha: kOpacitySubtle),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppBorderRadius.md,
        borderSide: BorderSide(
          color: cs.primary,
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: kSpacing16, vertical: kSpacing14),
    );
  }

  /// 紧凑输入框
  static InputDecoration compact(
    BuildContext context, {
    required String label,
    String? hint,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: cs.surfaceContainer.withValues(alpha: 0.2),
      border: OutlineInputBorder(
        borderRadius: AppBorderRadius.sm,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppBorderRadius.sm,
        borderSide: BorderSide(
          color: cs.outline.withValues(alpha: kOpacityLight),
          width: 1,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: kSpacing12, vertical: kSpacing8),
    );
  }
}

/// 分割线快速生成
class AppDividers {
  AppDividers._();

  /// 轻微分割线
  static Widget light(ColorScheme cs) {
    return Divider(
      height: 1,
      thickness: 1,
      color: cs.outlineVariant.withValues(alpha: kOpacitySubtle),
    );
  }

  /// 标准分割线
  static Widget standard(ColorScheme cs) {
    return Divider(
      height: 1,
      thickness: 1,
      color: cs.outline.withValues(alpha: kOpacityLight),
    );
  }

  /// 强调分割线
  static Widget strong(ColorScheme cs) {
    return Divider(
      height: 1,
      thickness: 1,
      color: cs.outline.withValues(alpha: kOpacityMedium),
    );
  }

  /// 竖直分割线
  static Widget vertical(ColorScheme cs, {double height = 32}) {
    return SizedBox(
      height: height,
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: cs.outlineVariant.withValues(alpha: kOpacitySubtle),
      ),
    );
  }
}

/// 悬停效果快速应用
class AppHoverEffect extends StatefulWidget {
  const AppHoverEffect({
    super.key,
    required this.child,
    this.onHover,
    this.cursor = SystemMouseCursors.basic,
  });

  final Widget child;
  final ValueChanged<bool>? onHover;
  final MouseCursor cursor;

  @override
  State<AppHoverEffect> createState() => _AppHoverEffectState();
}

class _AppHoverEffectState extends State<AppHoverEffect> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) {
        setState(() => _isHovered = true);
        widget.onHover?.call(true);
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        widget.onHover?.call(false);
      },
      child: AnimatedOpacity(
        duration: AppDuration.standard,
        opacity: _isHovered ? 0.9 : 1.0,
        child: widget.child,
      ),
    );
  }
}

/// 状态指示器
class StateIndicator extends StatelessWidget {
  const StateIndicator({
    super.key,
    required this.state,
    this.size = 8,
  });

  final IndicatorState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final color = switch (state) {
      IndicatorState.success => cs.tertiary,
      IndicatorState.warning => cs.secondary,
      IndicatorState.error => cs.error,
      IndicatorState.disabled => cs.outline.withValues(alpha: kOpacityDisabled),
      IndicatorState.info => cs.primary,
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

enum IndicatorState {
  success,
  warning,
  error,
  disabled,
  info,
}

/// 徽章快速生成
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.backgroundColor,
    this.textColor,
    this.size = BadgeSize.medium,
  });

  final String label;
  final Color? backgroundColor;
  final Color? textColor;
  final BadgeSize size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final (bgColor, txtColor, padding, textStyle) = switch (size) {
      BadgeSize.small => (
          backgroundColor ?? cs.primaryContainer,
          textColor ?? cs.onPrimaryContainer,
          const EdgeInsets.symmetric(horizontal: kSpacing8, vertical: kSpacing4),
          textTheme.labelSmall,
        ),
      BadgeSize.medium => (
          backgroundColor ?? cs.primaryContainer,
          textColor ?? cs.onPrimaryContainer,
          const EdgeInsets.symmetric(horizontal: kSpacing12, vertical: kSpacing6),
          textTheme.labelSmall,
        ),
      BadgeSize.large => (
          backgroundColor ?? cs.primaryContainer,
          textColor ?? cs.onPrimaryContainer,
          const EdgeInsets.symmetric(horizontal: kSpacing16, vertical: kSpacing8),
          textTheme.bodySmall,
        ),
    };

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: AppBorderRadius.sm,
      ),
      child: Text(
        label,
        style: textStyle?.copyWith(color: txtColor),
      ),
    );
  }
}

enum BadgeSize {
  small,
  medium,
  large,
}

/// 骨架屏加载器
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({
    super.key,
    required this.child,
    this.isLoading = false,
  });

  final Widget child;
  final bool isLoading;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppDuration.skeletonShimmer,
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading) {
      return widget.child;
    }

    final cs = Theme.of(context).colorScheme;

    return ShaderMask(
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.5, 1.0],
          colors: [
            cs.surface,
            cs.surfaceContainer.withValues(alpha: 0.3),
            cs.surface,
          ],
        ).createShader(bounds);
      },
      child: widget.child,
    );
  }
}
