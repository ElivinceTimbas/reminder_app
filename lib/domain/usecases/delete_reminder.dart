import '../repositories/reminder_repository.dart';

/// Deletes a reminder and takes its notifications with it.
///
/// Returns the list position the row held, so a caller can put it back there.
class DeleteReminder {
  const DeleteReminder(this._reminders);

  final ReminderRepository _reminders;

  Future<int?> call(String id) => _reminders.delete(id);
}
