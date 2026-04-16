import 'dart:convert';
import 'dart:io';

import 'package:crash_emas_tool/models/projects_workspace.dart';
import 'package:crash_emas_tool/services/test_local_config_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('applyDecodedMapForTest 扁平配置覆盖当前活动项目', () {
    final ws = ProjectsWorkspace.empty();
    final r = TestLocalConfigLoader.applyDecodedMapForTest(
      {
        'appKey': '112233',
        'gitlabBaseUrl': 'https://example.com',
      },
      ws,
    );
    expect(r, isNotNull);
    expect(r!.mode, TestConfigApplyMode.toolConfig);
    expect(ws.projects.first.config.appKey, '112233');
    expect(ws.projects.first.config.gitlabBaseUrl, 'https://example.com');
  });

  test('applyDecodedMapForTest 含 projects 时替换整个工作区', () {
    final ws = ProjectsWorkspace.empty();
    final r = TestLocalConfigLoader.applyDecodedMapForTest(
      {
        'schemaVersion': 2,
        'openProjectHubOnLaunch': false,
        'activeProjectId': 'pid_test',
        'projects': [
          {
            'id': 'pid_test',
            'name': '仅测试',
            'config': {
              'appKey': '999',
              'accessKeyId': 'id1',
            },
          },
        ],
      },
      ws,
    );
    expect(r, isNotNull);
    expect(r!.mode, TestConfigApplyMode.workspace);
    expect(ws.projects.length, 1);
    expect(ws.activeProjectId, 'pid_test');
    expect(ws.openProjectHubOnLaunch, false);
    expect(ws.projects.first.name, '仅测试');
    expect(ws.projects.first.config.appKey, '999');
  });

  test('optionalLegacyAppVersionFromImportRoot 仅读应用版本相关键', () {
    expect(
      TestLocalConfigLoader.optionalLegacyAppVersionFromImportRoot({
        'emasAppVersion': '  1.2.3  ',
      }),
      '1.2.3',
    );
    expect(
      TestLocalConfigLoader.optionalLegacyAppVersionFromImportRoot({
        'packageName': 'com.example.app',
        'appVersion': '3.8.0',
      }),
      '3.8.0',
    );
    expect(
      TestLocalConfigLoader.optionalLegacyAppVersionFromImportRoot({
        'projects': [
          {
            'id': 'p1',
            'config': {'versionName': 'from_project'},
          },
        ],
        'activeProjectId': 'p1',
      }),
      'from_project',
    );
  });

  test('applyFromFile 从临时文件读取扁平 JSON', () async {
    final dir = await Directory.systemTemp.createTemp('crash_tools_cfg_');
    final f = File('${dir.path}/t.json');
    await f.writeAsString(jsonEncode({'appKey': '777'}));
    final ws = ProjectsWorkspace.empty();
    final r = await TestLocalConfigLoader.applyFromFile(f, ws);
    expect(r, isNotNull);
    expect(ws.projects.first.config.appKey, '777');
    await dir.delete(recursive: true);
  });
}
