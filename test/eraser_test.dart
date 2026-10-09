import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_page/src/ink/eraser.dart';
import 'package:yet_another_page/src/ink/stroke.dart';

void main() {
  test('object eraser removes only the stroke it touches', () {
    final line = _line(const [0, 20, 40]);
    expect(strokeHitsEraser(line, const [Offset(20, 0)]), isTrue);
    expect(strokeHitsEraser(line, const [Offset(20, 80)]), isFalse);
  });

  test('region eraser keeps the untouched ends and their widths', () {
    final line = _line(const [0, 20, 40, 60, 80]);
    final pieces = eraseRegion(line, const [Offset(40, 0)]);
    expect(pieces, isNotNull);
    expect(pieces, hasLength(2));
    expect(pieces!.first.points.map((point) => point.x), [0, 20]);
    expect(pieces.last.points.map((point) => point.x), [60, 80]);
    expect(pieces.first.points.first.width, line.points.first.width);
    expect(pieces.first.id, isNot(line.id));
    expect(pieces.last.id, isNot(pieces.first.id));
    expect(eraseRegion(line, const [Offset(40, 80)]), isNull);
  });
}

StrokeObject _line(List<double> xs) {
  return StrokeObject(
    id: 'stroke',
    tool: 'pen',
    color: penColor,
    baseWidth: penBaseWidth,
    finalized: true,
    points: [
      for (var index = 0; index < xs.length; index++)
        StrokePoint(
          x: xs[index],
          y: 0,
          time: index * 0.01,
          width: 3,
          height: 3,
          opacity: 1,
          pressure: 0.5,
        ),
    ],
  );
}
