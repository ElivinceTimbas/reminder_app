import '../repositories/sound_library.dart';

/// Closes the open take. Null if nothing was captured.
class StopRecording {
  const StopRecording(this._sounds);

  final SoundLibrary _sounds;

  Future<String?> call() => _sounds.stopRecording();
}
