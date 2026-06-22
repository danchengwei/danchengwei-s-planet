import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class MaterialSurface extends StatelessWidget {
  const MaterialSurface({
    super.key,
    required this.child,
    this.surfaceLevel = SurfaceLevel.base,
    this.borderRadius = kRadius16,
    this.hasBorder = true,
    this.padding = const EdgeInsets.all(kSpacing16),
    this.onTap,
  });

  final Widget child;
  final SurfaceLevel surfaceLevel;
  final double borderRadius;
  final bool hasBorder;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bgColor = switch (surfaceLevel) {
      SurfaceLevel.base => cs.surface,
      SurfaceLevel.low => cs.surfaceContainerLow,
      SurfaceLevel.standard => cs.surfaceContainer,
      SurfaceLevel.high => cs.surfaceContainerHigh,
      SurfaceLevel.highest => cs.surfaceContainerHighest,
    };

    Widget content = Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
        border: hasBorder
            ? Border.all(
                color: cs.outlineVariant.withValues(alpha: kOpacitySubtle),
                width: 1,
              )
            : null,
      ),
      padding: padding,
      child: child,
    );

    if (onTap != null) {
      content = GestureDetector(
        onTap: onTap,
        child: content,
      );
    }

    return content;
  }
}

enum SurfaceLevel { base, low, standard, high, highest }
