import 'package:flutter/services.dart';

/// A stylus side control. The hardware gesture differs by platform.
///
/// A platform reports a press with [StylusSideButton.report]. It does not
/// decide what the app does next. iOS reports an Apple Pencil Pro squeeze.
/// Another platform reports its own side button the same way.
abstract interface class StylusSideButton {
  static const channelName = 'dev.yetanotherpage/stylus';
  static const reportMethod = 'sideButton';

  void addListener(StylusSideButtonListener listener);

  void removeListener(StylusSideButtonListener listener);

  /// [globalPosition] is the pointer in global coordinates, when known.
  void report(Offset? globalPosition);
}

typedef StylusSideButtonListener = void Function(Offset? globalPosition);

/// Receives [StylusSideButton.reportMethod] from the current platform.
class ChannelStylusSideButton implements StylusSideButton {
  final List<StylusSideButtonListener> _listeners = [];

  void attachPlatform() {
    const MethodChannel(
      StylusSideButton.channelName,
    ).setMethodCallHandler((call) async {
      if (call.method != StylusSideButton.reportMethod) {
        return;
      }
      report(_position(call.arguments));
    });
  }

  @override
  void addListener(StylusSideButtonListener listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(StylusSideButtonListener listener) {
    _listeners.remove(listener);
  }

  @override
  void report(Offset? globalPosition) {
    if (_listeners.isEmpty) {
      return;
    }
    _listeners.last(globalPosition);
  }

  Offset? _position(Object? arguments) {
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

/// Side button used by the app. Platforms and tests call [report].
final ChannelStylusSideButton stylusSideButton = ChannelStylusSideButton();
