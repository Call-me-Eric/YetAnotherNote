import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ink/pen_palette.dart';
import '../ink/stroke.dart';
import '../input/finger.dart';

class PenPresetTarget {
  const PenPresetTarget(this.rect, this.onLong);

  final Rect rect;
  final VoidCallback onLong;
}

class PenPresetBar extends StatelessWidget {
  const PenPresetBar({
    required this.palette,
    required this.onChanged,
    super.key,
  });

  final PenPalette palette;
  final ValueChanged<PenPalette> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('pen-presets'),
      height: 64,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < palette.widths.length; index++)
              _SlotPress(
                key: ValueKey('pen-width-$index'),
                selected: index == palette.widthIndex,
                onShort: () => onChanged(palette.selectWidth(index)),
                onLong: () => _editWidth(context, index),
                child: _WidthMark(width: palette.widths[index]),
              ),
            const _GroupDivider(),
            for (var index = 0; index < palette.colors.length; index++)
              _SlotPress(
                key: ValueKey('pen-color-$index'),
                selected: index == palette.colorIndex,
                onShort: () => onChanged(palette.selectColor(index)),
                onLong: () => _editColor(context, index),
                child: _ColorMark(color: palette.colors[index]),
              ),
            const _GroupDivider(),
            for (var index = 0; index < palette.dashes.length; index++)
              _SlotPress(
                key: ValueKey('pen-dash-$index'),
                selected: index == palette.dashIndex,
                onShort: () => onChanged(palette.selectDash(index)),
                onLong: () => _editDash(context, index),
                child: _DashSample(
                  dash: palette.dashes[index],
                  color: Color(palette.color),
                  width: palette.width.clamp(1, 6),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editWidth(BuildContext context, int index) async {
    onChanged(palette.selectWidth(index));
    var width = palette.widths[index];
    await showDialog<void>(
      context: context,
      builder: (context) => _WidthDialog(
        color: Color(palette.color),
        width: width,
        onChanged: (value) {
          width = value;
          onChanged(palette.selectWidth(index).updateWidth(index, value));
        },
      ),
    );
  }

  Future<void> _editColor(BuildContext context, int index) async {
    final saved = await showDialog<int>(
      context: context,
      builder: (context) => _ColorDialog(color: palette.colors[index]),
    );
    if (saved == null) {
      return;
    }
    onChanged(palette.selectColor(index).updateColor(index, saved));
  }

  Future<void> _editDash(BuildContext context, int index) async {
    onChanged(palette.selectDash(index));
    var dash = palette.dashes[index];
    await showDialog<void>(
      context: context,
      builder: (context) => _DashDialog(
        color: Color(palette.color),
        width: palette.width,
        dash: dash,
        onChanged: (value) {
          dash = value;
          onChanged(palette.selectDash(index).updateDash(index, value));
        },
      ),
    );
  }
}

class PenPresetArc extends StatefulWidget {
  const PenPresetArc({
    required this.palette,
    required this.center,
    required this.onChanged,
    required this.onTargets,
    super.key,
  });

  final PenPalette palette;
  final Offset center;
  final ValueChanged<PenPalette> onChanged;
  final ValueChanged<List<PenPresetTarget>> onTargets;

  static const radius = 176.0;
  static const start = math.pi + 0.28;
  static const sweep = math.pi - 0.56;
  static const gap = 0.38;

  @override
  State<PenPresetArc> createState() => _PenPresetArcState();
}

class _PenPresetArcState extends State<PenPresetArc> {
  var _scroll = 0.0;
  Offset? _dragDown;
  var _dragging = false;

  List<_ArcPiece> get _pieces {
    final palette = widget.palette;
    return [
      for (var index = 0; index < palette.widths.length; index++)
        _ArcPiece.slot(
          child: _WidthMark(width: palette.widths[index]),
          selected: index == palette.widthIndex,
          onShort: () => widget.onChanged(palette.selectWidth(index)),
          onLong: () => _editWidth(index),
        ),
      const _ArcPiece.divider(),
      for (var index = 0; index < palette.colors.length; index++)
        _ArcPiece.slot(
          child: _ColorMark(color: palette.colors[index]),
          selected: index == palette.colorIndex,
          onShort: () => widget.onChanged(palette.selectColor(index)),
          onLong: () => _editColor(index),
        ),
      const _ArcPiece.divider(),
      for (var index = 0; index < palette.dashes.length; index++)
        _ArcPiece.slot(
          child: _DashSample(
            dash: palette.dashes[index],
            color: Color(palette.color),
            width: palette.width.clamp(1, 6),
          ),
          selected: index == palette.dashIndex,
          onShort: () => widget.onChanged(palette.selectDash(index)),
          onLong: () => _editDash(index),
        ),
    ];
  }

  double get _maxScroll {
    final span = math.max(0, _pieces.length - 1) * PenPresetArc.gap;
    return math.max(0.0, span - PenPresetArc.sweep);
  }

  @override
  Widget build(BuildContext context) {
    final pieces = _pieces;
    final targets = <PenPresetTarget>[];
    final children = <Widget>[
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _ArcLinePainter(widget.center),
          ),
        ),
      ),
    ];
    for (var index = 0; index < pieces.length; index++) {
      final piece = pieces[index];
      final angle =
          PenPresetArc.start + index * PenPresetArc.gap - _scroll;
      if (angle < PenPresetArc.start - 0.05 ||
          angle > PenPresetArc.start + PenPresetArc.sweep + 0.05) {
        continue;
      }
      final rect = _arcRect(widget.center, angle, piece.divider ? 18 : 56);
      if (!piece.divider && piece.onLong != null) {
        targets.add(PenPresetTarget(rect, piece.onLong!));
      }
      children.add(
        Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: piece.divider
              ? const Center(
                  child: SizedBox(
                    width: 1,
                    height: 28,
                    child: ColoredBox(color: Color(0xFF222222)),
                  ),
                )
              : _SlotPress(
                  selected: piece.selected,
                  onShort: piece.onShort!,
                  onLong: piece.onLong!,
                  child: piece.child!,
                ),
        ),
      );
    }
    widget.onTargets(targets);
    return Listener(
      key: const ValueKey('pen-preset-arc'),
      onPointerDown: (event) {
        _dragDown = event.position;
        _dragging = false;
      },
      onPointerMove: (event) {
        final down = _dragDown;
        if (down == null) {
          return;
        }
        if (!_dragging && (event.position - down).distance > fingerSlop) {
          _dragging = true;
        }
        if (_dragging) {
          setState(() {
            _scroll = (_scroll - event.delta.dx / PenPresetArc.radius).clamp(
              0.0,
              _maxScroll,
            );
          });
        }
      },
      onPointerUp: (_) => _dragDown = null,
      child: Stack(children: children),
    );
  }

  Future<void> _editWidth(int index) async {
    final palette = widget.palette;
    widget.onChanged(palette.selectWidth(index));
    var width = palette.widths[index];
    await showDialog<void>(
      context: context,
      builder: (context) => _WidthDialog(
        color: Color(palette.color),
        width: width,
        onChanged: (value) {
          width = value;
          widget.onChanged(palette.selectWidth(index).updateWidth(index, value));
        },
      ),
    );
  }

  Future<void> _editColor(int index) async {
    final palette = widget.palette;
    final saved = await showDialog<int>(
      context: context,
      builder: (context) => _ColorDialog(color: palette.colors[index]),
    );
    if (saved == null) {
      return;
    }
    widget.onChanged(palette.selectColor(index).updateColor(index, saved));
  }

  Future<void> _editDash(int index) async {
    final palette = widget.palette;
    widget.onChanged(palette.selectDash(index));
    var dash = palette.dashes[index];
    await showDialog<void>(
      context: context,
      builder: (context) => _DashDialog(
        color: Color(palette.color),
        width: palette.width,
        dash: dash,
        onChanged: (value) {
          dash = value;
          widget.onChanged(palette.selectDash(index).updateDash(index, value));
        },
      ),
    );
  }
}

