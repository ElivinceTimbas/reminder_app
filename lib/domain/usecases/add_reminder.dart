import '../entities/reminder.dart';
import '../repositories/reminder_repository.dart';

/// Saves a new reminder and schedules it.
///
/// "Save" rather than "insert": any id is accepted, so the same call restores a
/// row the UI just undid. [sortOrder] is how the caller pins that row's old
/// list position; null lets the store decide.
class AddReminder {
  const AddReminder(this._reminders);

  final ReminderRepository _reminders;

  Future<void> call(Reminder reminder, {int? sortOrder}) =>
      _reminders.upsert(reminder, sortOrder: sortOrder);
}
