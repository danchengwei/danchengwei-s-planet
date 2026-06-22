/// 内置壁纸资源（`pubspec.yaml` 中 `resources/` 声明）；一次仅显示一张。
abstract final class WallpaperCatalog {
  /// 图片叠在主题底色上的不透明度（0~1）；铺满窗口 [BoxFit.cover] 后略透明以不抢内容。
  static const double imageOpacity = 0.40;

  /// 切换顺序：无 → 各张图 → 再回到无。
  static const List<String> cycleIds = ['', 'jimeng1', 'jimeng2', 'jimeng3', 'jimeng4'];

  static String? assetPathFor(String id) {
    switch (id.trim()) {
      case 'jimeng1':
        return 'resources/jimeng1.png';
      case 'jimeng2':
        return 'resources/jimeng2.png';
      case 'jimeng3':
        return 'resources/jimeng3.png';
      case 'jimeng4':
        return 'resources/jimeng4.png';
      default:
        return null;
    }
  }

  static String nextId(String current) {
    final c = current.trim();
    var i = cycleIds.indexOf(c);
    if (i < 0) i = -1;
    return cycleIds[(i + 1) % cycleIds.length];
  }

  static String labelFor(String id) {
    switch (id.trim()) {
      case 'jimeng1':
        return '壁纸 1';
      case 'jimeng2':
        return '壁纸 2';
      case 'jimeng3':
        return '壁纸 3';
      case 'jimeng4':
        return '壁纸 4';
      default:
        return '无壁纸';
    }
  }
}
