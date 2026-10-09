import 'dart:convert';

const _encoder = JsonEncoder.withIndent('  ');

String encodeJson(Object value) => '${_encoder.convert(value)}\n';

class NoteManifest {
  const NoteManifest({
    required this.id,
    required this.title,
    required this.formatVersion,
    required this.pageOrder,
    this.deletedPageIds = const [],
  });

  final String id;
  final String title;
  final int formatVersion;
  final List<String> pageOrder;
  final List<String> deletedPageIds;

  NoteManifest copyWith({
    String? title,
    List<String>? pageOrder,
    List<String>? deletedPageIds,
  }) {
    return NoteManifest(
      id: id,
      title: title ?? this.title,
      formatVersion: formatVersion,
      pageOrder: pageOrder ?? this.pageOrder,
      deletedPageIds: deletedPageIds ?? this.deletedPageIds,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'formatVersion': formatVersion,
    'pageOrder': pageOrder,
    'deletedPageIds': deletedPageIds,
  };

  factory NoteManifest.fromJson(Map<String, Object?> json) {
    return NoteManifest(
      id: json['id']! as String,
      title: json['title']! as String,
      formatVersion: json['formatVersion']! as int,
      pageOrder: (json['pageOrder']! as List<Object?>).cast<String>(),
      deletedPageIds:
          (json['deletedPageIds'] as List<Object?>?)?.cast<String>() ??
          const [],
    );
  }
}

class LayerFile {
  const LayerFile({
    required this.id,
    required this.name,
    required this.objects,
    required this.deletedObjectIds,
    this.visible = true,
    this.locked = false,
  });

  final String id;
  final String name;
  final List<Object?> objects;
  final List<String> deletedObjectIds;
  final bool visible;
  final bool locked;

  LayerFile copyWith({
    bool? visible,
    bool? locked,
    List<Object?>? objects,
    List<String>? deletedObjectIds,
  }) {
    return LayerFile(
      id: id,
      name: name,
      objects: objects ?? this.objects,
      deletedObjectIds: deletedObjectIds ?? this.deletedObjectIds,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'objects': objects,
    'deletedObjectIds': deletedObjectIds,
    'visible': visible,
    'locked': locked,
  };

  factory LayerFile.fromJson(Map<String, Object?> json) {
    return LayerFile(
      id: json['id']! as String,
      name: json['name']! as String,
      objects: (json['objects']! as List<Object?>).toList(),
      deletedObjectIds: (json['deletedObjectIds']! as List<Object?>)
          .cast<String>(),
      visible: json['visible'] as bool? ?? true,
      locked: json['locked'] as bool? ?? false,
    );
  }
}

class PageFile {
  const PageFile({
    required this.id,
    required this.width,
    required this.height,
    required this.layers,
    required this.deletedLayerIds,
  });

  final String id;
  final double width;
  final double height;

  /// Bottom to top.
  final List<LayerFile> layers;
  final List<String> deletedLayerIds;

  Map<String, Object> toJson() => {
    'width': width,
    'height': height,
    'layerOrder': [for (final layer in layers) layer.id],
    'deletedLayerIds': deletedLayerIds,
  };

  /// [layers] stays bottom to top. Moving upward places the layer later in that list.
  PageFile moveLayer(String layerId, {required bool upward}) {
    final index = layers.indexWhere((layer) => layer.id == layerId);
    final target = index + (upward ? 1 : -1);
    if (index < 0 || target < 0 || target >= layers.length) {
      return this;
    }
    final next = [...layers];
    final layer = next.removeAt(index);
    next.insert(target, layer);
    return PageFile(
      id: id,
      width: width,
      height: height,
      layers: next,
      deletedLayerIds: deletedLayerIds,
    );
  }

  PageFile updateLayer(
    String layerId,
    LayerFile Function(LayerFile layer) update,
  ) {
    return PageFile(
      id: id,
      width: width,
      height: height,
      deletedLayerIds: deletedLayerIds,
      layers: [
        for (final layer in layers)
          if (layer.id == layerId) update(layer) else layer,
      ],
    );
  }
}

PageFile emptyCopyOf(
  PageFile source, {
  required String id,
  required List<String> layerIds,
}) {
  return PageFile(
    id: id,
    width: source.width,
    height: source.height,
    deletedLayerIds: const [],
    layers: [
      for (var index = 0; index < source.layers.length; index++)
        LayerFile(
          id: layerIds[index],
          name: source.layers[index].name,
          visible: source.layers[index].visible,
          locked: source.layers[index].locked,
          objects: const [],
          deletedObjectIds: const [],
        ),
    ],
  );
}

class NoteSummary {
  const NoteSummary({required this.directoryName, required this.manifest});

  final String directoryName;
  final NoteManifest manifest;

  String get title => manifest.title;
  String get id => manifest.id;
}

class OpenNote {
  const OpenNote({
    required this.directoryName,
    required this.manifest,
    required this.pages,
  });

  final String directoryName;
  final NoteManifest manifest;
  final List<PageFile> pages;

  String get title => manifest.title;
  String get id => manifest.id;
}
