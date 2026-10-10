import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../ids.dart';
import '../ui/text_box_view.dart';
import 'stroke.dart';
import 'text_box.dart';

/// Turns a text box into one stroke per connected ink component.
///
/// Each horizontal run is a segment. A point with [StrokePoint.gap] starts a
/// new run, so the component stays one object without bridges between rows.
Future<List<StrokeObject>> fixTextBox(TextBox box) async {
  const ratio = 4.0;
  final image = await _raster(box, ratio);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final width = image.width;
  final height = image.height;
  image.dispose();
  if (bytes == null || width == 0 || height == 0) {
    return const [];
  }
  final pixels = bytes.buffer.asUint8List();
  final labels = _components(pixels, width, height);
  final thickness = 1 / ratio;
  final strokes = <StrokeObject>[];
  for (final rows in labels) {
    final points = <StrokePoint>[];
    final keys = rows.keys.toList()..sort();
    for (final row in keys) {
      final cols = rows[row]!..sort();
      var runStart = cols.first;
      var previous = cols.first;
      void emit(int from, int to) {
        final y = box.y + (row + 0.5) * thickness;
        final x0 = box.x + (from + 0.5) * thickness;
        final x1 = box.x + (to + 0.5) * thickness;
        if (from == to) {
          points.add(_dot(x0, y, thickness, gap: true));
          return;
        }
        points.add(_dot(x0, y, thickness, gap: true));
        points.add(_dot(x1, y, thickness, gap: false));
      }

      for (final col in cols.skip(1)) {
        if (col == previous + 1) {
          previous = col;
          continue;
        }
        emit(runStart, previous);
        runStart = previous = col;
      }
      emit(runStart, previous);
    }
    if (points.isEmpty) {
      continue;
    }
    strokes.add(
      StrokeObject(
        id: newId(),
        tool: 'fixed',
        color: 0xFF000000,
        baseWidth: thickness,
        finalized: true,
        points: points,
      ),
    );
  }
  return strokes;
}

StrokePoint _dot(double x, double y, double thickness, {required bool gap}) {
  return StrokePoint(
    x: x,
    y: y,
    time: 0,
    width: thickness,
    height: thickness,
    opacity: 1,
    pressure: 0.5,
    gap: gap,
  );
}

Future<ui.Image> _raster(TextBox box, double ratio) async {
  final boundary = RenderRepaintBoundary();
  final view = ui.PlatformDispatcher.instance.views.first;
  final size = Size(box.width, box.height);
  final renderView = RenderView(
    view: view,
    child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
    configuration: ViewConfiguration(
      physicalConstraints: BoxConstraints.tight(size * ratio),
      logicalConstraints: BoxConstraints.tight(size),
      devicePixelRatio: ratio,
    ),
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final buildOwner = BuildOwner(focusManager: FocusManager());
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: SizedBox(
          width: box.width,
          height: box.height,
          child: Padding(
            padding: const EdgeInsets.all(textBoxPadding),
            child: Align(
              alignment: Alignment.topLeft,
              child: MarkdownBody(
                source: box.source,
                width: box.width - textBoxPadding * 2,
              ),
            ),
          ),
        ),
      ),
    ),
  ).attachToRenderTree(buildOwner);
  buildOwner.buildScope(root);
  buildOwner.finalizeTree();
  pipeline.flushLayout();
  pipeline.flushCompositingBits();
  pipeline.flushPaint();
  return boundary.toImage(pixelRatio: ratio);
}

/// 4-connected components of opaque pixels, grouped by row.
List<Map<int, List<int>>> _components(List<int> pixels, int width, int height) {
  final seen = List<bool>.filled(width * height, false);
  final found = <Map<int, List<int>>>[];
  bool opaque(int x, int y) => pixels[(y * width + x) * 4 + 3] > 160;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final start = y * width + x;
      if (seen[start] || !opaque(x, y)) {
        continue;
      }
      final rows = <int, List<int>>{};
      final queue = <int>[start];
      seen[start] = true;
      var head = 0;
      while (head < queue.length) {
        final index = queue[head++];
        final px = index % width;
        final py = index ~/ width;
        rows.putIfAbsent(py, () => []).add(px);
        for (final next in [index - 1, index + 1, index - width, index + width]) {
          if (next < 0 || next >= seen.length) {
            continue;
          }
          final nx = next % width;
          final ny = next ~/ width;
          if ((nx - px).abs() + (ny - py).abs() != 1) {
            continue;
          }
          if (seen[next] || !opaque(nx, ny)) {
            continue;
          }
          seen[next] = true;
          queue.add(next);
        }
      }
      found.add(rows);
    }
  }
  return found;
}
