import '../../domain/entities/reminder.dart';
import '../../domain/repositories/reminder_repository.dart';
import '../../domain/repositories/reminder_scheduler.dart';
import '../datasources/reminder_local_data_source.dart';
import '../models/reminder_row.dart';

/// Persists reminders and reconciles their OS notifications.
/// Failed schedules remain visible as disabled drafts for retry.
class SqfliteReminderRepository implements ReminderRepository {
  SqfliteReminderRepository({
    required this._database,
    required this._scheduler,
  });

  final ReminderStore _database;
  final ReminderScheduler _scheduler;
  Future<void> _pending = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<List<Reminder>> getAll() => _serialize(_getAll);

  Future<List<Reminder>> _getAll() async {
    var rows = (await _database.readAll()).toList();
    if (_scheduler is ReminderScheduleStatus) {
      final pending = await (_scheduler as ReminderScheduleStatus)
          .pendingReminderIds();
      var changedElsewhere = false;
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        final reminder = ReminderRow.fromRow(row);
        if (!reminder.isEnabled ||
            reminder.isInterval ||
            reminder.weekdays.isNotEmpty ||
            pending.contains(reminder.id)) {
          continue;
        }
        if (await _database.completeOnce(
          reminder.id,
          row['scheduleVersion'] as int? ?? 0,
        )) {
          // Keep the delivered notification available for Snooze.
          rows[index] = {...row, 'isEnabled': 0, 'isCompleted': 1};
        } else {
          changedElsewhere = true;
        }
      }
      if (changedElsewhere) rows = await _database.readAll();
    }
    return rows.map(ReminderRow.fromRow).toList();
  }

  Future<void> restoreIntervalSchedules() async {
    Object? firstError;
    for (final reminder in await getAll()) {
      if (!reminder.isInterval) continue;
      try {
        // Replaces old timing and cancels any leftover interval Snooze alerts.
        await upsert(reminder);
      } on Object catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) throw firstError;
  }

  @override
  Future<void> upsert(Reminder reminder, {int? sortOrder}) =>
      _serialize(() => _upsert(reminder, sortOrder: sortOrder));

  Future<void> _upsert(Reminder reminder, {int? sortOrder}) async {
    if (reminder.isEnabled && _scheduler is NotificationPermissions) {
      final status = await (_scheduler as NotificationPermissions)
          .checkPermissions();
      if (status != NotificationPermissionStatus.allowed) {
        throw const ReminderSchedulingException(
          'Alert access is unavailable. Enable notifications and alarms in settings, then retry.',
        );
      }
    }
    if (reminder.isEnabled && _scheduler is ReminderScheduleValidation) {
      await (_scheduler as ReminderScheduleValidation).validateSchedule(
        reminder,
      );
    }
    await _database.write(ReminderRow.toRow(reminder), sortOrder: sortOrder);
    try {
      await _scheduler.schedule(reminder);
    } on Object {
      var cancelled = false;
      try {
        await _scheduler.cancel(reminder.id);
        cancelled = true;
      } on Object {
        // Keep the cancellation failure visible in the recovery message.
      }
      await _database.write(
        ReminderRow.toRow(reminder.copyWith(isEnabled: false)),
        sortOrder: sortOrder,
      );
      throw ReminderSchedulingException(
        cancelled
            ? 'The alert could not be scheduled. Your reminder was saved paused. Retry here, or turn it on from the reminder list.'
            : 'The alert could not be updated. Your reminder was saved paused; existing alerts may still fire. Retry here, or turn it on from the reminder list.',
      );
    }
  }

  @override
  Future<int?> delete(String id) => _serialize(() => _delete(id));

  Future<int?> _delete(String id) async {
    final previous = (await _getAll()).where((r) => r.id == id).firstOrNull;
    // Keep the row when cancellation fails so the user can retry deleting it.
    await _scheduler.cancel(id);
    try {
      return await _database.delete(id);
    } on Object {
      if (previous != null) {
        try {
          await _upsert(previous);
        } on Object {
          try {
            await _database.write(
              ReminderRow.toRow(previous.copyWith(isEnabled: false)),
              sortOrder: null,
            );
          } on Object {
            throw const ReminderSchedulingException(
              'Could not delete the reminder or restore its alerts. Check this reminder before relying on it.',
            );
          }
          throw const ReminderSchedulingException(
            'Could not delete the reminder or restore its alerts. It was saved paused; turn it on to retry.',
          );
        }
      }
      rethrow;
    }
  }
}
