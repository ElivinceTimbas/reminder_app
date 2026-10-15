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

  test('overnight active hours anchor intervals to their start', () {
    final reminder = hourly().copyWith(
      minute: 15,
      intervalMinutes: 120,
      quietStartMinute: 12 * 60,
      quietEndMinute: 14 * 60,
    );
    expect(
      reminder.nextOccurrence(from: DateTime(2026, 10, 13, 11, 15)),
      DateTime(2026, 10, 13, 14),
    );
  });

  test('rejects schedules with no permitted occurrence', () {
    expect(() => hourly(excluded: {1, 2, 3, 4, 5, 6, 7}), throwsArgumentError);
    expect(
      () => hourly().copyWith(quietEndMinute: 22 * 60),
      throwsArgumentError,
    );
    expect(() => hourly().copyWith(intervalMinutes: 0), throwsArgumentError);
  });

  test('9am active start replaces a saved :57 cadence', () {
    final reminder = hourly().copyWith(
      minute: 57,
      quietStartMinute: 12 * 60,
      quietEndMinute: 9 * 60,
    );
    expect(reminder.intervalTimes, [9 * 60, 10 * 60, 11 * 60]);
    expect(
      reminder.nextOccurrence(from: DateTime(2026, 10, 14, 8, 57)),
      DateTime(2026, 10, 14, 9),
    );
    expect(
      reminder.nextOccurrence(from: DateTime(2026, 10, 14, 9, 57)),
      DateTime(2026, 10, 14, 10),
    );
  });

  test('all-day intervals retain the selected minute without drifting', () {
    final reminder = hourly().copyWith(minute: 15, clearQuietHours: true);
    expect(
      reminder.nextOccurrence(from: DateTime(2026, 10, 14, 9, 57)),
      DateTime(2026, 10, 14, 10, 15),
    );
  });

  test('a daily interval starts at active hours even in a short window', () {
    final reminder = hourly().copyWith(
      intervalMinutes: 1440,
      quietStartMinute: 10 * 60 + 30,
      quietEndMinute: 10 * 60,
    );
    expect(reminder.intervalTimes, [10 * 60]);
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

  test('saved exclusions become matching active hours and selected days', () {
    final reminder = ReminderRow.fromRow(
      ReminderRow.toRow(hourly(excluded: {6, 7})),
    );
    expect(reminder.activeStartMinute, 7 * 60);
    expect(reminder.activeEndMinute, 22 * 60);
    expect(reminder.activeWeekdays, {1, 2, 3, 4, 5});
    expect(reminder.isActiveMinute(7 * 60), isTrue);
    expect(reminder.isActiveMinute(22 * 60), isFalse);
  });

  test('overnight active hours fire only on selected calendar days', () {
    final reminder = hourly(excluded: {1, 3, 4, 5, 6, 7}).copyWith(
      quietStartMinute: 7 * 60,
      quietEndMinute: 22 * 60,
    );
    expect(reminder.activeWeekdays, {DateTime.tuesday});
    expect(reminder.isActiveMinute(22 * 60), isTrue);
    expect(reminder.isActiveMinute(7 * 60), isFalse);
    expect(
      reminder.nextOccurrence(from: DateTime(2026, 10, 13, 23, 30)),
      DateTime(2026, 10, 20),
    );
  });
}
