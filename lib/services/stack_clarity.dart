/// 堆栈中是否更容易定位到**业务代码**（相对系统/框架栈帧）。
enum StackClarityLevel {
  /// 存在非系统包名的栈帧，适合结合 GitLab 等做类/文件级修改建议。
  businessLikely,

  /// 栈帧多为 java/android/kotlin/flutter 框架或无法解析出业务包。
  systemFrameworkDominant,

  /// 无堆栈或过短。
  unknown,
}

/// 供大模型提示词使用的堆栈解读摘要。
class StackClarity {
  const StackClarity({
    required this.level,
    required this.summaryForPrompt,
    this.appFrameSamples = const [],
  });

  final StackClarityLevel level;
  final String summaryForPrompt;
  final List<String> appFrameSamples;
}

final _javaAt = RegExp(r'^\s*at\s+([\w.$]+)\s*\(', multiLine: true);

/// 视为「系统/运行时/平台」的包前缀（小写比较），用于与业务代码区分。
bool _isSystemJavaKotlinFrame(String qualifiedClass) {
  final q = qualifiedClass.trim().toLowerCase();
  const prefixes = <String>[
    'java.',
    'javax.',
    'jdk.',
    'sun.',
    'com.android.',
    'android.',
    'androidx.', // 多为框架与通用库栈帧；业务若在此扩展需结合其它线索
    'kotlin.',
    'kotlinx.',
    'dalvik.',
    'libcore.',
    'org.apache.',
    'org.json.',
    'com.google.android.gms.', // Play services
    'com.google.android.material.',
  ];
  for (final p in prefixes) {
    if (q.startsWith(p)) return true;
  }
  return false;
}

final _dartFrame = RegExp(
  r'#\d+\s+.+\((package:[\w_]+/[^)]*|dart:[^)]+)\)',
  multiLine: true,
);

bool _isSystemDartPackage(String pathInParens) {
  final s = pathInParens.toLowerCase();
  return s.startsWith('package:flutter/') ||
      s.startsWith('dart:') ||
      s.startsWith('package:flutter_test/');
}

/// 根据堆栈文本判断更适合「代码级」还是「思路级」分析。
StackClarity analyzeStackClarity(String? stack) {
  if (stack == null || stack.trim().length < 8) {
    return const StackClarity(
      level: StackClarityLevel.unknown,
      summaryForPrompt: '堆栈缺失或过短，无法判断是否能定位业务代码。',
    );
  }

  final samples = <String>[];
  var javaFrames = 0;
  var javaBusiness = 0;
  for (final m in _javaAt.allMatches(stack)) {
    final cls = m.group(1);
    if (cls == null || cls.isEmpty) continue;
    javaFrames++;
    if (!_isSystemJavaKotlinFrame(cls)) {
      javaBusiness++;
      if (samples.length < 4) {
        samples.add('at $cls(...)');
      }
    }
  }

  if (javaFrames > 0) {
    if (javaBusiness > 0) {
      return StackClarity(
        level: StackClarityLevel.businessLikely,
        summaryForPrompt:
            '堆栈中出现疑似**业务包**的栈帧（非 java/android/kotlin 等系统前缀），有利于结合仓库检索定位模块/类。',
        appFrameSamples: samples,
      );
    }
    return const StackClarity(
      level: StackClarityLevel.systemFrameworkDominant,
      summaryForPrompt:
          '堆栈中可见的 Java/Kotlin 帧主要为**系统、Android 框架或通用 AndroidX**等，缺少明确业务包名；请避免臆造业务源文件路径。',
    );
  }

  // Dart / Flutter
  var dartBiz = 0;
  for (final m in _dartFrame.allMatches(stack)) {
    final loc = m.group(1);
    if (loc == null) continue;
    if (!_isSystemDartPackage(loc)) {
      dartBiz++;
      if (samples.length < 4) samples.add(loc);
    }
  }
  if (dartBiz > 0) {
    return StackClarity(
      level: StackClarityLevel.businessLikely,
      summaryForPrompt: '堆栈中出现 **package:** 业务包路径（非 flutter/dart: 运行时），有利于对照仓库分析。',
      appFrameSamples: samples,
    );
  }
  if (_dartFrame.hasMatch(stack)) {
    return const StackClarity(
      level: StackClarityLevel.systemFrameworkDominant,
      summaryForPrompt:
          '堆栈主要为 **Flutter/Dart 框架**（package:flutter、dart: 等），业务代码帧不明显；请从症状与生命周期推断业务侧修改思路。',
    );
  }

  // iOS 常见符号（弱启发）：仅有系统库时常无法看到应用模块名
  final lower = stack.toLowerCase();
  final iosSystemHints = RegExp(
    r'(uikit|corefoundation|libsystem|libdispatch|libobjc|swiftui|cfnetwork)\b',
    caseSensitive: false,
  );
  if (iosSystemHints.hasMatch(lower) && !lower.contains('.swift') && !lower.contains('.m:')) {
    return const StackClarity(
      level: StackClarityLevel.systemFrameworkDominant,
      summaryForPrompt:
          '堆栈以 **iOS 系统框架符号**为主，未见明确应用内 .swift/.m 符号；请勿编造具体业务文件名，侧重排查思路与防御性修改。',
    );
  }

  if (lower.contains('.swift') || RegExp(r'\b\w+\s+\w+\s*\+\[\w+\s\w+\]').hasMatch(stack)) {
    return StackClarity(
      level: StackClarityLevel.businessLikely,
      summaryForPrompt: '堆栈中可见 **应用侧 Swift/ObjC** 相关符号，可尝试结合仓库搜索对应类/方法。',
      appFrameSamples: samples,
    );
  }

  return StackClarity(
    level: StackClarityLevel.unknown,
    summaryForPrompt: '堆栈格式未明确归类；请结合 JSON 其它字段保守分析，并列出需补充的符号化/日志信息。',
  );
}
