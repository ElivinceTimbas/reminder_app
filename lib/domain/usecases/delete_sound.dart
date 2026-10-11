import '../entities/library_sound.dart';
import '../repositories/sound_library.dart';

/// Removes a library entry. Refuses any path outside the library.
class DeleteSound {
  const DeleteSound(this._sounds);

  final SoundLibrary _sounds;

  Future<void> call(LibrarySound sound) => _sounds.deleteSound(sound.path);
}
