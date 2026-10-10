import 'package:flutter/material.dart';

import '../ink/pen_palette.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({required this.load, required this.save, super.key});

  final Future<PenPalette> Function() load;
  final Future<void> Function(PenPalette palette) save;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  PenPalette? _palette;

  @override
  void initState() {
    super.initState();
    widget.load().then((palette) {
      if (mounted) {
        setState(() => _palette = palette);
      }
    });
  }

  Future<void> _update(PenPalette palette) async {
    setState(() => _palette = palette);
    await widget.save(palette);
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: palette == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _CountTile(
                  label: '尺寸数量',
                  count: palette.widths.length,
                  onChanged: (count) => _update(palette.setWidthCount(count)),
                ),
                _CountTile(
                  label: '颜色数量',
                  count: palette.colors.length,
                  onChanged: (count) => _update(palette.setColorCount(count)),
                ),
                _CountTile(
                  label: '虚实数量',
                  count: palette.dashes.length,
                  onChanged: (count) => _update(palette.setDashCount(count)),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    '数量减少时，从末尾删掉多余的预设，删掉的不能恢复。新的尺寸是 3，新的颜色是白色，新的虚实是纯实线。',
                  ),
                ),
              ],
            ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.label,
    required this.count,
    required this.onChanged,
  });

  final String label;
  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '减少$label',
            onPressed: count <= PenPalette.minSlots
                ? null
                : () => onChanged(count - 1),
            icon: const Icon(Icons.remove),
          ),
          Text('$count'),
          IconButton(
            tooltip: '增加$label',
            onPressed: count >= PenPalette.maxSlots
                ? null
                : () => onChanged(count + 1),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
