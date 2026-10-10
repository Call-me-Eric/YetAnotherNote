import 'dart:math' as math;
import 'dart:ui';

import 'stroke.dart';
import 'text_box.dart';

class NoteClipboard {
  static List<StrokeObject> strokes = const [];
  static List<TextBox> texts = const [];

  static bool get isEmpty => strokes.isEmpty && texts.isEmpty;

  static void put({
    required List<StrokeObject> strokes,
    required List<TextBox> texts,
  }) {
    NoteClipboard.strokes = strokes;
    NoteClipboard.texts = texts;
  }
}

bool pointInPolygon(Offset point, List<Offset> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[j];
    final b = polygon[i];
    final intersect =
        ((b.dy > point.dy) != (a.dy > point.dy)) &&
        (point.dx <
            (a.dx - b.dx) * (point.dy - b.dy) / (a.dy - b.dy + 0.0000001) +
                b.dx);
    if (intersect) {
      inside = !inside;
    }
  }
  return inside;
}

bool strokeHitsRegion(
  StrokeObject stroke, {
  Rect? rect,
  List<Offset>? polygon,
}) {
  final points = stroke.points;
  for (var index = 0; index < points.length; index++) {
    final point = points[index];
    final at = Offset(point.x, point.y);
    final radius = point.width / 2;
    if (rect != null && _diskHitsRect(at, radius, rect)) {
      return true;
    }
    if (polygon != null &&
        polygon.length >= 3 &&
        _diskHitsPolygon(at, radius, polygon)) {
      return true;
    }
    if (index == points.length - 1 || points[index + 1].gap) {
      continue;
    }
    final next = points[index + 1];
    final end = Offset(next.x, next.y);
    final reach = (point.width + next.width) / 4;
    if (rect != null && _capsuleHitsRect(at, end, reach, rect)) {
      return true;
    }
    if (polygon != null &&
        polygon.length >= 3 &&
        _capsuleHitsPolygon(at, end, reach, polygon)) {
      return true;
    }
  }
  return false;
}

bool textHitsRegion(TextBox box, {Rect? rect, List<Offset>? polygon}) {
  if (rect != null && rect.overlaps(box.rect)) {
    return true;
  }
  if (polygon == null || polygon.length < 3) {
    return false;
  }
  final corners = [
    box.rect.topLeft,
    box.rect.topRight,
    box.rect.bottomRight,
    box.rect.bottomLeft,
  ];
  for (final corner in corners) {
    if (pointInPolygon(corner, polygon)) {
      return true;
    }
  }
  for (final vertex in polygon) {
    if (box.rect.contains(vertex)) {
      return true;
    }
  }
  for (var index = 0; index < corners.length; index++) {
    final a = corners[index];
    final b = corners[(index + 1) % corners.length];
    for (var edge = 0; edge < polygon.length; edge++) {
      if (_segmentsCross(a, b, polygon[edge], polygon[(edge + 1) % polygon.length])) {
        return true;
      }
    }
  }
  return false;
}

bool _diskHitsRect(Offset center, double radius, Rect rect) {
  final nearest = Offset(
    center.dx.clamp(rect.left, rect.right),
    center.dy.clamp(rect.top, rect.bottom),
  );
  return (center - nearest).distance <= radius;
}

bool _diskHitsPolygon(Offset center, double radius, List<Offset> polygon) {
  if (pointInPolygon(center, polygon)) {
    return true;
  }
  for (var index = 0; index < polygon.length; index++) {
    final distance = _pointSegmentDistance(
      center,
      polygon[index],
      polygon[(index + 1) % polygon.length],
    );
    if (distance <= radius) {
      return true;
    }
  }
  return false;
}

bool _capsuleHitsRect(Offset start, Offset end, double radius, Rect rect) {
  if (_diskHitsRect(start, radius, rect) || _diskHitsRect(end, radius, rect)) {
    return true;
  }
  final corners = [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ];
  for (var index = 0; index < corners.length; index++) {
    final a = corners[index];
    final b = corners[(index + 1) % corners.length];
    if (_segmentsCross(start, end, a, b)) {
      return true;
    }
    if (_pointSegmentDistance(a, start, end) <= radius) {
      return true;
    }
  }
  return false;
}

