import 'package:flutter/material.dart';

import '../ink/pen_palette.dart';
import '../input/stylus_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.load,
    required this.save,
    required this.loadStylus,
    required this.saveStylus,
    super.key,
  });

  final Future<PenPalette> Function() load;
  final Future<void> Function(PenPalette palette) save;
  final Future<StylusPreferences> Function() loadStylus;
  final Future<void> Function(StylusPreferences preferences) saveStylus;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  PenPalette? _palette;
  StylusPreferences _stylus = StylusPreferences.initial;

  @override
  void initState() {
    super.initState();
    widget.load().then((palette) {
      if (mounted) {
        setState(() => _palette = palette);
      }
    });
    widget.loadStylus().then((preferences) {
      if (mounted) {
        setState(() => _stylus = preferences);
      }
    });
  }

  Future<void> _saveStylus(StylusPreferences preferences) async {
    setState(() => _stylus = preferences);
    await widget.saveStylus(preferences);
  }

  String _doubleTapLabel(DoubleTapAction action) {
    return switch (action) {
      DoubleTapAction.eraser => '切换橡皮',
      DoubleTapAction.off => '关闭',
    };
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
                SwitchListTile(
                  title: const Text('套索震动'),
                  subtitle: const Text('手写笔支持震动时，圈选移动中轻震。默认打开。'),
                  value: _stylus.selectionHaptic,
                  onChanged: (value) => _saveStylus(
                    _stylus.copyWith(selectionHaptic: value),
                  ),
                ),
                ListTile(
                  title: const Text('敲击两下'),
                  subtitle: Text(_doubleTapLabel(_stylus.doubleTap)),
                  trailing: DropdownButton<DoubleTapAction>(
                    value: _stylus.doubleTap,
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      _saveStylus(_stylus.copyWith(doubleTap: value));
                    },
                    items: const [
                      DropdownMenuItem(
                        value: DoubleTapAction.eraser,
                        child: Text('切换橡皮'),
                      ),
                      DropdownMenuItem(
                        value: DoubleTapAction.off,
                        child: Text('关闭'),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    '手写笔支持敲击时，敲两下生效。切换橡皮：不是橡皮就换成橡皮，已经是橡皮就回到之前的工具，没有之前的工具就回到钢笔。',
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
