/// Material 3 样式系统导出中心
/// 统一导出所有样式定义

export 'app_text_styles.dart';
export 'app_card_style.dart';
export 'component_decorations.dart';

/// 样式系统快速参考
const String styleSystemGuide = '''
Material 3 样式系统快速参考
==========================

TEXT STYLES (文本样式)
├── displayLarge      → 显示标题（用于主标题）
├── headlineLarge     → 页面标题
├── headlineMedium    → 模块标题
├── headlineSmall     → 小标题
├── titleLarge        → 卡片标题
├── titleMedium       → 子标题
├── titleSmall        → 小标题
├── bodyLarge         → 主文本
├── bodyMedium        → 常规文本
├── bodySmall         → 副文本（灰化）
├── labelLarge        → 主要标签
├── labelMedium       → 次要标签
└── labelSmall        → 辅助标签

使用扩展方法示例：
  • headlineLargeEmphasis    → 强调标题（加粗）
  • bodyMediumRegular        → 常规正文
  • bodySmallMuted           → 灰化副文本
  • titleLargeEmphasis       → 加粗卡片标题

CARD STYLES (卡片样式)
├── AppCardStyle.standard()  → 标准卡片
├── AppCardStyle.elevated()  → 浮起卡片
├── AppCardStyle.minimal()   → 极简卡片
├── AppCardStyle.filled()    → 填充卡片
├── AppCardStyle.hover()     → 悬停状态
├── AppCardStyle.accent()    → 强调卡片
├── AppCardStyle.error()     → 错误卡片
└── AppCardStyle.success()   → 成功卡片

快速使用：
  Container(
    decoration: AppCardStyle.standard(cs),
    child: // 内容
  )

或使用 AppCard widget：
  AppCard(
    style: AppCardStyleEnum.standard,
    child: // 内容
  )

BUTTON STYLES (按钮样式)
├── AppButtonStyle.filled()     → 填充按钮
├── AppButtonStyle.outlined()   → 描边按钮
└── AppButtonStyle.text()       → 文字按钮

INPUT STYLES (输入框样式)
├── AppInputDecoration.standard()  → 标准输入框
└── AppInputDecoration.compact()   → 紧凑输入框

DIVIDERS (分割线)
├── AppDividers.light()      → 轻分割线
├── AppDividers.standard()   → 标准分割线
├── AppDividers.strong()     → 强分割线
└── AppDividers.vertical()   → 竖直分割线

DECORATIVE COMPONENTS (装饰组件)
├── StateIndicator    → 状态指示点
├── AppBadge          → 徽章
├── SkeletonLoader    → 骨架屏
├── AppHoverEffect    → 悬停效果
└── CardSection       → 卡片内容分段

USAGE PATTERNS (使用模式)

1. 文本样式：
   Text(
     'Title',
     style: Theme.of(context).textTheme.headlineLarge,
   )

2. 卡片组件：
   AppCard(
     style: AppCardStyleEnum.standard,
     padding: EdgeInsets.all(kSpacing16),
     child: Text('Content'),
   )

3. 输入框：
   TextField(
     decoration: AppInputDecoration.standard(
       context,
       label: 'Label',
       prefixIcon: Icon(Icons.search),
     ),
   )

4. 按钮：
   FilledButton(
     onPressed: () {},
     style: AppButtonStyle.filled(cs),
     child: Text('Button'),
   )

5. 分割线：
   AppDividers.light(cs)

6. 状态指示：
   StateIndicator(state: IndicatorState.success)

7. 徽章：
   AppBadge(
     label: 'New',
     size: BadgeSize.small,
   )
''';
