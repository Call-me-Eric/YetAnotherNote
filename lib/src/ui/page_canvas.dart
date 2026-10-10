import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../ink/eraser.dart';
import '../ink/stroke.dart';
import '../ink/text_box.dart';
import '../input/finger.dart';
import '../input/stylus_feedback.dart';
import 'selection_frame.dart';
import 'text_box_view.dart';
import '../storage/note_document.dart';

class InkPatch {
  const InkPatch({
    required this.pageId,
    required this.bounds,
    required this.paint,
    this.onApplied,
  });

  final String pageId;
  final Rect bounds;
  final void Function(Canvas canvas) paint;
  final VoidCallback? onApplied;
}

final _idleSelection = ValueNotifier<SelectionPreview?>(null);

class SelectionPreview {
  const SelectionPreview({
    required this.strokes,
    required this.bounds,
    this.outline = const [],
    this.image,
    this.imageRect,
    this.transform,
  });

  final List<StrokeObject> strokes;
  final Rect bounds;
  final List<Offset> outline;
  final ui.Image? image;
  final Rect? imageRect;
  final Float64List? transform;
}

class StrokeFade {
  const StrokeFade({this.pageId, this.strokes = const [], this.solid = false});

  final String? pageId;
  final List<StrokeObject> strokes;
  final bool solid;
}

class PageCanvas extends StatelessWidget {
  const PageCanvas({
    required this.pages,
    required this.selectedPageId,
    required this.transformation,
    required this.onSelectPage,
    required this.onStrokeStart,
    required this.onStrokeMove,
    required this.onStrokeEnd,
    required this.settledStrokes,
    required this.tool,
    required this.hiddenIds,
    required this.patches,
    required this.fading,
    required this.onEraseStart,
    required this.onEraseMove,
    required this.onEraseEnd,
    required this.textBoxes,
    required this.editingTextId,
    required this.selectedTextId,
    required this.onTextCommit,
    required this.onTextDraft,
    required this.onTextResize,
    required this.onTextBlur,
    required this.onSuppressPan,
    required this.onTextCreate,
    required this.onTextSelect,
    required this.onTextEdit,
    required this.onTextDelete,
    required this.onTextMove,
    required this.onTextMoveEnd,
    this.onTextHover,
    this.onTip,
    this.onScaleSettled,
    this.viewScale = 1,
    this.preview,
    this.previewPageId,
    this.eraserRadius = 14,
    this.penWidth = 3,
    this.lassoPoints = const [],
    this.lassoOutline = const [],
    this.lassoRect,
    this.selectionBounds,
    this.selectionInk = const [],
    this.onLassoStart,
    this.onLassoMove,
    this.onLassoEnd,
    this.onSelectionMove,
    this.onSelectionMoveEnd,
    this.onSelectionScale,
    this.onSelectionScaleEnd,
    this.onSelectionRotate,
    this.onSelectionRotateEnd,
    this.onSelectionMenu,
    this.onSelectionClear,
    this.selectionHaptic = false,
    required this.selectionLive,
    required this.live,
    super.key,
  });

  final List<PageFile> pages;
  final String selectedPageId;
  final TransformationController transformation;
  final ValueChanged<String> onSelectPage;
  final void Function(String pageId, PointerEvent event) onStrokeStart;
  final void Function(String pageId, PointerEvent event) onStrokeMove;
  final ValueChanged<String> onStrokeEnd;
  final List<({String pageId, String layerId, StrokeObject stroke})>
  settledStrokes;
  final InkTool tool;
  final Set<String> hiddenIds;
  final ValueListenable<InkPatch?> patches;
  final ValueListenable<StrokeFade> fading;
  final void Function(String pageId, Offset point) onEraseStart;
  final void Function(String pageId, Offset point) onEraseMove;
  final ValueChanged<String> onEraseEnd;
  final List<({String pageId, TextBox box})> textBoxes;
  final String? editingTextId;
  final String? selectedTextId;
  final void Function(TextBox box, String source) onTextCommit;
  final void Function(TextBox box, String source) onTextDraft;
  final void Function(TextBox box, double width, double height) onTextResize;
  final VoidCallback onTextBlur;
  final void Function(int pointer) onSuppressPan;
  final void Function(String pageId, Rect rect) onTextCreate;
  final void Function(String pageId, String id) onTextSelect;
  final void Function(String pageId, String id) onTextEdit;
  final void Function(String pageId, String id) onTextDelete;
  final void Function(String pageId, String id, Offset delta) onTextMove;
  final void Function(String pageId, String id) onTextMoveEnd;
  final void Function(String pageId, Offset? local, Offset? global)?
  onTextHover;
  final ValueChanged<Offset?>? onTip;
  final VoidCallback? onScaleSettled;
  final double viewScale;
  final StrokeObject? preview;
  final String? previewPageId;
  final double eraserRadius;
  final double penWidth;
  final List<Offset> lassoPoints;
  final List<Offset> lassoOutline;
  final Rect? lassoRect;
  final Rect? selectionBounds;
  final List<StrokeObject> selectionInk;
  final void Function(String pageId, Offset point)? onLassoStart;
  final void Function(String pageId, Offset point)? onLassoMove;
  final void Function(String pageId, Offset point)? onLassoEnd;
  final void Function(Offset delta)? onSelectionMove;
  final VoidCallback? onSelectionMoveEnd;
  final void Function(SelectionHandle handle, Offset delta)? onSelectionScale;
  final VoidCallback? onSelectionScaleEnd;
  final void Function(Offset pointer)? onSelectionRotate;
  final VoidCallback? onSelectionRotateEnd;
  final VoidCallback? onSelectionMenu;
  final VoidCallback? onSelectionClear;
  final bool selectionHaptic;
  final ValueListenable<SelectionPreview?> selectionLive;
  final ValueListenable<({String pageId, StrokeObject stroke})?> live;

