/// 堆栈中的应用代码位置
class ApplicationCodeLocation {
  ApplicationCodeLocation({
    required this.className,
    required this.methodName,
    required this.fileName,
    required this.lineNumber,
  });

  final String className;
  final String methodName;
  final String fileName;
  final int lineNumber;

  @override
  String toString() => '$className.$methodName($fileName:$lineNumber)';
}

/// 系统调用链条目
class SystemCallEntry {
  SystemCallEntry({
    required this.className,
    required this.methodName,
  });

  final String className;
  final String methodName;

  @override
  String toString() => '$className.$methodName';
}

/// Native 库信息
class NativeLibrary {
  NativeLibrary({
    required this.name,
    required this.address,
    this.functionName,
  });

  final String name;      // e.g., libhwui.so
  final String address;   // 内存地址
  final String? functionName;

  @override
  String toString() => '$name($address)';
}

/// 结构化堆栈信息
class StructuredStackInfo {
  StructuredStackInfo({
    required this.rawStack,
    this.crashType = 'Unknown',
    this.exceptionName,
    this.applicationCodeLocation,
    this.systemCallChain = const [],
    this.nativeLibraries = const [],
    this.javaClasses = const [],
    this.lineCount = 0,
  });

  /// 原始堆栈文本
  final String rawStack;

  /// 崩溃类型（Java/Native/Unknown）
  final String crashType;

  /// 异常名称（如果有）
  final String? exceptionName;

  /// 应用代码位置（堆栈指向的最相关的应用代码）
  final ApplicationCodeLocation? applicationCodeLocation;

  /// 系统调用链（从上到下）
  final List<SystemCallEntry> systemCallChain;

  /// 涉及的 Native 库
  final List<NativeLibrary> nativeLibraries;

  /// 涉及的 Java 类
  final List<String> javaClasses;

  /// 堆栈行数
  final int lineCount;

  Map<String, dynamic> toJson() => {
        'crashType': crashType,
        'exceptionName': exceptionName,
        'applicationCodeLocation': applicationCodeLocation?.toString(),
        'systemCallChainCount': systemCallChain.length,
        'nativeLibrariesCount': nativeLibraries.length,
        'javaClassesCount': javaClasses.length,
        'lineCount': lineCount,
      };
}

/// 堆栈解析器
class StackParser {
  /// 解析堆栈并提取结构化信息
  static StructuredStackInfo parse(String stackTrace) {
    final lines = stackTrace.split('\n');
    final trimmedLines = lines.where((l) => l.trim().isNotEmpty).toList();

    // 检测崩溃类型和异常名称
    final (crashType, exceptionName) = _detectCrashType(stackTrace);

    // 提取应用代码位置（第一个应用代码行）
    ApplicationCodeLocation? appCodeLoc;
    for (final line in trimmedLines) {
      final parsed = _parseJavaLine(line);
      if (parsed != null && _isApplicationCode(parsed.className)) {
        appCodeLoc = parsed;
        break;
      }
    }

    // 提取系统调用链（前 5 个系统调用）
    final systemCalls = <SystemCallEntry>[];
    for (final line in trimmedLines.take(20)) {
      final entry = _parseSystemCall(line);
      if (entry != null && systemCalls.length < 5) {
        systemCalls.add(entry);
      }
    }

    // 提取 Native 库
    final nativeLibs = <NativeLibrary>[];
    for (final line in trimmedLines) {
      final lib = _parseNativeLib(line);
      if (lib != null) {
        nativeLibs.add(lib);
      }
    }

    // 提取 Java 类
    final javaClasses = <String>{};
    for (final line in trimmedLines) {
      final parsed = _parseJavaLine(line);
      if (parsed != null) {
        javaClasses.add(parsed.className);
      }
    }

    return StructuredStackInfo(
      rawStack: stackTrace,
      crashType: crashType,
      exceptionName: exceptionName,
      applicationCodeLocation: appCodeLoc,
      systemCallChain: systemCalls,
      nativeLibraries: nativeLibs,
      javaClasses: javaClasses.toList(),
      lineCount: trimmedLines.length,
    );
  }

