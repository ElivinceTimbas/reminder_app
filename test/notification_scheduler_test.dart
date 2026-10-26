import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reminder_app/data/repositories/notification_reminder_scheduler.dart';
import 'package:reminder_app/domain/entities/reminder.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  late tz.Location previousLocation;

  setUp(() {
    previousLocation = tz.local;
    tz.setLocalLocation(tz.UTC);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'pendingNotificationRequests' ? [] : null;
        });
  });

  tearDown(() {
    tz.setLocalLocation(previousLocation);
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final reminder = Reminder(id: 'r1', title: 'Water', hour: 17, minute: 0);
  final schedules = [
    ('one-off', reminder, 1, null),
    (
      'weekly',
      reminder.copyWith(weekdays: {DateTime.monday, DateTime.friday}),
      2,
      DateTimeComponents.dayOfWeekAndTime,
    ),
    (
      'daily interval',
      reminder.copyWith(intervalMinutes: 1440),
      1,
      DateTimeComponents.time,
    ),
    (
      'weekday interval',
      reminder.copyWith(
        intervalMinutes: 1440,
        excludedWeekdays: {DateTime.saturday, DateTime.sunday},
      ),
      5,
      DateTimeComponents.dayOfWeekAndTime,
    ),
  ];

  for (final (name, scheduledReminder, count, components) in schedules) {
    test(
      '$name uses an alarm-clock trigger at the selected local minute',
      () async {
        await NotificationReminderScheduler().schedule(scheduledReminder);

        final scheduledCalls = calls.where(
          (call) => call.method == 'zonedSchedule',
        );
        expect(scheduledCalls, hasLength(count));
        for (final call in scheduledCalls) {
          final args = call.arguments as Map;
          final specifics = args['platformSpecifics'] as Map;
          expect(
            specifics['scheduleMode'],
            AndroidScheduleMode.alarmClock.name,
          );
          expect(args['matchDateTimeComponents'], components?.index);
          expect(args['timeZoneName'], 'UTC');
          final date = DateTime.parse(
            args['scheduledDateTimeISO8601'] as String,
          ).toLocal();
          expect(date.hour, 17);
          expect(date.minute, 0);
          expect(date.second, 0);
          expect(date.millisecond, 0);
          expect(date.microsecond, 0);
        }
      },
    );
  }

  test('all schedule variants discard the current fractional second', () {
    final now = DateTime(2026, 10, 23, 16, 59, 59, 999, 999);
    final expected = DateTime(2026, 10, 23, 17);
    for (final (_, scheduledReminder, _, _) in schedules) {
      expect(scheduledReminder.nextOccurrence(from: now), expected);
    }
    expect(reminder.nextOccurrenceOn(DateTime.friday, from: now), expected);
    expect(
      reminder
          .copyWith(intervalMinutes: 1440)
          .nextIntervalSlot(
            17 * 60,
            weekday: DateTime.friday,
            from: now,
          ),
      expected,
    );
  });
}
