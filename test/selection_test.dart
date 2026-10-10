import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_page/src/ink/selection.dart';
import 'package:yet_another_page/src/ink/stroke.dart';
import 'package:yet_another_page/src/ink/text_box.dart';
import 'package:yet_another_page/src/ui/selection_frame.dart';

void main() {
  test('a stroke is selected when only its edge crosses the lasso', () {
    final stroke = StrokeObject(
      id: 'line',
      tool: 'pen',
      color: penColor,
      baseWidth: 4,
      finalized: true,
      points: [
        StrokePoint(
          x: 0,
          y: 10,
          time: 0,
          width: 4,
          height: 4,
          opacity: 1,
          pressure: 1,
        ),
        StrokePoint(
          x: 40,
          y: 10,
          time: 1,
          width: 4,
          height: 4,
          opacity: 1,
          pressure: 1,
        ),
      ],
    );

    expect(
      strokeHitsRegion(stroke, rect: const Rect.fromLTWH(18, 0, 4, 30)),
      isTrue,
    );
    expect(
      strokeHitsRegion(
        stroke,
        polygon: const [
          Offset(18, 0),
          Offset(22, 0),
          Offset(22, 30),
          Offset(18, 30),
        ],
      ),
      isTrue,
    );
    expect(
      strokeHitsRegion(stroke, rect: const Rect.fromLTWH(100, 100, 10, 10)),
      isFalse,
    );
  });

  test('ink just outside the outline still counts when the stroke is thick', () {
    final stroke = StrokeObject(
      id: 'dot',
      tool: 'pen',
      color: penColor,
      baseWidth: 10,
      finalized: true,
      points: [
        StrokePoint(
          x: 0,
          y: 0,
          time: 0,
          width: 10,
          height: 10,
          opacity: 1,
          pressure: 1,
        ),
      ],
    );
    expect(
      strokeHitsRegion(stroke, rect: const Rect.fromLTWH(4, -2, 4, 4)),
      isTrue,
    );
  });

  test('a text box is selected when the lasso only cuts through it', () {
    const box = TextBox(
      id: 't',
      version: 1,
      x: 0,
      y: 0,
      width: 40,
      height: 20,
      source: '字',
    );
    expect(
      textHitsRegion(
        box,
        polygon: const [
          Offset(10, -5),
          Offset(12, -5),
          Offset(12, 30),
          Offset(10, 30),
        ],
      ),
      isTrue,
    );
    expect(
      textHitsRegion(box, rect: const Rect.fromLTWH(100, 100, 5, 5)),
      isFalse,
    );
  });

  test('corner scale keeps the opposite corner fixed', () {
    const bounds = Rect.fromLTWH(10, 20, 40, 60);
    final matrix = selectionScaleMatrix(
      handle: SelectionHandle.bottomRight,
      startBounds: bounds,
      startPointer: bounds.bottomRight,
      currentPointer: const Offset(90, 140),
    );
    Offset map(Offset point) {
      final m = matrix.storage;
      return Offset(
        m[0] * point.dx + m[4] * point.dy + m[12],
        m[1] * point.dx + m[5] * point.dy + m[13],
      );
    }

    expect(map(bounds.topLeft), bounds.topLeft);
    expect(map(bounds.bottomRight).dx, closeTo(90, 0.001));
    expect(map(bounds.bottomRight).dy, closeTo(140, 0.001));
  });

  test('move-style translation is absolute from the drag start', () {
    const start = Offset(10, 10);
    const current = Offset(40, 25);
    final delta = current - start;
    final matrix = Matrix4.translationValues(delta.dx, delta.dy, 0);
    final m = matrix.storage;
    expect(m[12], 30);
    expect(m[13], 15);
  });

  test('rotate matrix spins around the frozen selection center', () {
    const center = Offset(50, 50);
    final matrix = selectionRotateMatrix(
      center: center,
      startPointer: const Offset(50, 20),
      currentPointer: const Offset(80, 50),
    );
    Offset map(Offset point) {
      final m = matrix.storage;
      return Offset(
        m[0] * point.dx + m[4] * point.dy + m[12],
        m[1] * point.dx + m[5] * point.dy + m[13],
      );
    }

    expect(map(center), center);
    final spun = map(const Offset(50, 20));
    expect(spun.dx, closeTo(80, 0.001));
    expect(spun.dy, closeTo(50, 0.001));
  });
}
