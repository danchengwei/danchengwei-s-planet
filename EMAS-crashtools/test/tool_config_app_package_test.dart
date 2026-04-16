import 'package:flutter_test/flutter_test.dart';

import 'package:crash_emas_tool/models/tool_config.dart';

void main() {
  test('appPackageName：fromJson 兼容 packageName / androidPackageName，且 appPackageName 优先', () {
    expect(ToolConfig.fromJson({'packageName': ' com.a '}).appPackageName, 'com.a');
    expect(ToolConfig.fromJson({'androidPackageName': 'com.b'}).appPackageName, 'com.b');
    expect(
      ToolConfig.fromJson({
        'appPackageName': 'com.c',
        'packageName': 'com.a',
      }).appPackageName,
      'com.c',
    );
  });

  test('appPackageName：fromJson 支持测试键 emasListNameQuery（无前述键时）', () {
    expect(
      ToolConfig.fromJson({'emasListNameQuery': 'com.xiwang.youke.debug'}).appPackageName,
      'com.xiwang.youke.debug',
    );
    expect(
      ToolConfig.fromJson({
        'appPackageName': 'com.a',
        'emasListNameQuery': 'com.xiwang.youke.debug',
      }).appPackageName,
      'com.a',
    );
  });

  test('appPackageNameForOpenApi：空白视为 null', () {
    expect(ToolConfig().appPackageNameForOpenApi, isNull);
    expect(ToolConfig(appPackageName: '  ').appPackageNameForOpenApi, isNull);
    expect(ToolConfig(appPackageName: 'x.y').appPackageNameForOpenApi, 'x.y');
  });
}
