import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/mcp_config_defaults.dart';
import '../models/tool_config.dart';
import '../services/mcp_brew_gitlab_service.dart';

class _GitRepoRow {
  _GitRepoRow({String projectId = '', String repoName = ''})
      : projectIdCtrl = TextEditingController(text: projectId),
        repoNameCtrl = TextEditingController(text: repoName);

  final TextEditingController projectIdCtrl;
  final TextEditingController repoNameCtrl;

  void dispose() {
    projectIdCtrl.dispose();
    repoNameCtrl.dispose();
  }
}

/// 当前业务项目的 GitLab API 配置（与 [SettingsTab] 中其它项独立成页，仍写入同一 [ToolConfig]）。
class GitLabSettingsTab extends StatefulWidget {
  const GitLabSettingsTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<GitLabSettingsTab> createState() => _GitLabSettingsTabState();
}

class _GitLabSettingsTabState extends State<GitLabSettingsTab> {
  late TextEditingController _glUrl;
  late TextEditingController _glToken;
  late TextEditingController _glRef;
  late String _boundProjectId;
  final List<_GitRepoRow> _repoRows = [];

  @override
  void initState() {
    super.initState();
    _glUrl = TextEditingController();
    _glToken = TextEditingController();
    _glRef = TextEditingController();
    _boundProjectId = widget.controller.activeProject.id;
    _bindGitlabFromConfig();
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    final id = widget.controller.activeProject.id;
    if (!mounted || id == _boundProjectId) return;
    setState(() {
      _boundProjectId = id;
      _bindGitlabFromConfig();
    });
  }

  void _disposeRepoRows() {
    for (final r in _repoRows) {
      r.dispose();
    }
    _repoRows.clear();
  }

