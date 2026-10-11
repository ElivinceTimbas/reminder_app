import '../../domain/entities/reminder.dart';
import '../../domain/repositories/reminder_repository.dart';
import '../../domain/repositories/reminder_scheduler.dart';
import '../datasources/reminder_local_data_source.dart';
import '../models/reminder_row.dart';

/// sqflite + OS notifications behind the domain's [ReminderRepository].
///
/// This is the ONE place the write-then-schedule invariant is implemented, and
/// the reason it lives here rather than in `AddReminder`/`ToggleReminder` is
/// the second one: two writers, one fact. Every write
/// path in the app has to pass through this class for the store to stay
/// consistent, and that is not something a use case can promise about a use
/// case written after it.
class SqfliteReminderRepository implements ReminderRepository {
  const SqfliteReminderRepository({
    required this._database,
    required this._scheduler,
  });

  final ReminderStore _database;
  final ReminderScheduler _scheduler;

  @override
  Future<List<Reminder>> getAll() async =>
      (await _database.readAll()).map(ReminderRow.fromRow).toList();

  @override
  Future<void> upsert(Reminder reminder, {int? sortOrder}) async {
    await _database.write(ReminderRow.toRow(reminder), sortOrder: sortOrder);
    await _scheduler.schedule(reminder);
  }

  @override
  Future<int?> delete(String id) async {
    final order = await _database.delete(id);
    await _scheduler.cancel(id);
    return order;
  }
}
