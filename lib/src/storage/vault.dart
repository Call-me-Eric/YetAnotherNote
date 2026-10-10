import 'dart:convert';
import 'dart:io';

import '../ids.dart';
import '../ink/pen_palette.dart';
import '../input/stylus_preferences.dart';
import '../ink/stroke.dart';
import '../ink/text_box.dart';
import '../paper.dart';
import 'atomic_file.dart';
import 'note_document.dart';

abstract interface class NoteLibrary {
  Future<List<OpenNote>> listNotes();

  Future<List<NoteSummary>> listSummaries();

  Future<OpenNote> createNote(String title);

  Future<OpenNote> openNote(String directoryName);

  Future<OpenNote> renameNote(OpenNote note, String title);

  Future<OpenNote> insertPage(
    OpenNote note, {
    required String pageId,
    required bool before,
  });

  Future<OpenNote> deletePage(OpenNote note, {required String pageId});

  Future<void> deleteNote(OpenNote note);

  Future<OpenNote> moveLayer(
    OpenNote note, {
    required String pageId,
    required String layerId,
    required bool upward,
  });

  Future<OpenNote> setLayerVisible(
    OpenNote note, {
    required String pageId,
    required String layerId,
    required bool visible,
  });

  Future<OpenNote> setLayerLocked(
    OpenNote note, {
    required String pageId,
    required String layerId,
    required bool locked,
  });

  Future<OpenNote> saveTextBox(
    OpenNote note, {
    required String pageId,
    required String layerId,
    required TextBox box,
  });

  Future<OpenNote> saveStroke(
    OpenNote note, {
    required String pageId,
    required String layerId,
    required StrokeObject stroke,
  });

  Future<OpenNote> changeMarks(
    OpenNote note, {
    required String pageId,
    required String layerId,
    List<StrokeObject> add = const [],
    List<String> tombstone = const [],
    List<String> restore = const [],
  });
}

class NoteNameTaken implements Exception {
  NoteNameTaken(this.title);

  final String title;

  @override
  String toString() => '已经有名为「$title」的笔记';
}

class Vault implements NoteLibrary {
  Vault(this.root);

  final Directory root;

  static const deviceFileName = 'device.json';
  static const penFileName = 'pen.json';
  static const stylusFileName = 'stylus.json';
  static const noteSuffix = '.yep';

  Future<PenPalette> readPenPalette() async {
    final file = File('${root.path}/$penFileName');
    if (!await file.exists()) {
      return PenPalette.initial();
    }
    try {
      return PenPalette.fromJson(jsonDecode(await file.readAsString()));
    } on FormatException {
      return PenPalette.initial();
    }
  }

  Future<StylusPreferences> readStylusPreferences() async {
    final file = File('${root.path}/$stylusFileName');
    if (!await file.exists()) {
      return StylusPreferences.initial;
    }
    try {
      return StylusPreferences.fromJson(jsonDecode(await file.readAsString()));
    } on FormatException {
      return StylusPreferences.initial;
    }
  }

  Future<void> writeStylusPreferences(StylusPreferences preferences) async {
    await root.create(recursive: true);
    await writeAtomic(
      File('${root.path}/$stylusFileName'),
      encodeJson(preferences.toJson()),
    );
  }

  Future<void> writePenPalette(PenPalette palette) async {
    await root.create(recursive: true);
    await writeAtomic(
      File('${root.path}/$penFileName'),
      encodeJson(palette.toJson()),
    );
  }

  Future<String> deviceId() async {
    await root.create(recursive: true);
    final file = File('${root.path}/$deviceFileName');
    if (await file.exists()) {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return json['deviceId']! as String;
    }
    final id = newId();
    await writeAtomic(file, encodeJson({'deviceId': id}));
    return id;
  }

