import '../repositories/sound_library.dart';

/// Throws the open take away and deletes the file.
///
/// Held as an instance rather than looked up on demand: the only caller is
/// widget `dispose`, which has no business reading a provider off a half-dead
/// element.
class CancelRecording {
  const CancelRecording(this._sounds);

  final SoundLibrary _sounds;

  Future<void> call() => _sounds.cancelRecording();
}