Rect _arcRect(Offset center, double angle, double button) {
  final dx = center.dx + math.cos(angle) * PenPresetArc.radius - button / 2;
  final dy = center.dy + math.sin(angle) * PenPresetArc.radius - button / 2;
  return Rect.fromLTWH(dx, dy, button, button);
}

class _ArcPiece {
  const _ArcPiece.slot({
    required this.child,
    required this.selected,
    required this.onShort,
    required this.onLong,
  }) : divider = false;

  const _ArcPiece.divider()
    : divider = true,
      child = null,
      selected = false,
      onShort = null,
      onLong = null;

  final bool divider;
  final Widget? child;
  final bool selected;
  final VoidCallback? onShort;
  final VoidCallback? onLong;
}

class _ArcLinePainter extends CustomPainter {
  const _ArcLinePainter(this.center);

  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: center, radius: PenPresetArc.radius);
    canvas.drawArc(
      rect,
      PenPresetArc.start,
      PenPresetArc.sweep,
      false,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      rect,
      PenPresetArc.start,
      PenPresetArc.sweep,
      false,
      Paint()
        ..color = const Color(0xFF222222)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ArcLinePainter oldDelegate) =>
      oldDelegate.center != center;
}

class _WidthMark extends StatelessWidget {
  const _WidthMark({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          width.toStringAsFixed(1),
          style: const TextStyle(fontSize: 11, color: Color(0xFF222222)),
        ),
        const SizedBox(height: 2),
        Container(
          width: 36,
          height: width.clamp(1.0, 24.0),
          color: const Color(0xFF222222),
        ),
      ],
    );
  }
}