  @override
  Future<List<OpenNote>> listNotes() async {
    if (!await root.exists()) {
      return const [];
    }
    final notes = <OpenNote>[];
    await for (final entity in root.list()) {
      if (entity is! Directory || !_isNoteDirectory(entity.path)) {
        continue;
      }
      try {
        notes.add(await openNote(_nameOf(entity)));
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    notes.sort((a, b) => a.title.compareTo(b.title));
    return notes;
  }

  @override
  Future<List<NoteSummary>> listSummaries() async {
    if (!await root.exists()) {
      return const [];
    }
    final notes = <NoteSummary>[];
    await for (final entity in root.list()) {
      if (entity is! Directory || !_isNoteDirectory(entity.path)) {
        continue;
      }
      try {
        final manifest = NoteManifest.fromJson(
          jsonDecode(await File('${entity.path}/manifest.json').readAsString())
              as Map<String, Object?>,
        );
        notes.add(
          NoteSummary(directoryName: _nameOf(entity), manifest: manifest),
        );
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    notes.sort((a, b) => a.title.compareTo(b.title));
    return notes;
  }

  @override
  Future<OpenNote> createNote(String title) async {
    await root.create(recursive: true);
    final noteId = newId();
    final pageId = newId();
    final layerId = newId();
    final manifest = NoteManifest(
      id: noteId,
      title: _displayTitle(title),
      formatVersion: formatVersion,
      pageOrder: [pageId],
    );
    final layer = LayerFile(
      id: layerId,
      name: defaultInkLayerName,
      objects: const [],
      deletedObjectIds: const [],
    );
    final page = PageFile(
      id: pageId,
      width: a4Width,
      height: a4Height,
      layers: [layer],
      deletedLayerIds: const [],
    );
    final directoryName = await _uniqueDirectoryName(manifest.title);
    final staging = Directory('${root.path}/.$directoryName.partial');
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);
    try {
      await _writeNote(staging, manifest: manifest, pages: [page]);
      await staging.rename('${root.path}/$directoryName');
    } catch (error) {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
      rethrow;
    }
    return openNote(directoryName);
  }

  @override
  Future<OpenNote> openNote(String directoryName) async {
    final directory = Directory('${root.path}/$directoryName');
    final manifestFile = File('${directory.path}/manifest.json');
    final manifest = NoteManifest.fromJson(
      jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>,
    );
    final pages = <PageFile>[];
    for (final pageId in manifest.pageOrder) {
      if (manifest.deletedPageIds.contains(pageId)) {
        continue;
      }
      final pageDirectory = Directory('${directory.path}/pages/$pageId');
      final pageJson = jsonDecode(
        await File('${pageDirectory.path}/page.json').readAsString(),
      ) as Map<String, Object?>;
      final layerOrder = (pageJson['layerOrder']! as List<Object?>)
          .cast<String>();
      final layers = <LayerFile>[];
      for (final layerId in layerOrder) {
        final layerJson = jsonDecode(
          await File('${pageDirectory.path}/$layerId.json').readAsString(),
        ) as Map<String, Object?>;
        layers.add(
          LayerFile.fromJson(await _expandStrokeRefs(pageDirectory, layerJson)),
        );
      }
      pages.add(
        PageFile(
          id: pageId,
          width: (pageJson['width']! as num).toDouble(),
          height: (pageJson['height']! as num).toDouble(),
          layers: layers,
          deletedLayerIds: (pageJson['deletedLayerIds']! as List<Object?>)
              .cast<String>(),
        ),
      );
    }
    return OpenNote(
      directoryName: directoryName,
      manifest: manifest,
      pages: pages,
    );
  }

  @override
  Future<OpenNote> renameNote(OpenNote note, String title) async {
    final displayTitle = _displayTitle(title);
    final current = Directory('${root.path}/${note.directoryName}');
    final desired = '${_directoryBase(displayTitle)}$noteSuffix';
    if (desired != note.directoryName &&
        await Directory('${root.path}/$desired').exists()) {
      throw NoteNameTaken(displayTitle);
    }
    final nextName = desired;
    final updated = note.manifest.copyWith(title: displayTitle);
    await writeAtomic(
      File('${current.path}/manifest.json'),
      encodeJson(updated.toJson()),
    );
    if (nextName != note.directoryName) {
      await current.rename('${root.path}/$nextName');
    }
    return OpenNote(
      directoryName: nextName,
      manifest: updated,
      pages: note.pages,
    );
  }

  @override
  Future<OpenNote> insertPage(
    OpenNote note, {
    required String pageId,
    required bool before,
  }) async {
    final index = note.pages.indexWhere((page) => page.id == pageId);
    if (index < 0) {
      throw ArgumentError('未知页面 $pageId');
    }
    final page = emptyCopyOf(
      note.pages[index],
      id: newId(),
      layerIds: [for (final _ in note.pages[index].layers) newId()],
    );
    final directory = Directory('${root.path}/${note.directoryName}');
    await _writePage(directory, page);
    final order = [...note.manifest.pageOrder];
    order.insert(before ? index : index + 1, page.id);
    await writeAtomic(
      File('${directory.path}/manifest.json'),
      encodeJson(note.manifest.copyWith(pageOrder: order).toJson()),
    );
    return openNote(note.directoryName);
  }

  @override
  Future<OpenNote> deletePage(OpenNote note, {required String pageId}) async {
    if (!note.manifest.pageOrder.contains(pageId) ||
        note.manifest.deletedPageIds.contains(pageId)) {
      throw ArgumentError('未知页面 $pageId');
    }
    if (note.pages.length <= 1) {
      throw StateError('至少保留一页');
    }
    final deleted = [...note.manifest.deletedPageIds];
    if (!deleted.contains(pageId)) {
      deleted.add(pageId);
    }
    final directory = Directory('${root.path}/${note.directoryName}');
    await writeAtomic(
      File('${directory.path}/manifest.json'),
      encodeJson(
        note.manifest
            .copyWith(
              pageOrder: [
                for (final id in note.manifest.pageOrder)
                  if (id != pageId) id,
              ],
              deletedPageIds: deleted,
            )
            .toJson(),
      ),
    );
    return openNote(note.directoryName);
  }

  @override
  Future<void> deleteNote(OpenNote note) async {
    final directory = Directory('${root.path}/${note.directoryName}');
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  @override
  Future<OpenNote> moveLayer(
    OpenNote note, {
    required String pageId,
    required String layerId,
    required bool upward,
  }) async {
    final page = _page(note, pageId);
    final moved = page.moveLayer(layerId, upward: upward);
    if (identical(moved, page)) {
      return note;
    }
    await _writePage(Directory('${root.path}/${note.directoryName}'), moved);
    return openNote(note.directoryName);
  }

  @override
  Future<OpenNote> setLayerVisible(
    OpenNote note, {
    required String pageId,
    required String layerId,
    required bool visible,
  }) {
    return _updateLayer(
      note,
      pageId,
      layerId,
      (layer) => layer.copyWith(visible: visible),
    );
  }

  @override
  Future<OpenNote> setLayerLocked(
    OpenNote note, {
    required String pageId,
    required String layerId,
    required bool locked,
  }) {
    return _updateLayer(
      note,
      pageId,
      layerId,
      (layer) => layer.copyWith(locked: locked),
    );
  }

  @override
  Future<OpenNote> saveTextBox(
    OpenNote note, {
    required String pageId,
    required String layerId,
    required TextBox box,
  }) async {
    final page = _page(note, pageId);
    final layer = page.layers.firstWhere(
      (item) => item.id == layerId,
      orElse: () => throw ArgumentError('未知图层 $layerId'),
    );
    var version = box.version;
    for (final object in layer.objects) {
      final existing = TextBox.fromObject(object);
      if (existing != null && existing.id == box.id) {
        version = existing.version + 1;
      }
    }
    final next = box.copyWith(version: version < 1 ? 1 : version);
    final memoryObjects = [
      for (final object in layer.objects)
        if (TextBox.fromObject(object)?.id != box.id) object,
      next.toJson(),
    ];
    final directory = Directory(
      '${root.path}/${note.directoryName}/pages/$pageId',
    );
    final stored = layer.copyWith(
      objects: [for (final object in memoryObjects) _storedObject(object)],
    );
    await writeAtomic(
      File('${directory.path}/$layerId.json'),
      encodeJson(stored.toJson()),
    );
    return OpenNote(
      directoryName: note.directoryName,
      manifest: note.manifest,
      pages: [
        for (final item in note.pages)
          if (item.id == page.id)
            page.updateLayer(
              layer.id,
              (_) => layer.copyWith(objects: memoryObjects),
            )
          else
            item,
      ],
    );
  }

  @override
  Future<OpenNote> saveStroke(
    OpenNote note, {
    required String pageId,
    required String layerId,
    required StrokeObject stroke,
  }) async {
    final page = _page(note, pageId);
    final layer = page.layers.firstWhere(
      (item) => item.id == layerId,
      orElse: () => throw ArgumentError('未知图层 $layerId'),
    );
    final existing = strokesIn(layer.objects)
        .where((item) => item.id == stroke.id);
    if (existing.isNotEmpty && existing.first.finalized) {
      return note;
    }
    final memoryObjects = [
      for (final object in layer.objects)
        if (_strokeId(object) != stroke.id) object,
      stroke.toJson(),
    ];
    final directory = Directory(
      '${root.path}/${note.directoryName}/pages/$pageId',
    );
    await _spillStrokes(directory, memoryObjects);
    final stored = layer.copyWith(
      objects: [for (final object in memoryObjects) _storedObject(object)],
    );
    await writeAtomic(
      File('${directory.path}/$layerId.json'),
      encodeJson(stored.toJson()),
    );
    return OpenNote(
      directoryName: note.directoryName,
      manifest: note.manifest,
      pages: [
        for (final item in note.pages)
          if (item.id == page.id)
            page.updateLayer(
              layer.id,
              (_) => layer.copyWith(objects: memoryObjects),
            )
          else
            item,
      ],
    );
  }

  @override
  Future<OpenNote> changeMarks(
    OpenNote note, {
    required String pageId,
    required String layerId,
    List<StrokeObject> add = const [],
    List<String> tombstone = const [],
    List<String> restore = const [],
  }) async {
    final page = _page(note, pageId);
    final layer = page.layers.firstWhere(
      (item) => item.id == layerId,
      orElse: () => throw ArgumentError('未知图层 $layerId'),
    );
    final deleted = [...layer.deletedObjectIds];
    for (final id in tombstone) {
      if (!deleted.contains(id)) {
        deleted.add(id);
      }
    }
    deleted.removeWhere(restore.contains);
    final memoryObjects = [
      ...layer.objects,
      for (final stroke in add) stroke.toJson(),
    ];
    final directory = Directory(
      '${root.path}/${note.directoryName}/pages/$pageId',
    );
    await _spillStrokes(directory, memoryObjects);
    final stored = layer.copyWith(
      objects: [for (final object in memoryObjects) _storedObject(object)],
      deletedObjectIds: deleted,
    );
    await writeAtomic(
      File('${directory.path}/$layerId.json'),
      encodeJson(stored.toJson()),
    );
    final memory = layer.copyWith(
      objects: memoryObjects,
      deletedObjectIds: deleted,
    );
    return OpenNote(
      directoryName: note.directoryName,
      manifest: note.manifest,
      pages: [
        for (final item in note.pages)
          if (item.id == page.id)
            page.updateLayer(layer.id, (_) => memory)
          else
            item,
      ],
    );
  }

  String? _strokeId(Object? object) {
    if (object is! Map) {
      return null;
    }
    final type = object['type'];
    final id = object['id'];
    if (id is! String || (type != 'stroke' && type != 'strokeRef')) {
      return null;
    }
    return id;
  }

  Object? _storedObject(Object? object) {
    final id = _strokeId(object);
    if (id == null) {
      return object;
    }
    return {'type': 'strokeRef', 'id': id};
  }

  Future<void> _spillStrokes(
    Directory pageDirectory,
    List<Object?> objects,
  ) async {
    final strokes = Directory('${pageDirectory.path}/strokes');
    await strokes.create(recursive: true);
    for (final object in objects) {
      if (object is! Map ||
          object['type'] != 'stroke' ||
          object['points'] is! List) {
        continue;
      }
      final id = object['id'];
      if (id is! String) {
        continue;
      }
      final file = File('${strokes.path}/$id.json');
      if (await file.exists()) {
        continue;
      }
      await writeAtomic(
        file,
        encodeJson(Map<String, Object?>.from(object).cast<String, Object>()),
      );
    }
  }

  Future<Map<String, Object?>> _expandStrokeRefs(
    Directory pageDirectory,
    Map<String, Object?> layerJson,
  ) async {
    final objects = layerJson['objects'];
    if (objects is! List) {
      return layerJson;
    }
    final expanded = <Object?>[];
    for (final object in objects) {
      if (object is Map && object['type'] == 'strokeRef') {
        final id = object['id'];
        if (id is! String) {
          continue;
        }
        final file = File('${pageDirectory.path}/strokes/$id.json');
        if (!await file.exists()) {
          continue;
        }
        expanded.add(jsonDecode(await file.readAsString()));
        continue;
      }
      expanded.add(object);
    }
    return {...layerJson, 'objects': expanded};
  }

  Future<OpenNote> _updateLayer(
    OpenNote note,
    String pageId,
    String layerId,
    LayerFile Function(LayerFile layer) update,
  ) async {
    final page = _page(note, pageId).updateLayer(layerId, update);
    final directory = Directory(
      '${root.path}/${note.directoryName}/pages/$pageId',
    );
    final layer = page.layers.firstWhere((item) => item.id == layerId);
    await writeAtomic(
      File('${directory.path}/$layerId.json'),
      encodeJson(layer.toJson()),
    );
    return openNote(note.directoryName);
  }

  PageFile _page(OpenNote note, String pageId) {
    return note.pages.firstWhere(
      (page) => page.id == pageId,
      orElse: () => throw ArgumentError('未知页面 $pageId'),
    );
  }

  Future<void> _writeNote(
    Directory directory, {
    required NoteManifest manifest,
    required List<PageFile> pages,
  }) async {
    await writeAtomic(
      File('${directory.path}/manifest.json'),
      encodeJson(manifest.toJson()),
    );
    for (final page in pages) {
      await _writePage(directory, page);
    }
    await Directory('${directory.path}/assets').create();
  }

  Future<void> _writePage(Directory noteDirectory, PageFile page) async {
    final pageDirectory = Directory('${noteDirectory.path}/pages/${page.id}');
    await pageDirectory.create(recursive: true);
    await writeAtomic(
      File('${pageDirectory.path}/page.json'),
      encodeJson(page.toJson()),
    );
    for (final layer in page.layers) {
      await writeAtomic(
        File('${pageDirectory.path}/${layer.id}.json'),
        encodeJson(layer.toJson()),
      );
    }
  }

  Future<String> _uniqueDirectoryName(String title) async {
    final base = _directoryBase(title);
    var candidate = '$base$noteSuffix';
    var suffix = 2;
    while (await Directory('${root.path}/$candidate').exists()) {
      candidate = '$base $suffix$noteSuffix';
      suffix += 1;
    }
    return candidate;
  }

  static String _displayTitle(String title) {
    final trimmed = title.trim();
    return trimmed.isEmpty ? '未命名' : trimmed;
  }

  static String _directoryBase(String title) {
    var base = _displayTitle(title);
    if (base.toLowerCase().endsWith(noteSuffix)) {
      base = base.substring(0, base.length - noteSuffix.length).trim();
    }
    base = base
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (base.isEmpty || base == '.' || base == '..') {
      return '未命名';
    }
    return base;
  }

  static bool _isNoteDirectory(String path) {
    final name = _nameOf(Directory(path));
    return !name.startsWith('.') && name.endsWith(noteSuffix);
  }

  static String _nameOf(Directory directory) {
    final path = directory.path;
    final index = path.lastIndexOf(Platform.pathSeparator);
    return index == -1 ? path : path.substring(index + 1);
  }
}
