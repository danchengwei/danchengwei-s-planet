import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/llm_provider_presets.dart';
import '../models/tool_config.dart';

/// 全量配置：EMAS、控制台链接模板、大模型、Agent（GitLab 见侧栏「GitLab」页）。
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late TextEditingController _ak;
  late TextEditingController _sk;
  late TextEditingController _region;
  late TextEditingController _appKey;
  late TextEditingController _os;
  late TextEditingController _biz;
  late TextEditingController _emasName;
  late TextEditingController _console;
  late TextEditingController _consoleTpl;
  late TextEditingController _llmUrl;
  late TextEditingController _llmPathCtrl;
  late TextEditingController _llmKey;
  late TextEditingController _llmModel;
  late TextEditingController _llmSystem;
  String _llmPresetId = LlmProviderPreset.customId;
  late TextEditingController _agentWd;
  late TextEditingController _agentExe;
  late TextEditingController _agentMode;
  late TextEditingController _agentArgs;

  /// clipboard | claude_stdin | custom（与下方配置字段联动；已去掉 Cursor CLI 预设）。
  String _agentPreset = 'clipboard';

  /// 崩溃 Biz 下列表使用本地 Mock，便于无 AK 时预览 UI。
  bool _mockCrash = false;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    final c = widget.controller.config;
    _ak = TextEditingController(text: c.accessKeyId);
    _sk = TextEditingController(text: c.accessKeySecret);
    _region = TextEditingController(text: c.region);
    _appKey = TextEditingController(text: c.appKey);
    _os = TextEditingController(text: c.os);
    _biz = TextEditingController(text: c.bizModule);
    _emasName = TextEditingController(text: c.emasListNameQuery);
    _console = TextEditingController(text: c.consoleBaseUrl);
    _consoleTpl = TextEditingController(text: c.consoleIssueUrlTemplate);
    _llmUrl = TextEditingController(text: c.llmBaseUrl);
    var pid = c.llmProviderPresetId.trim();
    if (LlmProviderPreset.byId(pid) == null) pid = LlmProviderPreset.customId;
    _llmPresetId = pid;
    _llmPathCtrl = TextEditingController(text: c.effectiveLlmChatPath);
    _llmKey = TextEditingController(text: c.llmApiKey);
    _llmModel = TextEditingController(text: c.llmModel);
    _llmSystem = TextEditingController(text: c.llmSystemPrompt);
    _agentWd = TextEditingController(text: c.agentWorkDir);
    _agentExe = TextEditingController(text: c.agentExecutable);
    _agentMode = TextEditingController(text: c.agentMode);
    _agentArgs = TextEditingController(text: c.agentFixedArgs);
    _migrateLegacyCursorAgentConfig();
    _inferAgentPresetFromControllers();
    _mockCrash = c.emasUseMockCrashData;
  }

  /// 旧版 Cursor CLI（args）已移除，打开配置页时自动改为 Claude Code（stdin）。
  void _migrateLegacyCursorAgentConfig() {
    final m = _agentMode.text.trim().toLowerCase();
    final e = _agentExe.text.trim().toLowerCase();
    if (m == 'args' && e == 'cursor') {
      _agentMode.text = 'stdin';
      _agentExe.text = 'claude';
      _agentArgs.text = '[]';
    }
  }

  void _inferAgentPresetFromControllers() {
    final m = _agentMode.text.trim().toLowerCase();
    final e = _agentExe.text.trim().toLowerCase();
    if (m == 'clipboard' || (m.isEmpty && e.isEmpty)) {
      _agentPreset = 'clipboard';
      return;
    }
    if (m == 'stdin' && (e.isEmpty || e == 'claude')) {
      _agentPreset = 'claude_stdin';
      return;
    }
    // 旧版曾用 cursor + args，现统一走 Claude Code CLI
    if (m == 'args' && e == 'cursor') {
      _agentPreset = 'claude_stdin';
      return;
    }
    _agentPreset = 'custom';
  }

  void _applyAgentPreset(String preset) {
    switch (preset) {
      case 'clipboard':
        _agentMode.text = 'clipboard';
        _agentExe.text = '';
        _agentArgs.text = '[]';
        return;
      case 'claude_stdin':
        _agentMode.text = 'stdin';
        _agentExe.text = 'claude';
        _agentArgs.text = '[]';
        return;
      case 'custom':
        if (_agentMode.text.trim().isEmpty) _agentMode.text = 'stdin';
        if (_agentExe.text.trim().isEmpty) _agentExe.text = 'claude';
        if (_agentArgs.text.trim().isEmpty) _agentArgs.text = '[]';
        return;
      default:
        return;
    }
  }

  void _onAgentPresetChanged(String? v) {
    if (v == null) return;
    setState(() {
      _agentPreset = v;
      _applyAgentPreset(v);
    });
  }

  @override
  void dispose() {
    _ak.dispose();
    _sk.dispose();
    _region.dispose();
    _appKey.dispose();
    _os.dispose();
    _biz.dispose();
    _emasName.dispose();
    _console.dispose();
    _consoleTpl.dispose();
    _llmUrl.dispose();
    _llmPathCtrl.dispose();
    _llmKey.dispose();
    _llmModel.dispose();
    _llmSystem.dispose();
    _agentWd.dispose();
    _agentExe.dispose();
    _agentMode.dispose();
    _agentArgs.dispose();
    super.dispose();
  }

  void _onLlmPresetChanged(String? id) {
    if (id == null) return;
    setState(() {
      _llmPresetId = id;
      final p = LlmProviderPreset.byId(id);
      if (p == null) return;
      if (p.id != LlmProviderPreset.customId) {
        if (p.baseUrl.isNotEmpty) _llmUrl.text = p.baseUrl;
        if (p.defaultModel.isNotEmpty) _llmModel.text = p.defaultModel;
        _llmPathCtrl.text = p.chatPath;
      }
    });
  }

  Future<void> _pickAgentProjectDir() async {
    if (!mounted) return;
    final hint = _agentWd.text.trim();
    try {
      final path = await getDirectoryPath(
        confirmButtonText: '选择此文件夹',
        initialDirectory: hint.isEmpty ? null : hint,
      );
      if (!mounted) return;
      if (path != null && path.isNotEmpty) {
        setState(() => _agentWd.text = path);
      }
    } catch (e, st) {
      debugPrint('getDirectoryPath failed: $e\n$st');
    }
  }

  Future<void> _save() async {
    final cur = widget.controller.config;
    final next = ToolConfig(
      accessKeyId: _ak.text,
      accessKeySecret: _sk.text,
      region: _region.text,
      appKey: _appKey.text,
      os: _os.text,
      bizModule: _biz.text,
      emasListNameQuery: _emasName.text,
      consoleBaseUrl: _console.text,
      consoleIssueUrlTemplate: _consoleTpl.text,
      gitlabBaseUrl: cur.gitlabBaseUrl,
      gitlabToken: cur.gitlabToken,
      gitlabProjects: List<GitlabProjectBinding>.from(cur.gitlabProjects),
      gitlabRef: cur.gitlabRef,
      llmBaseUrl: _llmUrl.text,
      llmApiKey: _llmKey.text,
      llmModel: _llmModel.text,
      llmProviderPresetId: _llmPresetId,
      llmChatCompletionsPath: () {
        final preset = LlmProviderPreset.byId(_llmPresetId);
        if (_llmPresetId == LlmProviderPreset.customId) {
          final t = _llmPathCtrl.text.trim();
          return t.isEmpty ? 'v1/chat/completions' : t;
        }
        return preset?.chatPath ?? 'v1/chat/completions';
      }(),
      llmSystemPrompt: _llmSystem.text,
      agentWorkDir: _agentWd.text,
      agentExecutable: _agentExe.text,
      agentMode: _agentMode.text,
      agentFixedArgs: _agentArgs.text,
      wallpaperId: widget.controller.config.wallpaperId,
      uiPrimaryRailWidth: widget.controller.config.uiPrimaryRailWidth,
      uiWorkbenchSidebarWidth: widget.controller.config.uiWorkbenchSidebarWidth,
      mcpServers: Map<String, dynamic>.from(
        jsonDecode(jsonEncode(cur.mcpServers)) as Map,
      ),
      mcpExportIncludeById: Map<String, bool>.from(cur.mcpExportIncludeById),
      mcpGitlabInstallAck: cur.mcpGitlabInstallAck,
      emasUseMockCrashData: _mockCrash,
    );
    final sec = next.validateSecretEndpointsUseHttps();
    if (sec.isNotEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('无法保存'),
          content: Text(sec.join('\n')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定')),
          ],
        ),
      );
      return;
    }
    try {
      await widget.controller.saveConfig(next);
    } catch (e, st) {
      debugPrint('saveConfig failed: $e\n$st');
      if (!mounted) return;
      final cs = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '保存失败：$e',
            style: TextStyle(color: cs.onErrorContainer),
          ),
          backgroundColor: cs.errorContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '保存成功。配置已写入本机，下次打开将自动加载本次保存的内容。',
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final hasWallpaper = widget.controller.config.wallpaperId
            .trim()
            .isNotEmpty;
        final bodyFill = hasWallpaper
            ? cs.surface.withValues(alpha: 0.92)
            : cs.surface;
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('配置'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_rounded, size: 20),
                  label: const Text('保存'),
                ),
              ),
            ],
          ),
          body: ColoredBox(
            color: bodyFill,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _ConnectivityCard(controller: widget.controller),
                const SizedBox(height: 20),
                _settingsSection(
                  context,
                  icon: Icons.cloud_outlined,
                  title: '阿里云 EMAS',
                  children: [
                    _fieldReq(_ak, 'AccessKey ID'),
                    _fieldReq(_sk, 'AccessKey Secret', obscure: true),
                    _fieldReq(_region, 'Region', hintText: 'cn-shanghai'),
                    _fieldReq(_appKey, 'AppKey', hintText: '数字'),
                    _fieldReq(_os, 'Os', hintText: 'android / ios'),
                    _fieldReq(_biz, 'BizModule'),
                    _fieldOpt(
                      _emasName,
                      'GetIssues Name',
                      hintText: '可选，如 Android 包名 com.example.app',
                    ),
                    _fieldOpt(_console, '控制台 URL'),
                    _fieldOpt(_consoleTpl, '单条问题 URL 模板'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('崩溃列表 Mock 数据'),
                      subtitle: Text(
                        '开启后，工作台选中「崩溃」且 Biz 为 crash 时，一键获取使用本地假数据（含翻页）；详情仅对 mock_digest_* 生效。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      value: _mockCrash,
                      onChanged: (v) => setState(() => _mockCrash = v),
                    ),
                  ],
                ),
                _settingsSection(
                  context,
                  icon: Icons.psychology_outlined,
                  title: '大模型',
                  children: [
                    _styledDropdown<String>(
                      context,
                      value: _llmPresetId,
                      label: '服务商',
                      prefixIcon: Icons.storefront_outlined,
                      borderRadius: BorderRadius.circular(14),
                      dropdownColor: cs.surfaceContainerHigh,
                      items: [
                        for (final p in LlmProviderPreset.all)
                          DropdownMenuItem<String>(
                            value: p.id,
                            child: Text(p.label),
                          ),
                      ],
                      onChanged: _onLlmPresetChanged,
                    ),
                    _fieldOpt(_llmUrl, 'LLM Base URL'),
                    if (_llmPresetId == LlmProviderPreset.customId)
                      _fieldOpt(
                        _llmPathCtrl,
                        'Chat 路径',
                        hintText: 'v1/chat/completions',
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Chat 路径',
                            prefixIcon: Icon(
                              Icons.route_rounded,
                              size: 22,
                              color: cs.primary.withValues(alpha: 0.85),
                            ),
                            contentPadding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
                          ),
                          child: SelectableText(
                            LlmProviderPreset.byId(_llmPresetId)?.chatPath ?? '',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.onSurface),
                          ),
                        ),
                      ),
                    _fieldOpt(_llmKey, 'API Key', obscure: true),
                    _fieldOpt(_llmModel, '模型'),
                    _fieldOpt(
                      _llmSystem,
                      'System 提示词',
                      maxLines: 4,
                      helperText: '实际请求时会在末尾自动追加说明：优先通过用户本机 GitLab MCP 查仓库（与侧栏 MCP 导出一致）。',
                    ),
                  ],
                ),
                _settingsSection(
                  context,
                  icon: Icons.smart_toy_outlined,
                  title: 'Agent',
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextField(
                        controller: _agentWd,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: '工程目录',
                          prefixIcon: Icon(
                            Icons.folder_copy_outlined,
                            size: 22,
                            color: cs.primary.withValues(alpha: 0.85),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: _pickAgentProjectDir,
                          icon: const Icon(Icons.folder_open_rounded),
                          label: const Text('浏览目录'),
                        ),
                      ),
                    ),
                    _styledDropdown<String>(
                      context,
                      value: _agentPreset,
                      label: '启动方式',
                      prefixIcon: Icons.settings_ethernet_rounded,
                      borderRadius: BorderRadius.circular(14),
                      dropdownColor: cs.surfaceContainerHigh,
                      items: const [
                        DropdownMenuItem(value: 'clipboard', child: Text('剪贴板')),
                        DropdownMenuItem(value: 'claude_stdin', child: Text('Claude CLI（stdin）')),
                        DropdownMenuItem(value: 'custom', child: Text('自定义')),
                      ],
                      onChanged: _onAgentPresetChanged,
                    ),
                    if (_agentPreset == 'custom') ...[
                      _fieldOpt(_agentExe, '可执行文件'),
                      _fieldOpt(_agentMode, '模式'),
                      _fieldOpt(_agentArgs, '前置参数 JSON', maxLines: 2),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _settingsSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.42)),
        ),
        color: cs.surfaceContainerLow.withValues(alpha: 0.45),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.52),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 20, color: cs.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.15,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _styledDropdown<T>(
    BuildContext context, {
    required T value,
    required String label,
    required IconData prefixIcon,
    required BorderRadius borderRadius,
    required Color dropdownColor,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<T>(
        key: ValueKey<T>(value),
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(
            prefixIcon,
            size: 22,
            color: cs.primary.withValues(alpha: 0.85),
          ),
        ),
        borderRadius: borderRadius,
        dropdownColor: dropdownColor,
        elevation: 3,
        icon: Icon(Icons.keyboard_arrow_down_rounded, color: cs.primary),
        isExpanded: true,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.onSurface),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool obscure = false,
    int maxLines = 1,
    String? helperText,
    String? hintText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          helperText: helperText,
          helperMaxLines: 3,
          alignLabelWithHint: maxLines > 1,
          isDense: false,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        obscureText: obscure,
        maxLines: obscure ? 1 : maxLines,
        minLines: maxLines > 1 ? 2 : null,
      ),
    );
  }

  Widget _fieldReq(
    TextEditingController c,
    String label, {
    bool obscure = false,
    int maxLines = 1,
    String? helperText,
    String? hintText,
  }) {
    return _field(
      c,
      '$label（必填）',
      obscure: obscure,
      maxLines: maxLines,
      helperText: helperText,
      hintText: hintText,
    );
  }

  Widget _fieldOpt(
    TextEditingController c,
    String label, {
    bool obscure = false,
    int maxLines = 1,
    String? helperText,
    String? hintText,
  }) {
    return _field(
      c,
      '$label（可选）',
      obscure: obscure,
      maxLines: maxLines,
      helperText: helperText,
      hintText: hintText,
    );
  }
}

