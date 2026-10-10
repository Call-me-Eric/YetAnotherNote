import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../input/finger.dart';

class EraserOptionsBar extends StatelessWidget {
  const EraserOptionsBar({
    required this.region,
    required this.radius,
    required this.onRegion,
    required this.onRadius,
    super.key,
  });

  final bool region;
  final double radius;
  final ValueChanged<bool> onRegion;
  final ValueChanged<double> onRadius;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('eraser-options'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Choice(
            label: '笔画',
            selected: !region,
            onTap: () => onRegion(false),
          ),
          _Choice(
            label: '区域',
            selected: region,
            onTap: () => onRegion(true),
          ),
          const SizedBox(width: 8),
          const Text('半径'),
          SizedBox(
            width: 160,
            child: Slider(
              min: 4,
              max: 48,
              value: radius.clamp(4, 48),
              onChanged: onRadius,
            ),
          ),
          Text(radius.toStringAsFixed(0)),
        ],
      ),
    );
  }
}

class LassoOptionsBar extends StatelessWidget {
  const LassoOptionsBar({
    required this.rect,
    required this.strokes,
    required this.texts,
    required this.highlighters,
    required this.onRect,
    required this.onStrokes,
    required this.onTexts,
    required this.onHighlighters,
    super.key,
  });

  final bool rect;
  final bool strokes;
  final bool texts;
  final bool highlighters;
  final ValueChanged<bool> onRect;
  final ValueChanged<bool> onStrokes;
  final ValueChanged<bool> onTexts;
  final ValueChanged<bool> onHighlighters;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('lasso-options'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Choice(label: '自由', selected: !rect, onTap: () => onRect(false)),
          _Choice(label: '矩形', selected: rect, onTap: () => onRect(true)),
          const _BarDivider(),
          _Choice(
            label: '笔画',
            selected: strokes,
            onTap: () => onStrokes(!strokes),
          ),
          _Choice(
            label: '文本',
            selected: texts,
            onTap: () => onTexts(!texts),
          ),
          _Choice(
            label: '荧光笔',
            selected: highlighters,
            onTap: () => onHighlighters(!highlighters),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? scheme.primary : const Color(0xFFBBBBBB),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

class _BarDivider extends StatelessWidget {
  const _BarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFF222222),
    );
  }
}

