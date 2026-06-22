import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class AppDivider extends StatelessWidget {
  const AppDivider({
    super.key,
    this.thickness = 1,
    this.height = 1,
    this.margin = EdgeInsets.zero,
    this.intensity = DividerIntensity.light,
  });

  final double thickness;
  final double height;
  final EdgeInsets margin;
  final DividerIntensity intensity;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final alpha = switch (intensity) {
      DividerIntensity.light => kOpacitySubtle,
      DividerIntensity.medium => kOpacityLight,
      DividerIntensity.strong => kOpacityMedium,
    };

    return Container(
      margin: margin,
      height: height,
      color: cs.outlineVariant.withValues(alpha: alpha),
    );
  }
}

enum DividerIntensity { light, medium, strong }
