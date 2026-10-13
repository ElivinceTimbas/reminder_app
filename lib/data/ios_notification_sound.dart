import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'repositories/file_system_sound_library.dart';

/// Works in background isolates as well as the foreground engine.
Future<String?> iosNotificationSoundName(
  String path, {
  Future<Directory> Function()? libraryDirectory,
}) async {
  try {
    final library = await (libraryDirectory ?? getLibraryDirectory)();
    final sounds = p.join(library.path, 'Sounds');
    if (!p.equals(p.dirname(path), sounds) ||
        p.extension(path).toLowerCase() != '.wav') {
      return null;
    }
    validateNotificationWav(await File(path).readAsBytes());
    return p.basename(path);
  } on Object {
    return null;
  }
}
