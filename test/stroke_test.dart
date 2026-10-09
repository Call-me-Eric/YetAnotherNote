import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_page/src/ink/stroke.dart';

void main() {
  test('mouse samples use fixed pressure and a provisional width', () {
    final point = mouseSample(x: 4, y: 8, time: 0.2, baseWidth: penBaseWidth);
    expect(point.pressure, missingPressure);
    expect(point.opacity, missingOpacity);
    expect(point.azimuth, isNull);
    expect(point.altitude, isNull);
    expect(point.width, penBaseWidth);
    expect(point.height, penBaseWidth);
  });

  test('baking writes width from speed and does not need to be run again', () {
    final slow = bakePenStroke(
      StrokeObject(
        id: 'slow',
        tool: 'pen',
        color: penColor,
        baseWidth: penBaseWidth,
        finalized: false,
        points: [
          mouseSample(x: 0, y: 0, time: 0, baseWidth: penBaseWidth),
          mouseSample(x: 40, y: 0, time: 1, baseWidth: penBaseWidth),
        ],
      ),
    );
    final fast = bakePenStroke(
      StrokeObject(
        id: 'fast',
        tool: 'pen',
        color: penColor,
        baseWidth: penBaseWidth,
        finalized: false,
        points: [
          mouseSample(x: 0, y: 0, time: 0, baseWidth: penBaseWidth),
          mouseSample(x: 40, y: 0, time: 0.02, baseWidth: penBaseWidth),
        ],
      ),
    );

    expect(slow.finalized, isTrue);
    expect(fast.finalized, isTrue);
    expect(slow.points.last.width, greaterThan(fast.points.last.width));
    expect(slow.points.last.height, slow.points.last.width);
    expect(outlineOf(slow.points).getBounds().width, greaterThan(0));
  });

  test('the first point can be extended without erasing the stroke', () {
    final first = mouseSample(x: 0, y: 0, time: 0, baseWidth: penBaseWidth);
    final points = [first];
    final next = appendCausalPoint(
      raw: points,
      painted: points,
      sample: mouseSample(x: 40, y: 0, time: 0.05, baseWidth: penBaseWidth),
      baseWidth: penBaseWidth,
      connected: 0,
    );
    final finished = finishStroke(
      raw: next.raw,
      painted: next.painted,
      connected: next.connected,
    );
    expect(next.raw.length, 2);
    expect(next.connected, 0);
    expect(finished.painted.length, greaterThan(2));
    expect(finished.painted.first.x, 0);
    expect(finished.painted.last.x, 40);
  });

  test('the newest sample waits so the previous gap can be curved', () {
    final first = mouseSample(x: 0, y: 0, time: 0, baseWidth: penBaseWidth);
    var raw = <StrokePoint>[first];
    var painted = <StrokePoint>[first];
    var connected = 0;
    final second = appendCausalPoint(
      raw: raw,
      painted: painted,
      sample: mouseSample(x: 40, y: 0, time: 0.008, baseWidth: penBaseWidth),
      baseWidth: penBaseWidth,
      connected: connected,
    );
    raw = second.raw;
    painted = second.painted;
    connected = second.connected;
    expect(painted.length, 1);

    final third = appendCausalPoint(
      raw: raw,
      painted: painted,
      sample: mouseSample(x: 70, y: 24, time: 0.016, baseWidth: penBaseWidth),
      baseWidth: penBaseWidth,
      connected: connected,
    );
    expect(third.connected, 1);
    expect(third.painted.last.x, closeTo(40, 0.01));
    expect(third.painted.last.time, closeTo(0.008, 0.0001));
  });

  test('a fast jump is filled so consecutive samples stay close', () {
    final baked = bakePenStroke(
      StrokeObject(
        id: 'jump',
        tool: 'pen',
        color: penColor,
        baseWidth: penBaseWidth,
        finalized: false,
        points: [
          mouseSample(x: 0, y: 0, time: 0, baseWidth: penBaseWidth),
          mouseSample(x: 120, y: 0, time: 0.03, baseWidth: penBaseWidth),
        ],
      ),
    );

    expect(baked.points.length, greaterThan(20));
    for (var index = 1; index < baked.points.length; index++) {
      final distance = (baked.points[index].x - baked.points[index - 1].x)
          .abs();
      expect(distance, lessThanOrEqualTo(straightSpacing + 0.05));
    }
  });

  test('a fast circle is filled along the curve instead of the chord', () {
    const radius = 80.0;
    const count = 8;
    final raw = <StrokePoint>[
      for (var index = 0; index <= count; index++)
        mouseSample(
          x: radius * math.cos(-math.pi / 2 + (2 * math.pi * index / count)),
          y: radius * math.sin(-math.pi / 2 + (2 * math.pi * index / count)),
          time: index * 0.008,
          baseWidth: penBaseWidth,
        ),
    ];
    final dense = densifySamples(raw);
    const segment = 3;
    final midAngle = -math.pi / 2 + (2 * math.pi * (segment + 0.5) / count);
    final target = Offset(
      radius * math.cos(midAngle),
      radius * math.sin(midAngle),
    );
    final chord = Offset(
      (raw[segment].x + raw[segment + 1].x) / 2,
      (raw[segment].y + raw[segment + 1].y) / 2,
    );

    var nearestDistance = double.infinity;
    for (final point in dense) {
      final dx = point.x - target.dx;
      final dy = point.y - target.dy;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance < nearestDistance) {
        nearestDistance = distance;
      }
    }
    final chordDx = chord.dx - target.dx;
    final chordDy = chord.dy - target.dy;
    final chordError = math.sqrt(chordDx * chordDx + chordDy * chordDy);
    expect(nearestDistance, lessThan(2));
    expect(nearestDistance, lessThan(chordError));
  });

  test('the gap between samples follows the recent motion', () {
    final corner = densifySamples([
      mouseSample(x: 0, y: 0, time: 0, baseWidth: penBaseWidth),
      mouseSample(x: 80, y: 0, time: 0.01, baseWidth: penBaseWidth),
      mouseSample(x: 80, y: 80, time: 0.02, baseWidth: penBaseWidth),
    ]);
    final approach = [
      for (final point in corner)
        if (point.time > 0.002 && point.time < 0.009) point,
    ];
    expect(approach, isNotEmpty);
    expect(
      approach.map((point) => point.y.abs()).reduce(math.max),
      greaterThan(2),
    );
    expect(corner.last.x, closeTo(80, 0.01));
    expect(corner.last.y, closeTo(80, 0.01));
  });

  test('a turn is sampled more tightly than a straight segment', () {
    final straight = densifySamples([
      mouseSample(x: 0, y: 0, time: 0, baseWidth: penBaseWidth),
      mouseSample(x: 80, y: 0, time: 0.02, baseWidth: penBaseWidth),
    ]);
    final corner = densifySamples([
      mouseSample(x: 0, y: 0, time: 0, baseWidth: penBaseWidth),
      mouseSample(x: 80, y: 0, time: 0.01, baseWidth: penBaseWidth),
      mouseSample(x: 80, y: 80, time: 0.02, baseWidth: penBaseWidth),
    ]);
    final leg = [
      for (final point in corner)
        if (point.time > 0 && point.time < 0.01) point,
    ];

    expect(leg.length, greaterThan(straight.length));
    for (var index = 1; index < leg.length; index++) {
      final dx = leg[index].x - leg[index - 1].x;
      final dy = leg[index].y - leg[index - 1].y;
      expect(math.sqrt(dx * dx + dy * dy), lessThan(straightSpacing));
    }
  });

  test('a sparse fast circle follows the arc', () {
    const radius = 80.0;
    const count = 4;
    final raw = <StrokePoint>[
      for (var index = 0; index <= count; index++)
        mouseSample(
          x: radius * math.cos(2 * math.pi * index / count),
          y: radius * math.sin(2 * math.pi * index / count),
          time: index * 0.02,
          baseWidth: penBaseWidth,
        ),
    ];
    final dense = densifySamples(raw);
    const segment = 2;
    final midAngle = (segment + 0.5) * 2 * math.pi / count;
    final target = Offset(
      radius * math.cos(midAngle),
      radius * math.sin(midAngle),
    );
    final chord = Offset(
      (raw[segment].x + raw[segment + 1].x) / 2,
      (raw[segment].y + raw[segment + 1].y) / 2,
    );
    var nearest = double.infinity;
    for (final point in dense) {
      final distance = math.sqrt(
        math.pow(point.x - target.dx, 2) + math.pow(point.y - target.dy, 2),
      );
      if (distance < nearest) {
        nearest = distance;
      }
    }
    final chordError = math.sqrt(
      math.pow(chord.dx - target.dx, 2) + math.pow(chord.dy - target.dy, 2),
    );
    expect(nearest, lessThan(12));
    expect(nearest, lessThan(chordError));
  });

  test('a very short gap is connected directly', () {
    final dense = densifySamples([
      mouseSample(x: 0, y: 0, time: 0, baseWidth: penBaseWidth),
      mouseSample(x: 12, y: 0, time: 0.02, baseWidth: penBaseWidth),
      mouseSample(x: 12.4, y: 0.3, time: 0.021, baseWidth: penBaseWidth),
    ]);
    final tiny = [
      for (final point in dense)
        if (point.time >= 0.02) point,
    ];
    expect(tiny.length, 2);
    expect(tiny.last.x, closeTo(12.4, 0.01));
    expect(tiny.last.y, closeTo(0.3, 0.01));
  });

  test('dense writing does not jump when one sample shifts', () {
    final dense = densifySamples([
      for (var index = 0; index < 12; index++)
        mouseSample(
          x: 3.0 * index,
          y: index == 6 ? 7 : 0,
          time: index * 0.008,
          baseWidth: penBaseWidth,
        ),
    ]);
    for (final point in dense) {
      if (point.time < 0.032 || point.time > 0.064) {
        expect(point.y.abs(), lessThan(1.5));
      }
    }
  });

  test('a sudden offset does not throw a spur off the circle', () {
    const radius = 80.0;
    const count = 8;
    final raw = <StrokePoint>[
      for (var index = 0; index <= count; index++)
        mouseSample(
          x:
              (radius + (index == 4 ? 28 : 0)) *
              math.cos(2 * math.pi * index / count),
          y:
              (radius + (index == 4 ? 28 : 0)) *
              math.sin(2 * math.pi * index / count),
          time: index * 0.008,
          baseWidth: penBaseWidth,
        ),
    ];
    final dense = densifySamples(raw);
    var farthest = 0.0;
    for (final point in dense) {
      final distance = math.sqrt(point.x * point.x + point.y * point.y);
      if (distance > farthest) {
        farthest = distance;
      }
    }
    expect(farthest, greaterThan(radius + 20));
    expect(farthest, lessThan(radius + 36));
  });

  test('ink already drawn does not move when a later sample arrives', () {
    final first = mouseSample(x: 0, y: 0, time: 0, baseWidth: penBaseWidth);
    var raw = <StrokePoint>[first];
    var painted = <StrokePoint>[first];
    var connected = 0;
    for (var index = 1; index <= 6; index++) {
      final next = appendCausalPoint(
        raw: raw,
        painted: painted,
        sample: mouseSample(
          x: 18.0 * index,
          y: index.isEven ? 0 : 8,
          time: 0.008 * index,
          baseWidth: penBaseWidth,
        ),
        baseWidth: penBaseWidth,
        connected: connected,
      );
      raw = next.raw;
      painted = next.painted;
      connected = next.connected;
    }
    final frozen = [for (final point in painted) point];
    final later = appendCausalPoint(
      raw: raw,
      painted: painted,
      sample: mouseSample(x: 140, y: 30, time: 0.08, baseWidth: penBaseWidth),
      baseWidth: penBaseWidth,
      connected: connected,
    );
    expect(frozen, isNotEmpty);
    expect(later.painted.length, greaterThanOrEqualTo(frozen.length));
    for (var index = 0; index < frozen.length; index++) {
      expect(later.painted[index].x, closeTo(frozen[index].x, 0.001));
      expect(later.painted[index].y, closeTo(frozen[index].y, 0.001));
      expect(later.painted[index].width, closeTo(frozen[index].width, 0.001));
    }
  });

  test('stylus pose is stored and a finger does not draw', () {
    final event = PointerDownEvent(
      kind: PointerDeviceKind.stylus,
      pressure: 0.8,
      pressureMin: 0,
      pressureMax: 1,
      tilt: 0.4,
      orientation: 0.25,
    );
    final point = sampleFromPointer(
      event: event,
      x: 3,
      y: 4,
      time: 0,
      baseWidth: penBaseWidth,
    );
    expect(point.pressure, closeTo(0.8, 0.001));
    expect(point.azimuth, 0.25);
    expect(point.altitude, closeTo((3.141592653589793 / 2) - 0.4, 0.001));
    expect(drawsInk(PointerDeviceKind.stylus), isTrue);
    expect(drawsInk(PointerDeviceKind.mouse), isTrue);
    expect(drawsInk(PointerDeviceKind.touch), isFalse);
  });

  test('a stroke already on the page is not drawn again', () {
    final stroke = StrokeObject(
      id: 'done',
      tool: 'pen',
      color: penColor,
      baseWidth: penBaseWidth,
      finalized: true,
      points: [mouseSample(x: 0, y: 0, time: 0, baseWidth: penBaseWidth)],
    );
    final drawn = <String>{};
    expect(undrawnStrokes(drawn, [stroke]).single.id, 'done');
    drawn.add('done');
    expect(undrawnStrokes(drawn, [stroke]), isEmpty);
  });
}
