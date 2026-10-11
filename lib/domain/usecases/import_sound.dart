import '../repositories/sound_library.dart';

/// Copies a sound file into the library, reusing the entry if those exact bytes
/// are already there. Returns the library path.
class ImportSound {
  const ImportSound(this._sounds);

  final SoundLibrary _sounds;

  Future<String> call(String sourcePath) => _sounds.importSound(sourcePath);
}
