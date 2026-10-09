import 'dart:ui';

class TextBox {
  const TextBox({
    required this.id,
    required this.version,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.source,
  });

  final String id;
  final int version;
  final double x;
  final double y;
  final double width;
  final double height;
  final String source;

  TextBox copyWith({
    int? version,
    double? x,
    double? y,
    double? width,
    double? height,
    String? source,
  }) {
    return TextBox(
      id: id,
      version: version ?? this.version,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      source: source ?? this.source,
    );
  }

  Map<String, Object> toJson() => {
    'type': 'text',
    'id': id,
    'version': version,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'source': source,
  };

  static TextBox? fromObject(Object? object) {
    if (object is! Map || object['type'] != 'text') {
      return null;
    }
    final id = object['id'];
    if (id is! String) {
      return null;
    }
    return TextBox(
      id: id,
      version: object['version'] is num
          ? (object['version'] as num).toInt()
          : 1,
      x: (object['x'] as num?)?.toDouble() ?? 0,
      y: (object['y'] as num?)?.toDouble() ?? 0,
      width: (object['width'] as num?)?.toDouble() ?? 200,
      height: (object['height'] as num?)?.toDouble() ?? 80,
      source: object['source'] as String? ?? '',
    );
  }

  Rect get rect => Rect.fromLTWH(x, y, width, height);
}