class ChoiceArcItem {
  const ChoiceArcItem({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
}

class ChoiceArc extends StatelessWidget {
  const ChoiceArc({required this.center, required this.items, super.key});

  final Offset center;
  final List<ChoiceArcItem> items;

  static const radius = 176.0;
  static const buttonSize = 52.0;
  static const _start = math.pi + 0.28;
  static const _sweep = math.pi - 0.56;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ChoiceArcPainter(center, _start, _sweep),
            ),
          ),
        ),
        for (var index = 0; index < items.length; index++)
          _button(scheme, index, items[index]),
      ],
    );
  }

  Widget _button(ColorScheme scheme, int index, ChoiceArcItem item) {
    final count = items.length;
    final t = count == 1 ? 0.5 : index / (count - 1);
    final angle = _start + _sweep * t;
    final left = center.dx + math.cos(angle) * radius - buttonSize / 2;
    final top = center.dy + math.sin(angle) * radius - buttonSize / 2;
    return Positioned(
      left: left,
      top: top,
      width: buttonSize,
      height: buttonSize,
      child: Material(
        color: item.selected ? scheme.primaryContainer : Colors.white,
        elevation: 3,
        shape: const CircleBorder(
          side: BorderSide(color: Color(0xFF3D7EFF), width: 1.2),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: item.onPressed,
          child: Center(
            child: Text(
              item.label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF222222)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceArcPainter extends CustomPainter {
  const _ChoiceArcPainter(this.center, this.start, this.sweep);

  final Offset center;
  final double start;
  final double sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: center, radius: ChoiceArc.radius);
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..color = const Color(0xFF3D7EFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ChoiceArcPainter oldDelegate) =>
      oldDelegate.center != center;
}

class SelectionFrame extends StatelessWidget {
  const SelectionFrame({
    required this.bounds,
    required this.onMove,
    required this.onMoveEnd,
    required this.onScale,
    required this.onScaleEnd,
    required this.onRotate,
    required this.onRotateEnd,
    required this.onMenu,
    super.key,
  });

  final Rect bounds;
  /// Page-space pointer position (not frame-local delta).
  final void Function(Offset pagePoint) onMove;
  final VoidCallback onMoveEnd;
  final void Function(SelectionHandle handle, Offset pagePoint) onScale;
  final VoidCallback onScaleEnd;
  final void Function(Offset pagePoint) onRotate;
  final VoidCallback onRotateEnd;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final stem = 16 + bounds.shortestSide * 0.12;
    Offset pagePoint(Offset global) {
      final box = context.findRenderObject() as RenderBox?;
      if (box == null) {
        return global;
      }
      return box.globalToLocal(global);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: bounds.left,
          top: bounds.top,
          width: bounds.width,
          height: bounds.height,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              PanGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
                    PanGestureRecognizer.new,
                    (instance) {
                      instance.onUpdate = (details) =>
                          onMove(pagePoint(details.globalPosition));
                      instance.onEnd = (_) => onMoveEnd();
                    },
                  ),
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer
                  >(
                    () => LongPressGestureRecognizer(duration: fingerLongPress),
                    (instance) {
                      instance.onLongPress = onMenu;
                    },
                  ),
            },
            child: CustomPaint(
              painter: _DashRectPainter(),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        for (final handle in SelectionHandle.values)
          if (handle != SelectionHandle.rotate)
            _knob(
              handle.anchor(bounds),
              onPan: (global) => onScale(handle, pagePoint(global)),
              onEnd: onScaleEnd,
            ),
        Positioned(
          left: bounds.center.dx - 0.5,
          top: bounds.top - stem,
          width: 1,
          height: stem,
          child: const ColoredBox(color: Color(0xFF3D7EFF)),
        ),
        _knob(
          Offset(bounds.center.dx, bounds.top - stem),
          onPan: (global) => onRotate(pagePoint(global)),
          onEnd: onRotateEnd,
        ),
      ],
    );
  }

  Widget _knob(
    Offset center, {
    required void Function(Offset global) onPan,
    required VoidCallback onEnd,
  }) {
    const size = 16.0;
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onPan(details.globalPosition),
        onPanEnd: (_) => onEnd(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: const Color(0xFF222222), width: 1.4),
          ),
        ),
      ),
    );
  }
}

enum SelectionHandle {
  topLeft,
  topRight,
  bottomRight,
  bottomLeft,
  top,
  right,
  bottom,
  left,
  rotate,
}

extension SelectionHandleGeometry on SelectionHandle {
  Offset anchor(Rect bounds) {
    return switch (this) {
      SelectionHandle.topLeft => bounds.topLeft,
      SelectionHandle.topRight => bounds.topRight,
      SelectionHandle.bottomRight => bounds.bottomRight,
      SelectionHandle.bottomLeft => bounds.bottomLeft,
      SelectionHandle.top => bounds.topCenter,
      SelectionHandle.right => bounds.centerRight,
      SelectionHandle.bottom => bounds.bottomCenter,
      SelectionHandle.left => bounds.centerLeft,
      SelectionHandle.rotate => bounds.topCenter,
    };
  }

  /// Fixed pivot while dragging this handle (GoodNotes: opposite side/corner).
  Offset opposite(Rect bounds) {
    return switch (this) {
      SelectionHandle.topLeft => bounds.bottomRight,
      SelectionHandle.topRight => bounds.bottomLeft,
      SelectionHandle.bottomRight => bounds.topLeft,
      SelectionHandle.bottomLeft => bounds.topRight,
      SelectionHandle.top => bounds.bottomCenter,
      SelectionHandle.right => bounds.centerLeft,
      SelectionHandle.bottom => bounds.topCenter,
      SelectionHandle.left => bounds.centerRight,
      SelectionHandle.rotate => bounds.center,
    };
  }