  void _bindGitlabFromConfig() {
    final c = widget.controller.config;
    _glUrl.text = c.gitlabBaseUrl;
    _glToken.text = c.gitlabToken;
    final r = c.gitlabRef.trim();
    _glRef.text = r.isEmpty ? 'main' : r;
    _disposeRepoRows();
    final list = c.gitlabBindingsResolved;
    if (list.isEmpty) {
      _repoRows.add(_GitRepoRow());
    } else {
      for (final b in list) {
        _repoRows.add(_GitRepoRow(projectId: b.projectId, repoName: b.repoName));
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _disposeRepoRows();
    _glUrl.dispose();
    _glToken.dispose();
    _glRef.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final projects = _repoRows
        .map(
          (r) => GitlabProjectBinding(
            projectId: r.projectIdCtrl.text.trim(),
            repoName: r.repoNameCtrl.text.trim(),
          ),
        )
        .where((b) => b.projectId.isNotEmpty)
        .toList();
    final base = widget.controller.config.toJson();
    base['gitlabBaseUrl'] = _glUrl.text;
    base['gitlabToken'] = _glToken.text;
    base['gitlabProjects'] = projects.map((e) => e.toJson()).toList();
    base['gitlabProjectId'] = projects.isNotEmpty ? projects.first.projectId : '';
    final ref = _glRef.text.trim();
    base['gitlabRef'] = ref.isEmpty ? 'main' : ref;
    final next = ToolConfig.fromJson(base);
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
      String? brewExe;
      if (McpBrewGitlabService.platformMayUseBrew &&
          await McpBrewGitlabService.hasBrew() &&
          await McpBrewGitlabService.isFormulaInstalled()) {
        brewExe = await McpBrewGitlabService.resolveExecutablePath();
      }
      final merged = McpConfigDefaults.autoMergedMcpServersForSave(
        currentMcpServers: next.mcpServers,
        gitlabToken: next.gitlabToken,
        gitlabBaseUrl: next.gitlabBaseUrl,
        gitlabBrewExecutable: brewExe,
      );
      final base = next.toJson();
      base['mcpServers'] = merged;
      await widget.controller.saveConfig(ToolConfig.fromJson(base));
    } catch (e, st) {
      debugPrint('saveConfig (GitLab) failed: $e\n$st');
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
          '保存成功。GitLab 已写入本机；工作区 MCP 已合并 Token（默认仅持久化 gitlab；写入 Cursor 时会带上内置 Cursor / Claude）。',
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final hasWallpaper = widget.controller.config.wallpaperId.trim().isNotEmpty;
        final bodyFill = hasWallpaper ? cs.surface.withValues(alpha: 0.92) : cs.surface;
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('GitLab'),
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
                Text(
                  '当前项目：${widget.controller.activeProjectName}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'GitLab 无需在后台预先关联模块或建索引；具备权限的 Token + 项目 ID 即可调 API。'
                  '令牌建议在「个人设置 → Access Tokens」勾选 read_api、read_repository。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '检索等价于官方：GET …/api/v4/projects/项目ID/search?scope=blobs&search=关键词（PRIVATE-TOKEN）。'
                  '本工具用返回的文件名、路径与代码片段，并拉取该路径最近提交；不调用 files/…/raw 取全文。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '同一业务项目下可配置多组「仓库名 → Project Id」；堆栈检索会按列表**从上到下**依次搜索各仓库并合并命中（仓库名仅用于界面与提示词区分来源）。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 20),
                _GitlabConnectivityStrip(controller: widget.controller),
                const SizedBox(height: 20),
                _gitlabSection(
                  context,
                  children: [
                    _fieldOpt(_glUrl, 'Base URL', hintText: 'https://gitlab.example.com'),
                    _fieldOpt(
                      _glToken,
                      'Private Token',
                      obscure: true,
                      helperText: '请求头 PRIVATE-TOKEN；建议权限 read_api、read_repository',
                    ),
                    _fieldOpt(_glRef, 'Ref', hintText: 'main / develop'),
                    const SizedBox(height: 8),
                    Text(
                      '仓库列表',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...List<Widget>.generate(_repoRows.length, (i) => _repoRowTile(context, i)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _repoRows.add(_GitRepoRow())),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('添加仓库'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _gitlabSection(BuildContext context, {required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
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
                  child: Icon(Icons.code_rounded, size: 20, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '实例与多仓库',
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
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool obscure = false,
    int maxLines = 1,
    String? hintText,
    String? helperText,
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        obscureText: obscure,
        maxLines: obscure ? 1 : maxLines,
        minLines: maxLines > 1 ? 2 : null,
      ),
    );
  }

  Widget _fieldOpt(
    TextEditingController c,
    String label, {
    bool obscure = false,
    int maxLines = 1,
    String? hintText,
    String? helperText,
  }) {
    return _field(
      c,
      '$label（可选）',
      obscure: obscure,
      maxLines: maxLines,
      hintText: hintText,
      helperText: helperText,
    );
  }

  Widget _repoRowTile(BuildContext context, int index) {
    final row = _repoRows[index];
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  controller: row.repoNameCtrl,
                  decoration: const InputDecoration(
                    labelText: '仓库名（展示用）',
                    hintText: '如 android-shell',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 6,
                child: TextField(
                  controller: row.projectIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Project Id',
                    hintText: '数字或 group%2Fproject',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              IconButton(
                tooltip: '删除此行',
                onPressed: _repoRows.length <= 1
                    ? null
                    : () {
                        setState(() {
                          row.dispose();
                          _repoRows.removeAt(index);
                        });
                      },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 仅检测 GitLab API（保存后再测更准确）。
class _GitlabConnectivityStrip extends StatefulWidget {
  const _GitlabConnectivityStrip({required this.controller});

  final AppController controller;

  @override
  State<_GitlabConnectivityStrip> createState() => _GitlabConnectivityStripState();
}

class _GitlabConnectivityStripState extends State<_GitlabConnectivityStrip> {
  bool _busy = false;
  String? _gitlab;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _gitlab = null;
    });
    final g = await widget.controller.probeGitlabConnection();
    if (!mounted) return;
    setState(() {
      _gitlab = g;
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
                  'GitLab 连接',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _gitlab ?? '尚未检测',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _gitlab == null ? cs.outline : cs.onSurface,
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _run,
              icon: _busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    )
                  : const Icon(Icons.wifi_tethering, size: 20),
              label: Text(_busy ? '检测中…' : '检测 GitLab API'),
            ),
          ],
        ),
      ),
    );
  }
}
