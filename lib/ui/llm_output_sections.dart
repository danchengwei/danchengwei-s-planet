import 'package:flutter/material.dart';

/// 解析大模型返回的 Markdown 二级标题，映射到「原因 / 修复 / 代码」等卡片。
class ParsedLlmSection {
  const ParsedLlmSection({required this.title, required this.body});

  final String title;
  final String body;
}

/// 将 `## 标题` 分段；无法识别的正文放在 [preamble]。
class LlmOutputParseResult {
  const LlmOutputParseResult({required this.preamble, required this.sections});

  final String preamble;
  final List<ParsedLlmSection> sections;
}

LlmOutputParseResult parseLlmMarkdownSections(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return const LlmOutputParseResult(preamble: '', sections: []);
  }
  final header = RegExp(r'^##\s+(.+)$', multiLine: true);
  final matches = header.allMatches(text).toList();
  if (matches.isEmpty) {
    return LlmOutputParseResult(preamble: text, sections: const []);
  }
  final sections = <ParsedLlmSection>[];
  final preamble = text.substring(0, matches.first.start).trim();
  for (var i = 0; i < matches.length; i++) {
    final m = matches[i];
    final title = m.group(1)?.trim() ?? '章节';
    final start = m.end;
    final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
    final body = text.substring(start, end).trim();
    if (body.isNotEmpty) {
      sections.add(ParsedLlmSection(title: title, body: body));
    }
  }
  return LlmOutputParseResult(preamble: preamble, sections: sections);
}

/// 根据标题关键字选择图标与强调色（Material 色调）。
({IconData icon, Color? tint}) iconForSectionTitle(String title) {
  final t = title.toLowerCase();
  if (t.contains('原因') || t.contains('根因') || t.contains('分析')) {
    return (icon: Icons.psychology_outlined, tint: null);
  }
  if (t.contains('修复') || t.contains('方案') || t.contains('建议')) {
    return (icon: Icons.build_outlined, tint: null);
  }
  if (t.contains('代码') || t.contains('变更') || t.contains('diff') || t.contains('补丁')) {
    return (icon: Icons.code_outlined, tint: null);
  }
  if (t.contains('验证') || t.contains('测试')) {
    return (icon: Icons.fact_check_outlined, tint: null);
  }
  return (icon: Icons.article_outlined, tint: null);
}

/// 分段展示 AI 输出；无 ## 时整段放入单卡片。
Widget buildLlmSectionCards(BuildContext context, String raw) {
  final theme = Theme.of(context);
  final parsed = parseLlmMarkdownSections(raw);
  final children = <Widget>[];

  if (parsed.preamble.isNotEmpty) {
    children.add(_SectionCard(
      title: '摘要',
      icon: Icons.notes_outlined,
      child: SelectableText(parsed.preamble, style: theme.textTheme.bodyLarge?.copyWith(height: 1.45)),
    ));
  }

  for (final s in parsed.sections) {
    final meta = iconForSectionTitle(s.title);
    final low = s.title.toLowerCase();
    final mono = low.contains('代码') || low.contains('变更') || low.contains('diff') || low.contains('补丁');
    children.add(
      _SectionCard(
        title: s.title,
        icon: meta.icon,
        child: SelectableText(
          s.body,
          style: theme.textTheme.bodyLarge?.copyWith(
            height: 1.45,
            fontFamily: mono ? 'monospace' : null,
          ),
        ),
      ),
    );
  }

  if (children.isEmpty) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        '暂无分析内容；在列表中点「查看」将自动分析，或在详情页点击「生成 AI 分析」',
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        children[i],
      ],
    ],
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
