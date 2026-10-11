import 'import_sound.dart';
import '../repositories/sound_library.dart';

/// "Add a sound from my device": open the OS picker, then import the choice.
///
/// Two steps because they are two failures: the user can decline the picker,
/// and the file they picked can still be unusable. Keeping the import a
/// separate use case also means the picker's platform code does not have to
/// know anything about how the library stores things.
class PickSound {
  PickSound(this._sounds) : _import = ImportSound(_sounds);

  final SoundLibrary _sounds;
  final ImportSound _import;

  /// The library path for the picked file, or null if the picker was cancelled.
  Future<String?> call() async {
    final source = await _sounds.pickSoundFile();
    return source == null ? null : _import(source);
  }
}
