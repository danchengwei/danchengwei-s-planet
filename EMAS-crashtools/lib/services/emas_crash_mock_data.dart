import '../aliyun/emas_appmonitor_client.dart';

/// 本地预览用：模拟「崩溃」Biz 下的 GetIssues / GetIssue 数据结构，不请求网络。
class EmasCrashMockData {
  EmasCrashMockData._();

  static const String digestPrefix = 'mock_digest';

  static String _digest(int n) =>
      '${digestPrefix}_${n.toString().padLeft(3, '0')}';

  static final List<IssueListItem> _all = _buildItems();

  static List<IssueListItem> _buildItems() {
    const stack1 = '''
java.lang.NullPointerException: Attempt to invoke virtual method 'void android.widget.TextView.setText(java.lang.CharSequence)' on a null object reference
	at com.xiwang.youke.ui.home.HomeFragment.onViewCreated(HomeFragment.kt:118)
	at androidx.fragment.app.Fragment.performCreateView(Fragment.java:3119)
	at androidx.fragment.app.FragmentStateManager.createView(FragmentStateManager.java:577)
	at androidx.fragment.app.FragmentManager.moveToState(FragmentManager.java:1356)
	at android.app.ActivityThread.main(ActivityThread.java:8638)''';

    const stack2 = '''
android.view.InflateException: Binary XML file line #42 in com.xiwang.youke.debug:layout/fragment_player: Error inflating class <unknown>
Caused by: java.lang.reflect.InvocationTargetException
	at java.lang.reflect.Constructor.newInstance0(Native Method)
	at com.xiwang.youke.player.LiveRoomView.<init>(LiveRoomView.kt:55)
	at android.view.LayoutInflater.createView(LayoutInflater.java:858)''';

    const stack3 = '''
java.lang.IllegalStateException: Fragment already added: UserCenterFragment{deadbeef}
	at androidx.fragment.app.FragmentStore.addFragment(FragmentStore.java:165)
	at com.xiwang.youke.MainActivity.switchTab(MainActivity.java:203)
	at android.os.Handler.handleCallback(Handler.java:958)''';

    return [
      IssueListItem(
        digestHash: _digest(1),
        errorName:
            "java.lang.NullPointerException: Attempt to invoke virtual method 'void android.widget.TextView.setText'",
        stack: stack1,
        errorCount: 1284,
        errorDeviceCount: 892,
        eventTime: '2026-04-08 10:23:00',
        errorType: 'java',
      ),
      IssueListItem(
        digestHash: _digest(2),
        errorName: 'android.view.InflateException: Binary XML file line #42 in layout/fragment_player',
        stack: stack2,
        errorCount: 356,
        errorDeviceCount: 201,
        eventTime: '2026-04-08 09:10:00',
        errorType: 'java',
      ),
      IssueListItem(
        digestHash: _digest(3),
        errorName: 'java.lang.IllegalStateException: Fragment already added: UserCenterFragment',
        stack: stack3,
        errorCount: 89,
        errorDeviceCount: 67,
        eventTime: '2026-04-07 22:01:00',
        errorType: 'java',
      ),
      IssueListItem(
        digestHash: _digest(4),
        errorName: 'kotlin.UninitializedPropertyAccessException: lateinit property adapter has not been initialized',
        stack:
            'kotlin.UninitializedPropertyAccessException: lateinit property adapter has not been initialized\n'
            '\tat com.xiwang.youke.course.CourseListActivity.onResume(CourseListActivity.kt:71)\n'
            '\tat android.app.Instrumentation.callActivityOnResume(Instrumentation.java:1603)',
        errorCount: 45,
        errorDeviceCount: 38,
        eventTime: '2026-04-07 18:44:00',
        errorType: 'kotlin',
      ),
      IssueListItem(
        digestHash: _digest(5),
        errorName: 'java.lang.OutOfMemoryError: Failed to allocate a 1048592 byte allocation with 25165824 free',
        stack:
            'java.lang.OutOfMemoryError: Failed to allocate a 1048592 byte allocation with 25165824 free bytes until OOM\n'
            '\tat com.xiwang.youke.media.BitmapLoader.decode(BitmapLoader.java:88)\n'
            '\tat dalvik.system.VMRuntime.newNonMovableArray(Native Method)',
        errorCount: 12,
        errorDeviceCount: 9,
        eventTime: '2026-04-06 11:02:00',
        errorType: 'java',
      ),
    ] +
        List.generate(
          20,
          (i) => IssueListItem(
            digestHash: _digest(6 + i),
            errorName: 'java.lang.RuntimeException: Mock 分页数据 #${6 + i}（用于预览翻页与长列表）',
            stack:
                'java.lang.RuntimeException: mock row ${6 + i}\n\tat com.xiwang.youke.Mock.line${6 + i}(Mock.kt:${10 + i})',
            errorCount: 3 + i,
            errorDeviceCount: 2 + (i % 4),
            eventTime: '2026-04-05 12:00:00',
            errorType: 'java',
          ),
        );
  }

  /// 与真实 [EmasAppMonitorClient.getIssues] 分页语义一致（PageIndex 从 1 起）。
  static GetIssuesResult mockGetIssues({
    required int pageIndex,
    required int pageSize,
  }) {
    final all = _all;
    final total = all.length;
    final pages = total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;
    final pi = pageIndex < 1 ? 1 : pageIndex;
    final start = (pi - 1) * pageSize;
    if (start >= total) {
      return GetIssuesResult(
        items: const [],
        total: total,
        pageNum: pi,
        pageSize: pageSize,
        pages: pages,
      );
    }
    final end = start + pageSize > total ? total : start + pageSize;
    return GetIssuesResult(
      items: all.sublist(start, end),
      total: total,
      pageNum: pi,
      pageSize: pageSize,
      pages: pages,
    );
  }

  /// 模拟 GetIssue 顶层 JSON（详情页会递归找 Stack 等字段）。
  static Map<String, dynamic> mockGetIssue(String digestHash) {
    IssueListItem? row;
    for (final e in _all) {
      if (e.digestHash == digestHash) {
        row = e;
        break;
      }
    }
    final title = row?.errorName ?? 'Mock 崩溃（未匹配 digest）';
    final stack = row?.stack ??
        'java.lang.Exception: mock fallback\n\tat com.xiwang.youke.Unknown.method(Unknown.kt:1)';
    final count = row?.errorCount ?? 1;
    return {
      'Success': true,
      'RequestId': 'MOCK-REQUEST-ID',
      'Code': '200',
      'Model': {
        'DigestHash': digestHash,
        'ErrorName': title,
        'Stack': stack,
        'ErrorCount': count,
        'ErrorDeviceCount': row?.errorDeviceCount ?? 1,
        'EventTime': row?.eventTime ?? '2026-04-08 00:00:00',
        'ErrorType': row?.errorType ?? 'java',
        'Os': 'android',
        'BizModule': 'crash',
      },
    };
  }

  static bool isMockDigest(String digestHash) =>
      digestHash.trim().startsWith(digestPrefix);
}
