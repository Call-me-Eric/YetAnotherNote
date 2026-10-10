import 'dart:convert';

import 'stroke.dart';

/// One stored dash: [cycle] is the repeat length in points, [ratio] is the
/// fraction of that repeat which is drawn. 1 is a solid line.
class PenDash {
  const PenDash({required this.cycle, required this.ratio});

  final double cycle;
  final double ratio;

  bool get solid => ratio >= 0.999;

  PenDash copyWith({double? cycle, double? ratio}) {
    return PenDash(cycle: cycle ?? this.cycle, ratio: ratio ?? this.ratio);
  }

  Map<String, Object> toJson() => {'cycle': cycle, 'ratio': ratio};

  static PenDash fromJson(Object? json) {
    if (json is! Map) {
      return PenPalette.solidDash;
    }
    final cycle = (json['cycle'] as num?)?.toDouble() ?? PenPalette.solidDash.cycle;
    final ratio = (json['ratio'] as num?)?.toDouble() ?? 1;
    return PenDash(
      cycle: cycle.clamp(PenPalette.cycleMin, PenPalette.cycleMax),
      ratio: ratio.clamp(0.0, 1.0),
    );
  }
}

/// The pen slots kept on this device: widths, colors, and dash patterns.
///
/// The manual leaves the three default widths blank. They are 1.5, 3 and 6,
/// with 3 selected so a new install matches the previous pen. A new width slot
/// starts at 3. New colors are white. New dashes are solid.
class PenPalette {
  const PenPalette({
    required this.widths,
    required this.widthIndex,
    required this.colors,
    required this.colorIndex,
    required this.dashes,
    required this.dashIndex,
  });

  static const minSlots = 1;
  static const maxSlots = 12;
  static const widthMin = 0.5;
  static const widthMax = 24.0;
  static const cycleMin = 4.0;
  static const cycleMax = 120.0;
  static const newWidth = penBaseWidth;
  static const newColor = 0xFFFFFFFF;
  static const solidDash = PenDash(cycle: 24, ratio: 1);

  static const defaultWidths = [1.5, 3.0, 6.0];
  static const defaultColors = <int>[
    0xFF000000,
    0xFFFFFFFF,
    0xFFFF0000,
    0xFF0000FF,
    0xFFFFFF00,
  ];

  final List<double> widths;
  final int widthIndex;
  final List<int> colors;
  final int colorIndex;
  final List<PenDash> dashes;
  final int dashIndex;

  factory PenPalette.initial() {
    return const PenPalette(
      widths: defaultWidths,
      widthIndex: 1,
      colors: defaultColors,
      colorIndex: 0,
      dashes: [solidDash],
      dashIndex: 0,
    );
  }

  double get width => widths[_index(widthIndex, widths.length)];
  int get color => colors[_index(colorIndex, colors.length)];
  PenDash get dash => dashes[_index(dashIndex, dashes.length)];

  PenPalette selectWidth(int index) => _copy(widthIndex: _index(index, widths.length));

  PenPalette selectColor(int index) => _copy(colorIndex: _index(index, colors.length));

  PenPalette selectDash(int index) => _copy(dashIndex: _index(index, dashes.length));

  PenPalette updateWidth(int index, double width) {
    final next = [...widths];
    next[_index(index, next.length)] = width.clamp(widthMin, widthMax);
    return _copy(widths: next);
  }

  PenPalette updateColor(int index, int color) {
    final next = [...colors];
    next[_index(index, next.length)] = color;
    return _copy(colors: next);
  }

  PenPalette updateDash(int index, PenDash dash) {
    final next = [...dashes];
    next[_index(index, next.length)] = PenDash(
      cycle: dash.cycle.clamp(cycleMin, cycleMax),
      ratio: dash.ratio.clamp(0.0, 1.0),
    );
    return _copy(dashes: next);
  }

  PenPalette setWidthCount(int count) {
    return _copy(
      widths: _resize(widths, count, newWidth),
      widthIndex: _index(widthIndex, count.clamp(minSlots, maxSlots)),
    );
  }

  PenPalette setColorCount(int count) {
    return _copy(
      colors: _resize(colors, count, newColor),
      colorIndex: _index(colorIndex, count.clamp(minSlots, maxSlots)),
    );
  }

  PenPalette setDashCount(int count) {
    return _copy(
      dashes: _resize(dashes, count, solidDash),
      dashIndex: _index(dashIndex, count.clamp(minSlots, maxSlots)),
    );
  }

  Map<String, Object> toJson() => {
    'widths': widths,
    'widthIndex': widthIndex,
    'colors': colors,
    'colorIndex': colorIndex,
    'dashes': [for (final dash in dashes) dash.toJson()],
    'dashIndex': dashIndex,
  };

  factory PenPalette.fromJson(Object? json) {
    if (json is! Map) {
      return PenPalette.initial();
    }
    final widths = _nums(json['widths'], fallback: defaultWidths);
    final colors = _ints(json['colors'], fallback: defaultColors);
    final dashes = _dashes(json['dashes']);
    return PenPalette(
      widths: widths,
      widthIndex: _index(_asInt(json['widthIndex']), widths.length),
      colors: colors,
      colorIndex: _index(_asInt(json['colorIndex']), colors.length),
      dashes: dashes,
      dashIndex: _index(_asInt(json['dashIndex']), dashes.length),
    );
  }

  static String encode(PenPalette palette) => '${jsonEncode(palette.toJson())}\n';

  PenPalette _copy({
    List<double>? widths,
    int? widthIndex,
    List<int>? colors,
    int? colorIndex,
    List<PenDash>? dashes,
    int? dashIndex,
  }) {
    return PenPalette(
      widths: widths ?? this.widths,
      widthIndex: widthIndex ?? this.widthIndex,
      colors: colors ?? this.colors,
      colorIndex: colorIndex ?? this.colorIndex,
      dashes: dashes ?? this.dashes,
      dashIndex: dashIndex ?? this.dashIndex,
    );
  }

  static List<T> _resize<T>(List<T> values, int count, T fill) {
    final nextCount = count.clamp(minSlots, maxSlots);
    if (nextCount == values.length) {
      return values;
    }
    if (nextCount < values.length) {
      return values.sublist(0, nextCount);
    }
    return [...values, for (var i = values.length; i < nextCount; i++) fill];
  }

  static int _index(int index, int length) {
    if (length <= 0) {
      return 0;
    }
    if (index < 0) {
      return 0;
    }
    if (index >= length) {
      return length - 1;
    }
    return index;
  }

  static int _asInt(Object? value) => value is num ? value.toInt() : 0;

  static List<double> _nums(Object? value, {required List<double> fallback}) {
    if (value is! List || value.isEmpty) {
      return fallback;
    }
    final widths = [
      for (final item in value)
        if (item is num) item.toDouble().clamp(widthMin, widthMax),
    ];
    if (widths.isEmpty) {
      return fallback;
    }
    return widths.take(maxSlots).toList();
  }

  static List<int> _ints(Object? value, {required List<int> fallback}) {
    if (value is! List || value.isEmpty) {
      return fallback;
    }
    final colors = [
      for (final item in value)
        if (item is num) item.toInt(),
    ];
    if (colors.isEmpty) {
      return fallback;
    }
    return colors.take(maxSlots).toList();
  }

  static List<PenDash> _dashes(Object? value) {
    if (value is! List || value.isEmpty) {
      return const [solidDash];
    }
    final dashes = [for (final item in value) PenDash.fromJson(item)];
    if (dashes.isEmpty) {
      return const [solidDash];
    }
    return dashes.take(maxSlots).toList();
  }
}
