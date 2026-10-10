import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_page/src/ink/selection.dart';
import 'package:yet_another_page/src/ink/stroke.dart';
import 'package:yet_another_page/src/ink/text_box.dart';

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
}