  /// 检测崩溃类型和异常名称
  static (String, String?) _detectCrashType(String stack) {
    final lower = stack.toLowerCase();

    // 检测异常名称
    String? exceptionName;
    final exceptionPattern = RegExp(r'([A-Za-z_][A-Za-z0-9_.]*(?:Exception|Error|Violation))');
    final match = exceptionPattern.firstMatch(stack);
    if (match != null) {
      exceptionName = match.group(1);
    }

    // 检测类型
    if (lower.contains('exception') || lower.contains('java.') || exceptionName != null) {
      return ('Java', exceptionName);
    }
    if (lower.contains('signal') || lower.contains('sigsegv') || lower.contains('sigabrt')) {
      return ('Native', exceptionName);
    }

    return ('Unknown', exceptionName);
  }

  /// 解析 Java 堆栈行（at 格式）
  static ApplicationCodeLocation? _parseJavaLine(String line) {
    // 格式: at com.example.ClassName.methodName(FileName.java:123)
    final pattern = RegExp(
      r'at\s+([\w.$]+)\.([\w<>$]+)\(([\w.]+):?(\d+)?\)',
    );
    final match = pattern.firstMatch(line);
    if (match != null) {
      return ApplicationCodeLocation(
        className: match.group(1) ?? '',
        methodName: match.group(2) ?? '',
        fileName: match.group(3) ?? '',
        lineNumber: int.tryParse(match.group(4) ?? '0') ?? 0,
      );
    }
    return null;
  }

  /// 解析系统调用
  static SystemCallEntry? _parseSystemCall(String line) {
    // 寻找 android.* 或 java.* 的系统类
    final pattern = RegExp(r'at\s+(android|java|sun|libcore)[.\w$]*\.([\w<>$]+)');
    final match = pattern.firstMatch(line);
    if (match != null) {
      final className = line.substring(
        line.indexOf('at ') + 3,
        line.indexOf('.${match.group(2)!}') + 1,
      ).trimRight();
      return SystemCallEntry(
        className: className,
        methodName: match.group(2) ?? '',
      );
    }
    return null;
  }

  /// 解析 Native 库信息
  static NativeLibrary? _parseNativeLib(String line) {
    // 格式: #0  0x00001234 in functionName /path/to/libxxx.so
    final pattern = RegExp(
      r'(lib[\w.]+\.so)\s*\(0x([\da-f]+)',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(line);
    if (match != null) {
      return NativeLibrary(
        name: match.group(1) ?? '',
        address: '0x${match.group(2)}',
      );
    }
    return null;
  }

  /// 判断是否为应用代码（非系统/框架）
  static bool _isApplicationCode(String className) {
    final excludedPrefixes = [
      'java.',
      'android.',
      'androidx.',
      'com.android.',
      'libcore.',
      'sun.',
      'org.chromium.',
      'kotlin.',
    ];

    for (final prefix in excludedPrefixes) {
      if (className.startsWith(prefix)) {
        return false;
      }
    }

    return true;
  }

  /// 提取文件路径列表（用于源码查找）
  static List<String> extractFileNames(String stackTrace) {
    final files = <String>{};
    final pattern = RegExp(r'\(([A-Za-z_][\w.]*\.java):');
    for (final match in pattern.allMatches(stackTrace)) {
      final fileName = match.group(1);
      if (fileName != null) {
        files.add(fileName);
      }
    }
    return files.toList();
  }

  /// 提取函数名列表（用于代码查找）
  static List<String> extractFunctionNames(String stackTrace) {
    final functions = <String>{};
    final pattern = RegExp(r'at\s+[\w.$]+\.([<\w>$]+)\(');
    for (final match in pattern.allMatches(stackTrace)) {
      final func = match.group(1);
      if (func != null && func != '<init>' && func != '<clinit>') {
        functions.add(func);
      }
    }
    return functions.toList();
  }
}
