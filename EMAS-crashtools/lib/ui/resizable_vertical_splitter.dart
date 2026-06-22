import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

/// 纵向分隔条：水平拖动即可调整左侧区域宽度（桌面端鼠标、触控板与触屏均可）。
class ResizableVerticalSplitter extends StatelessWidget {
  const ResizableVerticalSplitter({
    super.key,
    required this.color,
    required this.onDragDelta,
    this.onDragEnd,
    this.hitWidth = 6,
  });

  final Color color;
  final ValueChanged<double> onDragDelta;
  final VoidCallback? onDragEnd;
  final double hitWidth;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: Semantics(
        label: '调整侧栏宽度',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => onDragDelta(d.delta.dx),
          onHorizontalDragEnd: (_) => onDragEnd?.call(),
          // 避免与列表纵向滚动抢手势：仅指针类设备参与水平拖曳
          supportedDevices: const {
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
            PointerDeviceKind.touch,
          },
          child: SizedBox(
            width: hitWidth,
            child: Center(
              child: Container(
                width: 1,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
