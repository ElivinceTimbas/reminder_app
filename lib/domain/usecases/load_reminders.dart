import '../entities/reminder.dart';
import '../repositories/reminder_repository.dart';

/// Every reminder, in list order.
class LoadReminders {
  const LoadReminders(this._reminders);

  final ReminderRepository _reminders;

  Future<List<Reminder>> call() => _reminders.getAll();
}
