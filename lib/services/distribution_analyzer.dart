/// Android 系统版本分布
class OsVersionDistribution {
  OsVersionDistribution({
    required this.osVersion,
    required this.count,
    required this.percentage,
  });

  final String osVersion;  // e.g., "Android 12+"
  final int count;
  final double percentage; // 0-100

  Map<String, dynamic> toJson() => {
        'osVersion': osVersion,
        'count': count,
        'percentage': percentage,
      };
}

/// 机型分布
class DeviceDistribution {
  DeviceDistribution({
    required this.deviceModel,
    required this.count,
    required this.percentage,
  });

  final String deviceModel;  // e.g., "华为 Mate 40"
  final int count;
  final double percentage;

  Map<String, dynamic> toJson() => {
        'deviceModel': deviceModel,
        'count': count,
        'percentage': percentage,
      };
}

/// 品牌分布
class BrandDistribution {
  BrandDistribution({
    required this.brand,
    required this.count,
    required this.percentage,
  });

  final String brand;  // e.g., "华为"
  final int count;
  final double percentage;

  Map<String, dynamic> toJson() => {
        'brand': brand,
        'count': count,
        'percentage': percentage,
      };
}

/// 版本分布
class VersionDistribution {
  VersionDistribution({
    required this.version,
    required this.count,
    required this.percentage,
  });

  final String version;  // e.g., "10.16.03"
  final int count;
  final double percentage;

  Map<String, dynamic> toJson() => {
        'version': version,
        'count': count,
        'percentage': percentage,
      };
}

/// 完整的分布分析结果
class DistributionAnalysis {
  DistributionAnalysis({
    required this.totalCount,
    this.osVersions = const [],
    this.devices = const [],
    this.brands = const [],
    this.versions = const [],
  });

  final int totalCount;
  final List<OsVersionDistribution> osVersions;
  final List<DeviceDistribution> devices;
  final List<BrandDistribution> brands;
  final List<VersionDistribution> versions;

  Map<String, dynamic> toJson() => {
        'totalCount': totalCount,
        'osVersions': osVersions.map((e) => e.toJson()).toList(),
        'devices': devices.map((e) => e.toJson()).toList(),
        'brands': brands.map((e) => e.toJson()).toList(),
        'versions': versions.map((e) => e.toJson()).toList(),
      };
}

/// 分布分析器
class DistributionAnalyzer {
  /// 分析 EMAS API 返回的问题数据，提取分布信息
  static DistributionAnalysis analyze({
    required Map<String, dynamic> issueData,
    int topN = 5,
  }) {
    final totalCount = issueData['ErrorCount'] ?? 0;

    // 解析 OS 版本分布
    final osVersions = _parseOsVersionDistribution(
      issueData['SystemVersionDistribution'],
      totalCount,
      topN,
    );

    // 解析设备分布
    final devices = _parseDeviceDistribution(
      issueData['DeviceDistribution'],
      totalCount,
      topN,
    );

    // 解析品牌分布
    final brands = _parseBrandDistribution(
      issueData['BrandDistribution'],
      totalCount,
      topN,
    );

    // 解析版本分布
    final versions = _parseVersionDistribution(
      issueData['VersionDistribution'],
      totalCount,
      topN,
    );

    return DistributionAnalysis(
      totalCount: totalCount,
      osVersions: osVersions,
      devices: devices,
      brands: brands,
      versions: versions,
    );
  }

  /// 解析 OS 版本分布（从 API 返回的数据）
  static List<OsVersionDistribution> _parseOsVersionDistribution(
    dynamic data,
    int totalCount,
    int topN,
  ) {
    if (data is! List) return [];

    final List<OsVersionDistribution> result = [];

    for (final item in data) {
      if (item is Map<String, dynamic>) {
        final version = item['Version']?.toString() ?? 'Unknown';
        final count = (item['Count'] as num?)?.toInt() ?? 0;

        result.add(OsVersionDistribution(
          osVersion: _formatOsVersion(version),
          count: count,
          percentage: totalCount > 0 ? (count / totalCount) * 100 : 0,
        ));
      }
    }

    // 按数量排序并取 Top N
    result.sort((a, b) => b.count.compareTo(a.count));
    return result.take(topN).toList();
  }

  /// 解析设备分布
  static List<DeviceDistribution> _parseDeviceDistribution(
    dynamic data,
    int totalCount,
    int topN,
  ) {
    if (data is! List) return [];

    final List<DeviceDistribution> result = [];

    for (final item in data) {
      if (item is Map<String, dynamic>) {
        final model = item['Model']?.toString() ?? 'Unknown';
        final count = (item['Count'] as num?)?.toInt() ?? 0;

        result.add(DeviceDistribution(
          deviceModel: model,
          count: count,
          percentage: totalCount > 0 ? (count / totalCount) * 100 : 0,
        ));
      }
    }

    result.sort((a, b) => b.count.compareTo(a.count));
    return result.take(topN).toList();
  }

