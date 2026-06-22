/// Material 3 尺寸系统
/// 全局尺寸常量：导轨宽度、侧栏宽度、图标尺寸等

// 导航栏相关
class NavigationDimensions {
  /// 导航侧边栏最小宽度
  static const double railMin = 76;

  /// 导航侧边栏最大宽度
  static const double railMax = 132;

  /// 导航侧边栏默认宽度
  static const double railDefault = 88;

  /// 导航栏标签最小宽度
  static const double labelMinWidth = 50;

  /// 导航栏标签最大宽度
  static const double labelMaxWidth = 120;
}

// 工作台侧栏相关
class WorkbenchDimensions {
  /// 工作台侧栏最小宽度
  static const double sidebarMin = 152;

  /// 工作台侧栏最大宽度
  static const double sidebarMax = 440;

  /// 工作台侧栏默认宽度
  static const double sidebarDefault = 200;

  /// 工作台主内容最小宽度（响应式断点）
  static const double mainContentMinWidth = 400;
}

// 图标和头像尺寸
class IconDimensions {
  /// 小图标（标签、Chip）
  static const double small = 16;

  /// 标准图标（按钮、列表）
  static const double standard = 20;

  /// 标准图标（导航、卡片）
  static const double medium = 24;

  /// 大图标（主要操作）
  static const double large = 32;

  /// 超大图标（特殊展示）
  static const double xlarge = 48;

  /// 头像小号
  static const double avatarSmall = 32;

  /// 头像标准
  static const double avatarStandard = 40;

  /// 头像大号
  static const double avatarLarge = 56;
}

// 文本相关尺寸
class TextDimensions {
  /// 最小行高（紧凑）
  static const double lineHeightTight = 1.2;

  /// 标准行高
  static const double lineHeightNormal = 1.5;

  /// 宽松行高（辅助文本）
  static const double lineHeightLoose = 1.6;

  /// 代码行高（monospace）
  static const double lineHeightCode = 1.4;
}

// 卡片和容器相关
class ContainerDimensions {
  /// 列表项最小高度
  static const double listItemHeight = 56;

  /// 列表项紧凑高度
  static const double listItemCompactHeight = 48;

  /// 列表项宽松高度
  static const double listItemLooseHeight = 64;

  /// 按钮标准高度
  static const double buttonHeight = 40;

  /// 按钮小号高度
  static const double buttonSmallHeight = 32;

  /// 按钮大号高度
  static const double buttonLargeHeight = 48;

  /// 输入框高度
  static const double textFieldHeight = 56;

  /// 输入框紧凑高度
  static const double textFieldCompactHeight = 48;

  /// Chip 高度
  static const double chipHeight = 32;

  /// Chip 紧凑高度
  static const double chipCompactHeight = 24;
}

// 分隔线相关
class DividerDimensions {
  /// 分隔线厚度
  static const double thickness = 1;

  /// 分隔线无缝隙厚度（像素级）
  static const double hairline = 0.5;

  /// 分隔线高度（竖直分隔）
  static const double verticalHeight = 32;
}

// 阴影相关（高程）
class ElevationDimensions {
  /// 无阴影
  static const double none = 0;

  /// 极微阴影（level 1）
  static const double level1 = 1;

  /// 轻微阴影（level 2）
  static const double level2 = 3;

  /// 标准阴影（level 3）
  static const double level3 = 6;

  /// 强阴影（level 4）
  static const double level4 = 8;

  /// 最强阴影（level 5）
  static const double level5 = 12;
}

// 响应式断点
class ResponsiveBreakpoints {
  /// 超小屏（手机竖屏）
  static const double xs = 360;

  /// 小屏（手机横屏/平板竖屏）
  static const double sm = 600;

  /// 中屏（平板）
  static const double md = 840;

  /// 大屏（桌面）
  static const double lg = 1200;

  /// 超大屏
  static const double xl = 1600;

  /// 检查是否超小屏幕
  static bool isXSmall(double width) => width < sm;

  /// 检查是否小屏幕
  static bool isSmall(double width) => width >= sm && width < md;

  /// 检查是否中屏
  static bool isMedium(double width) => width >= md && width < lg;

  /// 检查是否大屏
  static bool isLarge(double width) => width >= lg;
}

// 默认间隔和间距（高频使用）
class DefaultDimensions {
  /// 页面最大宽度（限制大屏布局）
  static const double maxPageWidth = 1400;

  /// 窄栏最大宽度
  static const double narrowColumnWidth = 280;

  /// 中等栏宽度
  static const double mediumColumnWidth = 400;

  /// 宽栏宽度
  static const double wideColumnWidth = 600;

  /// 对话框最大宽度
  static const double dialogMaxWidth = 560;

  /// 底部抽屉最大高度
  static const double bottomSheetMaxHeight = 0.75; // 屏幕高度的 75%

  /// SnackBar 最小宽度
  static const double snackBarMinWidth = 256;
}
