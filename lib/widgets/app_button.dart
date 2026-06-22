/// Material 3 标准按钮组件
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../styles/component_decorations.dart';

/// 统一按钮组件包装器
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.type = ButtonType.filled,
    this.size = ButtonSize.medium,
    this.isLoading = false,
    this.isEnabled = true,
    this.icon,
    this.iconPosition = IconPosition.start,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonType type;
  final ButtonSize size;
  final bool isLoading;
  final bool isEnabled;
  final IconData? icon;
  final IconPosition iconPosition;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = _getStyle(cs);
    final (padding, height) = _getSizeConfig();

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null && iconPosition == IconPosition.start) ...[
          Icon(icon, size: 20),
          const SizedBox(width: kSpacing8),
        ],
        if (isLoading)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(
                type == ButtonType.filled ? cs.onPrimary : cs.primary,
              ),
            ),
          )
        else
          Text(label),
        if (icon != null && iconPosition == IconPosition.end) ...[
          const SizedBox(width: kSpacing8),
          Icon(icon, size: 20),
        ],
      ],
    );

    Widget button = SizedBox(
      height: height,
      child: switch (type) {
        ButtonType.filled => FilledButton(
            onPressed: isEnabled && !isLoading ? onPressed : null,
            style: style,
            child: content,
          ),
        ButtonType.outlined => OutlinedButton(
            onPressed: isEnabled && !isLoading ? onPressed : null,
            style: style,
            child: content,
          ),
        ButtonType.text => TextButton(
            onPressed: isEnabled && !isLoading ? onPressed : null,
            style: style,
            child: content,
          ),
      },
    );

    return button;
  }

  ButtonStyle _getStyle(ColorScheme cs) {
    return switch (type) {
      ButtonType.filled => AppButtonStyle.filled(cs),
      ButtonType.outlined => AppButtonStyle.outlined(cs),
      ButtonType.text => AppButtonStyle.text(cs),
    };
  }

  (EdgeInsets, double) _getSizeConfig() {
    return switch (size) {
      ButtonSize.small => (
          const EdgeInsets.symmetric(horizontal: kSpacing16, vertical: kSpacing8),
          32,
        ),
      ButtonSize.medium => (
          const EdgeInsets.symmetric(horizontal: kSpacing20, vertical: kSpacing12),
          40,
        ),
      ButtonSize.large => (
          const EdgeInsets.symmetric(horizontal: kSpacing24, vertical: kSpacing16),
          48,
        ),
    };
  }
}

enum ButtonType { filled, outlined, text }
enum ButtonSize { small, medium, large }
enum IconPosition { start, end }