  bool get corner => index < 4;
  bool get horizontal =>
      this == SelectionHandle.left || this == SelectionHandle.right;
}

class _DashRectPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF3D7EFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const dash = 6.0;
    const gap = 4.0;
    void edge(Offset a, Offset b) {
      final delta = b - a;
      final length = delta.distance;
      if (length == 0) {
        return;
      }
      final step = delta / length;
      var traveled = 0.0;
      while (traveled < length) {
        final end = (traveled + dash).clamp(0.0, length);
        canvas.drawLine(a + step * traveled, a + step * end, paint);
        traveled += dash + gap;
      }
    }

    edge(Offset.zero, Offset(size.width, 0));
    edge(Offset(size.width, 0), Offset(size.width, size.height));
    edge(Offset(size.width, size.height), Offset(0, size.height));
    edge(Offset(0, size.height), Offset.zero);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Absolute scale matrix from gesture start (opposite corner/edge fixed).
Matrix4 selectionScaleMatrix({
  required SelectionHandle handle,
  required Rect startBounds,
  required Offset startPointer,
  required Offset currentPointer,
}) {
  final origin = handle.opposite(startBounds);
  final startHandle = handle.anchor(startBounds);
  final target = startHandle + (currentPointer - startPointer);
  if (handle.corner) {
    final startVec = startHandle - origin;
    final endVec = target - origin;
    final startLen = startVec.distance;
    if (startLen < 1e-6) {
      return Matrix4.identity();
    }
    final crossed = startVec.dx * endVec.dx + startVec.dy * endVec.dy < 0;
    final scale = crossed
        ? 0.2
        : (endVec.distance / startLen).clamp(0.2, 8.0);
    return _scaleAbout(origin, scale, scale);
  }
  if (handle.horizontal) {
    final startSpan = startHandle.dx - origin.dx;
    if (startSpan.abs() < 1e-6) {
      return Matrix4.identity();
    }
    var scale = (target.dx - origin.dx) / startSpan;
    if (scale < 0) {
      scale = 0.2;
    } else {
      scale = scale.clamp(0.2, 8.0);
    }
    return _scaleAbout(origin, scale, 1);
  }
  final startSpan = startHandle.dy - origin.dy;
  if (startSpan.abs() < 1e-6) {
    return Matrix4.identity();
  }
  var scale = (target.dy - origin.dy) / startSpan;
  if (scale < 0) {
    scale = 0.2;
  } else {
    scale = scale.clamp(0.2, 8.0);
  }
  return _scaleAbout(origin, 1, scale);
}

Matrix4 selectionRotateMatrix({
  required Offset center,
  required Offset startPointer,
  required Offset currentPointer,
}) {
  final start = math.atan2(
    startPointer.dy - center.dy,
    startPointer.dx - center.dx,
  );
  final end = math.atan2(
    currentPointer.dy - center.dy,
    currentPointer.dx - center.dx,
  );
  final turns = end - start;
  if (turns == 0) {
    return Matrix4.identity();
  }
  return Matrix4.identity()
    ..translateByDouble(center.dx, center.dy, 0, 1)
    ..rotateZ(turns)
    ..translateByDouble(-center.dx, -center.dy, 0, 1);
}

Matrix4 _scaleAbout(Offset origin, double scaleX, double scaleY) {
  return Matrix4.identity()
    ..translateByDouble(origin.dx, origin.dy, 0, 1)
    ..scaleByDouble(scaleX, scaleY, 1, 1)
    ..translateByDouble(-origin.dx, -origin.dy, 0, 1);
}