class _ColorMark extends StatelessWidget {
  const _ColorMark({required this.color});

  final int color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color(color),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: const SizedBox(width: 22, height: 22),
    );
  }
}

class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFF222222),
    );
  }
}

class _SlotPress extends StatefulWidget {
  const _SlotPress({
    required this.selected,
    required this.onShort,
    required this.onLong,
    required this.child,
    super.key,
  });

  final bool selected;
  final VoidCallback onShort;
  final VoidCallback onLong;
  final Widget child;

  @override
  State<_SlotPress> createState() => _SlotPressState();
}

class _SlotPressState extends State<_SlotPress> {
  Timer? _timer;
  int? _pointer;
  Offset? _down;
  var _held = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _pointerDown(PointerDownEvent event) {
    if (_pointer != null) {
      return;
    }
    _pointer = event.pointer;
    _down = event.position;
    _held = false;
    _timer = Timer(fingerLongPress, () {
      if (!mounted || _pointer != event.pointer) {
        return;
      }
      _held = true;
      widget.onLong();
    });
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    final down = _down;
    if (down != null && (event.position - down).distance > fingerSlop) {
      _timer?.cancel();
      _pointer = null;
    }
  }

  void _pointerUp(PointerEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _timer?.cancel();
    final short = !_held;
    _pointer = null;
    if (short) {
      widget.onShort();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Listener(
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerUp,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: widget.selected ? scheme.primaryContainer : Colors.white,
          border: Border.all(
            color: widget.selected ? scheme.primary : const Color(0xFFBBBBBB),
            width: widget.selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: widget.child,
      ),
    );
  }
}

class _WidthDialog extends StatefulWidget {
  const _WidthDialog({
    required this.color,
    required this.width,
    required this.onChanged,
  });

  final Color color;
  final double width;
  final ValueChanged<double> onChanged;

