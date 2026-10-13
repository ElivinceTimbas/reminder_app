import 'package:flutter_test/flutter_test.dart';
import 'package:reminder_app/domain/entities/reminder.dart';

void main() {
  // 2026-09-29 is a Tuesday (weekday 2).
  final tuesdayNoon = DateTime(2026, 9, 29, 12, 0);

  Reminder at(int hour, int minute, {Set<int> weekdays = const {}}) => Reminder(
    id: 'r1',
    title: 'test',
    hour: hour,
    minute: minute,
    weekdays: weekdays,
  );

  group('nextOccurrence with no weekdays (remind once)', () {
    test('returns today when the time is still ahead', () {
      final next = at(18, 30).nextOccurrence(from: tuesdayNoon);
      expect(next, DateTime(2026, 9, 29, 18, 30));
    });

    test('returns tomorrow when the time already passed', () {
      final next = at(9, 0).nextOccurrence(from: tuesdayNoon);
      expect(next, DateTime(2026, 9, 30, 9, 0));
    });

    test('rolls to tomorrow when the time is exactly now', () {
      final next = at(12, 0).nextOccurrence(from: tuesdayNoon);
      expect(next, DateTime(2026, 9, 30, 12, 0));
    });

    test('keeps the selected wall-clock time across a calendar day', () {
      // Run with TZ=America/New_York as well to cover the spring DST change.
      final next = at(9, 0).nextOccurrence(from: DateTime(2026, 3, 7, 12));
      expect(next, DateTime(2026, 3, 8, 9));
      expect(next.hour, 9);
    });
  });

  group('nextOccurrence with weekdays', () {
    test('returns today when today matches and time is ahead', () {
      final next = at(
        18,
        30,
        weekdays: {2, 4},
      ).nextOccurrence(from: tuesdayNoon);
      expect(next, DateTime(2026, 9, 29, 18, 30));
    });

    test('picks the earliest future match across several weekdays', () {
      // Mon/Wed/Fri at 08:00, evaluated Tue noon -> Wed 30th.
      final next = at(
        8,
        0,
        weekdays: {1, 3, 5},
      ).nextOccurrence(from: tuesdayNoon);
      expect(next, DateTime(2026, 9, 30, 8, 0));
    });

    test('rolls to the next selected weekday when todays time passed', () {
      // Tue noon, reminder at 09:00 on Mon/Wed -> Wed 30th.
      final next = at(9, 0, weekdays: {1, 3}).nextOccurrence(from: tuesdayNoon);
      expect(next, DateTime(2026, 9, 30, 9, 0));
    });

    test('wraps a full week when only the current weekday is selected', () {
      // Every Tuesday at 09:00, evaluated Tue 12:00 -> next Tuesday.
      final next = at(9, 0, weekdays: {2}).nextOccurrence(from: tuesdayNoon);
      expect(next, DateTime(2026, 10, 6, 9, 0));
    });

    test('result always lands on a selected weekday', () {
      final r = at(23, 59, weekdays: {7});
      expect(r.nextOccurrence(from: tuesdayNoon).weekday, DateTime.sunday);
    });
  });

  group('nextOccurrenceOn (the one-day primitive behind nextOccurrence)', () {
    test('finds the requested day and ignores the weekday set', () {
      final r = at(9, 0, weekdays: {1, 3});
      expect(
        r.nextOccurrenceOn(4, from: tuesdayNoon),
        DateTime(2026, 10, 1, 9, 0),
      );
    });

    test(
      'wraps a week when the requested day is today but the time passed',
      () {
        expect(
          at(9, 0, weekdays: {2}).nextOccurrenceOn(2, from: tuesdayNoon),
          DateTime(2026, 10, 6, 9, 0),
        );
      },
    );

    test('agrees with nextOccurrence when a single day is selected', () {
      final r = at(9, 0, weekdays: {3});
      expect(
        r.nextOccurrenceOn(3, from: tuesdayNoon),
        r.nextOccurrence(from: tuesdayNoon),
      );
    });
  });

  group('validation', () {
    test('rejects an out-of-range hour', () {
      expect(() => at(24, 0), throwsRangeError);
      expect(() => at(-1, 0), throwsRangeError);
    });

    test('rejects an out-of-range minute', () {
      expect(() => at(0, 60), throwsRangeError);
      expect(() => at(0, -1), throwsRangeError);
    });
  });

  // The `time` getter that used to sit here returned a Material `TimeOfDay`.
  // It is gone: the entity is pure Dart and stores the wall clock as two ints.
  // The UI builds `TimeOfDay(hour: r.hour, minute: r.minute)` at the edge.
  test('hour and minute are plain ints, readable without Material', () {
    final r = at(7, 45);
    expect(r.hour, 7);
    expect(r.minute, 45);
  });

  test('copyWith can clear soundPath', () {
    final r = at(9, 0).copyWith(soundPath: '/tmp/a.m4a');
    expect(r.copyWith(clearSoundPath: true).soundPath, isNull);
  });
}
