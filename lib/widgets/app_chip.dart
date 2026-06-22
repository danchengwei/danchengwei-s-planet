import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.onDeleted,
    this.isSelected = false,
    this.chipType = ChipType.input,
  });

  final String label;
  final VoidCallback? onDeleted;
  final bool isSelected;
  final ChipType chipType;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final bgColor = isSelected
        ? cs.primaryContainer
        : cs.surfaceContainer.withValues(alpha: 0.5);

    return Chip(
      label: Text(
        label,
        style: textTheme.labelSmall?.copyWith(
          color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.sm,
        side: BorderSide(
          color: isSelected
              ? cs.primary.withValues(alpha: kOpacityLight)
              : cs.outline.withValues(alpha: kOpacitySubtle),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: kSpacing8, vertical: kSpacing4),
      onDeleted: onDeleted,
      deleteIcon: Icon(Icons.close, size: 16),
    );
  }
}

enum ChipType { input, choice, filter, suggestion }
