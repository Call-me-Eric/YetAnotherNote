import 'package:flutter/gestures.dart';

/// Movement within this distance stays a press. Past it, the gesture is a drag.
const fingerSlop = 10.0;

/// A press that is still inside [fingerSlop] after this delay is a long press.
const fingerLongPress = Duration(milliseconds: 380);

/// Touch is always a finger. A stylus is a finger only when the current surface
/// says so. A stylus that reports itself as touch is already a finger.
bool actsAsFinger(PointerDeviceKind kind, {required bool stylusAsFinger}) {
  if (kind == PointerDeviceKind.touch) {
    return true;
  }
  if (!stylusAsFinger) {
    return false;
  }
  return kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;
}
