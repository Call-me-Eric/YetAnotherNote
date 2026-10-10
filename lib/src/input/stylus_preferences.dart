enum DoubleTapAction { off, eraser }

class StylusPreferences {
  const StylusPreferences({
    required this.selectionHaptic,
    required this.doubleTap,
  });

  static const initial = StylusPreferences(
    selectionHaptic: true,
    doubleTap: DoubleTapAction.eraser,
  );

  final bool selectionHaptic;
  final DoubleTapAction doubleTap;

  StylusPreferences copyWith({
    bool? selectionHaptic,
    DoubleTapAction? doubleTap,
  }) {
    return StylusPreferences(
      selectionHaptic: selectionHaptic ?? this.selectionHaptic,
      doubleTap: doubleTap ?? this.doubleTap,
    );
  }

  Map<String, Object> toJson() => {
    'selectionHaptic': selectionHaptic,
    'doubleTap': doubleTap.name,
  };

  static StylusPreferences fromJson(Object? json) {
    if (json is! Map) {
      return initial;
    }
    final haptic = json['selectionHaptic'];
    final tap = json['doubleTap'];
    return StylusPreferences(
      selectionHaptic: haptic is bool ? haptic : true,
      doubleTap: tap == 'off' ? DoubleTapAction.off : DoubleTapAction.eraser,
    );
  }
}
