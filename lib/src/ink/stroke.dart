import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';

const penBaseWidth = 3.0;
const penColor = 0xFF000000;
const missingPressure = 0.5;
const missingOpacity = 1.0;
const straightSpacing = 1.0;
const tightSpacing = 0.4;

/// Gaps this short are joined directly. A circle fit on them is just noise.
const minFitDistance = 1.5;

/// Handwriting samples are denser than this. Fitting them bows the stroke, then later samples pull it back.
const directJoinDistance = 8;
const curveWindow = 0.032;

class StrokePoint {
  const StrokePoint({
    required this.x,
    required this.y,
    required this.time,
    required this.width,
    required this.height,
    required this.opacity,
    required this.pressure,
    this.azimuth,
    this.altitude,
    this.gap = false,
  });

  final double x;
  final double y;
  final double time;
  final double width;
  final double height;
  final double opacity;
  final double pressure;
  final double? azimuth;
  final double? altitude;

  /// When true, this point starts a new run and is not joined to the previous point.
  final bool gap;

  StrokePoint copyWith({double? x, double? y, double? width, double? height}) {
    return StrokePoint(
      x: x ?? this.x,
      y: y ?? this.y,
      time: time,
      width: width ?? this.width,
      height: height ?? this.height,
      opacity: opacity,
      pressure: pressure,
      azimuth: azimuth,
      altitude: altitude,
      gap: gap,
    );
  }

  Map<String, Object> toJson() => {
    'x': x,
    'y': y,
    'time': time,
    'width': width,
    'height': height,
    'opacity': opacity,
    'pressure': pressure,
    'azimuth': ?azimuth,
    'altitude': ?altitude,
    if (gap) 'gap': true,
  };

