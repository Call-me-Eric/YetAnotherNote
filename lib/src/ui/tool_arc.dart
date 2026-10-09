import 'dart:math' as math;

import 'package:flutter/material.dart';

class ToolArcAction {
  const ToolArcAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
}

class ToolArc extends StatelessWidget {
  const ToolArc({
    required this.center,
    required this.actions,
    required this.onDismiss,
    super.key,
  });

  final Offset center;
  final List<ToolArcAction> actions;
  final VoidCallback onDismiss;

  static const radius = 108.0;
  static const _start = math.pi + 0.28;
  static const _sweep = math.pi - 0.56;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final placed = _clamp(center, size, padding);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        key: const ValueKey('tool-arc'),
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ArcLinePainter(placed, _start, _sweep),
              ),
            ),
          ),
          for (var index = 0; index < actions.length; index++)
            _button(context, placed, index, actions[index]),
        ],
      ),
    );
  }

  Widget _button(
    BuildContext context,
    Offset origin,
    int index,
    ToolArcAction action,
  ) {
    final t = actions.length == 1 ? 0.5 : index / (actions.length - 1);
    final angle = _start + _sweep * t;
    const button = 48.0;
    final dx = origin.dx + math.cos(angle) * radius - button / 2;
    final dy = origin.dy + math.sin(angle) * radius - button / 2;
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: dx,
      top: dy,
      width: button,
      height: button,
      child: Material(
        color: action.selected ? scheme.primaryContainer : Colors.white,
        elevation: 3,
        shape: const CircleBorder(
          side: BorderSide(color: Color(0xFF222222), width: 1.2),
        ),
        child: IconButton(
          key: ValueKey(action.id),
          tooltip: action.label,
          onPressed: action.onPressed,
          icon: Icon(action.icon, color: const Color(0xFF222222)),
        ),
      ),
    );
  }

  static Offset _clamp(Offset center, Size size, EdgeInsets padding) {
    const reach = radius + 28;
    final left = padding.left + reach;
    final top = padding.top + reach;
    final right = size.width - padding.right - reach;
    final bottom = size.height - padding.bottom - reach;
    if (right <= left || bottom <= top) {
      return center;
    }
    return Offset(center.dx.clamp(left, right), center.dy.clamp(top, bottom));
  }
}

class _ArcLinePainter extends CustomPainter {
  const _ArcLinePainter(this.center, this.start, this.sweep);

  final Offset center;
  final double start;
  final double sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: center, radius: ToolArc.radius);
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
