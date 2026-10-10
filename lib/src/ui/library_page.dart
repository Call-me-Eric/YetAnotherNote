import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../ink/pen_palette.dart';
import '../input/finger.dart';
import '../input/stylus_side_button.dart';
import '../storage/note_document.dart';
import '../storage/vault.dart';
import 'note_page.dart';
import 'settings_page.dart';
import 'title_dialog.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({required this.vault, super.key});

  final NoteLibrary vault;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late Future<List<NoteSummary>> _notes;
  NoteSummary? _hovered;
  Offset? _hoverPosition;
  int? _pressPointer;
  Offset? _pressDown;
  NoteSummary? _pressNote;
  Timer? _pressTimer;
  var _pressHeld = false;
  var _pressDragged = false;
  var _menuOpen = false;

  @override
  void initState() {
    super.initState();
    _notes = widget.vault.listSummaries();
    stylusSideButton.addListener(_onSideButton);
  }

  @override
  void dispose() {
    _pressTimer?.cancel();
    stylusSideButton.removeListener(_onSideButton);
    super.dispose();
  }

  void _reload() {
    setState(() {
      _notes = widget.vault.listSummaries();
    });
  }

  void _onSideButton(Offset? position) {
    final note = _hovered;
    if (note == null || _menuOpen || !mounted) {
      return;
    }
    _showMenu(note, position ?? _hoverPosition ?? Offset.zero);
  }

  void _noteDown(NoteSummary note, PointerDownEvent event) {
    final finger = actsAsFinger(event.kind, stylusAsFinger: true);
    if (!finger && event.kind != PointerDeviceKind.mouse) {
      return;
    }
    _pressTimer?.cancel();
    _pressPointer = event.pointer;
    _pressDown = event.position;
    _pressNote = note;
    _pressHeld = false;
    _pressDragged = false;
    _pressTimer = Timer(fingerLongPress, () {
      if (!mounted || _pressPointer != event.pointer || _pressDragged) {
        return;
      }
      _pressHeld = true;
      final held = _pressNote;
      if (held != null) {
        _showMenu(held, _pressDown ?? event.position);
      }
    });
  }

  void _noteMove(PointerMoveEvent event) {
    if (event.pointer != _pressPointer) {
      return;
    }
    final down = _pressDown;
    if (down != null && (event.position - down).distance > fingerSlop) {
      _pressDragged = true;
      _pressTimer?.cancel();
    }
  }

  void _noteUp(PointerEvent event) {
    if (event.pointer != _pressPointer) {
      return;
    }
    _pressTimer?.cancel();
    final note = _pressNote;
    final open = !_pressHeld && !_pressDragged;
    _pressPointer = null;
    _pressNote = null;
    _pressDown = null;
    if (open && note != null) {
      _open(note);
    }
  }

  Future<void> _showMenu(NoteSummary note, Offset global) async {
    if (_menuOpen) {
      return;
    }
    _menuOpen = true;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(global.dx, global.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'rename', child: Text('重命名')),
        PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    );
    _menuOpen = false;
    if (!mounted || action == null) {
      return;
    }
    if (action == 'rename') {
      await _rename(note);
    } else if (action == 'delete') {
      await _delete(note);
    }
  }

  Future<void> _rename(NoteSummary note) async {
    final title = await askTitle(context, heading: '重命名', initial: note.title);
    if (title == null || !mounted) {
      return;
    }
    try {
      await widget.vault.renameNote(
        OpenNote(
          directoryName: note.directoryName,
          manifest: note.manifest,
          pages: const [],
        ),
        title,
      );
      _reload();
    } on NoteNameTaken catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _delete(NoteSummary note) async {
    final ok = await askConfirm(
      context,
      heading: '删除笔记',
      body: '「${note.title}」会从笔记库里去掉。',
    );
    if (!ok || !mounted) {
      return;
    }
    await widget.vault.deleteNote(
      OpenNote(
        directoryName: note.directoryName,
        manifest: note.manifest,
        pages: const [],
      ),
    );
    if (_hovered?.directoryName == note.directoryName) {
      _hovered = null;
    }
    _reload();
  }

  Future<void> _open(NoteSummary note) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _NoteGate(
          vault: widget.vault,
          load: widget.vault.openNote(note.directoryName),
        ),
      ),
    );
    _reload();
  }

  Future<void> _create() async {
    final title = await askTitle(context, heading: '新建笔记', initial: '');
    if (title == null || !mounted) {
      return;
    }
    try {
      final note = await widget.vault.createNote(title);
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => _NoteGate(
            vault: widget.vault,
            load: Future<OpenNote>.value(note),
          ),
        ),
      );
      _reload();
    } on NoteNameTaken catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('YetAnotherPage'),
        actions: [
          IconButton(
            tooltip: '设置',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => SettingsPage(
                    load: () {
                      final vault = widget.vault;
                      if (vault is Vault) {
                        return vault.readPenPalette();
                      }
                      return Future.value(PenPalette.initial());
                    },
                    save: (palette) {
                      final vault = widget.vault;
                      if (vault is Vault) {
                        return vault.writePenPalette(palette);
                      }
                      return Future.value();
                    },
                  ),
                ),
              );
            },
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: FutureBuilder<List<NoteSummary>>(
        future: _notes,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('无法读取笔记库：${snapshot.error}'));
          }
          final notes = snapshot.data ?? const <NoteSummary>[];
          if (notes.isEmpty) {
            return const Center(child: Text('还没有笔记'));
          }
          return ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return MouseRegion(
                onHover: (event) {
                  _hovered = note;
                  _hoverPosition = event.position;
                },
                onExit: (_) {
                  if (_hovered?.directoryName == note.directoryName) {
                    _hovered = null;
                  }
                },
                child: Listener(
                  onPointerDown: (event) => _noteDown(note, event),
                  onPointerMove: _noteMove,
                  onPointerUp: _noteUp,
                  onPointerCancel: _noteUp,
                  child: ListTile(
                    title: Text(note.title),
                    subtitle: Text(note.directoryName),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        label: const Text('新建笔记'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

class _NoteGate extends StatefulWidget {
  const _NoteGate({required this.vault, required this.load});

  final NoteLibrary vault;
  final Future<OpenNote> load;

  @override
  State<_NoteGate> createState() => _NoteGateState();
}

class _NoteGateState extends State<_NoteGate> {
  OpenNote? _note;
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.load.then(
      (note) {
        if (mounted) {
          setState(() => _note = note);
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(() => _error = error);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    if (note != null) {
      return NotePage(vault: widget.vault, note: note);
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: _error == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(
                      color: scheme.primary,
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '正在打开笔记',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              )
            : Text('无法打开笔记：$_error'),
      ),
    );
  }
}