  factory StrokePoint.fromJson(Map<String, Object?> json) {
    return StrokePoint(
      x: (json['x']! as num).toDouble(),
      y: (json['y']! as num).toDouble(),
      time: (json['time']! as num).toDouble(),
      width: (json['width']! as num).toDouble(),
      height: (json['height']! as num).toDouble(),
      opacity: (json['opacity']! as num).toDouble(),
      pressure: (json['pressure']! as num).toDouble(),
      azimuth: (json['azimuth'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      gap: json['gap'] == true,
    );
  }
}

class StrokeObject {
  const StrokeObject({
    required this.id,
    required this.tool,
    required this.color,
    required this.baseWidth,
    required this.points,
    required this.finalized,
    this.dashCycle = 24,
    this.dashRatio = 1,
  });

  final String id;
  final String tool;
  final int color;
  final double baseWidth;
  final List<StrokePoint> points;
  final bool finalized;

  /// Length of one dash repeat, in points. Ignored when [dashRatio] is 1.
  final double dashCycle;

  /// Fraction of each repeat that is drawn. 1 is a solid line.
  final double dashRatio;

  StrokeObject copyWith({List<StrokePoint>? points, bool? finalized}) {
    return StrokeObject(
      id: id,
      tool: tool,
      color: color,
      baseWidth: baseWidth,
      points: points ?? this.points,
      finalized: finalized ?? this.finalized,
      dashCycle: dashCycle,
      dashRatio: dashRatio,
    );
  }

  Map<String, Object> toJson() => {
    'type': 'stroke',
    'id': id,
    'tool': tool,
    'color': color,
    'baseWidth': baseWidth,
    'finalized': finalized,
    'dashCycle': dashCycle,
    'dashRatio': dashRatio,
    'points': [for (final point in points) point.toJson()],
  };

  factory StrokeObject.fromJson(Map<String, Object?> json) {
    return StrokeObject(
      id: json['id']! as String,
      tool: json['tool']! as String,
      color: json['color']! as int,
      baseWidth: (json['baseWidth']! as num).toDouble(),
      points: [
        for (final point in json['points']! as List<Object?>)
          StrokePoint.fromJson((point as Map).cast<String, Object?>()),
      ],
      finalized: json['finalized'] as bool? ?? false,
      dashCycle: (json['dashCycle'] as num?)?.toDouble() ?? 24,
      dashRatio: (json['dashRatio'] as num?)?.toDouble() ?? 1,
    );
  }
}

StrokeObject? strokeFromObject(Object? object) {
  if (object is! Map) {
    return null;
  }
  final json = object.cast<String, Object?>();
  if (json['type'] != 'stroke') {
    return null;
  }
  return StrokeObject.fromJson(json);
}

List<StrokeObject> strokesIn(Iterable<Object?> objects) {
  return [for (final object in objects) ?strokeFromObject(object)];
}

/// Carries the last sample's fitted circle and the sums behind it.
/// The next sample slides that window instead of starting over.
class StrokeCursor {
  int connected = 0;
  double incomingX = 0;
  double incomingY = 0;
  bool hasIncoming = false;
  _Poly? _poly;
  final _PolySums _sums = _PolySums();
}

/// Samples a mouse point. Pressure and opacity use fixed values.
StrokePoint mouseSample({
  required double x,
  required double y,
  required double time,
  required double baseWidth,
}) {
  return StrokePoint(
    x: x,
    y: y,
    time: time,
    width: baseWidth,
    height: baseWidth,
    opacity: missingOpacity,
    pressure: missingPressure,
  );
}

/// Builds the points that are both shown while drawing and stored on pen up.
/// A segment is painted only after later samples have arrived, so the curve is final.
StrokeObject bakePenStroke(StrokeObject stroke) {
  return stroke.copyWith(
    points: causalPaint(stroke.points, stroke.baseWidth),
    finalized: true,
  );
}

List<StrokePoint> pointsForPaint(StrokeObject stroke) {
  if (stroke.finalized) {
    return stroke.points;
  }
  return causalPaint(stroke.points, stroke.baseWidth);
}

List<StrokePoint> causalPaint(List<StrokePoint> raw, double baseWidth) {
  if (raw.isEmpty) {
    return raw;
  }
  var painted = <StrokePoint>[];
  var kept = <StrokePoint>[];
  final cursor = StrokeCursor();
  for (final sample in raw) {
    final next = appendCausalPoint(
      raw: kept,
      painted: painted,
      sample: sample,
      baseWidth: baseWidth,
      connected: cursor.connected,
      cursor: cursor,
    );
    kept = next.raw;
    painted = next.painted;
  }
  return finishStroke(
    raw: kept,
    painted: painted,
    connected: cursor.connected,
    cursor: cursor,
  ).painted;
}

List<StrokePoint> densifySamples(List<StrokePoint> points) {
  return causalPaint(
    points,
    points.isEmpty ? penBaseWidth : points.first.width,
  );
}

({List<StrokePoint> raw, List<StrokePoint> painted, int connected})
appendCausalPoint({
  required List<StrokePoint> raw,
  required List<StrokePoint> painted,
  required StrokePoint sample,
  required double baseWidth,
  required int connected,
  StrokeCursor? cursor,
}) {
  if (identical(raw, painted)) {
    painted = List<StrokePoint>.of(painted);
  }
  final sized = raw.isEmpty
      ? sample.copyWith(width: baseWidth, height: baseWidth)
      : _widthFromPrevious(raw.last, sample, baseWidth);
  raw.add(sized);
  if (painted.isEmpty) {
    painted.add(raw.first);
  }
  final ready = _drawReady(
    raw: raw,
    painted: painted,
    connected: connected,
    hold: _holdCount(raw),
    cursor: cursor,
  );
  cursor?.connected = ready;
  return (raw: raw, painted: painted, connected: ready);
}

({List<StrokePoint> raw, List<StrokePoint> painted, int connected})
finishStroke({
  required List<StrokePoint> raw,
  required List<StrokePoint> painted,
  required int connected,
  StrokeCursor? cursor,
}) {
  if (painted.isEmpty && raw.isNotEmpty) {
    painted.add(raw.first);
  }
  final ready = _drawReady(
    raw: raw,
    painted: painted,
    connected: connected,
    hold: 1,
    cursor: cursor,
  );
  cursor?.connected = ready;
  return (raw: raw, painted: painted, connected: ready);
}

int _drawReady({
  required List<StrokePoint> raw,
  required List<StrokePoint> painted,
  required int connected,
  required int hold,
  StrokeCursor? cursor,
}) {
  var next = connected;
  while (raw.length - 1 - next >= hold) {
    next += 1;
    _appendArc(painted, raw, next, cursor);
  }
  return next;
}

/// How many not-yet-connected samples to wait for. A longer gap means the input is late,
/// so the curve needs more following points before it is drawn.
int _holdCount(List<StrokePoint> raw) {
  if (raw.length < 2) {
    return 2;
  }
  final gap = raw.last.time - raw[raw.length - 2].time;
  if (gap >= 0.024) {
    return 4;
  }
  if (gap >= 0.014) {
    return 3;
  }
  return 2;
}

void _appendArc(
  List<StrokePoint> result,
  List<StrokePoint> raw,
  int index,
  StrokeCursor? cursor,
) {
  final start = raw[index - 1];
  final end = raw[index];
  void remember() {
    if (cursor == null) {
      return;
    }
    cursor.incomingX = end.x - start.x;
    cursor.incomingY = end.y - start.y;
    cursor.hasIncoming = true;
  }

  final chord = _hypot(end.x - start.x, end.y - start.y);
  if (chord < minFitDistance) {
    _addIfLater(result, end);
    remember();
    return;
  }
  if (chord < directJoinDistance) {
    final bulge = _allowedBulge(raw, index, start, end, chord, cursor);
    if (bulge < 0.7) {
      _appendChord(result, start, end, straightSpacing);
      remember();
      return;
    }
  }
  final poly = _polyFor(raw, index, cursor);
  if (poly == null || (end.time - start.time).abs() <= 0.0001) {
    _appendChord(result, start, end, straightSpacing);
    remember();
    return;
  }
  final atStart = poly.at(start.time);
  final atEnd = poly.at(end.time);
  Offset at(double u) {
    final time = start.time + (end.time - start.time) * u;
    final point = poly.at(time);
    return Offset(
      point.dx + (start.x - atStart.dx) * (1 - u) + (end.x - atEnd.dx) * u,
      point.dy + (start.y - atStart.dy) * (1 - u) + (end.y - atEnd.dy) * u,
    );
  }

  final allowed = _allowedBulge(raw, index, start, end, chord, cursor);
  final rough = at(0.5);
  if (_hypot(
        rough.dx - (start.x + end.x) / 2,
        rough.dy - (start.y + end.y) / 2,
      ) >
      allowed) {
    _appendChord(result, start, end, straightSpacing);
    remember();
    return;
  }
  final spacing = allowed > 2 ? tightSpacing : straightSpacing;
  final lengthGuess = math.max(
    chord,
    _hypot(rough.dx - start.x, rough.dy - start.y) +
        _hypot(end.x - rough.dx, end.y - rough.dy),
  );
  final steps = math.max(1, (lengthGuess / spacing).ceil());
  for (var step = 1; step <= steps; step++) {
    final u = step / steps;
    if (step == steps) {
      _addIfLater(result, end);
      break;
    }
    final point = at(u);
    _addIfLater(
      result,
      _lerpSample(start, end, u).copyWith(x: point.dx, y: point.dy),
    );
  }
  remember();
}

double _allowedBulge(
  List<StrokePoint> raw,
  int index,
  StrokePoint start,
  StrokePoint end,
  double chord,
  StrokeCursor? cursor,
) {
  var inX = 0.0;
  var inY = 0.0;
  if (cursor != null && cursor.hasIncoming) {
    inX = cursor.incomingX;
    inY = cursor.incomingY;
  } else if (index >= 2) {
    final previous = raw[index - 2];
    inX = start.x - previous.x;
    inY = start.y - previous.y;
  }
  final incoming = _hypot(inX, inY);
  var expected = 0.0;
  if (incoming > 0.5) {
    expected = math.max(
      expected,
      _bulgeForTurn(inX, inY, end.x - start.x, end.y - start.y, chord),
    );
  }
  if (index + 1 < raw.length) {
    final next = raw[index + 1];
    expected = math.max(
      expected,
      _bulgeForTurn(
        end.x - start.x,
        end.y - start.y,
        next.x - end.x,
        next.y - end.y,
        chord,
      ),
    );
  }
  return math.max(1.0, expected * 1.35);
}

double _bulgeForTurn(
  double inX,
  double inY,
  double outX,
  double outY,
  double chord,
) {
  final incoming = _hypot(inX, inY);
  final outgoing = _hypot(outX, outY);
  if (incoming <= 0.5 || outgoing <= 0.5) {
    return 0;
  }
  final cross = inX * outY - inY * outX;
  final dot = inX * outX + inY * outY;
  final delta = math.atan2(cross, dot).abs();
  if (delta <= 0.001 || delta >= 2.5) {
    return 0;
  }
  return chord * (1 - math.cos(delta)) / (2 * math.sin(delta));
}

void _appendChord(
  List<StrokePoint> result,
  StrokePoint start,
  StrokePoint end,
  double spacing,
) {
  final distance = _hypot(end.x - start.x, end.y - start.y);
  final steps = math.max(1, (distance / spacing).ceil());
  for (var step = 1; step <= steps; step++) {
    _addIfLater(
      result,
      step == steps ? end : _lerpSample(start, end, step / steps),
    );
  }
}

void _addIfLater(List<StrokePoint> result, StrokePoint point) {
  final last = result.last;
  if (point.time + 0.0000001 < last.time) {
    return;
  }
  if (_hypot(point.x - last.x, point.y - last.y) < 0.05 &&
      (point.time - last.time).abs() < 0.0001) {
    return;
  }
  result.add(point);
}

class _Poly {
  const _Poly(this.ax, this.bx, this.cx, this.ay, this.by, this.cy);

  final double ax;
  final double bx;
  final double cx;
  final double ay;
  final double by;
  final double cy;

  Offset at(double time) {
    final t2 = time * time;
    return Offset(ax * t2 + bx * time + cx, ay * t2 + by * time + cy);
  }
}

_Poly? _polyFor(List<StrokePoint> raw, int index, StrokeCursor? cursor) {
  final from = math.max(0, index - 1);
  final to = math.min(raw.length, index + 2);
  if (to - from < 3) {
    return null;
  }
  final cached = cursor?._poly;
  if (cached != null && _polyFits(raw, from, to, cached)) {
    return cached;
  }
  if (cursor != null) {
    cursor._sums.sync(raw, from, to);
    final fitted = cursor._sums.solve(raw);
    cursor._poly = fitted;
    return fitted;
  }
  return _fitPoly(raw.sublist(from, to));
}

bool _polyFits(List<StrokePoint> raw, int from, int to, _Poly poly) {
  var error = 0.0;
  var count = 0;
  for (var index = from; index < to; index++) {
    final point = raw[index];
    final at = poly.at(point.time);
    error += _hypot(point.x - at.dx, point.y - at.dy);
    count += 1;
  }
  return count >= 3 && error / count <= 8;
}

class _PolySums {
  double st4 = 0;
  double st3 = 0;
  double st2 = 0;
  double st1 = 0;
  double sn = 0;
  double xt2 = 0;
  double xt1 = 0;
  double x = 0;
  double yt2 = 0;
  double yt1 = 0;
  double y = 0;
  int from = 0;
  int to = 0;

  void sync(List<StrokePoint> raw, int nextFrom, int nextTo) {
    if (nextFrom < from || nextTo < to || to < nextFrom) {
      st4 = 0;
      st3 = 0;
      st2 = 0;
      st1 = 0;
      sn = 0;
      xt2 = 0;
      xt1 = 0;
      x = 0;
      yt2 = 0;
      yt1 = 0;
      y = 0;
      from = nextFrom;
      to = nextFrom;
    }
    while (from < nextFrom) {
      _accumulate(raw[from], -1);
      from += 1;
    }
    while (to < nextTo) {
      _accumulate(raw[to], 1);
      to += 1;
    }
  }

  void _accumulate(StrokePoint point, double sign) {
    final t = point.time;
    final t2 = t * t;
    st4 += sign * t2 * t2;
    st3 += sign * t2 * t;
    st2 += sign * t2;
    st1 += sign * t;
    sn += sign;
    xt2 += sign * t2 * point.x;
    xt1 += sign * t * point.x;
    x += sign * point.x;
    yt2 += sign * t2 * point.y;
    yt1 += sign * t * point.y;
    y += sign * point.y;
  }

  _Poly? solve(List<StrokePoint> raw) {
    final poly = _solve();
    if (poly == null || !_polyFits(raw, from, to, poly)) {
      return null;
    }
    if (sn <= 3) {
      return poly;
    }
    var worst = -1;
    var worstMiss = 0.0;
    for (var index = from; index < to; index++) {
      final point = raw[index];
      final at = poly.at(point.time);
      final miss = _hypot(point.x - at.dx, point.y - at.dy);
      if (miss > worstMiss) {
        worstMiss = miss;
        worst = index;
      }
    }
    if (worst < 0 || worstMiss <= 6) {
      return poly;
    }
    final copy = _PolySums()
      ..st4 = st4
      ..st3 = st3
      ..st2 = st2
      ..st1 = st1
      ..sn = sn
      ..xt2 = xt2
      ..xt1 = xt1
      ..x = x
      ..yt2 = yt2
      ..yt1 = yt1
      ..y = y
      ..from = from
      ..to = to;
    copy._accumulate(raw[worst], -1);
    final without = copy._solve();
    if (without == null) {
      return poly;
    }
    return without;
  }

  _Poly? _solve() {
    if (sn < 3) {
      return null;
    }
    final det = _det3(st4, st3, st2, st3, st2, st1, st2, st1, sn);
    if (det.abs() > 1e-12) {
      final ax = _det3(xt2, st3, st2, xt1, st2, st1, x, st1, sn) / det;
      final bx = _det3(st4, xt2, st2, st3, xt1, st1, st2, x, sn) / det;
      final cx = _det3(st4, st3, xt2, st3, st2, xt1, st2, st1, x) / det;
      final ay = _det3(yt2, st3, st2, yt1, st2, st1, y, st1, sn) / det;
      final by = _det3(st4, yt2, st2, st3, yt1, st1, st2, y, sn) / det;
      final cy = _det3(st4, st3, yt2, st3, st2, yt1, st2, st1, y) / det;
      return _Poly(ax, bx, cx, ay, by, cy);
    }
    final det2 = st2 * sn - st1 * st1;
    if (det2.abs() < 1e-12) {
      return null;
    }
    final bx = (xt1 * sn - st1 * x) / det2;
    final cx = (st2 * x - st1 * xt1) / det2;
    final by = (yt1 * sn - st1 * y) / det2;
    final cy = (st2 * y - st1 * yt1) / det2;
    return _Poly(0, bx, cx, 0, by, cy);
  }
}

_Poly? _fitPoly(List<StrokePoint> points) {
  if (points.length < 3) {
    return null;
  }
  final sums = _PolySums();
  for (final point in points) {
    sums._accumulate(point, 1);
  }
  sums.to = points.length;
  final poly = sums._solve();
  if (poly == null || !_polyFits(points, 0, points.length, poly)) {
    return null;
  }
  return poly;
}

double _det3(
  double a,
  double b,
  double c,
  double d,
  double e,
  double f,
  double g,
  double h,
  double i,
) {
  return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
}

StrokePoint _widthFromPrevious(
  StrokePoint previous,
  StrokePoint next,
  double baseWidth,
) {
  final dt = next.time - previous.time;
  final distance = _hypot(next.x - previous.x, next.y - previous.y);
  final speed = dt <= 0.0001 ? 0.0 : distance / dt;
  final pace = (speed / 900).clamp(0.0, 1.0);
  final pressure = next.pressure <= 0 ? missingPressure : next.pressure;
  final width = baseWidth * (1.1 - 0.2 * pace) * (0.7 + 0.6 * pressure);
  return next.copyWith(width: width, height: width);
}

StrokePoint _lerpSample(StrokePoint start, StrokePoint end, double t) {
  double? angle(double? from, double? to) {
    if (from == null || to == null) {
      return null;
    }
    return from + (to - from) * t;
  }

  return StrokePoint(
    x: start.x + (end.x - start.x) * t,
    y: start.y + (end.y - start.y) * t,
    time: start.time + (end.time - start.time) * t,
    width: start.width + (end.width - start.width) * t,
    height: start.height + (end.height - start.height) * t,
    opacity: start.opacity + (end.opacity - start.opacity) * t,
    pressure: start.pressure + (end.pressure - start.pressure) * t,
    azimuth: angle(start.azimuth, end.azimuth),
    altitude: angle(start.altitude, end.altitude),
  );
}

double _hypot(double x, double y) => math.sqrt(x * x + y * y);

bool drawsInk(PointerDeviceKind kind) {
  return kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus ||
      kind == PointerDeviceKind.mouse;
}

StrokePoint sampleFromPointer({
  required PointerEvent event,
  required double x,
  required double y,
  required double time,
  required double baseWidth,
}) {
  return StrokePoint(
    x: x,
    y: y,
    time: time,
    width: baseWidth,
    height: baseWidth,
    opacity: missingOpacity,
    pressure: _pressureOf(event),
    azimuth: _hasStylusPose(event) ? event.orientation : null,
    altitude: _hasStylusPose(event) ? (math.pi / 2) - event.tilt : null,
  );
}

bool _hasStylusPose(PointerEvent event) {
  return event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;
}

double _pressureOf(PointerEvent event) {
  if (!_hasStylusPose(event) || event.pressureMax <= event.pressureMin) {
    return missingPressure;
  }
  return ((event.pressure - event.pressureMin) /
          (event.pressureMax - event.pressureMin))
      .clamp(0.0, 1.0);
}

void paintStroke(Canvas canvas, StrokeObject stroke) {
  if (stroke.tool == 'fixed') {
    _paintFixed(canvas, stroke);
    return;
  }
  final paint = Paint()
    ..color = Color(stroke.color)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  final points = stroke.points;
  if (points.isEmpty) {
    return;
  }
  final solid = stroke.dashRatio >= 0.999 || stroke.dashCycle <= 0;
  if (points.length == 1) {
    if (!solid && stroke.dashRatio <= 0) {
      return;
    }
    canvas.drawCircle(
      Offset(points.single.x, points.single.y),
      points.single.width / 2,
      paint..style = PaintingStyle.fill,
    );
    return;
  }
  paint.style = PaintingStyle.stroke;
  _paintIsolated(canvas, paint, points);
  if (solid) {
    for (var index = 0; index < points.length - 1; index++) {
      final start = points[index];
      final end = points[index + 1];
    if (points[index + 1].gap) {
      continue;
    }
    canvas.drawLine(
      Offset(start.x, start.y),
      Offset(end.x, end.y),
      paint..strokeWidth = (start.width + end.width) / 2,
    );
    }
    return;
  }
  paint
    ..strokeCap = StrokeCap.butt
    ..strokeJoin = StrokeJoin.bevel;
  final cycle = stroke.dashCycle;
  final on = cycle * stroke.dashRatio.clamp(0.0, 1.0);
  if (on <= 0) {
    return;
  }
  var traveled = 0.0;
  for (var index = 0; index < points.length - 1; index++) {
    final start = points[index];
    final end = points[index + 1];
    if (end.gap) {
      continue;
    }
    paint.strokeWidth = (start.width + end.width) / 2;
    final length = _hypot(end.x - start.x, end.y - start.y);
    if (length == 0) {
      continue;
    }
    var local = 0.0;
    while (local < length - 0.001) {
      final into = (traveled + local) % cycle;
      final drawing = into < on;
      final remain = drawing ? on - into : cycle - into;
      final step = math.min(math.max(remain, 0.001), length - local);
      if (drawing) {
        final from = local / length;
        final to = math.min(1.0, (local + step) / length);
        canvas.drawLine(
          Offset(
            start.x + (end.x - start.x) * from,
            start.y + (end.y - start.y) * from,
          ),
          Offset(
            start.x + (end.x - start.x) * to,
            start.y + (end.y - start.y) * to,
          ),
          paint,
        );
      }
      local += step;
    }
    traveled += length;
  }
}

void _paintFixed(Canvas canvas, StrokeObject stroke, {Paint? paint}) {
  final fill = Paint()
    ..color = paint?.color ?? Color(stroke.color)
    ..blendMode = paint?.blendMode ?? BlendMode.srcOver
    ..isAntiAlias = false
    ..style = PaintingStyle.fill;
  final points = stroke.points;
  var index = 0;
  while (index < points.length) {
    final start = points[index];
    if (index + 1 < points.length && !points[index + 1].gap) {
      final end = points[index + 1];
      final height = start.height;
      final left = math.min(start.x, end.x) - height / 2;
      final right = math.max(start.x, end.x) + height / 2;
      canvas.drawRect(
        Rect.fromLTRB(left, start.y - height / 2, right, start.y + height / 2),
        fill,
      );
      index += 2;
      continue;
    }
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(start.x, start.y),
        width: start.width,
        height: start.height,
      ),
      fill,
    );
    index += 1;
  }
}

