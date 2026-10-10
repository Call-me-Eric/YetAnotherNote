import 'package:flutter/services.dart';

/// Stylus hardware, as reported by the current platform.
///
/// The app only sees this interface. A platform adapter translates its own
/// side button, double tap, and haptic into these calls. Platforms without
/// one of the gestures simply never report it.
abstract interface class StylusSideButton {
  static const channelName = 'dev.yetanotherpage/stylus';
  static const sideButtonMethod = 'sideButton';
  static const doubleTapMethod = 'doubleTap';
  static const prepareHapticMethod = 'prepareHaptic';
  static const playHapticMethod = 'playHaptic';

  void addListener(StylusSideButtonListener listener);

  void removeListener(StylusSideButtonListener listener);

  /// [globalPosition] is the pointer in global coordinates, when known.
  void report(Offset? globalPosition);

  void addDoubleTapListener(VoidCallback listener);

  void removeDoubleTapListener(VoidCallback listener);

  void reportDoubleTap();

  /// Warm the stylus haptic, if this platform has one.
  void prepareHaptic();

  /// Play a short stylus haptic at [global], if this platform has one.
  void playHaptic(Offset global);
}

typedef StylusSideButtonListener = void Function(Offset? globalPosition);

/// Receives platform stylus events and asks the platform to play haptics.
class ChannelStylusSideButton implements StylusSideButton {
  final List<StylusSideButtonListener> _listeners = [];
  final List<VoidCallback> _doubleTaps = [];

  void attachPlatform() {
    const MethodChannel(
      StylusSideButton.channelName,
    ).setMethodCallHandler((call) async {
      if (call.method == StylusSideButton.sideButtonMethod) {
        report(_position(call.arguments));
        return;
      }
      if (call.method == StylusSideButton.doubleTapMethod) {
        reportDoubleTap();
      }
    });
  }

  @override
  void addDoubleTapListener(VoidCallback listener) {
    _doubleTaps.add(listener);
  }

  @override
  void removeDoubleTapListener(VoidCallback listener) {
    _doubleTaps.remove(listener);
  }

  @override
  void reportDoubleTap() {
    if (_doubleTaps.isEmpty) {
      return;
    }
    _doubleTaps.last();
  }

  @override
  void prepareHaptic() {
    const MethodChannel(
      StylusSideButton.channelName,
    ).invokeMethod<void>(StylusSideButton.prepareHapticMethod).catchError((
      Object _,
    ) {});
  }

  @override
  void playHaptic(Offset global) {
    const MethodChannel(StylusSideButton.channelName).invokeMethod<void>(
      StylusSideButton.playHapticMethod,
      {'x': global.dx, 'y': global.dy},
    ).catchError((Object _) {});
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
