import '../../domain/entities/reminder.dart';

/// sqflite row <-> [Reminder] mapping.
///
/// The entity stays ignorant of persistence (no JSON, no column names); this is
/// the only place that knows a weekday set is a comma-joined string.
class ReminderRow {
  const ReminderRow._();

  /// Columns and their sqflite types, in insert order — the positional `?`
  /// placeholders in the data source's raw INSERT are generated from these
  /// keys, so the order is load-bearing.
  static Map<String, Object?> toRow(Reminder r) => {
    'id': r.id,
    'title': r.title,
    'hour': r.hour,
    'minute': r.minute,
    // laziest thing that works: "1,3,5", no join table, no JSON codec.
    'weekdays': (r.weekdays.toList()..sort()).join(','),
    'soundPath': r.soundPath,
    'isEnabled': r.isEnabled ? 1 : 0,
  };

  static Reminder fromRow(Map<String, Object?> row) {
    final weekdays = (row['weekdays'] as String? ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .map(int.parse)
        .toSet();
    return Reminder(
      id: row['id'] as String,
      title: row['title'] as String,
      hour: row['hour'] as int,
      minute: row['minute'] as int,
      weekdays: weekdays,
      soundPath: row['soundPath'] as String?,
      isEnabled: (row['isEnabled'] as int? ?? 1) == 1,
    );
  }
}
