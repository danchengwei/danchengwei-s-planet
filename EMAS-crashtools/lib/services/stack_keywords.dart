/// 从堆栈中提取可用于 GitLab 搜索的关键词（路径片段、类名等）。
List<String> extractStackKeywords(String? stack, {int maxCount = 8}) {
  if (stack == null || stack.trim().isEmpty) return const [];
  final seen = <String>{};
  final out = <String>[];

  void add(String s) {
    final t = s.trim();
    if (t.length < 4) return;
    if (seen.contains(t)) return;
    seen.add(t);
    out.add(t);
  }

  // Java/Kotlin: at com.foo.Bar.method(File.java:12)
  final atRe = RegExp(r'at\s+([\w$.]+)\.(\w+)\s*\([^)]+\)');
  for (final m in atRe.allMatches(stack)) {
    add(m.group(1)!.split('.').last);
    add(m.group(1)!);
  }

  // 文件路径
  final pathRe = RegExp(
    r'([\w/\\.-]+\.(?:java|kt|kts|dart|swift|c|cpp|cc|h|m|mm|tsx?|jsx?)(?::\d+)?)',
    caseSensitive: false,
  );
  for (final m in pathRe.allMatches(stack)) {
    final p = m.group(1)!;
    add(p.split(RegExp(r'[/\\]')).last);
    if (p.contains('/')) add(p);
  }

  // 简单 token（大写字母开头的 Kotlin/Java 类名）
  final clsRe = RegExp(r'\b([A-Z][\w]{2,})\b');
  for (final m in clsRe.allMatches(stack)) {
    add(m.group(1)!);
  }

  return out.take(maxCount).toList();
}
