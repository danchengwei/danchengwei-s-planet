import 'package:crash_emas_tool/services/emas_crash_mock_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Mock 崩溃列表总数与分页', () {
    final p1 = EmasCrashMockData.mockGetIssues(pageIndex: 1, pageSize: 20);
    expect(p1.total, 25);
    expect(p1.items.length, 20);
    expect(p1.pages, 2);
    final p2 = EmasCrashMockData.mockGetIssues(pageIndex: 2, pageSize: 20);
    expect(p2.items.length, 5);
  });

  test('mock_digest 详情与列表 digest 一致', () {
    expect(EmasCrashMockData.isMockDigest('mock_digest_001'), isTrue);
    expect(EmasCrashMockData.isMockDigest('real_xyz'), isFalse);
    final j = EmasCrashMockData.mockGetIssue('mock_digest_001');
    expect(j['Model'], isA<Map>());
    final m = j['Model']! as Map;
    expect(m['DigestHash'], 'mock_digest_001');
    expect((m['Stack'] as String).contains('HomeFragment'), isTrue);
  });
}
