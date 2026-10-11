import '../entities/library_sound.dart';

/// The shared library of formerly used sounds, plus recording.
///
/// The library is a first-class folder in app support: a sound picked from
/// anywhere is copied in once, re-picking the same sound reuses the entry, and
/// recordings land in it too, so a take is a reusable library entry rather than
/// an orphan file in the documents root.
///
/// The operations are the ones a caller actually performs, in the order it
/// performs them — `pickSoundFile` hands back the chosen *source* and the
/// caller decides to import it, which keeps "ask the OS" and "own the bytes"
/// as separate steps.
abstract class SoundLibrary {
  /// The sounds library, created on demand.
  Future<List<LibrarySound>> listSounds();

  /// Whether the microphone may be used. Asked before a recording starts so a
  /// refusal is reported as a refusal rather than as a failed recording.
  Future<bool> hasPermission();

  /// Opens the system audio picker and returns the chosen file's path, or null
  /// if the picker was cancelled. Does NOT import: feed the result to
  /// `importSound`.
  Future<String?> pickSoundFile();

  /// Copies [sourcePath] into the library and returns the library path —
  /// the existing entry if those exact bytes are already there, a fresh copy
  /// otherwise. Throws if [sourcePath] does not exist.
  Future<String> importSound(String sourcePath);

  /// Removes a library entry. Refuses any path outside the library.
  Future<void> deleteSound(String path);

  /// Starts recording into the library; returns the in-progress file path, or
  /// null if permission was refused.
  Future<String?> startRecording();

  /// Stops recording; returns the file path, or null if nothing was captured.
  Future<String?> stopRecording();

  /// Abandons the take in progress and deletes it.
  Future<void> cancelRecording();
}
