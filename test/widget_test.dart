import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_page/src/ink/stroke.dart';
import 'package:yet_another_page/src/ink/text_box.dart';
import 'package:yet_another_page/src/paper.dart';
import 'package:yet_another_page/src/storage/note_document.dart';
import 'package:yet_another_page/src/storage/vault.dart';
import 'package:yet_another_page/src/input/stylus_side_button.dart';
import 'package:yet_another_page/src/ui/library_page.dart';
import 'package:yet_another_page/src/ui/note_page.dart';

void main() {
  testWidgets('create a note and open it again', (tester) async {
    final library = _MemoryLibrary();

    await tester.pumpWidget(MaterialApp(home: LibraryPage(vault: library)));
    await tester.pump();
    expect(find.text('还没有笔记'), findsOneWidget);

    await tester.tap(find.text('新建笔记'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '第一章');
    await tester.tap(find.text('确定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text((await library.listNotes()).single.pages.single.id),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('图层'));
    await tester.pumpAndSettle();
    expect(find.text('墨水'), findsOneWidget);

    Navigator.of(tester.element(find.text('墨水'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    Navigator.of(tester.element(find.byTooltip('图层'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
  });

  testWidgets('a stylus side button opens and closes the tool arc', (
    tester,
  ) async {
    final library = _MemoryLibrary();
    final note = await library.createNote('笔');
    await tester.pumpWidget(
      MaterialApp(
        home: NotePage(vault: library, note: note),
      ),
    );
    await tester.pump();

    stylusSideButton.report(const Offset(240, 320));
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-arc')), findsOneWidget);
    expect(find.byKey(const ValueKey('arc-pen')), findsOneWidget);
    expect(find.byKey(const ValueKey('arc-region-eraser')), findsOneWidget);
    expect(find.byKey(const ValueKey('arc-redo')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('arc-object-eraser')));
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-arc')), findsNothing);

    stylusSideButton.report(null);
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-arc')), findsOneWidget);
    stylusSideButton.report(const Offset(240, 320));
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-arc')), findsNothing);
  });
}

class _MemoryLibrary implements NoteLibrary {
  final Map<String, OpenNote> _notes = {};

  @override
  Future<List<OpenNote>> listNotes() async => _notes.values.toList();

  @override
  Future<List<NoteSummary>> listSummaries() async {
    return [
      for (final note in _notes.values)
        NoteSummary(directoryName: note.directoryName, manifest: note.manifest),
    ];
  }

  @override
  Future<OpenNote> createNote(String title) async {
    final note = OpenNote(
      directoryName: '$title.yep',
      manifest: NoteManifest(
        id: 'note-1',
        title: title,
        formatVersion: formatVersion,
        pageOrder: const ['page-1'],
      ),
      pages: const [
        PageFile(
          id: 'page-1',
          width: a4Width,
          height: a4Height,
          layers: [
            LayerFile(
              id: 'layer-1',
              name: defaultInkLayerName,
              objects: [],
              deletedObjectIds: [],
            ),
          ],
          deletedLayerIds: [],
        ),
      ],
    );
    _notes[note.directoryName] = note;
    return note;
  }

  @override
  Future<OpenNote> openNote(String directoryName) async =>
      _notes[directoryName]!;

  @override
  Future<OpenNote> renameNote(OpenNote note, String title) async {
    throw UnimplementedError();
  }

  @override
  Future<OpenNote> insertPage(
    OpenNote note, {
    required String pageId,
    required bool before,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<OpenNote> deletePage(OpenNote note, {required String pageId}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteNote(OpenNote note) async {
    throw UnimplementedError();
  }

  @override
  Future<OpenNote> moveLayer(
    OpenNote note, {
    required String pageId,
    required String layerId,
    required bool upward,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<OpenNote> setLayerVisible(
    OpenNote note, {
    required String pageId,
    required String layerId,
    required bool visible,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<OpenNote> setLayerLocked(
    OpenNote note, {
    required String pageId,
    required String layerId,
    required bool locked,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<OpenNote> saveTextBox(
    OpenNote note, {
    required String pageId,
    required String layerId,
    required TextBox box,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<OpenNote> saveStroke(
    OpenNote note, {
    required String pageId,
    required String layerId,
    required StrokeObject stroke,
  }) async {
    throw UnimplementedError();
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
    throw UnimplementedError();
  }
}
