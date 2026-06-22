/// 各平台支持的业务模块和功能
///
/// 参考阿里云 EMAS APM CLI 官方支持矩阵
class PlatformCapabilities {
  /// 各平台支持的 bizModule 清单
  static const Map<String, Set<String>> supportedBizModules = {
    'android': {
      'crash',           // 崩溃
      'anr',            // ANR
      'lag',            // 卡顿
      'custom',         // 自定义监控
      'memory_leak',    // 内存泄漏
      'memory_alloc',   // 内存分配
      'startup',        // 启动时间
      'exception',      // 异常
      'h5whitescreen',  // H5 白屏
      'h5jserror',      // H5 JS 错误
    },
    'iphoneos': {
      'crash',
      'anr',
      'lag',
      'custom',
      'memory_leak',
      'memory_alloc',
      'startup',
      'exception',
      'h5whitescreen',
      'h5jserror',
    },
    'harmony': {
      'crash',          // ✅ 支持
      'lag',            // ✅ 支持
      'custom',         // ✅ 支持
      // ❌ 不支持: anr, memory_leak, memory_alloc
    },
  };

  /// 获取某个平台不支持的 bizModule
  static Set<String> unsupportedBizModules(String os) {
    final os_lower = os.toLowerCase().trim();
    const allBizModules = {
      'crash',
      'anr',
      'lag',
      'custom',
      'memory_leak',
      'memory_alloc',
      'startup',
      'exception',
      'h5whitescreen',
      'h5jserror',
    };

    final supported = supportedBizModules[os_lower] ?? {};
    return allBizModules.difference(supported);
  }

  /// 检查某个平台是否支持指定的 bizModule
  static bool isSupportedBizModule(String os, String bizModule) {
    final os_lower = os.toLowerCase().trim();
    final biz_lower = bizModule.toLowerCase().trim();
    return supportedBizModules[os_lower]?.contains(biz_lower) ?? false;
  }

  /// 获取平台的友好名称
  static String getPlatformName(String os) {
    final os_lower = os.toLowerCase().trim();
    switch (os_lower) {
      case 'android':
        return 'Android';
      case 'iphoneos':
        return 'iOS';
      case 'harmony':
        return 'HarmonyOS';
      default:
        return os;
    }
  }

  /// 获取 bizModule 的友好名称
  static String getBizModuleName(String bizModule) {
    final biz = bizModule.toLowerCase().trim();
    switch (biz) {
      case 'crash':
        return '崩溃';
      case 'anr':
        return 'ANR';
      case 'startup':
        return '启动';
      case 'exception':
        return '异常';
      case 'h5whitescreen':
        return 'H5白屏';
      case 'lag':
        return '卡顿';
      case 'h5jserror':
        return 'H5JS';
      case 'custom':
        return '自定义';
      case 'memory_leak':
        return '内存泄漏';
      case 'memory_alloc':
        return '内存分配';
      default:
        return bizModule;
    }
  }

  /// 生成平台不支持该功能的提示信息
  static String getUnsupportedMessage(String os, String bizModule) {
    final platformName = getPlatformName(os);
    final bizModuleName = getBizModuleName(bizModule);

    // 针对 HarmonyOS 的特殊提示
    if (os.toLowerCase().trim() == 'harmony') {
      return '$platformName 平台不支持「$bizModuleName」功能，仅支持崩溃、卡顿、自定义监控这些功能。';
    }

    return '$platformName 平台不支持「$bizModuleName」功能。';
  }

  /// 获取平台可用的 bizModule 列表及其友好名称
  static List<(String, String)> getAvailableBizModules(String os) {
    final os_lower = os.toLowerCase().trim();
    final supported = supportedBizModules[os_lower] ?? {};

    return supported
        .map((biz) => (biz, getBizModuleName(biz)))
        .toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
  }
}