  @override
  State<_WidthDialog> createState() => _WidthDialogState();
}

class _WidthDialogState extends State<_WidthDialog> {
  late double _width = widget.width;
  late final TextEditingController _field = TextEditingController(
    text: _width.toStringAsFixed(1),
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _set(double value, {required bool fromField}) {
    final next = value.clamp(PenPalette.widthMin, PenPalette.widthMax);
    setState(() => _width = next);
    widget.onChanged(next);
    if (!fromField) {
      _field.text = next.toStringAsFixed(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('尺寸'),
      content: SizedBox(
        width: 360,
        height: 220,
        child: Column(
          children: [
            Expanded(child: _LinePreview(color: widget.color, width: _width)),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    min: PenPalette.widthMin,
                    max: PenPalette.widthMax,
                    value: _width,
                    onChanged: (value) => _set(value, fromField: false),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: _field,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (text) {
                      final parsed = double.tryParse(text);
                      if (parsed != null) {
                        _set(parsed, fromField: true);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DashDialog extends StatefulWidget {
  const _DashDialog({
    required this.color,
    required this.width,
    required this.dash,
    required this.onChanged,
  });

  final Color color;
  final double width;
  final PenDash dash;
  final ValueChanged<PenDash> onChanged;

  @override
  State<_DashDialog> createState() => _DashDialogState();
}

class _DashDialogState extends State<_DashDialog> {
  late PenDash _dash = widget.dash;

  void _set(PenDash dash) {
    setState(() => _dash = dash);
    widget.onChanged(dash);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('虚实'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 72,
              child: _DashPreview(
                dash: _dash,
                color: widget.color,
                width: widget.width,
              ),
            ),
            const Align(alignment: Alignment.centerLeft, child: Text('循环长度')),
            Slider(
              min: PenPalette.cycleMin,
              max: PenPalette.cycleMax,
              value: _dash.cycle,
              onChanged: (value) => _set(_dash.copyWith(cycle: value)),
            ),
            const Align(alignment: Alignment.centerLeft, child: Text('虚实占比')),
            Slider(
              min: 0,
              max: 1,
              value: _dash.ratio,
              onChanged: (value) => _set(_dash.copyWith(ratio: value)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.color});

  final int color;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.color));
  var _rgb = false;

  static const _presets = <int>[
    0xFF000000,
    0xFFFFFFFF,
    0xFFFF0000,
    0xFF00FF00,
    0xFF0000FF,
    0xFFFFFF00,
    0xFF00FFFF,
    0xFFFF00FF,
  ];

  Color get _color => _hsv.toColor();

  void _setColor(Color color) {
    setState(() => _hsv = HSVColor.fromColor(color));
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return AlertDialog(
      title: const Text('颜色'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('HSV')),
                ButtonSegment(value: true, label: Text('RGB')),
              ],
              selected: {_rgb},
              onSelectionChanged: (value) => setState(() => _rgb = value.single),
            ),
            const SizedBox(height: 12),
            if (_rgb)
              _RgbBoard(color: color, onChanged: _setColor)
            else
              _HsvBoard(
                hsv: _hsv,
                onChanged: (value) => setState(() => _hsv = value),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in _presets)
                  GestureDetector(
                    onTap: () => _setColor(Color(preset)),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(preset),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF222222)),
                      ),
                      child: const SizedBox(width: 28, height: 28),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: '取消',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        IconButton(
          tooltip: '保存',
          onPressed: () => Navigator.pop(context, color.toARGB32()),
          icon: const Icon(Icons.check),
        ),
      ],
    );
  }
}

class _HsvBoard extends StatelessWidget {
  const _HsvBoard({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  void _pick(Offset local, Size size) {
    final saturation = (local.dx / size.width).clamp(0.0, 1.0);
    final value = (1 - local.dy / size.height).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(saturation).withValue(value));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 160,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                onPanDown: (details) => _pick(details.localPosition, size),
                onPanUpdate: (details) => _pick(details.localPosition, size),
                child: CustomPaint(
                  painter: _SvPainter(hsv),
                  child: Align(
                    alignment: Alignment(
                      hsv.saturation * 2 - 1,
                      (1 - hsv.value) * 2 - 1,
                    ),
                    child: const Icon(Icons.circle_outlined, color: Colors.white),
                  ),
                ),
              );
            },
          ),
        ),
        Slider(
          min: 0,
          max: 360,
          value: hsv.hue,
          activeColor: HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
          onChanged: (value) => onChanged(hsv.withHue(value)),
        ),
      ],
    );
  }
}

