import 'package:flutter/material.dart';

import '../models/wallpaper_catalog.dart';

/// 主窗口底层：主题色底 + 铺满窗口的壁纸（cover，与窗口四边对齐，等比放大可能裁切边缘）。
class AppWallpaperBackdrop extends StatelessWidget {
  const AppWallpaperBackdrop({
    super.key,
    required this.wallpaperId,
    required this.baseColor,
  });

  final String wallpaperId;
  final Color baseColor;

  @override
  Widget build(BuildContext context) {
    final path = WallpaperCatalog.assetPathFor(wallpaperId);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: baseColor),
        if (path != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: WallpaperCatalog.imageOpacity,
                child: Image.asset(
                  path,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, object, stackTrace) {
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}
