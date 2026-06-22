import 'package:flutter/material.dart';

/// 版本筛选组件（输入框样式 + 下拉菜单）
class VersionFilterWidget extends StatefulWidget {
  final List<String> versions;
  final String? selectedVersion;
  final ValueChanged<String?> onVersionChanged;
  final bool isLoading;

  const VersionFilterWidget({
    super.key,
    required this.versions,
    this.selectedVersion,
    required this.onVersionChanged,
    this.isLoading = false,
  });

  @override
  State<VersionFilterWidget> createState() => _VersionFilterWidgetState();
}

class _VersionFilterWidgetState extends State<VersionFilterWidget> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.selectedVersion);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(VersionFilterWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedVersion != widget.selectedVersion) {
      _controller.text = widget.selectedVersion ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showVersionMenu(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);

    showMenu<String?>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + renderBox.size.height + 8,
        offset.dx + renderBox.size.width,
        0,
      ),
      items: [
        PopupMenuItem<String?>(
          value: null,
          child: Text(
            '不筛选版本',
            style: textTheme.bodyMedium?.copyWith(
              color: widget.selectedVersion == null ? cs.primary : null,
              fontWeight: widget.selectedVersion == null ? FontWeight.w600 : null,
            ),
          ),
        ),
        ...widget.versions.map((version) {
          return PopupMenuItem<String?>(
            value: version,
            child: Text(
              version,
              style: textTheme.bodyMedium?.copyWith(
                color: widget.selectedVersion == version ? cs.primary : null,
                fontWeight: widget.selectedVersion == version ? FontWeight.w600 : null,
              ),
            ),
          );
        }),
      ],
      elevation: 8,
    ).then((value) {
      if (value != null || value == null) {
        widget.onVersionChanged(value);
        _controller.text = value ?? '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (widget.isLoading) {
      return Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(cs.primary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '加载版本中...',
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: () => _showVersionMenu(context),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        readOnly: true,
        onTap: () => _showVersionMenu(context),
        decoration: InputDecoration(
          hintText: '选择版本',
          hintStyle: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          prefixIcon: Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
          suffixIcon: widget.selectedVersion != null
              ? IconButton(
                  icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
                  onPressed: () {
                    widget.onVersionChanged(null);
                    _controller.text = '';
                  },
                )
              : Icon(Icons.arrow_drop_down, size: 20, color: cs.onSurfaceVariant),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: cs.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: cs.primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        style: textTheme.bodyMedium,
      ),
    );
  }
}