class _SvPainter extends CustomPainter {
  const _SvPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hue = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: [Colors.white, hue]).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SvPainter oldDelegate) => oldDelegate.hsv != hsv;
}

class _RgbBoard extends StatelessWidget {
  const _RgbBoard({required this.color, required this.onChanged});

  final Color color;
  final ValueChanged<Color> onChanged;

  void _pick(Offset local, Size size) {
    final red = (local.dx / size.width).clamp(0.0, 1.0);
    final green = (1 - local.dy / size.height).clamp(0.0, 1.0);
    onChanged(color.withValues(red: red, green: green));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 160,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                onPanDown: (details) => _pick(details.localPosition, size),
                onPanUpdate: (details) => _pick(details.localPosition, size),
                child: CustomPaint(
                  painter: _RgPainter(color.b),
                  child: Align(
                    alignment: Alignment(color.r * 2 - 1, (1 - color.g) * 2 - 1),
                    child: const Icon(
                      Icons.circle_outlined,
                      color: Colors.white,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Slider(
          min: 0,
          max: 1,
          value: color.b.clamp(0.0, 1.0),
          activeColor: Color.from(alpha: 1, red: 0, green: 0, blue: color.b),
          onChanged: (value) => onChanged(color.withValues(blue: value)),
        ),
      ],
    );
  }
}

class _RgPainter extends CustomPainter {
  const _RgPainter(this.blue);

  final double blue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Color.from(alpha: 1, red: 0, green: 0, blue: blue);
    final red = Color.from(alpha: 1, red: 1, green: 0, blue: blue);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: [base, red]).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF00FF00), Color(0x00000000)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RgPainter oldDelegate) => oldDelegate.blue != blue;
}

class _LinePreview extends StatelessWidget {
  const _LinePreview({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE8E8E8),
      child: Center(
        child: Container(
          height: width,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          color: color,
        ),
      ),
    );
  }
}

class _DashSample extends StatelessWidget {
  const _DashSample({
    required this.dash,
    required this.color,
    required this.width,
  });

  final PenDash dash;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 18,
      child: CustomPaint(
        painter: _DashPainter(dash: dash, color: color, width: width),
      ),
    );
  }
}

class _DashPreview extends StatelessWidget {
  const _DashPreview({
    required this.dash,
    required this.color,
    required this.width,
  });

  final PenDash dash;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cycles = 12.0;
    final length = dash.cycle * cycles < 960 ? 960.0 : dash.cycle * cycles;
    return SizedBox(
      height: 88,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFFE8E8E8)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: length,
            height: 88,
            child: CustomPaint(
              painter: _DashPainter(dash: dash, color: color, width: width),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter({
    required this.dash,
    required this.color,
    required this.width,
  });

  final PenDash dash;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE8E8E8),
    );
    final y = size.height / 2;
    paintStroke(
      canvas,
      StrokeObject(
        id: 'dash-preview',
        tool: 'pen',
        color: color.toARGB32(),
        baseWidth: width,
        finalized: true,
        dashCycle: dash.cycle,
        dashRatio: dash.ratio,
        points: [
          StrokePoint(
            x: 8,
            y: y,
            time: 0,
            width: width,
            height: width,
            opacity: 1,
            pressure: 1,
          ),
          StrokePoint(
            x: size.width - 8,
            y: y,
            time: 1,
            width: width,
            height: width,
            opacity: 1,
            pressure: 1,
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) {
    return oldDelegate.dash.cycle != dash.cycle ||
        oldDelegate.dash.ratio != dash.ratio ||
        oldDelegate.color != color ||
        oldDelegate.width != width;
  }
}