  /// 解析品牌分布
  static List<BrandDistribution> _parseBrandDistribution(
    dynamic data,
    int totalCount,
    int topN,
  ) {
    if (data is! List) return [];

    final List<BrandDistribution> result = [];

    for (final item in data) {
      if (item is Map<String, dynamic>) {
        final brand = item['Brand']?.toString() ?? 'Unknown';
        final count = (item['Count'] as num?)?.toInt() ?? 0;

        result.add(BrandDistribution(
          brand: brand,
          count: count,
          percentage: totalCount > 0 ? (count / totalCount) * 100 : 0,
        ));
      }
    }

    result.sort((a, b) => b.count.compareTo(a.count));
    return result.take(topN).toList();
  }

  /// 解析版本分布
  static List<VersionDistribution> _parseVersionDistribution(
    dynamic data,
    int totalCount,
    int topN,
  ) {
    if (data is! List) return [];

    final List<VersionDistribution> result = [];

    for (final item in data) {
      if (item is Map<String, dynamic>) {
        final version = item['Version']?.toString() ?? 'Unknown';
        final count = (item['Count'] as num?)?.toInt() ?? 0;

        result.add(VersionDistribution(
          version: version,
          count: count,
          percentage: totalCount > 0 ? (count / totalCount) * 100 : 0,
        ));
      }
    }

    result.sort((a, b) => b.count.compareTo(a.count));
    return result.take(topN).toList();
  }

  /// 格式化 OS 版本为友好名称
  static String _formatOsVersion(String version) {
    // 解析版本号 (e.g., "31" -> "Android 12+")
    final versionNum = int.tryParse(version) ?? 0;

    // Android API Level 映射
    const Map<int, String> androidLevels = {
      29: 'Android 10',
      30: 'Android 11',
      31: 'Android 12',
      32: 'Android 12L',
      33: 'Android 13',
      34: 'Android 14',
      35: 'Android 15',
    };

    if (androidLevels.containsKey(versionNum)) {
      if (versionNum >= 31) return '${androidLevels[versionNum]}+';
      return androidLevels[versionNum]!;
    }

    if (versionNum >= 31) {
      return 'Android ${versionNum - 20}+'; // 粗略估计
    }
    if (versionNum >= 29) {
      return 'Android ${versionNum - 18}';
    }

    return 'Android $version';
  }

  /// 生成分布分析的表格展示数据
  static String generateDistributionTable(DistributionAnalysis analysis) {
    final buffer = StringBuffer();

    // OS 版本分布表
    if (analysis.osVersions.isNotEmpty) {
      buffer.writeln('### 📱 系统版本分布分析');
      buffer.writeln('| 系统版本 | 崩溃次数 | 占比 |');
      buffer.writeln('|---------|---------|------|');
      for (final item in analysis.osVersions) {
        buffer.writeln('| ${item.osVersion} | ${item.count} | ${item.percentage.toStringAsFixed(2)}% |');
      }
      buffer.writeln();
    }

    // 机型分布表
    if (analysis.devices.isNotEmpty) {
      buffer.writeln('### 📱 机型分布分析');
      buffer.writeln('| 机型 | 崩溃次数 | 占比 |');
      buffer.writeln('|------|---------|------|');
      for (final item in analysis.devices) {
        buffer.writeln('| ${item.deviceModel} | ${item.count} | ${item.percentage.toStringAsFixed(2)}% |');
      }
      buffer.writeln();
    }

    // 品牌分布表
    if (analysis.brands.isNotEmpty) {
      buffer.writeln('### 🏷️ 品牌分布分析');
      buffer.writeln('| 品牌 | 崩溃次数 | 占比 |');
      buffer.writeln('|------|---------|------|');
      for (final item in analysis.brands) {
        buffer.writeln('| ${item.brand} | ${item.count} | ${item.percentage.toStringAsFixed(2)}% |');
      }
      buffer.writeln();
    }

    // 版本分布表
    if (analysis.versions.isNotEmpty) {
      buffer.writeln('### 📦 应用版本分布');
      buffer.writeln('| 版本 | 崩溃次数 | 占比 |');
      buffer.writeln('|------|---------|------|');
      for (final item in analysis.versions) {
        buffer.writeln('| ${item.version} | ${item.count} | ${item.percentage.toStringAsFixed(2)}% |');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }
}
