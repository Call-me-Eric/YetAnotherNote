import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../ids.dart';
import '../ink/eraser.dart';
import '../ink/stroke.dart';
import '../ink/text_box.dart';
import '../input/stylus_input.dart';
import '../storage/note_document.dart';
import '../storage/vault.dart';
import 'layer_panel.dart';
import 'page_canvas.dart';
import 'title_dialog.dart';
import 'tool_arc.dart';

class NotePage extends StatefulWidget {
  const NotePage({required this.vault, required this.note, super.key});

  final NoteLibrary vault;
  final OpenNote note;

  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> with TickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late OpenNote _note;
  late String _selectedPageId;
  late final TransformationController _transform;
  _PenSession? _session;
  StrokeObject? _preview;
  String? _previewPageId;
  final List<({String pageId, String layerId, StrokeObject stroke})> _settled =
      [];
  final ValueNotifier<({String pageId, StrokeObject stroke})?> _live =
      ValueNotifier(null);
  final ValueNotifier<InkPatch?> _patches = ValueNotifier(null);
  final ValueNotifier<StrokeFade> _fading = ValueNotifier(const StrokeFade());
  final List<Offset> _eraser = [];
  final List<_MarkEdit> _undoStack = [];
  final List<_MarkEdit> _redoStack = [];
  final Set<String> _hidden = {};
  final Map<int, Offset> _fingers = {};
  final Set<int> _ignoredFingers = {};
  var _multiTouch = false;
  Offset _panVelocity = Offset.zero;
  Duration? _lastPanStamp;
  Ticker? _inertia;
  Size _viewport = Size.zero;
  double _tileScale = 1;
  var _centered = false;
  var _centerScheduled = false;
  InkTool _tool = InkTool.pen;
  String? _editingTextId;
  String? _selectedTextId;
  String? _textHoverPageId;
  Offset? _textHoverLocal;
  final Map<String, ({String pageId, String layerId, TextBox box})>
  _textDrafts = {};
  String? _eraserPageId;
  String? _eraserLayerId;
  Offset? _tip;
  OverlayEntry? _arc;
  _InkLocator? _locator;
  String? _locatorPageId;
  String? _locatorLayerId;
  Future<void> _saveChain = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _selectedPageId = widget.note.pages.first.id;
    _transform = TransformationController();
    StylusInput.addHandler(_toggleArc);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  @override
  void dispose() {
    StylusInput.removeHandler(_toggleArc);
    _inertia?.dispose();
    _arc?.remove();
    _arc = null;
    _transform.dispose();
    _live.dispose();
    _patches.dispose();
    _fading.dispose();
    super.dispose();
  }

  PageFile get _selectedPage {
    return _note.pages.firstWhere(
      (page) => page.id == _selectedPageId,
      orElse: () => _note.pages.first,
    );
  }

  Future<void> _replace(Future<OpenNote> future, {String? selectPageId}) async {
    final updated = await future;
    if (!mounted) {
      return;
    }
    setState(() {
      _note = updated;
      if (selectPageId != null &&
          updated.pages.any((page) => page.id == selectPageId)) {
        _selectedPageId = selectPageId;
      } else if (!updated.pages.any((page) => page.id == _selectedPageId)) {
        _selectedPageId = updated.pages.first.id;
      }
    });
  }

