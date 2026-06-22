import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'theme_colors.dart';

/// 问题列表页面 - 显示 Top N 崩溃和 ANR
class IssuesListPage extends StatefulWidget {
  const IssuesListPage({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onOpenSettings,
  });

  final AppController controller;
  final VoidCallback onBack;
  final VoidCallback onOpenSettings;

  @override
  State<IssuesListPage> createState() => _IssuesListPageState();
}

class _IssuesListPageState extends State<IssuesListPage> {
  String _selectedType = 'crash'; // crash, anr, lag, custom

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeColors.lightGray,
      appBar: AppBar(
        title: const Text('📊 EMAS 问题列表'),
        backgroundColor: Colors.white,
        elevation: 1,
        foregroundColor: ThemeColors.textBlack,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: Column(
        children: [
          // 问题类型选择
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _TypeChip(
                  label: '🔴 Crash',
                  selected: _selectedType == 'crash',
                  onTap: () => setState(() => _selectedType = 'crash'),
                ),
                const SizedBox(width: 8),
                _TypeChip(
                  label: '🟡 ANR',
                  selected: _selectedType == 'anr',
                  onTap: () => setState(() => _selectedType = 'anr'),
                ),
                const SizedBox(width: 8),
                _TypeChip(
                  label: '🟠 Lag',
                  selected: _selectedType == 'lag',
                  onTap: () => setState(() => _selectedType = 'lag'),
                ),
                const SizedBox(width: 8),
                _TypeChip(
                  label: '⚪ Custom',
                  selected: _selectedType == 'custom',
                  onTap: () => setState(() => _selectedType = 'custom'),
                ),
              ],
            ),
          ),
          // 问题列表
          Expanded(
            child: _buildIssuesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildIssuesList() {
    // 模拟数据
    final issues = [
      _Issue(
        name: 'NullPointerException',
        count: 1000,
        devices: 500,
        errorRate: 0.05,
        version: '1.0',
      ),
      _Issue(
        name: 'ArrayIndexOutOfBoundsException',
        count: 800,
        devices: 400,
        errorRate: 0.04,
        version: '1.1',
      ),
      _Issue(
        name: 'IllegalStateException',
        count: 600,
        devices: 300,
        errorRate: 0.03,
        version: '1.0',
      ),
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: issues.length,
      itemBuilder: (context, index) {
        final issue = issues[index];
        return _IssueCard(
          issue: issue,
          onTap: () {
            // TODO: 进入问题详情页
          },
        );
      },
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? ThemeColors.primaryGreen : ThemeColors.borderGray,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : ThemeColors.textGray,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({
    required this.issue,
    required this.onTap,
  });

  final _Issue issue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(
          color: ThemeColors.borderGray,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          issue.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: ThemeColors.textBlack,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '首现版本: ${issue.version}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: ThemeColors.textGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  _StatItem(label: '次数', value: '${issue.count}'),
                  const SizedBox(width: 16),
                  _StatItem(label: '设备', value: '${issue.devices}'),
                  const SizedBox(width: 16),
                  _StatItem(
                    label: '率',
                    value: '${(issue.errorRate * 100).toStringAsFixed(1)}%',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeColors.primaryGreen,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 36),
                ),
                onPressed: onTap,
                child: const Text('查看详情'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: ThemeColors.primaryGreen,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: ThemeColors.textGray,
          ),
        ),
      ],
    );
  }
}

class _Issue {
  final String name;
  final int count;
  final int devices;
  final double errorRate;
  final String version;

  _Issue({
    required this.name,
    required this.count,
    required this.devices,
    required this.errorRate,
    required this.version,
  });
}
