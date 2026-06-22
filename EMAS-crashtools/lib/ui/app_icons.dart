import 'package:flutter/material.dart';

/// 应用图标管理器
class AppIcons {
  // 资源路径常数
  static const String _assetsPath = 'lib/assets';

  // 宠物图标路径
  static const String hamsterPng = '$_assetsPath/hamster.png';
  static const String hamsterSvg = '$_assetsPath/hamster.svg';
  static const String duckPng = '$_assetsPath/duck.png';
  static const String dollCatPng = '$_assetsPath/doll_cat.png';
  static const String shibaPng = '$_assetsPath/shiba.png';
  static const String orangeCatPng = '$_assetsPath/orange_cat.png';
  static const String borderColliePng = '$_assetsPath/border_collie.png';

  /// 获取概览图标（使用仓鼠）
  static Widget getOverviewIcon({double size = 20}) {
    return Image.asset(
      hamsterPng,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }

  /// 获取堆栈图标（使用可达鸭）
  static Widget getStackIcon({double size = 20}) {
    return Image.asset(
      duckPng,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }

  /// 获取分布图标（使用柴犬）
  static Widget getDistributionIcon({double size = 20}) {
    return Image.asset(
      shibaPng,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }

  /// 获取分析图标（使用布偶猫）
  static Widget getAnalysisIcon({double size = 20}) {
    return Image.asset(
      dollCatPng,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }

  /// 获取导出图标（使用橘猫）
  static Widget getExportIcon({double size = 20}) {
    return Image.asset(
      orangeCatPng,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }

  /// 获取上传图标（使用边牧）
  static Widget getUploadIcon({double size = 48}) {
    return Image.asset(
      borderColliePng,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }

  /// 带悬停动画的图标按钮
  static Widget createHoverIconButton({
    required String assetPath,
    required VoidCallback onTap,
    double size = 20,
    double hoverScale = 1.15,
    String? tooltip,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: tooltip ?? '',
          child: _HoverScaleImage(
            assetPath: assetPath,
            size: size,
            hoverScale: hoverScale,
          ),
        ),
      ),
    );
  }

  /// 带旋转动画的加载图标
  static Widget createLoadingIcon({
    required String assetPath,
    double size = 20,
    Duration duration = const Duration(milliseconds: 1000),
  }) {
    return _RotatingImage(
      assetPath: assetPath,
      size: size,
      duration: duration,
    );
  }

  /// 带淡出动画的图标
  static Widget createFadeInIcon({
    required String assetPath,
    double size = 20,
    Duration duration = const Duration(milliseconds: 500),
  }) {
    return _FadeInImage(
      assetPath: assetPath,
      size: size,
      duration: duration,
    );
  }
}

/// 悬停缩放图像组件
class _HoverScaleImage extends StatefulWidget {
  const _HoverScaleImage({
    required this.assetPath,
    required this.size,
    required this.hoverScale,
  });

  final String assetPath;
  final double size;
  final double hoverScale;

  @override
  State<_HoverScaleImage> createState() => _HoverScaleImageState();
}

class _HoverScaleImageState extends State<_HoverScaleImage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.hoverScale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        _controller.forward();
      },
      onExit: (_) {
        _controller.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Image.asset(
          widget.assetPath,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// 旋转动画图像组件
class _RotatingImage extends StatefulWidget {
  const _RotatingImage({
    required this.assetPath,
    required this.size,
    required this.duration,
  });

  final String assetPath;
  final double size;
  final Duration duration;

  @override
  State<_RotatingImage> createState() => _RotatingImageState();
}

class _RotatingImageState extends State<_RotatingImage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
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
    return RotationTransition(
      turns: _controller,
      child: Image.asset(
        widget.assetPath,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// 淡出动画图像组件
class _FadeInImage extends StatefulWidget {
  const _FadeInImage({
    required this.assetPath,
    required this.size,
    required this.duration,
  });

  final String assetPath;
  final double size;
  final Duration duration;

  @override
  State<_FadeInImage> createState() => _FadeInImageState();
}

class _FadeInImageState extends State<_FadeInImage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Image.asset(
        widget.assetPath,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
      ),
    );
  }
}
