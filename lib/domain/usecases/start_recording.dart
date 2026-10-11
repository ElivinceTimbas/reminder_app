import '../repositories/sound_library.dart';

/// Opens a take. Null if the microphone permission was refused.
class StartRecording {
  const StartRecording(this._sounds);

  final SoundLibrary _sounds;

  Future<String?> call() => _sounds.startRecording();
}
