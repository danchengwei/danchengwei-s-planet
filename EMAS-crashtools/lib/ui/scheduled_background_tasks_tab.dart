import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/graytest_monitoring_task.dart';
import '../services/graytest_monitoring_service.dart';

/// 后台定时任务 Tab 页面
class ScheduledBackgroundTasksTab extends StatefulWidget {
  const ScheduledBackgroundTasksTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<ScheduledBackgroundTasksTab> createState() => _ScheduledBackgroundTasksTabState();
}

class _ScheduledBackgroundTasksTabState extends State<ScheduledBackgroundTasksTab>
    with SingleTickerProviderStateMixin {
  GraytestMonitoringService? _monitoringService;
  late TabController _tabController;
  bool _loading = false;
  List<GraytestMonitoringTask> _tasks = [];
  Map<String, List<TaskExecutionRecord>> _records = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    try {
      final config = widget.controller.config;
      _tasks = config.grayTestTasks
          .map((json) {
            try {
              return GraytestMonitoringTask.fromJson(json);
            } catch (e) {
              debugPrint('Failed to parse task: $e');
              return null;
            }
          })
          .whereType<GraytestMonitoringTask>()
          .toList();
      _records = {};
      setState(() {});
    } catch (e) {
      debugPrint('Error loading tasks: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: cs.primary),
      );
    }

    return Column(
      children: [
        // 顶部工具栏：全局控制 + 新增任务
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('后台定时任务', style: t.textTheme.titleLarge),
              Row(
                spacing: 12,
                children: [
                  _buildMonitoringToggle(cs),
                  FilledButton.tonalIcon(
                    onPressed: _showCreateTaskDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('新增任务'),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Tab 栏
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '任务管理'),
              Tab(text: '执行记录'),
            ],
          ),
        ),
        // Tab 内容
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildTasksPanel(),
              _buildRecordsPanel(),
            ],
          ),
        ),
      ],
    );
  }

  /// 后台任务开关和状态指示
  Widget _buildMonitoringToggle(ColorScheme cs) {
    // TODO: 从 service 获取实际状态
    final isMonitoring = widget.controller.config.grayTestMonitoringEnabled;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMonitoring ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        spacing: 8,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isMonitoring ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
          Text(
            isMonitoring ? '监听中' : '已停止',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          SizedBox(
            width: 40,
            height: 24,
            child: Switch(
              value: isMonitoring,
              onChanged: (v) async {
                widget.controller.config.grayTestMonitoringEnabled = v;
                if (_monitoringService != null) {
                  if (v) {
                    _monitoringService!.startMonitoring();
                  } else {
                    _monitoringService!.stopMonitoring();
                  }
                }
                await widget.controller.saveConfig(widget.controller.config);
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 任务列表面板
  Widget _buildTasksPanel() {
    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              '暂无任务',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: _showCreateTaskDialog,
              icon: const Icon(Icons.add),
              label: const Text('创建首个任务'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tasks.length,
      itemBuilder: (ctx, i) => _buildTaskCard(_tasks[i]),
    );
  }

  /// 任务卡片
  Widget _buildTaskCard(GraytestMonitoringTask task) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '版本: ${task.targetVersions.join(', ')}',
                        style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: task.enabled,
                  onChanged: (v) async {
                    if (_monitoringService != null) {
                      await _monitoringService!.setTaskEnabled(task.id, v);
                    }
                    // 同步本地状态
                    final idx = _tasks.indexWhere((t) => t.id == task.id);
                    if (idx >= 0) {
                      _tasks[idx] = _tasks[idx].copyWith(enabled: v);
                      await widget.controller.saveConfig(widget.controller.config);
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 12),
            Row(
              spacing: 8,
              children: [
                Chip(
                  label: Text(task.bizModule),
                  side: BorderSide(color: cs.outline),
                  backgroundColor: cs.surfaceContainerHighest,
                  deleteIconColor: cs.outline,
                ),
                Chip(
                  label: Text('检查频率: ${_formatInterval(task.checkIntervalSeconds)}'),
                  side: BorderSide(color: cs.outline),
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => _showEditTaskDialog(task),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑'),
                ),
                TextButton.icon(
                  onPressed: () => _confirmDeleteTask(task),
                  icon: const Icon(Icons.delete_outlined),
                  label: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 执行记录面板
  Widget _buildRecordsPanel() {
    final allRecords = _records.values.fold<List<TaskExecutionRecord>>(
      [],
      (prev, curr) => [...prev, ...curr],
    );
    allRecords.sort((a, b) => b.executedAt.compareTo(a.executedAt));

    if (allRecords.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              '暂无执行记录',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: allRecords.length,
      itemBuilder: (ctx, i) => _buildRecordCard(allRecords[i]),
    );
  }

  /// 执行记录卡片
  Widget _buildRecordCard(TaskExecutionRecord record) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    final statusColor = record.webhookStatus == 'sent'
        ? Colors.green
        : record.webhookStatus == 'pending'
            ? Colors.orange
            : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.issueTitle,
                        style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '版本: ${record.issueVersion} • 时间: ${_formatTime(record.executedAt)}',
                        style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    record.webhookStatus == 'sent'
                        ? '已发送'
                        : record.webhookStatus == 'pending'
                            ? '待发送'
                            : '发送失败',
                    style: t.textTheme.labelSmall?.copyWith(color: statusColor),
                  ),
                ),
              ],
            ),
            if (record.webhookError != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '错误: ${record.webhookError}',
                  style: t.textTheme.labelSmall?.copyWith(color: Colors.red),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 创建任务对话框
  void _showCreateTaskDialog() {
    _showTaskDialog(null);
  }

  /// 编辑任务对话框
  void _showEditTaskDialog(GraytestMonitoringTask task) {
    _showTaskDialog(task);
  }

  /// 任务对话框（新增/编辑）
  void _showTaskDialog(GraytestMonitoringTask? existingTask) {
    final isEdit = existingTask != null;
    final nameCtrl = TextEditingController(text: existingTask?.name ?? '');
    final webhookCtrl = TextEditingController(text: existingTask?.webhookUrl ?? '');
    final selectedVersions = <String>{...(existingTask?.targetVersions ?? [])};
    String selectedModule = existingTask?.bizModule ?? 'crash';
    int selectedInterval = existingTask?.checkIntervalSeconds ?? 3600;
    final intervalCtrl = TextEditingController(text: _formatInterval(selectedInterval));
    bool showCustomInterval = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(isEdit ? '编辑任务' : '创建新任务'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 任务名称
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '任务名称',
                      hintText: '如：v10.20 灰度监听',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 业务模块
                  DropdownButtonFormField<String>(
                    value: selectedModule,
                    decoration: const InputDecoration(
                      labelText: '业务模块',
                      border: OutlineInputBorder(),
                    ),
                    items: ['crash', 'anr', 'lag', 'custom'].map((m) {
                      return DropdownMenuItem(value: m, child: Text(m));
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) selectedModule = v;
                    },
                  ),
                  const SizedBox(height: 16),

                  // 检查间隔 - 快捷选择按钮
                  Text('检查间隔', style: Theme.of(ctx).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            selectedInterval = 3600;
                            intervalCtrl.text = _formatInterval(selectedInterval);
                            showCustomInterval = false;
                          });
                        },
                        child: const Text('1小时'),
                      ),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            selectedInterval = 10800;
                            intervalCtrl.text = _formatInterval(selectedInterval);
                            showCustomInterval = false;
                          });
                        },
                        child: const Text('3小时'),
                      ),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            selectedInterval = 18000;
                            intervalCtrl.text = _formatInterval(selectedInterval);
                            showCustomInterval = false;
                          });
                        },
                        child: const Text('5小时'),
                      ),
                      FilledButton.tonal(
                        onPressed: () {
                          setState(() {
                            showCustomInterval = !showCustomInterval;
                          });
                        },
                        child: Text(showCustomInterval ? '收起自定义' : '自定义'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (showCustomInterval)
                    TextField(
                      controller: intervalCtrl,
                      decoration: InputDecoration(
                        labelText: '自定义间隔',
                        hintText: '格式：数字 + 单位 (秒/分钟/小时) 如：30秒、5分钟、2小时',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        final seconds = _parseIntervalString(v);
                        if (seconds != null) {
                          selectedInterval = seconds;
                        }
                      },
                    ),
                  const SizedBox(height: 16),

                  // 目标版本
                  TextField(
                    decoration: InputDecoration(
                      labelText: '目标版本 (逗号分隔)',
                      hintText: '如：10.20.01, 10.20.02',
                      border: const OutlineInputBorder(),
                      helperText: '当前: ${selectedVersions.join(", ")}',
                    ),
                    onChanged: (v) {
                      selectedVersions
                        ..clear()
                        ..addAll(v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
                    },
                  ),
                  const SizedBox(height: 16),

                  // Webhook URL
                  TextField(
                    controller: webhookCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Webhook URL (必填)',
                      hintText: 'https://example.com/webhook',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final webhook = webhookCtrl.text.trim();

                if (name.isEmpty || webhook.isEmpty || selectedVersions.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('请填写所有必填项')),
                  );
                  return;
                }

                if (isEdit) {
                  final updated = existingTask!.copyWith(
                    name: name,
                    webhookUrl: webhook,
                    targetVersions: selectedVersions.toList(),
                    bizModule: selectedModule,
                    checkIntervalSeconds: selectedInterval,
                  );
                  final idx = _tasks.indexWhere((t) => t.id == updated.id);
                  if (idx >= 0) {
                    _tasks[idx] = updated;
                  }
                  if (_monitoringService != null) {
                    await _monitoringService!.updateTask(updated);
                  }
                } else {
                  final task = GraytestMonitoringTask(
                    id: 'task_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    enabled: true,
                    targetVersions: selectedVersions.toList(),
                    webhookUrl: webhook,
                    bizModule: selectedModule,
                    checkIntervalSeconds: selectedInterval,
                  );
                  _tasks.add(task);
                  if (_monitoringService != null) {
                    await _monitoringService!.addTask(task);
                  }
                }

                await widget.controller.saveConfig(widget.controller.config);
                setState(() {});
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(isEdit ? '保存' : '创建'),
            ),
          ],
        ),
      ),
    );
  }

  /// 确认删除任务
  void _confirmDeleteTask(GraytestMonitoringTask task) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('确定删除任务"${task.name}"吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              _tasks.removeWhere((t) => t.id == task.id);
              if (_monitoringService != null) {
                await _monitoringService!.deleteTask(task.id);
              }
              await widget.controller.saveConfig(widget.controller.config);
              setState(() {});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 解析间隔字符串（如"30秒"、"5分钟"、"2小时"）
  int? _parseIntervalString(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // 秒
    if (trimmed.endsWith('秒')) {
      final num = int.tryParse(trimmed.replaceAll('秒', '').trim());
      return num;
    }
    // 分钟
    if (trimmed.endsWith('分钟')) {
      final num = int.tryParse(trimmed.replaceAll('分钟', '').trim());
      return num != null ? num * 60 : null;
    }
    // 小时
    if (trimmed.endsWith('小时')) {
      final num = int.tryParse(trimmed.replaceAll('小时', '').trim());
      return num != null ? num * 3600 : null;
    }
    // 仅数字（默认为秒）
    return int.tryParse(trimmed);
  }

  String _formatInterval(int seconds) {
    if (seconds < 60) return '$seconds 秒';
    if (seconds < 3600) return '${seconds ~/ 60} 分钟';
    return '${seconds ~/ 3600} 小时';
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