  Future<void> _rename() async {
    final title = await askTitle(context, heading: '重命名', initial: _note.title);
    if (title == null || !mounted) {
      return;
    }
    try {
      await _replace(widget.vault.renameNote(_note, title));
    } on NoteNameTaken catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  void _zoom(double factor) {
    final next = Matrix4.copy(_transform.value);
    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    final zoom = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(factor, factor, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
    _transform.value = zoom * next;
    _settleScale();
  }

  void _settleScale() {
    final scale = _transform.value.getMaxScaleOnAxis();
    if ((scale - _tileScale).abs() < 0.04) {
      return;
    }
    setState(() => _tileScale = scale);
  }

  void _scheduleCenter(Size viewport) {
    _viewport = viewport;
    if (_centered ||
        _centerScheduled ||
        viewport.width <= 0 ||
        viewport.height <= 0) {
      return;
    }
    _centerScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _centered) {
        return;
      }
      _centered = true;
      final page = _selectedPage;
      const inset = 48.0;
      _transform.value = Matrix4.translationValues(
        viewport.width / 2 - inset - page.width / 2,
        viewport.height / 2 - inset - page.height / 2,
        0,
      );
    });
  }

  void _fingerDown(PointerDownEvent event) {
    final pans =
        event.kind == PointerDeviceKind.touch ||
        (_tool == InkTool.text && drawsInk(event.kind));
    if (!pans) {
      return;
    }
    _stopInertia();
    _ignoredFingers.remove(event.pointer);
    _fingers[event.pointer] = event.position;
    if (_fingers.length > 1) {
      _multiTouch = true;
      _panVelocity = Offset.zero;
      _stopInertia();
    }
    _lastPanStamp = event.timeStamp;
    if (!_multiTouch) {
      _panVelocity = Offset.zero;
    }
  }

  void _fingerMove(PointerMoveEvent event) {
    if (_ignoredFingers.contains(event.pointer)) {
      return;
    }
    final previous = _fingers[event.pointer];
    if (previous == null) {
      return;
    }
    _fingers[event.pointer] = event.position;
    if (_fingers.length != 1) {
      _lastPanStamp = event.timeStamp;
      return;
    }
    final delta = event.position - previous;
    final stamp = _lastPanStamp;
    _lastPanStamp = event.timeStamp;
    if (stamp != null) {
      final dt = (event.timeStamp - stamp).inMicroseconds / 1000000;
      if (dt > 0.001 && dt < 0.08) {
        final instant = delta / dt;
        _panVelocity = Offset(
          _panVelocity.dx * 0.45 + instant.dx * 0.55,
          _panVelocity.dy * 0.45 + instant.dy * 0.55,
        );
      }
    }
    _transform.value =
        Matrix4.translationValues(delta.dx, delta.dy, 0) * _transform.value;
  }

  void _fingerUp(PointerEvent event) {
    final ignored = _ignoredFingers.remove(event.pointer);
    final wasMoving = _fingers.containsKey(event.pointer);
    _fingers.remove(event.pointer);
    if (ignored || !wasMoving) {
      return;
    }
    if (_fingers.isNotEmpty) {
      _stopInertia();
      return;
    }
    if (_multiTouch) {
      _multiTouch = false;
      _panVelocity = Offset.zero;
      return;
    }
    _startInertia();
  }

  void _suppressPan(int pointer) {
    _stopInertia();
    _ignoredFingers.add(pointer);
    _fingers.remove(pointer);
    _panVelocity = Offset.zero;
    _lastPanStamp = null;
  }

  void _endMoving() {
    _stopInertia();
    _ignoredFingers.addAll(_fingers.keys);
    _fingers.clear();
    _panVelocity = Offset.zero;
    _lastPanStamp = null;
  }

  void _stopInertia() {
    _inertia?.stop();
    _panVelocity = Offset.zero;
  }

  void _startInertia() {
    if (_panVelocity.distance < 80) {
      _panVelocity = Offset.zero;
      return;
    }
    _inertia?.dispose();
    var last = Duration.zero;
    _inertia = createTicker((elapsed) {
      final dt = (elapsed - last).inMicroseconds / 1000000;
      last = elapsed;
      if (dt <= 0) {
        return;
      }
      _panVelocity *= math.exp(-3.4 * dt);
      if (_panVelocity.distance < 12) {
        _stopInertia();
        return;
      }
      final delta = _panVelocity * dt;
      _transform.value =
          Matrix4.translationValues(delta.dx, delta.dy, 0) * _transform.value;
    });
    _inertia!.start();
  }

  void _startStroke(String pageId, PointerEvent event) {
    _endMoving();
    final page = _note.pages.firstWhere((item) => item.id == pageId);
    final layer = _drawingLayer(page);
    if (layer == null) {
      return;
    }
    final first = sampleFromPointer(
      event: event,
      x: event.localPosition.dx,
      y: event.localPosition.dy,
      time: 0,
      baseWidth: penBaseWidth,
    );
    final stroke = StrokeObject(
      id: newId(),
      tool: 'pen',
      color: penColor,
      baseWidth: penBaseWidth,
      finalized: false,
      points: [first],
    );
    setState(() {
      _selectedPageId = pageId;
      _session = _PenSession(
        pageId: pageId,
        layerId: layer.id,
        started: event.timeStamp,
        raw: [first],
        stroke: stroke,
        cursor: StrokeCursor(),
      );
      _preview = stroke;
      _previewPageId = pageId;
    });
    _live.value = (pageId: pageId, stroke: stroke);
  }

  void _moveStroke(String pageId, PointerEvent event) {
    final session = _session;
    if (session == null || session.pageId != pageId) {
      return;
    }
    final sample = sampleFromPointer(
      event: event,
      x: event.localPosition.dx,
      y: event.localPosition.dy,
      time: (event.timeStamp - session.started).inMicroseconds / 1000000,
      baseWidth: penBaseWidth,
    );
    final next = appendCausalPoint(
      raw: session.raw,
      painted: session.stroke.points,
      sample: sample,
      baseWidth: penBaseWidth,
      connected: session.cursor.connected,
      cursor: session.cursor,
    );
    final stroke = session.stroke.copyWith(points: next.painted);
    _session = session.copyWith(raw: next.raw, stroke: stroke);
    _preview = stroke;
    _live.value = (pageId: pageId, stroke: stroke);
  }

  void _endStroke(String pageId) {
    final session = _session;
    if (session == null || session.pageId != pageId) {
      return;
    }
    final flushed = finishStroke(
      raw: session.raw,
      painted: session.stroke.points,
      connected: session.cursor.connected,
      cursor: session.cursor,
    );
    final baked = session.stroke.copyWith(
      points: flushed.painted,
      finalized: true,
    );
    setState(() {
      _session = null;
      _preview = null;
      _previewPageId = null;
      _settled.add((pageId: pageId, layerId: session.layerId, stroke: baked));
    });
    _live.value = null;
    _undoStack.add(
      _MarkEdit(
        pageId: pageId,
        layerId: session.layerId,
        added: [baked],
        tombstoned: const [],
      ),
    );
    _redoStack.clear();
    _persist(pageId, session.layerId, baked, publish: true);
  }

  void _persist(
    String pageId,
    String layerId,
    StrokeObject stroke, {
    required bool publish,
  }) {
    _saveChain = _saveChain.then((_) async {
      final updated = await widget.vault.saveStroke(
        _note,
        pageId: pageId,
        layerId: layerId,
        stroke: stroke,
      );
      if (!mounted) {
        return;
      }
      _note = updated;
      if (!publish) {
        return;
      }
      setState(() {
        _settled.removeWhere(
          (item) => item.pageId == pageId && item.stroke.id == stroke.id,
        );
      });
    });
  }

  void _eraseStart(String pageId, Offset point) {
    _endMoving();
    final page = _note.pages.firstWhere((item) => item.id == pageId);
    final layer = _drawingLayer(page);
    if (layer == null) {
      return;
    }
    _eraser
      ..clear()
      ..add(point);
    _eraserPageId = pageId;
    _eraserLayerId = layer.id;
    if (_tool == InkTool.regionEraser) {
      _punchEraser(pageId, point, point);
    } else {
      _fadeTouched(page, layer.id, [point]);
    }
  }

  void _eraseMove(String pageId, Offset point) {
    if (_eraserPageId != pageId || _eraser.isEmpty) {
      return;
    }
    if ((point - _eraser.last).distance < 1) {
      return;
    }
    final previous = _eraser.last;
    _eraser.add(point);
    if (_tool == InkTool.regionEraser) {
      _punchEraser(pageId, previous, point);
      return;
    }
    final page = _note.pages.firstWhere((item) => item.id == pageId);
    final layerId = _eraserLayerId;
    if (layerId == null) {
      return;
    }
    _fadeTouched(page, layerId, [previous, point]);
  }

  void _eraseEnd(String pageId) {
    final path = List<Offset>.of(_eraser);
    final layerId = _eraserLayerId;
    _eraser.clear();
    _eraserPageId = null;
    _eraserLayerId = null;
    if (path.isEmpty || layerId == null) {
      _fading.value = const StrokeFade();
      return;
    }
    final page = _note.pages.firstWhere((item) => item.id == pageId);
    final added = <StrokeObject>[];
    final tombstoned = <String>[];
    if (_tool == InkTool.objectEraser) {
      final hits = [
        for (final stroke in _fading.value.strokes)
          if (_fading.value.pageId == pageId) stroke,
      ];
      if (hits.isEmpty) {
        _fading.value = const StrokeFade();
        return;
      }
      tombstoned.addAll([for (final stroke in hits) stroke.id]);
      final punched = {for (final stroke in hits) stroke.id};
      _fading.value = StrokeFade(pageId: pageId, strokes: hits, solid: true);
      _punchStrokes(
        pageId,
        hits,
        onApplied: () {
          if (!mounted) {
            return;
          }
          final current = _fading.value;
          final left = [
            for (final stroke in current.strokes)
              if (!punched.contains(stroke.id)) stroke,
          ];
          _fading.value = StrokeFade(
            pageId: left.isEmpty ? null : current.pageId,
            strokes: left,
            solid: left.isNotEmpty && current.solid,
          );
        },
      );
      _commit(
        _MarkEdit(
          pageId: pageId,
          layerId: layerId,
          added: added,
          tombstoned: tombstoned,
        ),
      );
      return;
    }
    _fading.value = const StrokeFade();
    for (final stroke in _editableStrokes(page, layerId)) {
      final pieces = eraseRegion(stroke, path);
      if (pieces == null) {
        continue;
      }
      tombstoned.add(stroke.id);
      added.addAll(pieces);
    }
    if (tombstoned.isEmpty) {
      return;
    }
    _commit(
      _MarkEdit(
        pageId: pageId,
        layerId: layerId,
        added: added,
        tombstoned: tombstoned,
      ),
    );
  }

  List<StrokeObject> _editableStrokes(PageFile page, String layerId) {
    final layer = page.layers.where((item) => item.id == layerId);
    if (layer.isEmpty) {
      return const [];
    }
    final deleted = layer.single.deletedObjectIds.toSet();
    final strokes = [
      for (final stroke in strokesIn(layer.single.objects))
        if (stroke.finalized &&
            !deleted.contains(stroke.id) &&
            !_hidden.contains(stroke.id))
          stroke,
      for (final item in _settled)
        if (item.pageId == page.id &&
            item.layerId == layerId &&
            !_hidden.contains(item.stroke.id))
          item.stroke,
    ];
    final seen = <String>{};
    return [
      for (final stroke in strokes)
        if (seen.add(stroke.id)) stroke,
    ];
  }

  void _fadeTouched(PageFile page, String layerId, List<Offset> path) {
    if (path.isEmpty) {
      return;
    }
    final layer = page.layers.where((item) => item.id == layerId);
    if (layer.isEmpty) {
      return;
    }
    final objects = layer.single.objects;
    if (_locator == null ||
        !identical(_locator!.source, objects) ||
        _locatorPageId != page.id ||
        _locatorLayerId != layerId) {
      _locator = _InkLocator.from(objects);
      _locatorPageId = page.id;
      _locatorLayerId = layerId;
    }
    final query = Rect.fromPoints(path.first, path.last).inflate(eraserRadius);
    final deleted = layer.single.deletedObjectIds.toSet();
    final byId = {
      for (final stroke in _fading.value.strokes) stroke.id: stroke,
    };
    var changed = false;
    void consider(StrokeObject stroke) {
      if (byId.containsKey(stroke.id) || _hidden.contains(stroke.id)) {
        return;
      }
      if (strokeHitsEraser(stroke, path, near: query)) {
        byId[stroke.id] = stroke;
        changed = true;
      }
    }

    for (final stroke in _locator!.near(query, deleted)) {
      consider(stroke);
    }
    for (final item in _settled) {
      if (item.pageId != page.id || item.layerId != layerId) {
        continue;
      }
      if (!_boundsOf(item.stroke).inflate(eraserRadius).overlaps(query)) {
        continue;
      }
      consider(item.stroke);
    }
    if (changed) {
      _fading.value = StrokeFade(
        pageId: page.id,
        strokes: byId.values.toList(),
      );
    }
  }

  void _punchEraser(String pageId, Offset from, Offset to) {
    _patches.value = InkPatch(
      pageId: pageId,
      bounds: Rect.fromPoints(from, to).inflate(eraserRadius + 4),
      paint: (canvas) {
        final paint = Paint()
          ..blendMode = BlendMode.dstOut
          ..color = const Color(0xFFFFFFFF)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = (eraserRadius + 2) * 2
          ..style = PaintingStyle.stroke;
        if (from == to) {
          canvas.drawCircle(
            from,
            eraserRadius + 2,
            paint..style = PaintingStyle.fill,
          );
          return;
        }
        canvas.drawLine(from, to, paint);
      },
    );
  }

  void _punchStrokes(
    String pageId,
    List<StrokeObject> strokes, {
    VoidCallback? onApplied,
  }) {
    final painted = [
      for (final stroke in strokes)
        if (stroke.points.isNotEmpty) stroke,
    ];
    if (painted.isEmpty) {
      onApplied?.call();
      return;
    }
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (final stroke in painted) {
      for (final point in stroke.points) {
        final reach = point.width / 2 + 4;
        left = math.min(left, point.x - reach);
        top = math.min(top, point.y - reach);
        right = math.max(right, point.x + reach);
        bottom = math.max(bottom, point.y + reach);
      }
    }
    _patches.value = InkPatch(
      pageId: pageId,
      bounds: Rect.fromLTRB(left, top, right, bottom),
      onApplied: onApplied,
      paint: (canvas) {
        final paint = Paint()
          ..blendMode = BlendMode.dstOut
          ..color = const Color(0xFFFFFFFF);
        for (final stroke in painted) {
          paintStrokeCover(canvas, stroke, paint, pad: 3);
        }
      },
    );
  }

  void _commit(_MarkEdit edit) {
    _undoStack.add(edit);
    _redoStack.clear();
    _hidden.addAll(edit.tombstoned);
    for (final stroke in edit.added) {
      _settled.add((
        pageId: edit.pageId,
        layerId: edit.layerId,
        stroke: stroke,
      ));
    }
    setState(() {});
    _saveChain = _saveChain.then((_) async {
      final updated = await widget.vault.changeMarks(
        _note,
        pageId: edit.pageId,
        layerId: edit.layerId,
        add: edit.added,
        tombstone: edit.tombstoned,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _note = updated;
        _settled.removeWhere(
          (item) => edit.added.any((stroke) => stroke.id == item.stroke.id),
        );
        _hidden.removeAll(edit.tombstoned);
      });
    });
  }

  void _undo() {
    if (_undoStack.isEmpty) {
      return;
    }
    final edit = _undoStack.removeLast();
    _redoStack.add(edit);
    _retint(edit, undo: true);
  }

  void _redo() {
    if (_redoStack.isEmpty) {
      return;
    }
    final edit = _redoStack.removeLast();
    _undoStack.add(edit);
    _retint(edit, undo: false);
  }

  void _retint(_MarkEdit edit, {required bool undo}) {
    final tombstone = undo
        ? [for (final stroke in edit.added) stroke.id]
        : edit.tombstoned;
    final restore = undo
        ? edit.tombstoned
        : [for (final stroke in edit.added) stroke.id];
    _hidden
      ..addAll(tombstone)
      ..removeAll(restore);
    setState(() {});
    _saveChain = _saveChain.then((_) async {
      final updated = await widget.vault.changeMarks(
        _note,
        pageId: edit.pageId,
        layerId: edit.layerId,
        tombstone: tombstone,
        restore: restore,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _note = updated;
        _hidden.removeAll(tombstone);
      });
    });
  }

  LayerFile? _drawingLayer(PageFile page) {
    for (final layer in page.layers.reversed) {
      if (layer.visible && !layer.locked) {
        return layer;
      }
    }
    return null;
  }

  Future<void> _deletePage() async {
    if (_note.pages.length < 2) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('至少要留下一页')));
      return;
    }
    final ok = await askConfirm(context, heading: '删除此页', body: '这一页会从笔记里去掉。');
    if (!ok || !mounted) {
      return;
    }
    final pages = _note.pages;
    final index = pages.indexWhere((page) => page.id == _selectedPageId);
    final neighbor = pages[index > 0 ? index - 1 : index + 1].id;
    final pageId = _selectedPageId;
    await _replace(
      widget.vault.deletePage(_note, pageId: pageId),
      selectPageId: neighbor,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _settled.removeWhere((item) => item.pageId == pageId);
      _undoStack.removeWhere((edit) => edit.pageId == pageId);
      _redoStack.removeWhere((edit) => edit.pageId == pageId);
      if (_session?.pageId == pageId) {
        _session = null;
        _preview = null;
        _previewPageId = null;
        _live.value = null;
      }
    });
  }

  Future<void> _deleteNote() async {
    final ok = await askConfirm(
      context,
      heading: '删除笔记',
      body: '「${_note.title}」会从笔记库里去掉。',
    );
    if (!ok || !mounted) {
      return;
    }
    _closeArc();
    await widget.vault.deleteNote(_note);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  void _toggleArc(Offset? globalPosition) {
    if (_tool == InkTool.text &&
        _textHoverPageId != null &&
        _textHoverLocal != null) {
      final hit = _boxAt(_textHoverPageId!, _textHoverLocal!);
      if (hit != null) {
        _selectText(_textHoverPageId!, hit.id);
        return;
      }
    }
    if (_arc != null) {
      _closeArc();
      return;
    }
    final media = MediaQuery.of(context);
    final at =
        globalPosition ??
        _tip ??
        Offset(media.size.width / 2, media.size.height / 2);
    _arc = OverlayEntry(
      builder: (context) => ToolArc(
        center: at,
        onDismiss: _closeArc,
        actions: [
          ToolArcAction(
            id: 'arc-pen',
            icon: Icons.edit,
            label: '钢笔',
            selected: _tool == InkTool.pen,
            onPressed: () => _chooseTool(InkTool.pen),
          ),
          ToolArcAction(
            id: 'arc-text',
            icon: Icons.text_fields,
            label: '文字',
            selected: _tool == InkTool.text,
            onPressed: () => _chooseTool(InkTool.text),
          ),
          ToolArcAction(
            id: 'arc-object-eraser',
            icon: Icons.highlight_off,
            label: '对象橡皮',
            selected: _tool == InkTool.objectEraser,
            onPressed: () => _chooseTool(InkTool.objectEraser),
          ),
          ToolArcAction(
            id: 'arc-region-eraser',
            icon: Icons.auto_fix_off,
            label: '区域橡皮',
            selected: _tool == InkTool.regionEraser,
            onPressed: () => _chooseTool(InkTool.regionEraser),
          ),
          ToolArcAction(
            id: 'arc-undo',
            icon: Icons.undo,
            label: '撤销',
            onPressed: _undoStack.isEmpty ? null : () => _historyFromArc(_undo),
          ),
          ToolArcAction(
            id: 'arc-redo',
            icon: Icons.redo,
            label: '重做',
            onPressed: _redoStack.isEmpty ? null : () => _historyFromArc(_redo),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_arc!);
  }

  void _chooseTool(InkTool tool) {
    _closeArc();
    setState(() {
      _tool = tool;
      if (tool != InkTool.text) {
        _editingTextId = null;
        _selectedTextId = null;
      }
    });
  }

  List<({String pageId, TextBox box})> _textBoxes() {
    final boxes = <({String pageId, TextBox box})>[];
    final seen = <String>{};
    for (final page in _note.pages) {
      for (final layer in page.layers) {
        if (!layer.visible) {
          continue;
        }
        final deleted = layer.deletedObjectIds.toSet();
        for (final object in layer.objects) {
          final box = TextBox.fromObject(object);
          if (box == null ||
              deleted.contains(box.id) ||
              _hidden.contains(box.id)) {
            continue;
          }
          final draft = _textDrafts[box.id];
          final shown = draft == null ? box : draft.box;
          if (seen.add(shown.id)) {
            boxes.add((pageId: page.id, box: shown));
          }
        }
      }
    }
    for (final draft in _textDrafts.values) {
      if (seen.add(draft.box.id)) {
        boxes.add((pageId: draft.pageId, box: draft.box));
      }
    }
    return boxes;
  }

  TextBox? _boxAt(String pageId, Offset point) {
    final boxes = [
      for (final item in _textBoxes())
        if (item.pageId == pageId) item.box,
    ];
    for (final box in boxes.reversed) {
      if (box.rect.contains(point)) {
        return box;
      }
    }
    return null;
  }

  void _blurText() {
    _flushEditing();
    setState(() {
      _editingTextId = null;
      _selectedTextId = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _createText(String pageId, Rect rect) {
    _flushEditing();
    final page = _note.pages.firstWhere((item) => item.id == pageId);
    final layer = _drawingLayer(page);
    if (layer == null) {
      return;
    }
    final box = TextBox(
      id: newId(),
      version: 1,
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height,
      source: '',
    );
    setState(() {
      _selectedPageId = pageId;
      _selectedTextId = box.id;
      _editingTextId = box.id;
      _textDrafts[box.id] = (pageId: pageId, layerId: layer.id, box: box);
    });
    _persistText(pageId, layer.id, box);
  }

  void _selectText(String pageId, String id) {
    if (_editingTextId != null && _editingTextId != id) {
      _flushEditing();
    }
    setState(() {
      _selectedPageId = pageId;
      _selectedTextId = id;
      _editingTextId = null;
    });
  }

  void _editText(String pageId, String id) {
    if (_editingTextId == id) {
      return;
    }
    if (_editingTextId != null) {
      _flushEditing();
    }
    setState(() {
      _selectedPageId = pageId;
      _selectedTextId = id;
      _editingTextId = id;
    });
  }

  void _deleteText(String pageId, String id) {
    final layerId = _textDrafts[id]?.layerId ?? _layerOfText(id);
    if (layerId == null) {
      return;
    }
    setState(() {
      _textDrafts.remove(id);
      if (_editingTextId == id) {
        _editingTextId = null;
      }
      if (_selectedTextId == id) {
        _selectedTextId = null;
      }
    });
    _commit(
      _MarkEdit(
        pageId: pageId,
        layerId: layerId,
        added: const [],
        tombstoned: [id],
      ),
    );
  }

  void _moveText(String pageId, String id, Offset delta) {
    final current = _textDrafts[id];
    final stored = _storedText(id);
    final box = current?.box ?? stored;
    final layerId = current?.layerId ?? _layerOfText(id);
    if (box == null || layerId == null) {
      return;
    }
    final page = _note.pages.firstWhere((item) => item.id == pageId);
    final next = box.copyWith(
      x: (box.x + delta.dx).clamp(0.0, math.max(0.0, page.width - box.width)),
      y: (box.y + delta.dy).clamp(0.0, math.max(0.0, page.height - box.height)),
    );
    setState(() {
      _textDrafts[id] = (pageId: pageId, layerId: layerId, box: next);
    });
  }

  void _moveTextEnd(String pageId, String id) {
    final draft = _textDrafts[id];
    if (draft == null) {
      return;
    }
    _persistText(pageId, draft.layerId, draft.box);
  }

  TextBox? _storedText(String id) {
    for (final page in _note.pages) {
      for (final layer in page.layers) {
        for (final object in layer.objects) {
          final box = TextBox.fromObject(object);
          if (box?.id == id) {
            return box;
          }
        }
      }
    }
    return null;
  }

  void _draftText(TextBox box, String source) {
    final current = _textDrafts[box.id];
    final pageId = current?.pageId ?? _pageOfText(box.id);
    final layerId = current?.layerId ?? _layerOfText(box.id);
    if (pageId == null || layerId == null) {
      return;
    }
    final base = current?.box ?? box;
    _textDrafts[box.id] = (
      pageId: pageId,
      layerId: layerId,
      box: base.copyWith(source: source),
    );
  }

  void _flushEditing() {
    final id = _editingTextId;
    if (id == null) {
      return;
    }
    _editingTextId = null;
    final draft = _textDrafts[id];
    if (draft != null) {
      _persistText(draft.pageId, draft.layerId, draft.box);
    }
  }

  void _commitText(TextBox box, String source) {
    final draft = _textDrafts[box.id];
    final pageId = draft?.pageId ?? _pageOfText(box.id);
    final layerId = draft?.layerId ?? _layerOfText(box.id);
    if (pageId == null || layerId == null) {
      return;
    }
    final next = (draft?.box ?? box).copyWith(source: source);
    setState(() {
      _editingTextId = null;
      if (_tool == InkTool.text) {
        _selectedTextId = next.id;
      }
      _textDrafts[next.id] = (pageId: pageId, layerId: layerId, box: next);
    });
    _persistText(pageId, layerId, next);
  }

  void _resizeText(TextBox box, double width, double height) {
    final draft = _textDrafts[box.id];
    final pageId = draft?.pageId ?? _pageOfText(box.id);
    final layerId = draft?.layerId ?? _layerOfText(box.id);
    if (pageId == null || layerId == null) {
      return;
    }
    final page = _note.pages.firstWhere((item) => item.id == pageId);
    final next = (draft?.box ?? box).copyWith(
      width: width.clamp(64.0, page.width - (draft?.box ?? box).x),
      height: height.clamp(40.0, page.height - (draft?.box ?? box).y),
    );
    setState(() {
      _textDrafts[next.id] = (pageId: pageId, layerId: layerId, box: next);
    });
    _persistText(pageId, layerId, next);
  }

  String? _pageOfText(String id) {
    for (final page in _note.pages) {
      for (final layer in page.layers) {
        for (final object in layer.objects) {
          if (TextBox.fromObject(object)?.id == id) {
            return page.id;
          }
        }
      }
    }
    return null;
  }

  String? _layerOfText(String id) {
    for (final page in _note.pages) {
      for (final layer in page.layers) {
        for (final object in layer.objects) {
          if (TextBox.fromObject(object)?.id == id) {
            return layer.id;
          }
        }
      }
    }
    return null;
  }

  void _persistText(String pageId, String layerId, TextBox box) {
    _saveChain = _saveChain.then((_) async {
      final updated = await widget.vault.saveTextBox(
        _note,
        pageId: pageId,
        layerId: layerId,
        box: box,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _note = updated;
        final current = _textDrafts[box.id];
        if (current != null &&
            current.box.source == box.source &&
            current.box.width == box.width &&
            current.box.height == box.height) {
          _textDrafts.remove(box.id);
        }
      });
    });
  }

  void _historyFromArc(void Function() action) {
    action();
    _arc?.markNeedsBuild();
  }

  void _closeArc() {
    _arc?.remove();
    _arc = null;
  }

  Future<void> _insert({required bool before}) async {
    final currentId = _selectedPage.id;
    final beforeIds = _note.pages.map((page) => page.id).toSet();
    await _replace(
      widget.vault.insertPage(_note, pageId: currentId, before: before),
    );
    final inserted = _note.pages
        .map((page) => page.id)
        .where((id) => !beforeIds.contains(id));
    if (inserted.isNotEmpty) {
      setState(() => _selectedPageId = inserted.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _selectedPage;
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(_note.title),
        actions: [
          IconButton(
            onPressed: _rename,
            tooltip: '重命名',
            icon: const Icon(Icons.drive_file_rename_outline),
          ),
          IconButton(
            onPressed: _deleteNote,
            tooltip: '删除笔记',
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      endDrawer: Drawer(
        child: SafeArea(
          child: LayerPanel(
            page: page,
            onMove: (layerId, {required upward}) {
              _replace(
                widget.vault.moveLayer(
                  _note,
                  pageId: page.id,
                  layerId: layerId,
                  upward: upward,
                ),
              );
            },
            onVisible: (layerId, {required visible}) {
              _replace(
                widget.vault.setLayerVisible(
                  _note,
                  pageId: page.id,
                  layerId: layerId,
                  visible: visible,
                ),
              );
            },
            onLocked: (layerId, {required locked}) {
              _replace(
                widget.vault.setLayerLocked(
                  _note,
                  pageId: page.id,
                  layerId: layerId,
                  locked: locked,
                ),
              );
            },
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _scheduleCenter(constraints.biggest);
          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _fingerDown,
            onPointerMove: _fingerMove,
            onPointerUp: _fingerUp,
            onPointerCancel: _fingerUp,
            child: PageCanvas(
              pages: _note.pages,
              selectedPageId: page.id,
              transformation: _transform,
              preview: _preview,
              previewPageId: _previewPageId,
              settledStrokes: _settled,
              live: _live,
              tool: _tool,
              hiddenIds: _hidden,
              patches: _patches,
              fading: _fading,
              onSelectPage: (pageId) =>
                  setState(() => _selectedPageId = pageId),
              onStrokeStart: _startStroke,
              onStrokeMove: _moveStroke,
              onStrokeEnd: _endStroke,
              onEraseStart: _eraseStart,
              onEraseMove: _eraseMove,
              onEraseEnd: _eraseEnd,
              textBoxes: _textBoxes(),
              editingTextId: _editingTextId,
              selectedTextId: _selectedTextId,
              onTextCommit: _commitText,
              onTextDraft: _draftText,
              onTextResize: _resizeText,
              onTextBlur: _blurText,
              onSuppressPan: _suppressPan,
              onTextCreate: _createText,
              onTextSelect: _selectText,
              onTextEdit: _editText,
              onTextDelete: _deleteText,
              onTextMove: _moveText,
              onTextMoveEnd: _moveTextEnd,
              onTextHover: (pageId, local, global) {
                _tip = global;
                _textHoverPageId = local == null ? null : pageId;
                _textHoverLocal = local;
              },
              onTip: (tip) => _tip = tip,
              viewScale: _tileScale,
              onScaleSettled: _settleScale,
            ),
          );
        },
      ),
      bottomNavigationBar: Material(
        elevation: 2,
        child: SafeArea(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                IconButton(
                  tooltip: '钢笔',
                  onPressed: () => _chooseTool(InkTool.pen),
                  color: _tool == InkTool.pen
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  icon: const Icon(Icons.edit),
                ),
                IconButton(
                  tooltip: '文字',
                  onPressed: () => _chooseTool(InkTool.text),
                  color: _tool == InkTool.text
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  icon: const Icon(Icons.text_fields),
                ),
                IconButton(
                  tooltip: '对象橡皮',
                  onPressed: () => _chooseTool(InkTool.objectEraser),
                  color: _tool == InkTool.objectEraser
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  icon: const Icon(Icons.highlight_off),
                ),
                IconButton(
                  tooltip: '区域橡皮',
                  onPressed: () => _chooseTool(InkTool.regionEraser),
                  color: _tool == InkTool.regionEraser
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  icon: const Icon(Icons.auto_fix_off),
                ),
                IconButton(
                  tooltip: '撤销',
                  onPressed: _undoStack.isEmpty ? null : _undo,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: '重做',
                  onPressed: _redoStack.isEmpty ? null : _redo,
                  icon: const Icon(Icons.redo),
                ),
                IconButton(
                  tooltip: '缩小',
                  onPressed: () => _zoom(1 / 1.2),
                  icon: const Icon(Icons.zoom_out),
                ),
                IconButton(
                  tooltip: '放大',
                  onPressed: () => _zoom(1.2),
                  icon: const Icon(Icons.zoom_in),
                ),
                PopupMenuButton<bool>(
                  tooltip: '插入页面',
                  onSelected: (before) => _insert(before: before),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: true, child: Text('在此页前面插入')),
                    PopupMenuItem(value: false, child: Text('在此页后面插入')),
                  ],
                  icon: const Icon(Icons.note_add_outlined),
                ),
                IconButton(
                  tooltip: '删除此页',
                  onPressed: _deletePage,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                IconButton(
                  tooltip: '图层',
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  icon: const Icon(Icons.layers_outlined),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MarkEdit {
  const _MarkEdit({
    required this.pageId,
    required this.layerId,
    required this.added,
    required this.tombstoned,
  });

  final String pageId;
  final String layerId;
  final List<StrokeObject> added;
  final List<String> tombstoned;
}

class _PenSession {
  _PenSession({
    required this.pageId,
    required this.layerId,
    required this.started,
    required this.raw,
    required this.stroke,
    required this.cursor,
  });

  final String pageId;
  final String layerId;
  final Duration started;
  final List<StrokePoint> raw;
  final StrokeObject stroke;
  final StrokeCursor cursor;

  _PenSession copyWith({List<StrokePoint>? raw, StrokeObject? stroke}) {
    return _PenSession(
      pageId: pageId,
      layerId: layerId,
      started: started,
      raw: raw ?? this.raw,
      stroke: stroke ?? this.stroke,
      cursor: cursor,
    );
  }
}

Rect _boundsOf(StrokeObject stroke) {
  final points = stroke.points;
  if (points.isEmpty) {
    return Rect.zero;
  }
  var left = points.first.x;
  var top = points.first.y;
  var right = left;
  var bottom = top;
  for (final point in points) {
    final pad = point.width / 2;
    left = math.min(left, point.x - pad);
    top = math.min(top, point.y - pad);
    right = math.max(right, point.x + pad);
    bottom = math.max(bottom, point.y + pad);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

class _InkLocator {
  _InkLocator(this.source, this.strokes, this._buckets);

  static const cell = 48.0;

  final List<Object?> source;
  final List<StrokeObject> strokes;
  final Map<int, List<int>> _buckets;

  static _InkLocator from(List<Object?> source) {
    final strokes = <StrokeObject>[];
    final buckets = <int, List<int>>{};
    for (final stroke in strokesIn(source)) {
      if (!stroke.finalized || stroke.points.isEmpty) {
        continue;
      }
      final index = strokes.length;
      strokes.add(stroke);
      for (final point in stroke.points) {
        final pad = point.width / 2;
        final x0 = ((point.x - pad) / cell).floor();
        final x1 = ((point.x + pad) / cell).floor();
        final y0 = ((point.y - pad) / cell).floor();
        final y1 = ((point.y + pad) / cell).floor();
        for (var y = y0; y <= y1; y++) {
          for (var x = x0; x <= x1; x++) {
            final bucket = buckets.putIfAbsent((x << 21) ^ y, () => <int>[]);
            if (bucket.isEmpty || bucket.last != index) {
              bucket.add(index);
            }
          }
        }
      }
    }
    return _InkLocator(source, strokes, buckets);
  }

  Iterable<StrokeObject> near(Rect query, Set<String> deleted) sync* {
    final seen = <int>{};
    final x0 = (query.left / cell).floor();
    final x1 = (query.right / cell).floor();
    final y0 = (query.top / cell).floor();
    final y1 = (query.bottom / cell).floor();
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final bucket = _buckets[(x << 21) ^ y];
        if (bucket == null) {
          continue;
        }
        for (final index in bucket) {
          if (!seen.add(index)) {
            continue;
          }
          final stroke = strokes[index];
          if (deleted.contains(stroke.id)) {
            continue;
          }
          yield stroke;
        }
      }
    }
  }
}