bool _capsuleHitsPolygon(
  Offset start,
  Offset end,
  double radius,
  List<Offset> polygon,
) {
  if (_diskHitsPolygon(start, radius, polygon) ||
      _diskHitsPolygon(end, radius, polygon)) {
    return true;
  }
  for (var index = 0; index < polygon.length; index++) {
    final a = polygon[index];
    final b = polygon[(index + 1) % polygon.length];
    if (_segmentsCross(start, end, a, b)) {
      return true;
    }
    if (_pointSegmentDistance(a, start, end) <= radius) {
      return true;
    }
  }
  return false;
}

bool _segmentsCross(Offset a, Offset b, Offset c, Offset d) {
  final ab = b - a;
  final cd = d - c;
  final denom = _cross(ab, cd);
  if (denom.abs() <= 1e-8) {
    return false;
  }
  final ac = c - a;
  final t = _cross(ac, cd) / denom;
  final u = _cross(ac, ab) / denom;
  return t >= 0 && t <= 1 && u >= 0 && u <= 1;
}

double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

double _pointSegmentDistance(Offset point, Offset start, Offset end) {
  final delta = end - start;
  final lengthSquared = delta.dx * delta.dx + delta.dy * delta.dy;
  if (lengthSquared == 0) {
    return (point - start).distance;
  }
  final t =
      ((point.dx - start.dx) * delta.dx + (point.dy - start.dy) * delta.dy) /
      lengthSquared;
  final clamped = t.clamp(0.0, 1.0);
  final nearest = Offset(
    start.dx + delta.dx * clamped,
    start.dy + delta.dy * clamped,
  );
  return (point - nearest).distance;
}

Rect boundsOfObjects({
  required List<StrokeObject> strokes,
  required List<TextBox> texts,
}) {
  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;
  void grow(Rect rect) {
    left = left < rect.left ? left : rect.left;
    top = top < rect.top ? top : rect.top;
    right = right > rect.right ? right : rect.right;
    bottom = bottom > rect.bottom ? bottom : rect.bottom;
  }

  for (final stroke in strokes) {
    for (final point in stroke.points) {
      final pad = point.width / 2;
      grow(
        Rect.fromLTRB(
          point.x - pad,
          point.y - pad,
          point.x + pad,
          point.y + pad,
        ),
      );
    }
  }
  for (final box in texts) {
    grow(box.rect);
  }
  if (left == double.infinity) {
    return Rect.zero;
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

StrokeObject mapStroke(StrokeObject stroke, Offset Function(Offset) map) {
  return stroke.copyWith(
    points: [
      for (final point in stroke.points)
        point.copyWith(x: map(Offset(point.x, point.y)).dx, y: map(Offset(point.x, point.y)).dy),
    ],
  );
}

TextBox mapTextBox(TextBox box, Offset Function(Offset) map) {
  final corners = [
    map(box.rect.topLeft),
    map(box.rect.topRight),
    map(box.rect.bottomLeft),
    map(box.rect.bottomRight),
  ];
  var left = corners.first.dx;
  var top = corners.first.dy;
  var right = left;
  var bottom = top;
  for (final corner in corners) {
    left = left < corner.dx ? left : corner.dx;
    top = top < corner.dy ? top : corner.dy;
    right = right > corner.dx ? right : corner.dx;
    bottom = bottom > corner.dy ? bottom : corner.dy;
  }
  return box.copyWith(x: left, y: top, width: right - left, height: bottom - top);
}

Offset mapMove(Offset point, Offset delta) => point + delta;

Offset mapScale(
  Offset point,
  Offset center,
  double scaleX,
  double scaleY, {
  Offset origin = Offset.zero,
}) {
  final dx = point.dx - origin.dx;
  final dy = point.dy - origin.dy;
  return Offset(origin.dx + dx * scaleX, origin.dy + dy * scaleY);
}

Offset mapRotate(Offset point, Offset center, double radians) {
  final dx = point.dx - center.dx;
  final dy = point.dy - center.dy;
  final c = math.cos(radians);
  final s = math.sin(radians);
  return Offset(center.dx + dx * c - dy * s, center.dy + dx * s + dy * c);
}

Offset mapMirror(Offset point, Offset center, {required bool horizontal}) {
  if (horizontal) {
    return Offset(2 * center.dx - point.dx, point.dy);
  }
  return Offset(point.dx, 2 * center.dy - point.dy);
}