  static const pageGap = 32.0;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: transformation,
      constrained: false,
      panEnabled: false,
      scaleEnabled: true,
      minScale: 0.2,
      maxScale: 4,
      onInteractionEnd: (_) => onScaleSettled?.call(),
      boundaryMargin: const EdgeInsets.all(800),
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < pages.length; index++) ...[
              if (index > 0) const SizedBox(height: pageGap),
              _PageSheet(
                page: pages[index],
                selected: pages[index].id == selectedPageId,
                preview: pages[index].id == previewPageId ? preview : null,
                settled: [
                  for (final item in settledStrokes)
                    if (item.pageId == pages[index].id) item.stroke,
                ],
                live: live,
                transformation: transformation,
                onSelect: () => onSelectPage(pages[index].id),
                onStrokeStart: onStrokeStart,
                onStrokeMove: onStrokeMove,
                onStrokeEnd: onStrokeEnd,
                tool: tool,
                hiddenIds: hiddenIds,
                patches: patches,
                fading: fading,
                onEraseStart: onEraseStart,
                onEraseMove: onEraseMove,
                onEraseEnd: onEraseEnd,
                textBoxes: [
                  for (final item in textBoxes)
                    if (item.pageId == pages[index].id) item.box,
                ],
                editingTextId: editingTextId,
                selectedTextId: selectedTextId,
                onTextCommit: onTextCommit,
                onTextDraft: onTextDraft,
                onTextResize: onTextResize,
                onTextBlur: onTextBlur,
                onSuppressPan: onSuppressPan,
                onTextCreate: onTextCreate,
                onTextSelect: onTextSelect,
                onTextEdit: onTextEdit,
                onTextDelete: onTextDelete,
                onTextMove: onTextMove,
                onTextMoveEnd: onTextMoveEnd,
                onTextHover: onTextHover,
                onTip: onTip,
                viewScale: viewScale,
                eraserRadius: eraserRadius,
                penWidth: penWidth,
                lassoPoints: pages[index].id == selectedPageId
                    ? lassoPoints
                    : const [],
                lassoOutline: pages[index].id == selectedPageId
                    ? lassoOutline
                    : const [],
                selectionHaptic: selectionHaptic,
                lassoRect: pages[index].id == selectedPageId ? lassoRect : null,
                selectionBounds: pages[index].id == selectedPageId
                    ? selectionBounds
                    : null,
                selectionInk: pages[index].id == selectedPageId
                    ? selectionInk
                    : const [],
                onLassoStart: onLassoStart,
                onLassoMove: onLassoMove,
                onLassoEnd: onLassoEnd,
                onSelectionMove: onSelectionMove,
                onSelectionMoveEnd: onSelectionMoveEnd,
                onSelectionScale: onSelectionScale,
                onSelectionScaleEnd: onSelectionScaleEnd,
                onSelectionRotate: onSelectionRotate,
                onSelectionRotateEnd: onSelectionRotateEnd,
                onSelectionMenu: onSelectionMenu,
                onSelectionClear: onSelectionClear,
                selectionLive: pages[index].id == selectedPageId
                    ? selectionLive
                    : _idleSelection,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PageSheet extends StatefulWidget {
  const _PageSheet({
    required this.page,
    required this.selected,
    required this.preview,
    required this.settled,
    required this.live,
    required this.transformation,
    required this.onSelect,
    required this.onStrokeStart,
    required this.onStrokeMove,
    required this.onStrokeEnd,
    required this.tool,
    required this.hiddenIds,
    required this.patches,
    required this.fading,
    required this.onEraseStart,
    required this.onEraseMove,
    required this.onEraseEnd,
    required this.textBoxes,
    required this.editingTextId,
    required this.selectedTextId,
    required this.onTextCommit,
    required this.onTextDraft,
    required this.onTextResize,
    required this.onTextBlur,
    required this.onSuppressPan,
    required this.onTextCreate,
    required this.onTextSelect,
    required this.onTextEdit,
    required this.onTextDelete,
    required this.onTextMove,
    required this.onTextMoveEnd,
    this.onTextHover,
    this.onTip,
    this.viewScale = 1,
    this.eraserRadius = 14,
    this.penWidth = 3,
    this.lassoPoints = const [],
    this.lassoOutline = const [],
    this.lassoRect,
    this.selectionBounds,
    this.selectionInk = const [],
    this.onLassoStart,
    this.onLassoMove,
    this.onLassoEnd,
    this.onSelectionMove,
    this.onSelectionMoveEnd,
    this.onSelectionScale,
    this.onSelectionScaleEnd,
    this.onSelectionRotate,
    this.onSelectionRotateEnd,
    this.onSelectionMenu,
    this.onSelectionClear,
    this.selectionHaptic = false,
    required this.selectionLive,
  });

  final PageFile page;
  final bool selected;
  final StrokeObject? preview;
  final List<StrokeObject> settled;
  final ValueListenable<({String pageId, StrokeObject stroke})?> live;
  final TransformationController transformation;
  final VoidCallback onSelect;
  final void Function(String pageId, PointerEvent event) onStrokeStart;
  final void Function(String pageId, PointerEvent event) onStrokeMove;
  final ValueChanged<String> onStrokeEnd;
  final InkTool tool;
  final Set<String> hiddenIds;
  final ValueListenable<InkPatch?> patches;
  final ValueListenable<StrokeFade> fading;
  final void Function(String pageId, Offset point) onEraseStart;
  final void Function(String pageId, Offset point) onEraseMove;
  final ValueChanged<String> onEraseEnd;
  final List<TextBox> textBoxes;
  final String? editingTextId;
  final String? selectedTextId;
  final void Function(TextBox box, String source) onTextCommit;
  final void Function(TextBox box, String source) onTextDraft;
  final void Function(TextBox box, double width, double height) onTextResize;
  final VoidCallback onTextBlur;
  final void Function(int pointer) onSuppressPan;
  final void Function(String pageId, Rect rect) onTextCreate;
  final void Function(String pageId, String id) onTextSelect;
  final void Function(String pageId, String id) onTextEdit;
  final void Function(String pageId, String id) onTextDelete;
  final void Function(String pageId, String id, Offset delta) onTextMove;
  final void Function(String pageId, String id) onTextMoveEnd;
  final void Function(String pageId, Offset? local, Offset? global)?
  onTextHover;
  final ValueChanged<Offset?>? onTip;
  final double viewScale;
  final double eraserRadius;
  final double penWidth;
  final List<Offset> lassoPoints;
  final List<Offset> lassoOutline;
  final Rect? lassoRect;
  final Rect? selectionBounds;
  final List<StrokeObject> selectionInk;
  final void Function(String pageId, Offset point)? onLassoStart;
  final void Function(String pageId, Offset point)? onLassoMove;
  final void Function(String pageId, Offset point)? onLassoEnd;
  final void Function(Offset delta)? onSelectionMove;
  final VoidCallback? onSelectionMoveEnd;
  final void Function(SelectionHandle handle, Offset delta)? onSelectionScale;
  final VoidCallback? onSelectionScaleEnd;
  final void Function(Offset pointer)? onSelectionRotate;
  final VoidCallback? onSelectionRotateEnd;
  final VoidCallback? onSelectionMenu;
  final VoidCallback? onSelectionClear;
  final bool selectionHaptic;
  final ValueListenable<SelectionPreview?> selectionLive;

  @override
  State<_PageSheet> createState() => _PageSheetState();
}

class _PageSheetState extends State<_PageSheet> {
  static const _textHold = fingerLongPress;
  static const _textSlop = fingerSlop;
  static const _textMinWidth = 72.0;
  static const _textMinHeight = 44.0;

  int? _inkPointer;
  int? _textPointer;
  Offset? _textDown;
  Offset? _textLast;
  TextBox? _textBox;
  var _textHeld = false;
  Timer? _textTimer;
  Rect? _rubber;
  var _rubberReady = false;
  final Map<String, StrokeObject> _finalStrokes = {};
  final ValueNotifier<Offset?> _cursor = ValueNotifier(null);
  var _tipDown = false;
  int? _outsidePointer;
  Offset? _lassoHapticAt;
  var _hapticRun = 0.0;
  Offset? _outsideDown;
  Duration? _outsideStamp;

  @override
  void dispose() {
    _textTimer?.cancel();
    _cursor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final committed = _committedInk();
    return MouseRegion(
      onExit: (_) {
        if (_inkPointer == null) {
          _clearTip();
        }
      },
      child: Listener(
        onPointerHover: (event) {
          if (_inkPointer != null || event.kind == PointerDeviceKind.touch) {
            return;
          }
          if (!_inside(event.localPosition)) {
            _clearTip();
            return;
          }
          _trackTip(event, pressed: false);
        },
        onPointerDown: (event) {
          if (!_inside(event.localPosition)) {
            return;
          }
          if (_hitsSelection(event.localPosition)) {
            widget.onSuppressPan(event.pointer);
            widget.onSelect();
            _outsidePointer = null;
            return;
          }
          if (widget.selectionBounds != null && !drawsInk(event.kind)) {
            _outsidePointer = event.pointer;
            _outsideDown = event.localPosition;
            _outsideStamp = event.timeStamp;
          } else {
            _outsidePointer = null;
          }
          if (widget.tool == InkTool.lasso) {
            if (!drawsInk(event.kind)) {
              return;
            }
            _inkPointer = event.pointer;
            _lassoHapticAt = event.localPosition;
            _hapticRun = 0;
            widget.onSelect();
            widget.onLassoStart?.call(widget.page.id, event.localPosition);
            return;
          }
          if (widget.tool == InkTool.text && _textPointerKind(event.kind)) {
            _beginText(event);
            return;
          }
          if (!drawsInk(event.kind)) {
            widget.onSelect();
            return;
          }
          _inkPointer = event.pointer;
          _trackTip(event, pressed: true);
          widget.onSelect();
          if (widget.tool == InkTool.pen) {
            widget.onStrokeStart(widget.page.id, event);
            return;
          }
          widget.onEraseStart(widget.page.id, event.localPosition);
        },
        onPointerMove: (event) {
          if (event.pointer == _outsidePointer && _outsideDown != null) {
            if ((event.localPosition - _outsideDown!).distance > fingerSlop) {
              _outsidePointer = null;
            }
          }
          if (event.pointer == _textPointer) {
            _moveText(event.localPosition);
            return;
          }
          if (event.pointer == _inkPointer) {
            _trackTip(event, pressed: true);
          }
          if (event.pointer == _inkPointer && widget.tool == InkTool.lasso) {
            final previous = _lassoHapticAt;
            _lassoHapticAt = event.localPosition;
            if (widget.selectionHaptic &&
                _stylusKind(event.kind) &&
                previous != null) {
              _hapticRun += (event.localPosition - previous).distance;
              if (_hapticRun >= 16) {
                _hapticRun = 0;
                selectionHaptic(event.position);
              }
            }
            widget.onLassoMove?.call(widget.page.id, event.localPosition);
            return;
          }
          if (!drawsInk(event.kind) || !_inside(event.localPosition)) {
            return;
          }
          if (widget.tool == InkTool.pen) {
            widget.onStrokeMove(widget.page.id, event);
            return;
          }
          widget.onEraseMove(widget.page.id, event.localPosition);
        },
        onPointerUp: (event) {
          _finishOutside(event);
          if (event.pointer == _textPointer) {
            _endText();
            return;
          }
          if (event.pointer == _inkPointer && widget.tool == InkTool.lasso) {
            widget.onLassoEnd?.call(widget.page.id, event.localPosition);
            _inkPointer = null;
            _lassoHapticAt = null;
            return;
          }
          _finishPointer(event.pointer, event.kind);
        },
        onPointerCancel: (event) {
          _outsidePointer = null;
          if (event.pointer == _textPointer) {
            _cancelText();
            return;
          }
          _finishPointer(event.pointer, event.kind);
        },
        child: SizedBox(
          key: ValueKey('page-${widget.page.id}'),
          width: widget.page.width,
          height: widget.page.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: widget.selected ? color.primary : color.outline,
                width: widget.selected ? 3 : 1,
              ),
            ),
            child: ClipRect(
              child: Stack(
                children: [
                  _CommittedInk(
                    key: ValueKey('ink-${widget.page.id}'),
                    pageId: widget.page.id,
                    width: widget.page.width,
                    height: widget.page.height,
                    strokes: committed,
                    patches: widget.patches,
                    viewScale: widget.viewScale,
                  ),
                  ValueListenableBuilder<
                    ({String pageId, StrokeObject stroke})?
                  >(
                    valueListenable: widget.live,
                    builder: (context, live, _) {
                      final stroke =
                          live != null && live.pageId == widget.page.id
                          ? live.stroke
                          : null;
                      if (stroke == null) {
                        return const SizedBox.shrink();
                      }
                      return _LiveInk(
                        key: ValueKey('live-${widget.page.id}-${stroke.id}'),
                        stroke: stroke,
                        width: widget.page.width,
                        height: widget.page.height,
                        viewScale: widget.viewScale,
                      );
                    },
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        widget.page.id,
                        style: TextStyle(color: color.outline, fontSize: 12),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<StrokeFade>(
                    valueListenable: widget.fading,
                    builder: (context, fade, _) {
                      if (fade.pageId != widget.page.id ||
                          fade.strokes.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return CustomPaint(
                        painter: _FadePainter(fade.strokes, solid: fade.solid),
                        size: Size(widget.page.width, widget.page.height),
                      );
                    },
                  ),
                  if (_rubber != null &&
                      _rubber!.width > 0 &&
                      _rubber!.height > 0)
                    Positioned(
                      left: _rubber!.left,
                      top: _rubber!.top,
                      width: _rubber!.width,
                      height: _rubber!.height,
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          decoration: BoxDecoration(
                            color: _rubberReady
                                ? const Color(0xF2FFFFFF)
                                : const Color(0x55FFFFFF),
                            border: Border.all(
                              color: _rubberReady
                                  ? color.primary
                                  : color.primary.withValues(alpha: 0.45),
                              width: _rubberReady ? 1.6 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _LassoPainter(
                          points: widget.lassoPoints,
                          rect: widget.lassoRect,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: ValueListenableBuilder<SelectionPreview?>(
                      valueListenable: widget.selectionLive,
                      builder: (context, live, _) {
                        final ink = live?.strokes ?? const <StrokeObject>[];
                        final outline = live?.outline ?? widget.lassoOutline;
                        if (ink.isEmpty && outline.length < 2) {
                          return const SizedBox.shrink();
                        }
                        return IgnorePointer(
                          child: CustomPaint(
                            painter: _SelectionMarkPainter(
                              strokes: ink,
                              outline: outline,
                              image: live?.image,
                              imageRect: live?.imageRect,
                              transform: live?.transform,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned.fill(
                    child: TextBoxLayer(
                      boxes: widget.textBoxes,
                      pageWidth: widget.page.width,
                      editingId: widget.editingTextId,
                      selectedId: widget.selectedTextId,
                      interactive: widget.tool == InkTool.text,
                      onCommit: widget.onTextCommit,
                      onDraft: widget.onTextDraft,
                      onResize: widget.onTextResize,
                      onEdit: (box) =>
                          widget.onTextEdit(widget.page.id, box.id),
                      onDelete: (box) =>
                          widget.onTextDelete(widget.page.id, box.id),
                      onResizeDown: widget.onSuppressPan,
                    ),
                  ),
                  Positioned.fill(
                    child: ValueListenableBuilder<SelectionPreview?>(
                      valueListenable: widget.selectionLive,
                      builder: (context, live, _) {
                        final bounds = live?.bounds ?? widget.selectionBounds;
                        if (bounds == null) {
                          return const SizedBox.shrink();
                        }
                        return SelectionFrame(
                          key: const ValueKey('selection-frame'),
                          bounds: bounds,
                          onMove: (delta) => widget.onSelectionMove?.call(delta),
                          onMoveEnd: () => widget.onSelectionMoveEnd?.call(),
                          onScale: (handle, delta) =>
                              widget.onSelectionScale?.call(handle, delta),
                          onScaleEnd: () => widget.onSelectionScaleEnd?.call(),
                          onRotate: (pointer) =>
                              widget.onSelectionRotate?.call(pointer),
                          onRotateEnd: () => widget.onSelectionRotateEnd?.call(),
                          onMenu: () => widget.onSelectionMenu?.call(),
                        );
                      },
                    ),
                  ),
                  ValueListenableBuilder<Offset?>(
                    valueListenable: _cursor,
                    builder: (context, cursor, _) {
                      if (cursor == null || widget.tool == InkTool.text) {
                        return const SizedBox.shrink();
                      }
                      final eraser =
                          widget.tool == InkTool.objectEraser ||
                          widget.tool == InkTool.regionEraser;
                      final radius = eraser
                          ? widget.eraserRadius
                          : widget.penWidth / 2;
                      const pad = 2.0;
                      final side = (radius + pad) * 2;
                      return Positioned(
                        left: cursor.dx - radius - pad,
                        top: cursor.dy - radius - pad,
                        width: side,
                        height: side,
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _TipPainter(
                                Offset(radius + pad, radius + pad),
                                eraser: eraser,
                                radius: radius,
                                opaque: _tipDown,
                              ),
                              size: Size(side, side),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextBox? _boxAt(Offset point) {
    for (final box in widget.textBoxes.reversed) {
      if (box.rect.contains(point)) {
        return box;
      }
    }
    return null;
  }

  bool _onResizeHandle(Offset point) {
    final id = widget.selectedTextId;
    if (id == null || widget.editingTextId == id) {
      return false;
    }
    for (final box in widget.textBoxes) {
      if (box.id != id) {
        continue;
      }
      final corner = Offset(box.x + box.width, box.y + box.height);
      return (point - corner).distance <= 20;
    }
    return false;
  }

  /// Text gestures are finger gestures. In the text tool the stylus stands in
  /// for a finger, so it uses the same short press, long press, and drag.
  bool _textPointerKind(PointerDeviceKind kind) {
    return actsAsFinger(kind, stylusAsFinger: true) ||
        kind == PointerDeviceKind.mouse;
  }

  void _beginText(PointerDownEvent event) {
    if (_onResizeHandle(event.localPosition)) {
      return;
    }
    _cancelText();
    _textPointer = event.pointer;
    _textDown = event.localPosition;
    _textLast = event.localPosition;
    _textHeld = false;
    _textBox = _boxAt(event.localPosition);
    _textTimer = Timer(_textHold, () {
      if (!mounted || _textPointer != event.pointer) {
        return;
      }
      _textHeld = true;
      widget.onSuppressPan(event.pointer);
      final box = _textBox;
      if (box != null) {
        widget.onTextSelect(widget.page.id, box.id);
        return;
      }
      final origin = _textDown;
      if (origin == null) {
        return;
      }
      setState(() {
        _rubber = Rect.fromLTWH(origin.dx, origin.dy, 0, 0);
        _rubberReady = false;
      });
    });
  }

  void _moveText(Offset point) {
    final down = _textDown;
    if (down == null) {
      return;
    }
    if (!_textHeld) {
      if ((point - down).distance > _textSlop) {
        _textTimer?.cancel();
        _textPointer = null;
        _textBox = null;
      }
      return;
    }
    final box = _textBox;
    if (box != null) {
      final last = _textLast ?? down;
      _textLast = point;
      final delta = point - last;
      if (delta != Offset.zero) {
        widget.onTextMove(widget.page.id, box.id, delta);
      }
      return;
    }
    final width = point.dx - down.dx;
    final height = point.dy - down.dy;
    setState(() {
      if (width <= 0 || height <= 0) {
        _rubber = Rect.fromLTWH(down.dx, down.dy, 0, 0);
        _rubberReady = false;
        return;
      }
      _rubber = Rect.fromLTWH(down.dx, down.dy, width, height);
      _rubberReady = width >= _textMinWidth && height >= _textMinHeight;
    });
  }

  void _endText() {
    _textTimer?.cancel();
    final held = _textHeld;
    final box = _textBox;
    final rubber = _rubber;
    final ready = _rubberReady;
    _textPointer = null;
    _textDown = null;
    _textLast = null;
    _textBox = null;
    _textHeld = false;
    if (_rubber != null) {
      setState(() {
        _rubber = null;
        _rubberReady = false;
      });
    }
    if (!held) {
      if (box != null) {
        widget.onTextEdit(widget.page.id, box.id);
      } else {
        widget.onTextBlur();
      }
      return;
    }
    if (box != null) {
      widget.onTextMoveEnd(widget.page.id, box.id);
      return;
    }
    if (ready && rubber != null) {
      widget.onTextCreate(widget.page.id, rubber);
    }
  }

  void _cancelText() {
    _textTimer?.cancel();
    _textPointer = null;
    _textDown = null;
    _textLast = null;
    _textBox = null;
    _textHeld = false;
    if (_rubber != null) {
      setState(() {
        _rubber = null;
        _rubberReady = false;
      });
    }
  }

  void _trackTip(PointerEvent event, {required bool pressed}) {
    _tipDown = pressed;
    if (widget.tool == InkTool.text || widget.tool == InkTool.lasso) {
      _cursor.value = null;
      widget.onTip?.call(event.position);
      widget.onTextHover?.call(
        widget.page.id,
        event.localPosition,
        event.position,
      );
      return;
    }
    final eraser =
        widget.tool == InkTool.objectEraser ||
        widget.tool == InkTool.regionEraser;
    if (eraser) {
      _cursor.value = event.localPosition;
    } else if (!pressed && _inside(event.localPosition)) {
      _cursor.value = event.localPosition;
    } else {
      _cursor.value = null;
    }
    widget.onTip?.call(event.position);
  }

  void _clearTip() {
    _cursor.value = null;
    widget.onTip?.call(null);
    widget.onTextHover?.call(widget.page.id, null, null);
  }

  void _finishPointer(int pointer, PointerDeviceKind kind) {
    if (drawsInk(kind)) {
      if (widget.tool == InkTool.pen) {
        widget.onStrokeEnd(widget.page.id);
      } else {
        widget.onEraseEnd(widget.page.id);
      }
    }
    if (pointer == _inkPointer) {
      _inkPointer = null;
      _clearTip();
    }
  }

  void _finishOutside(PointerEvent event) {
    if (event.pointer != _outsidePointer || _outsideStamp == null) {
      return;
    }
    final elapsed = event.timeStamp - _outsideStamp!;
    _outsidePointer = null;
    if (elapsed < fingerLongPress) {
      widget.onSelectionClear?.call();
    }
  }

  bool _hitsSelection(Offset point) {
    final bounds = widget.selectionLive.value?.bounds ?? widget.selectionBounds;
    if (bounds == null) {
      return false;
    }
    if (bounds.inflate(20).contains(point)) {
      return true;
    }
    final stem = 16 + bounds.shortestSide * 0.12;
    final knob = Offset(bounds.center.dx, bounds.top - stem);
    return (point - knob).distance <= 22;
  }

  bool _inside(Offset point) {
    return point.dx >= 0 &&
        point.dy >= 0 &&
        point.dx <= widget.page.width &&
        point.dy <= widget.page.height;
  }

  List<StrokeObject> _committedInk() {
    final found = <StrokeObject>[];
    final seen = <String>{};
    for (final layer in widget.page.layers) {
      if (!layer.visible) {
        continue;
      }
      for (final object in layer.objects) {
        if (object is! Map) {
          continue;
        }
        final id = object['id'];
        final type = object['type'];
        if (id is! String || (type != 'stroke' && type != 'strokeRef')) {
          continue;
        }
        if (id == widget.preview?.id ||
            widget.hiddenIds.contains(id) ||
            _deleted.contains(id)) {
          continue;
        }
        seen.add(id);
        final cached = _finalStrokes[id];
        if (cached != null) {
          found.add(cached);
          continue;
        }
        final parsed = strokeFromObject(object);
        if (parsed == null || !parsed.finalized) {
          continue;
        }
        _finalStrokes[id] = parsed;
        found.add(parsed);
      }
    }
    _finalStrokes.removeWhere((id, _) => !seen.contains(id));
    final ids = {for (final stroke in found) stroke.id};
    return [
      ...found,
      for (final item in widget.settled)
        if (!ids.contains(item.id) &&
            item.id != widget.preview?.id &&
            !widget.hiddenIds.contains(item.id) &&
            !_deleted.contains(item.id))
          item,
    ];
  }

  Set<String> get _deleted {
    return {for (final layer in widget.page.layers) ...layer.deletedObjectIds};
  }
}

class _SelectionMarkPainter extends CustomPainter {
  const _SelectionMarkPainter({
    required this.strokes,
    required this.outline,
    this.image,
    this.imageRect,
    this.transform,
  });

  final List<StrokeObject> strokes;
  final List<Offset> outline;
  final ui.Image? image;
  final Rect? imageRect;
  final Float64List? transform;

  @override
  void paint(Canvas canvas, Size size) {
    final matrix = transform;
    if (matrix != null) {
      canvas.save();
      canvas.transform(matrix);
    }
    final shot = image;
    final rect = imageRect;
    if (shot != null && rect != null) {
      canvas.drawImageRect(
        shot,
        Rect.fromLTWH(0, 0, shot.width.toDouble(), shot.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      for (final stroke in strokes) {
        paintStroke(canvas, stroke);
      }
      if (outline.length >= 2) {
        final path = Path()..moveTo(outline.first.dx, outline.first.dy);
        for (final point in outline.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        path.close();
        _drawDashed(canvas, path, _selectionBlue);
      }
    }
    if (matrix != null) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionMarkPainter oldDelegate) => true;
}

bool _stylusKind(PointerDeviceKind kind) {
  return kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;
}

const _selectionBlue = Color(0xFF3D7EFF);

void _drawDashed(Canvas canvas, Path source, Color color) {
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..color = color;
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = math.min(distance + 6, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance = next + 4;
    }
  }
}

class _LassoPainter extends CustomPainter {
  const _LassoPainter({required this.points, required this.rect});

  final List<Offset> points;
  final Rect? rect;

  @override
  void paint(Canvas canvas, Size size) {
    if (rect != null && !rect!.isEmpty) {
      _drawDashed(canvas, Path()..addRect(rect!), _selectionBlue);
    }
    if (points.length >= 2) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      _drawDashed(canvas, path, _selectionBlue);
    }
  }

  @override
  bool shouldRepaint(covariant _LassoPainter oldDelegate) => true;
}

class _TipPainter extends CustomPainter {
  const _TipPainter(
    this.center, {
    required this.eraser,
    required this.radius,
    required this.opaque,
  });

  final Offset center;
  final bool eraser;
  final double radius;
  final bool opaque;

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = opaque || !eraser ? 1.0 : 0.35;
    if (eraser) {
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: alpha),
      );
      canvas.drawCircle(
        center,
        radius - 0.75,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF000000).withValues(alpha: alpha),
      );
      return;
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFF222222),
    );
  }

  @override
  bool shouldRepaint(covariant _TipPainter oldDelegate) =>
      oldDelegate.center != center ||
      oldDelegate.opaque != opaque ||
      oldDelegate.radius != radius;
}

class _FadePainter extends CustomPainter {
  const _FadePainter(this.strokes, {required this.solid});

  final List<StrokeObject> strokes;
  final bool solid;

  /// Extra width so the wash covers the ink's antialiased edge, not only its center.
  static const _pad = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final filter = Paint()
      ..colorFilter = ColorFilter.mode(
        solid ? const Color(0xFFFFFFFF) : const Color(0x99FFFFFF),
        BlendMode.modulate,
      );
    final cover = Paint()..color = const Color(0xFFFFFFFF);
    for (final stroke in strokes) {
      final bounds = _inkBounds(stroke.points).inflate(_pad + 1);
      if (bounds.isEmpty) {
        continue;
      }
      canvas.saveLayer(bounds, filter);
      paintStrokeCover(canvas, stroke, cover, pad: _pad);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FadePainter oldDelegate) =>
      oldDelegate.solid != solid || oldDelegate.strokes != strokes;
}

class _CommittedInk extends StatefulWidget {
  const _CommittedInk({
    required this.pageId,
    required this.width,
    required this.height,
    required this.strokes,
    required this.patches,
    this.viewScale = 1,
    super.key,
  });

  final String pageId;
  final double width;
  final double height;
  final List<StrokeObject> strokes;
  final ValueListenable<InkPatch?> patches;
  final double viewScale;

  @override
  State<_CommittedInk> createState() => _CommittedInkState();
}

class _CommittedInkState extends State<_CommittedInk> {
  static const _tileSize = 256.0;

  final Map<String, ui.Image> _tiles = {};
  final Set<String> _rasterized = {};
  var _chain = Future<void>.value();
  var _generation = 0;
  var _dabbed = false;
  final Set<String> _baked = {};
  double _dpr = 1;

  @override
  void initState() {
    super.initState();
    widget.patches.addListener(_onPatch);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dpr = MediaQuery.devicePixelRatioOf(context);
  }

  @override
  void didUpdateWidget(covariant _CommittedInk oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patches != widget.patches) {
      oldWidget.patches.removeListener(_onPatch);
      widget.patches.addListener(_onPatch);
    }
    if ((oldWidget.viewScale - widget.viewScale).abs() > 0.04) {
      _dropTiles();
    }
  }

  void _dropTiles() {
    _generation++;
    _rasterized.clear();
    _baked.clear();
    _dabbed = false;
    final retiring = List<ui.Image>.of(_tiles.values);
    _tiles.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final image in retiring) {
        image.dispose();
      }
    });
  }

  @override
  void dispose() {
    _generation++;
    widget.patches.removeListener(_onPatch);
    for (final image in _tiles.values) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncStrokes(widget.strokes);
    final pending = [
      for (final stroke in widget.strokes)
        if (!_baked.contains(stroke.id)) stroke,
    ];
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: [
          for (final entry in _tiles.entries)
            Positioned(
              key: ValueKey(entry.key),
              left: _left(entry.key),
              top: _top(entry.key),
              width: _tileWidth(_left(entry.key)),
              height: _tileHeight(_top(entry.key)),
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _TilePainter(entry.value),
                  size: Size(
                    _tileWidth(_left(entry.key)),
                    _tileHeight(_top(entry.key)),
                  ),
                ),
              ),
            ),
          if (pending.isNotEmpty)
            Positioned.fill(
              child: CustomPaint(painter: _VectorInkPainter(pending)),
            ),
        ],
      ),
    );
  }

  void _onPatch() {
    final patch = widget.patches.value;
    if (patch == null || patch.pageId != widget.pageId) {
      return;
    }
    _dabbed = true;
    _enqueue(patch.bounds, patch.paint, onApplied: patch.onApplied);
  }

  void _syncStrokes(List<StrokeObject> strokes) {
    final ids = {for (final stroke in strokes) stroke.id};
    final added = [
      for (final stroke in strokes)
        if (!_rasterized.contains(stroke.id)) stroke,
    ];
    final removed = _rasterized.difference(ids);
    if (_dabbed && removed.isNotEmpty) {
      final addedIds = [for (final stroke in added) stroke.id];
      _rasterized
        ..addAll(addedIds)
        ..removeAll(removed);
      _baked
        ..addAll(addedIds)
        ..removeAll(removed);
      _dabbed = false;
      return;
    }
    for (final stroke in added) {
      _rasterized.add(stroke.id);
      final bounds = _inkBounds(stroke.points).inflate(stroke.baseWidth + 2);
      _enqueue(
        bounds,
        (canvas) => paintStroke(canvas, stroke),
        bakeIds: [stroke.id],
      );
    }
    if (removed.isNotEmpty) {
      _rasterized
        ..clear()
        ..addAll(ids);
      _baked.clear();
      final retiring = Map<String, ui.Image>.of(_tiles);
      _tiles.clear();
      _generation++;
      for (final image in retiring.values) {
        image.dispose();
      }
      for (final stroke in strokes) {
        final bounds = _inkBounds(stroke.points).inflate(stroke.baseWidth + 2);
        _enqueue(
          bounds,
          (canvas) => paintStroke(canvas, stroke),
          bakeIds: [stroke.id],
        );
      }
    }
  }

  void _enqueue(
    Rect bounds,
    void Function(Canvas canvas) paint, {
    List<String> bakeIds = const [],
    VoidCallback? onApplied,
  }) {
    final generation = _generation;
    final tiles = _tileRects(bounds);
    _chain = _chain.then((_) async {
      if (!mounted || generation != _generation) {
        if (!mounted) {
          onApplied?.call();
        }
        return;
      }
      final updates = <String, ui.Image>{};
      for (final rect in tiles) {
        final next = await _renderTile(rect, paint);
        if (!mounted || generation != _generation) {
          next.dispose();
          for (final image in updates.values) {
            image.dispose();
          }
          if (!mounted) {
            onApplied?.call();
          }
          return;
        }
        final replaced = updates[_tileKey(rect)];
        if (replaced != null) {
          replaced.dispose();
        }
        updates[_tileKey(rect)] = next;
      }
      if (!mounted || generation != _generation) {
        for (final image in updates.values) {
          image.dispose();
        }
        return;
      }
      final retiring = <ui.Image>[];
      for (final entry in updates.entries) {
        final previous = _tiles[entry.key];
        _tiles[entry.key] = entry.value;
        if (previous != null) {
          retiring.add(previous);
        }
      }
      _baked.addAll(bakeIds);
      onApplied?.call();
      if (mounted) {
        setState(() {});
      }
      for (final image in retiring) {
        WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
      }
    });
  }

  Future<ui.Image> _renderTile(
    Rect rect,
    void Function(Canvas canvas) paint,
  ) async {
    final scale = (_dpr <= 0 ? 1.0 : _dpr) * widget.viewScale;
    final pixelsWide = math.max(1, (rect.width * scale).round());
    final pixelsHigh = math.max(1, (rect.height * scale).round());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final current = _tiles[_tileKey(rect)];
    if (current != null) {
      canvas.drawImageRect(
        current,
        Rect.fromLTWH(
          0,
          0,
          current.width.toDouble(),
          current.height.toDouble(),
        ),
        Rect.fromLTWH(0, 0, pixelsWide.toDouble(), pixelsHigh.toDouble()),
        Paint()..filterQuality = FilterQuality.none,
      );
    }
    canvas.save();
    canvas.scale(pixelsWide / rect.width, pixelsHigh / rect.height);
    canvas.translate(-rect.left, -rect.top);
    canvas.clipRect(rect);
    paint(canvas);
    canvas.restore();
    final picture = recorder.endRecording();
    return picture
        .toImage(pixelsWide, pixelsHigh)
        .whenComplete(picture.dispose);
  }

  List<Rect> _tileRects(Rect bounds) {
    final clipped = bounds.intersect(
      Rect.fromLTWH(0, 0, widget.width, widget.height),
    );
    if (clipped.isEmpty) {
      return const [];
    }
    final tiles = <Rect>[];
    final firstCol = (clipped.left / _tileSize).floor();
    final lastCol = ((clipped.right - 0.01) / _tileSize).floor();
    final firstRow = (clipped.top / _tileSize).floor();
    final lastRow = ((clipped.bottom - 0.01) / _tileSize).floor();
    for (var row = firstRow; row <= lastRow; row++) {
      for (var col = firstCol; col <= lastCol; col++) {
        final left = col * _tileSize;
        final top = row * _tileSize;
        if (left >= widget.width || top >= widget.height) {
          continue;
        }
        tiles.add(Rect.fromLTWH(left, top, _tileWidth(left), _tileHeight(top)));
      }
    }
    return tiles;
  }

  String _tileKey(Rect rect) => '${rect.left}:${rect.top}';

  double _left(String key) => double.parse(key.split(':').first);

  double _top(String key) => double.parse(key.split(':').last);

  double _tileWidth(double left) => math.min(_tileSize, widget.width - left);

  double _tileHeight(double top) => math.min(_tileSize, widget.height - top);
}

class _VectorInkPainter extends CustomPainter {
  const _VectorInkPainter(this.strokes);

  final List<StrokeObject> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final stroke in strokes) {
      paintStroke(canvas, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VectorInkPainter oldDelegate) {
    if (oldDelegate.strokes.length != strokes.length) {
      return true;
    }
    for (var index = 0; index < strokes.length; index++) {
      final previous = oldDelegate.strokes[index];
      final next = strokes[index];
      if (previous.id != next.id ||
          previous.points.length != next.points.length) {
        return true;
      }
    }
    return false;
  }
}

class _TilePainter extends CustomPainter {
  const _TilePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(covariant _TilePainter oldDelegate) =>
      oldDelegate.image != image;
}

class _LiveInk extends StatefulWidget {
  const _LiveInk({
    required this.stroke,
    required this.width,
    required this.height,
    this.viewScale = 1,
    super.key,
  });

  final StrokeObject stroke;
  final double width;
  final double height;
  final double viewScale;

  @override
  State<_LiveInk> createState() => _LiveInkState();
}

class _LiveInkState extends State<_LiveInk> {
  static const _tile = 256.0;

  final Map<String, ui.Image> _tiles = {};
  int _imagedUntil = 0;
  double _dpr = 1;
  var _generation = 0;
  var _baking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dpr = MediaQuery.devicePixelRatioOf(context);
  }

  @override
  void didUpdateWidget(covariant _LiveInk oldWidget) {
    super.didUpdateWidget(oldWidget);
    final scaleChanged = (oldWidget.viewScale - widget.viewScale).abs() > 0.04;
    if (oldWidget.stroke.id != widget.stroke.id || scaleChanged) {
      _generation++;
      final retiring = List<ui.Image>.of(_tiles.values);
      _tiles.clear();
      _imagedUntil = 0;
      _baking = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final image in retiring) {
          image.dispose();
        }
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    for (final image in _tiles.values) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.stroke.points;
    _scheduleBake(points);
    final tailStart = _imagedUntil == 0 ? 0 : math.max(0, _imagedUntil - 1);
    final tail = tailStart >= points.length
        ? const <StrokePoint>[]
        : points.sublist(tailStart);
    final bounds = _inkBounds(tail)
        .intersect(Offset.zero & Size(widget.width, widget.height));
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: [
          for (final entry in _tiles.entries)
            Positioned(
              left: _liveLeft(entry.key),
              top: _liveTop(entry.key),
              width: math.min(_tile, widget.width - _liveLeft(entry.key)),
              height: math.min(_tile, widget.height - _liveTop(entry.key)),
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _TilePainter(entry.value),
                  size: Size(
                    math.min(_tile, widget.width - _liveLeft(entry.key)),
                    math.min(_tile, widget.height - _liveTop(entry.key)),
                  ),
                ),
              ),
            ),
          if (!bounds.isEmpty)
            Positioned(
              left: bounds.left,
              top: bounds.top,
              width: bounds.width,
              height: bounds.height,
              child: CustomPaint(
                painter: _LiveStrokePainter(
                  widget.stroke.copyWith(points: tail),
                  bounds.topLeft,
                ),
                size: bounds.size,
              ),
            ),
        ],
      ),
    );
  }

  void _scheduleBake(List<StrokePoint> points) {
    if (_baking || points.length < 2) {
      return;
    }
    final freezeUntil = math.max(0, points.length - 8);
    if (freezeUntil < _imagedUntil + 24) {
      return;
    }
    _baking = true;
    final generation = _generation;
    final until = freezeUntil;
    final from = _imagedUntil == 0 ? 0 : _imagedUntil - 1;
    final slice = points.sublist(from, until).toList(growable: false);
    final id = widget.stroke.id;
    final tiles = _liveTiles(_inkBounds(slice).inflate(4));
    _paintTiles(tiles, slice, until, generation, id);
  }

  Future<void> _paintTiles(
    List<Rect> tiles,
    List<StrokePoint> slice,
    int until,
    int generation,
    String id,
  ) async {
    final updates = <String, ui.Image>{};
    try {
      for (final rect in tiles) {
        final next = await _renderLiveTile(rect, slice);
        if (!mounted || generation != _generation || widget.stroke.id != id) {
          next.dispose();
          for (final image in updates.values) {
            image.dispose();
          }
          if (mounted && generation == _generation) {
            _baking = false;
          }
          return;
        }
        updates['${rect.left}:${rect.top}'] = next;
      }
    } catch (_) {
      for (final image in updates.values) {
        image.dispose();
      }
      if (mounted && generation == _generation) {
        _baking = false;
      }
      return;
    }
    if (!mounted || generation != _generation) {
      for (final image in updates.values) {
        image.dispose();
      }
      return;
    }
    final retiring = <ui.Image>[];
    for (final entry in updates.entries) {
      final previous = _tiles[entry.key];
      _tiles[entry.key] = entry.value;
      if (previous != null) {
        retiring.add(previous);
      }
    }
    setState(() {
      _imagedUntil = until;
      _baking = false;
    });
    if (retiring.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final image in retiring) {
          image.dispose();
        }
      });
    }
  }

  Future<ui.Image> _renderLiveTile(Rect rect, List<StrokePoint> slice) {
    final scale = (_dpr <= 0 ? 1.0 : _dpr) * widget.viewScale;
    final pixelsWide = math.max(1, (rect.width * scale).round());
    final pixelsHigh = math.max(1, (rect.height * scale).round());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final current = _tiles['${rect.left}:${rect.top}'];
    if (current != null) {
      canvas.drawImageRect(
        current,
        Rect.fromLTWH(
          0,
          0,
          current.width.toDouble(),
          current.height.toDouble(),
        ),
        Rect.fromLTWH(0, 0, pixelsWide.toDouble(), pixelsHigh.toDouble()),
        Paint()..filterQuality = FilterQuality.none,
      );
    }
    canvas.save();
    canvas.scale(pixelsWide / rect.width, pixelsHigh / rect.height);
    canvas.translate(-rect.left, -rect.top);
    canvas.clipRect(rect);
    paintStroke(canvas, widget.stroke.copyWith(points: slice, finalized: true));
    canvas.restore();
    final picture = recorder.endRecording();
    return picture
        .toImage(pixelsWide, pixelsHigh)
        .whenComplete(picture.dispose);
  }

  double _liveLeft(String key) => double.parse(key.split(':').first);

  double _liveTop(String key) => double.parse(key.split(':').last);

  List<Rect> _liveTiles(Rect bounds) {
    final clipped = bounds.intersect(
      Rect.fromLTWH(0, 0, widget.width, widget.height),
    );
    if (clipped.isEmpty) {
      return const [];
    }
    final tiles = <Rect>[];
    final firstCol = (clipped.left / _tile).floor();
    final lastCol = ((clipped.right - 0.01) / _tile).floor();
    final firstRow = (clipped.top / _tile).floor();
    final lastRow = ((clipped.bottom - 0.01) / _tile).floor();
    for (var row = firstRow; row <= lastRow; row++) {
      for (var col = firstCol; col <= lastCol; col++) {
        final left = col * _tile;
        final top = row * _tile;
        if (left >= widget.width || top >= widget.height) {
          continue;
        }
        tiles.add(
          Rect.fromLTWH(
            left,
            top,
            math.min(_tile, widget.width - left),
            math.min(_tile, widget.height - top),
          ),
        );
      }
    }
    return tiles;
  }
}

Rect _inkBounds(List<StrokePoint> points) {
  if (points.isEmpty) {
    return Rect.zero;
  }
  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;
  for (final point in points) {
    final pad = point.width / 2 + 1;
    left = math.min(left, point.x - pad);
    top = math.min(top, point.y - pad);
    right = math.max(right, point.x + pad);
    bottom = math.max(bottom, point.y + pad);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

class _LiveStrokePainter extends CustomPainter {
  const _LiveStrokePainter(this.stroke, this.origin);

  final StrokeObject stroke;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(-origin.dx, -origin.dy);
    canvas.clipRect(
      Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height),
    );
    paintStroke(canvas, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiveStrokePainter oldDelegate) =>
      oldDelegate.stroke.points.length != stroke.points.length ||
      oldDelegate.origin != origin ||
      (stroke.points.isNotEmpty &&
          oldDelegate.stroke.points.last != stroke.points.last);
}
