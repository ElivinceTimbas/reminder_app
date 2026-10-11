import '../entities/reminder.dart';
import '../repositories/reminder_repository.dart';

/// Flips a reminder between on and off and saves it.
///
/// Takes the reminder rather than an id because "on" is a property of the
/// reminder, not of the list it happens to be in right now; finding the row is
/// the caller's business (the cubit owns the list).
class ToggleReminder {
  const ToggleReminder(this._reminders);

  final ReminderRepository _reminders;

  Future<void> call(Reminder reminder) =>
      _reminders.upsert(reminder.copyWith(isEnabled: !reminder.isEnabled));
}
