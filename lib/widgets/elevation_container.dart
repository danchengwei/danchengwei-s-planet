import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class ElevationContainer extends StatelessWidget {
  const ElevationContainer({
    super.key,
    required this.child,
    this.elevation = kElevationLevel1,
    this.borderRadius = kRadius16,
    this.color,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final double elevation;
  final double borderRadius;
  final Color? color;
  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? cs.surface,
        borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
        boxShadow: AppShadow.get(elevation),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
