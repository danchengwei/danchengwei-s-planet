import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crash_emas_tool/app_controller.dart';
import 'package:crash_emas_tool/ui/main_shell.dart';

void main() {
  testWidgets('工作台与侧栏可渲染', (WidgetTester tester) async {
    final c = AppController();
    await tester.pumpWidget(MaterialApp(home: MainShell(controller: c)));
    await tester.pump();
    expect(find.text('配置'), findsOneWidget);
    expect(find.textContaining('实时概览'), findsWidgets);
    expect(find.textContaining('崩溃分析'), findsWidgets);
  });
}
