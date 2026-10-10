import 'package:flutter/services.dart';

import 'stylus_side_button.dart';

/// Asks the platform to buzz the stylus, when that stylus can buzz.
/// Apple Pencil Pro plays this through UICanvasFeedbackGenerator. Other
/// pencils and platforms ignore it.
void selectionHaptic(Offset global) {
  const MethodChannel(
    StylusSideButton.channelName,
  ).invokeMethod<void>('selectionHaptic', {
    'x': global.dx,
    'y': global.dy,
  }).catchError((Object _) {});
}
