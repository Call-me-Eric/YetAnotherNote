import 'package:flutter/material.dart';

import '../storage/note_document.dart';

class LayerPanel extends StatelessWidget {
  const LayerPanel({
    required this.page,
    required this.onMove,
    required this.onVisible,
    required this.onLocked,
    super.key,
  });

  final PageFile page;
  final void Function(String layerId, {required bool upward}) onMove;
  final void Function(String layerId, {required bool visible}) onVisible;
  final void Function(String layerId, {required bool locked}) onLocked;

  @override
  Widget build(BuildContext context) {
    final topFirst = page.layers.reversed.toList();
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            '图层从上面盖住下面。纸张 ${page.width} × ${page.height} point',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        for (final layer in topFirst)
          ListTile(
            title: Text(layer.name),
            subtitle: Text(layer.locked ? '已锁定' : '可编辑'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: layer.visible ? '隐藏' : '显示',
                  onPressed: () => onVisible(layer.id, visible: !layer.visible),
                  icon: Icon(
                    layer.visible ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
                IconButton(
                  tooltip: layer.locked ? '解锁' : '锁定',
                  onPressed: () => onLocked(layer.id, locked: !layer.locked),
                  icon: Icon(layer.locked ? Icons.lock : Icons.lock_open),
                ),
                IconButton(
                  tooltip: '上移',
                  onPressed: layer.id == page.layers.last.id
                      ? null
                      : () => onMove(layer.id, upward: true),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: '下移',
                  onPressed: layer.id == page.layers.first.id
                      ? null
                      : () => onMove(layer.id, upward: false),
                  icon: const Icon(Icons.arrow_downward),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