void _paintIsolated(Canvas canvas, Paint paint, List<StrokePoint> points) {
  for (var index = 0; index < points.length; index++) {
    final point = points[index];
    final starts = index == 0 || point.gap;
    final ends = index == points.length - 1 || points[index + 1].gap;
    if (!starts || !ends) {
      continue;
    }
    canvas.drawCircle(
      Offset(point.x, point.y),
      point.width / 2,
      paint..style = PaintingStyle.fill,
    );
  }
  paint.style = PaintingStyle.stroke;
}

/// Draws a round stroke slightly wider than [paintStroke], so a wash or a cut covers the ink edge as well as the center.
void paintStrokeCover(
  Canvas canvas,
  StrokeObject stroke,
  Paint paint, {
  double pad = 0,
}) {
  if (stroke.tool == 'fixed') {
    _paintFixed(canvas, stroke, paint: paint);
    return;
  }
  final points = stroke.points;
  if (points.isEmpty) {
    return;
  }
  paint
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  if (points.length == 1) {
    canvas.drawCircle(
      Offset(points.single.x, points.single.y),
      points.single.width / 2 + pad,
      paint..style = PaintingStyle.fill,
    );
    return;
  }
  paint.style = PaintingStyle.stroke;
  for (var index = 0; index < points.length - 1; index++) {
    final start = points[index];
    final end = points[index + 1];
    if (end.gap) {
      continue;
    }
    canvas.drawLine(
      Offset(start.x, start.y),
      Offset(end.x, end.y),
      paint..strokeWidth = math.max(start.width, end.width) + pad * 2,
    );
  }
}

