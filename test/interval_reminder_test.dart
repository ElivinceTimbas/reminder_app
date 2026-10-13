import 'package:flutter_test/flutter_test.dart';
import 'package:reminder_app/data/models/reminder_row.dart';
import 'package:reminder_app/domain/entities/reminder.dart';

void main() {
  Reminder hourly({Set<int> excluded = const {}}) => Reminder(
    id: 'interval',
    title: 'Water',
    hour: 9,
    minute: 0,
    intervalMinutes: 60,
    quietStartMinute: 22 * 60,
    quietEndMinute: 7 * 60,
    excludedWeekdays: excluded,
  );

  test('overnight quiet hours include the start and exclude the end', () {
    final reminder = hourly();
    expect(
      reminder.nextOccurrence(from: DateTime(2026, 10, 13, 21, 59)),
      DateTime(2026, 10, 14, 7),
    );
    expect(reminder.isQuietMinute(22 * 60), isTrue);
    expect(reminder.isQuietMinute(7 * 60), isFalse);
  });

  test('quiet hours and excluded weekdays skip the entire weekend', () {
    final reminder = hourly(excluded: {DateTime.saturday, DateTime.sunday});
    expect(
      reminder.nextOccurrence(from: DateTime(2026, 10, 16, 21)),
      DateTime(2026, 10, 19, 7),
    );
  });

  test('daytime quiet hours preserve the original interval timing', () {
    final reminder = hourly().copyWith(
      minute: 15,
      intervalMinutes: 120,
      quietStartMinute: 12 * 60,
      quietEndMinute: 14 * 60,
    );
    expect(
      reminder.nextOccurrence(from: DateTime(2026, 10, 13, 11, 15)),
      DateTime(2026, 10, 13, 15, 15),
    );
  });

  test('rejects schedules with no permitted occurrence', () {
    expect(() => hourly(excluded: {1, 2, 3, 4, 5, 6, 7}), throwsArgumentError);
    expect(
      () => hourly().copyWith(quietEndMinute: 22 * 60),
      throwsArgumentError,
    );
    expect(
      () => hourly().copyWith(
        intervalMinutes: 1440,
        quietStartMinute: 8 * 60,
        quietEndMinute: 10 * 60,
      ),
      throwsArgumentError,
    );
    expect(() => hourly().copyWith(intervalMinutes: 0), throwsArgumentError);
  });

  test('SQLite rows preserve interval settings and accept legacy rows', () {
    final reminder = hourly(excluded: {6, 7});
    expect(ReminderRow.fromRow(ReminderRow.toRow(reminder)), reminder);
    final legacyRow = ReminderRow.toRow(reminder)
      ..remove('intervalMinutes')
      ..remove('quietStartMinute')
      ..remove('quietEndMinute')
      ..remove('excludedWeekdays');
    final legacy = ReminderRow.fromRow(legacyRow);
    expect(legacy.isInterval, isFalse);
    expect(legacy.excludedWeekdays, isEmpty);
  });
}
