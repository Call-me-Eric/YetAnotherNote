import 'package:flutter/services.dart';

/// Stylus gestures that open the tool arc.
///
/// Apple Pencil Pro squeeze calls [toggleToolArc]. Another pen can call the
/// same method, passing the pointer in global coordinates.
class StylusInput {
  static const channelName = 'dev.yetanotherpage/stylus';

  static final List<void Function(Offset? globalPosition)> _handlers = [];

  static void addHandler(void Function(Offset? globalPosition) handler) {
    _handlers.add(handler);
  }

  static void removeHandler(void Function(Offset? globalPosition) handler) {
    _handlers.remove(handler);
  }

  static void toggleToolArc(Offset? globalPosition) {
    if (_handlers.isEmpty) {
      return;
    }
    _handlers.last(globalPosition);
  }

  static void attachPlatform() {
    const MethodChannel(channelName).setMethodCallHandler((call) async {
      if (call.method != 'toggleToolArc') {
        return;
      }
      toggleToolArc(_position(call.arguments));
    });
  }

  static Offset? _position(Object? arguments) {
    if (arguments is! Map) {
      return null;
    }
    final x = arguments['x'];
    final y = arguments['y'];
    if (x is! num || y is! num) {
      return null;
    }
    return Offset(x.toDouble(), y.toDouble());
  }
}
