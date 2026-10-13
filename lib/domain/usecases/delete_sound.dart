import '../entities/library_sound.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/sound_library.dart';

/// Removes only sounds that are not referenced by a saved reminder.
class DeleteSound {
  const DeleteSound(this._sounds, this._reminders);

  final SoundLibrary _sounds;
  final ReminderRepository _reminders;

  Future<void> call(LibrarySound sound) async {
    final reminders = await _reminders.getAll();
    if (reminders.any((reminder) => reminder.soundPath == sound.path)) {
      throw StateError(
        'This sound is used by a reminder. Choose another sound for that reminder before deleting it.',
      );
    }
    await _sounds.stopPreview();
    await _sounds.deleteSound(sound.path);
  }
}
