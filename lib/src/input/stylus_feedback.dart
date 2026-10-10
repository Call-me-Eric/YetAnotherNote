import 'dart:ui';

import 'stylus_side_button.dart';

void prepareSelectionHaptic() {
  stylusSideButton.prepareHaptic();
}

void selectionHaptic(Offset global) {
  stylusSideButton.playHaptic(global);
}