/// 配置页顶部：各服务连接状态与一键检测（保存下方字段后再测更准确）。
class _ConnectivityCard extends StatefulWidget {
  const _ConnectivityCard({required this.controller});

  final AppController controller;

  @override
  State<_ConnectivityCard> createState() => _ConnectivityCardState();
}

class _ConnectivityCardState extends State<_ConnectivityCard> {
  bool _busy = false;
  String? _emas;
  String? _gitlab;
  String? _llm;

  Future<void> _runAll() async {
    setState(() {
      _busy = true;
      _emas = _gitlab = _llm = null;
    });
    final e = await widget.controller.probeEmasConnection();
    final g = await widget.controller.probeGitlabConnection();
    final l = await widget.controller.probeLlmConnection();
    if (!mounted) return;
    setState(() {
      _emas = e;
      _gitlab = g;
      _llm = l;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.link, color: cs.primary),
                const SizedBox(width: 10),
                Text(
                  '连接状态',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '保存后可测连通性',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            _StatusLine(label: 'EMAS OpenAPI', text: _emas),
            const SizedBox(height: 8),
            _StatusLine(label: 'GitLab API', text: _gitlab),
            const SizedBox(height: 8),
            _StatusLine(label: '大模型', text: _llm),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _runAll,
              icon: _busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.onPrimary,
                      ),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: Text(_busy ? '检测中…' : '一键检测连接'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, this.text});

  final String label;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            t ?? '尚未检测',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: t == null ? cs.outline : cs.onSurface,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
