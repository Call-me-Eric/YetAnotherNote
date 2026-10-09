import 'dart:io';

/// Writes [contents] to a temporary file, then replaces [file].
///
/// A crash while the temporary file is being written leaves the previous
/// [file] in place.
Future<void> writeAtomic(File file, String contents) async {
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(contents, flush: true);
  try {
    await temporary.rename(file.path);
  } on FileSystemException {
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }
}
