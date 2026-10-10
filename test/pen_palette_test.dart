import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_page/src/ink/pen_palette.dart';

void main() {
  test('slot limits drop the tail and new slots use the manual defaults', () {
    final palette = PenPalette.initial();
    expect(palette.widths, [1.5, 3, 6]);
    expect(palette.width, 3);
    expect(palette.colors, PenPalette.defaultColors);
    expect(palette.dashes.single.solid, isTrue);

    final more = palette.setWidthCount(4).setColorCount(6).setDashCount(2);
    expect(more.widths.last, PenPalette.newWidth);
    expect(more.colors.last, PenPalette.newColor);
    expect(more.dashes.last.solid, isTrue);

    final less = more
        .selectWidth(3)
        .selectColor(5)
        .selectDash(1)
        .setWidthCount(2)
        .setColorCount(3)
        .setDashCount(1);
    expect(less.widths, [1.5, 3]);
    expect(less.widthIndex, 1);
    expect(less.colors, PenPalette.defaultColors.take(3).toList());
    expect(less.colorIndex, 2);
    expect(less.dashes, hasLength(1));
    expect(less.dashIndex, 0);
  });

  test('a palette round trip keeps the selected slots', () {
    final palette = PenPalette.initial()
        .selectColor(2)
        .updateDash(0, const PenDash(cycle: 40, ratio: 0.5));
    final restored = PenPalette.fromJson(palette.toJson());
    expect(restored.color, palette.color);
    expect(restored.dash.cycle, 40);
    expect(restored.dash.ratio, 0.5);
  });
}
