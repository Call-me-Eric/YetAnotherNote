import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../ink/text_box.dart';
import 'markdown_math.dart';

const textBodySize = 14.0;
const textBoxPadding = 8.0;

class TextBoxLayer extends StatelessWidget {
  const TextBoxLayer({
    required this.boxes,
    required this.editingId,
    required this.selectedId,
    required this.pageWidth,
    required this.interactive,
    required this.onCommit,
    required this.onDraft,
    required this.onResize,
    required this.onResizeDown,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final List<TextBox> boxes;
  final double pageWidth;
  final String? editingId;
  final String? selectedId;
  final bool interactive;
  final void Function(TextBox box, String source) onCommit;
  final void Function(TextBox box, String source) onDraft;
  final void Function(TextBox box, double width, double height) onResize;
  final void Function(int pointer) onResizeDown;
  final ValueChanged<TextBox> onEdit;
  final ValueChanged<TextBox> onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final box in boxes)
          _TextFrame(
            key: ValueKey(box.id),
            box: box,
            editing: box.id == editingId,
            selected: box.id == selectedId,
            interactive: interactive,
            onCommit: (source) => onCommit(box, source),
            onDraft: (source) => onDraft(box, source),
            onResize: (width, height) => onResize(box, width, height),
            onResizeDown: onResizeDown,
          ),
        for (final box in boxes)
          if (interactive && box.id == selectedId && box.id != editingId)
            _TextMenu(
              box: box,
              pageWidth: pageWidth,
              onEdit: () => onEdit(box),
              onDelete: () => onDelete(box),
            ),
      ],
    );
  }
}

class _TextFrame extends StatefulWidget {
  const _TextFrame({
    required this.box,
    required this.editing,
    required this.selected,
    required this.interactive,
    required this.onCommit,
    required this.onDraft,
    required this.onResize,
    required this.onResizeDown,
    super.key,
  });

  final TextBox box;
  final bool editing;
  final bool selected;
  final bool interactive;
  final ValueChanged<String> onCommit;
  final ValueChanged<String> onDraft;
  final void Function(double width, double height) onResize;
  final void Function(int pointer) onResizeDown;

  @override
  State<_TextFrame> createState() => _TextFrameState();
}

class _TextFrameState extends State<_TextFrame> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.box.source,
  );
  late final FocusNode _focus = FocusNode();
  late double _width = widget.box.width;
  late double _height = widget.box.height;
  var _dragging = false;
  var _committed = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    if (widget.editing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focus.requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _TextFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editing && !widget.editing && !_committed) {
      _committed = true;
      final text = _controller.text;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onCommit(text);
        }
      });
    }
    if (!widget.editing && _controller.text != widget.box.source) {
      _controller.text = widget.box.source;
    }
    if (!_dragging) {
      _width = widget.box.width;
      _height = widget.box.height;
    }
    if (widget.editing && !oldWidget.editing) {
      _committed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focus.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus || _committed || !widget.editing) {
      return;
    }
    _committed = true;
    widget.onCommit(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: widget.box.x,
      top: widget.box.y,
      width: _width + 20,
      height: _height + 20,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: _width,
            height: _height,
            child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.editing ? const Color(0xF7FFFFFF) : null,
          border: widget.editing
              ? Border.all(color: scheme.primary, width: 1.5)
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(textBoxPadding),
                child: widget.editing
                    ? TextField(
                        controller: _controller,
                        focusNode: _focus,
                        expands: true,
                        maxLines: null,
                        style: const TextStyle(
                          fontSize: textBodySize,
                          height: 1.3,
                          color: Colors.black,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: widget.onDraft,
                      )
                    : ClipRect(
                        child: MarkdownBody(
                          source: widget.box.source,
                          width: _width - textBoxPadding * 2,
                        ),
                      ),
              ),
            ),
            if (widget.interactive && widget.selected && !widget.editing)
              Positioned(
                left: _width - 16,
                top: _height - 16,
                child: Listener(
                  onPointerDown: (event) => widget.onResizeDown(event.pointer),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      setState(() {
                        _dragging = true;
                        _width = (_width + details.delta.dx).clamp(64.0, 2000.0);
                        _height = (_height + details.delta.dy).clamp(
                          40.0,
                          2000.0,
                        );
                      });
                    },
                    onPanEnd: (_) {
                      _dragging = false;
                      widget.onResize(_width, _height);
                    },
                    child: const SizedBox(
                      width: 18,
                      height: 18,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.fromBorderSide(
                            BorderSide(color: Color(0xFF222222)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
        ],
      ),
    );
  }
}

class _TextMenu extends StatelessWidget {
  const _TextMenu({
    required this.box,
    required this.pageWidth,
    required this.onEdit,
    required this.onDelete,
  });

  final TextBox box;
  final double pageWidth;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    const menuWidth = 96.0;
    final rightSide = box.x + box.width + 10;
    final placeLeft = rightSide + menuWidth > pageWidth - 8;
    final left = placeLeft ? box.x - menuWidth - 10 : rightSide;
    return Positioned(
      left: left.clamp(4.0, math.max(4.0, pageWidth - menuWidth - 4)),
      top: box.y.clamp(4.0, double.infinity),
      width: menuWidth,
      child: Material(
        elevation: 3,
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: onEdit, child: const Text('编辑')),
            TextButton(onPressed: onDelete, child: const Text('删除')),
          ],
        ),
      ),
    );
  }
}

final _markdown = MarkdownGenerator(
  generators: [latexGenerator],
  inlineSyntaxList: [LatexSyntax()],
  linesMargin: const EdgeInsets.only(bottom: 4),
);

class _NoteHeading extends HeadingConfig {
  const _NoteHeading({required this.tag, required this.style});

  @override
  final String tag;

  @override
  final TextStyle style;

  @override
  HeadingDivider? get divider => null;

  @override
  EdgeInsets get padding => const EdgeInsets.only(bottom: 2);
}

class MarkdownBody extends StatelessWidget {
  const MarkdownBody({required this.source, required this.width, super.key});

  final String source;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (source.trim().isEmpty) {
      return const Text(
        '文字',
        style: TextStyle(fontSize: textBodySize, color: Color(0x66000000)),
      );
    }
    const body = TextStyle(
      fontSize: textBodySize,
      height: 1.3,
      color: Colors.black,
    );
    return SizedBox(
      width: width,
      child: MarkdownBlock(
        data: source,
        selectable: false,
        generator: _markdown,
        config: MarkdownConfig(
          configs: [
            const PConfig(textStyle: body),
            const _NoteHeading(
              tag: 'h1',
              style: TextStyle(
                fontSize: 22,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const _NoteHeading(
              tag: 'h2',
              style: TextStyle(
                fontSize: 18,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const _NoteHeading(
              tag: 'h3',
              style: TextStyle(
                fontSize: 16,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const ListConfig(marginLeft: 24, marginBottom: 2),
          ],
        ),
      ),
    );
  }
}