List<StrokeObject> undrawnStrokes(
  Set<String> drawnIds,
  List<StrokeObject> strokes,
) {
  return [
    for (final stroke in strokes)
      if (!drawnIds.contains(stroke.id)) stroke,
  ];
}

Path outlineOf(List<StrokePoint> points) {
  final path = Path();
  if (points.isEmpty) {
    return path;
  }
  if (points.length == 1) {
    final point = points.single;
    path.addOval(
      Rect.fromCircle(
        center: Offset(point.x, point.y),
        radius: point.width / 2,
      ),
    );
    return path;
  }
  final left = <Offset>[];
  final right = <Offset>[];
  for (var index = 0; index < points.length; index++) {
    final previous = index == 0 ? points[index] : points[index - 1];
    final next = index == points.length - 1 ? points[index] : points[index + 1];
    var dx = next.x - previous.x;
    var dy = next.y - previous.y;
    final length = _hypot(dx, dy);
    if (length == 0) {
      dx = 1;
      dy = 0;
    } else {
      dx /= length;
      dy /= length;
    }
    final half = points[index].width / 2;
    left.add(Offset(points[index].x - dy * half, points[index].y + dx * half));
    right.add(Offset(points[index].x + dy * half, points[index].y - dx * half));
  }
  path.moveTo(left.first.dx, left.first.dy);
  for (final point in left.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  for (final point in right.reversed) {
    path.lineTo(point.dx, point.dy);
  }
  path.close();
  return path;
}
