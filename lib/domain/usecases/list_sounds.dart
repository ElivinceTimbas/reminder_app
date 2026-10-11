import '../entities/library_sound.dart';
import '../repositories/sound_library.dart';

/// The sounds library.
class ListSounds {
  const ListSounds(this._sounds);

  final SoundLibrary _sounds;

  Future<List<LibrarySound>> call() => _sounds.listSounds();
}
