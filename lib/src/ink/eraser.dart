import 'dart:ui';

import '../ids.dart';
import 'stroke.dart';

enum InkTool { pen, text, objectEraser, regionEraser }

const eraserRadius = 14.0;

bool strokeHitsEraser(
  StrokeObject stroke,
  List<Offset> eraser, {
  double radius = eraserRadius,
  Rect? near,
}) {
  final points = stroke.points;
  if (points.isEmpty || eraser.isEmpty) {
    return false;
  }
  for (final point in points) {
    final pad = point.width / 2;
    if (near != null &&
        (point.x + pad < near.left ||
            point.x - pad > near.right ||
            point.y + pad < near.top ||
            point.y - pad > near.bottom)) {
      continue;
    }
    if (_nearEraser(Offset(point.x, point.y), eraser, radius + pad)) {
      return true;
    }
  }
  for (var index = 0; index < points.length - 1; index++) {
    final start = points[index];
    final end = points[index + 1];
    final pad = (start.width + end.width) / 4;
    if (near != null && !_spanHits(start.x, start.y, end.x, end.y, near, pad)) {
      continue;
    }
    if (_segmentHitsEraser(
      Offset(start.x, start.y),
      Offset(end.x, end.y),
      eraser,
      radius + pad,
    )) {
      return true;
    }
  }
  return false;
}

bool _spanHits(
  double ax,
  double ay,
  double bx,
  double by,
  Rect near,
  double pad,
) {
  final left = (ax < bx ? ax : bx) - pad;
  final right = (ax > bx ? ax : bx) + pad;
  final top = (ay < by ? ay : by) - pad;
  final bottom = (ay > by ? ay : by) + pad;
  return right >= near.left &&
      left <= near.right &&
      bottom >= near.top &&
      top <= near.bottom;
}

/// Cuts [stroke] where the eraser passes. Unchanged strokes return null.
/// A full erase returns an empty list. A partial erase returns the remaining pieces.
List<StrokeObject>? eraseRegion(
  StrokeObject stroke,
  List<Offset> eraser, {
  double radius = eraserRadius,
}) {
  final hit = _hits(stroke.points, eraser, radius);
  if (!hit.hit) {
    return null;
  }
  final runs = <List<StrokePoint>>[];
  var current = <StrokePoint>[];
  for (var index = 0; index < stroke.points.length; index++) {
    if (hit.erased[index]) {
      if (current.isNotEmpty) {
        runs.add(current);
        current = [];
      }
      continue;
    }
    current.add(stroke.points[index]);
    if (hit.cutAfter[index]) {
      runs.add(current);
      current = [];
    }
  }
  if (current.isNotEmpty) {
    runs.add(current);
  }
  return [
    for (final run in runs)
      if (run.isNotEmpty)
        StrokeObject(
          id: newId(),
          tool: stroke.tool,
          color: stroke.color,
          baseWidth: stroke.baseWidth,
          points: run,
          finalized: true,
        ),
  ];
}

class _Hit {
  const _Hit({required this.hit, required this.erased, required this.cutAfter});

  final bool hit;
  final List<bool> erased;
  final List<bool> cutAfter;
}

_Hit _hits(List<StrokePoint> points, List<Offset> eraser, double radius) {
  final erased = List<bool>.filled(points.length, false);
  final cutAfter = List<bool>.filled(points.length, false);
  if (points.isEmpty || eraser.isEmpty) {
    return _Hit(hit: false, erased: erased, cutAfter: cutAfter);
  }
  var hit = false;
  for (var index = 0; index < points.length; index++) {
    final point = points[index];
    final reach = radius + point.width / 2;
    if (_nearEraser(Offset(point.x, point.y), eraser, reach)) {
      erased[index] = true;
      hit = true;
    }
  }
  for (var index = 0; index < points.length - 1; index++) {
    final start = points[index];
    final end = points[index + 1];
    final reach = radius + (start.width + end.width) / 4;
    if (_segmentHitsEraser(
      Offset(start.x, start.y),
      Offset(end.x, end.y),
      eraser,
      reach,
    )) {
      cutAfter[index] = true;
      hit = true;
    }
  }
  return _Hit(hit: hit, erased: erased, cutAfter: cutAfter);
}

bool _nearEraser(Offset point, List<Offset> eraser, double reach) {
  if (eraser.length == 1) {
    return (point - eraser.single).distance <= reach;
  }
  for (var index = 0; index < eraser.length - 1; index++) {
    if (_pointSegment(point, eraser[index], eraser[index + 1]) <= reach) {
      return true;
    }
  }
  return false;
}

bool _segmentHitsEraser(
  Offset start,
  Offset end,
  List<Offset> eraser,
  double reach,
) {
  if (eraser.length == 1) {
    return _pointSegment(eraser.single, start, end) <= reach;
  }
  for (var index = 0; index < eraser.length - 1; index++) {
    if (_segmentsHit(start, end, eraser[index], eraser[index + 1], reach)) {
      return true;
    }
  }
  return false;
}

bool _segmentsHit(Offset a, Offset b, Offset c, Offset d, double limit) {
  if (_cross(b - a, d - c).abs() > 1e-6) {
    final ab = b - a;
    final cd = d - c;
    final ac = c - a;
    final denom = _cross(ab, cd);
    final t = _cross(ac, cd) / denom;
    final u = _cross(ac, ab) / denom;
    if (t >= 0 && t <= 1 && u >= 0 && u <= 1) {
      return true;
    }
  }
  return _pointSegment(a, c, d) <= limit ||
      _pointSegment(b, c, d) <= limit ||
      _pointSegment(c, a, b) <= limit ||
      _pointSegment(d, a, b) <= limit;
}

double _pointSegment(Offset point, Offset start, Offset end) {
  final delta = end - start;
  final lengthSquared = delta.dx * delta.dx + delta.dy * delta.dy;
  if (lengthSquared == 0) {
    return (point - start).distance;
  }
  final t =
      ((point - start).dx * delta.dx + (point - start).dy * delta.dy) /
      lengthSquared;
  final clamped = t.clamp(0.0, 1.0);
  final nearest = Offset(
    start.dx + delta.dx * clamped,
    start.dy + delta.dy * clamped,
  );
  return (point - nearest).distance;
}

double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
