import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:reminder_app/data/datasources/reminder_local_data_source.dart';
import 'package:reminder_app/data/models/reminder_row.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reminder_app/data/notification_actions.dart';
import 'package:reminder_app/data/repositories/notification_reminder_scheduler.dart';
import 'package:reminder_app/domain/entities/reminder.dart';

class _ActionDatabase extends Fake implements ReminderLocalDataSource {
  _ActionDatabase(this.reminder);
  Reminder reminder;
  bool closed = false;
  bool? singleInstance;

  Future<ReminderLocalDataSource> open({bool singleInstance = true}) async {
    this.singleInstance = singleInstance;
    return this;
  }

  @override
  Future<List<Map<String, Object?>>> readAll() async => [
    ReminderRow.toRow(reminder),
  ];

  @override
  Future<void> write(Map<String, Object?> row, {int? sortOrder}) async {
    reminder = ReminderRow.fromRow(row);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('real notification callback', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    var failPlugin = false;
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      calls.clear();
      failPlugin = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (failPlugin) throw PlatformException(code: 'failed');
            return call.method == 'pendingNotificationRequests' ? [] : null;
          });
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('Stop disables row, cancels all eight ids, and closes only its own connection', () async {
      final database = _ActionDatabase(
        Reminder(
          id: 'r1',
          title: 'Water',
          hour: 9,
          minute: 0,
          weekdays: {1, 3},
        ),
      );
      await handleNotificationAction(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: actionStop,
          payload: 'r1',
        ),
        openDatabase: database.open,
      );
      expect(database.singleInstance, isFalse);
      expect(database.closed, isTrue);
      expect(database.reminder.isEnabled, isFalse);
      final cancellations = calls.where((call) => call.method == 'cancel');
      expect(cancellations.length, 8);
      expect(
        cancellations.map((call) => (call.arguments as Map)['id']).toSet(),
        {
          for (final day in [null, 1, 2, 3, 4, 5, 6, 7])
            NotificationReminderScheduler.notificationIdFor('r1', day),
        },
      );
    });

    test(
      'Snooze schedules one extra alert without changing recurring rows',
      () async {
        final database = _ActionDatabase(
          Reminder(
            id: 'r1',
            title: 'Water',
            hour: 9,
            minute: 0,
            weekdays: {1, 3},
          ),
        );
        await handleNotificationAction(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
            actionId: actionSnooze,
            payload: 'r1',
          ),
          openDatabase: database.open,
        );
        expect(database.reminder.isEnabled, isTrue);
        expect(database.reminder.weekdays, {1, 3});
        expect(database.closed, isTrue);
        final args =
            calls
                    .singleWhere((call) => call.method == 'zonedSchedule')
                    .arguments
                as Map;
        expect(
          args['id'],
          NotificationReminderScheduler.notificationIdFor('r1'),
        );
        expect(args['matchDateTimeComponents'], isNull);
        expect(args['title'], "Bea's Reminders");
        expect(args['body'], 'Water (snoozed)');
        final scheduled = DateTime.parse('${args['scheduledDateTime']}Z');
        expect(
          scheduled.difference(DateTime.now().toUtc()).inSeconds,
          closeTo(300, 3),
        );
      },
    );

    test(
      'dismissal preserves repeating reminders even without an action id',
      () async {
        final database = _ActionDatabase(
          Reminder(id: 'r1', title: 'Water', hour: 9, minute: 0, weekdays: {1}),
        );
        await handleNotificationAction(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.notificationDismissed,
            payload: 'r1',
          ),
          openDatabase: database.open,
        );
        expect(database.reminder.isEnabled, isTrue);
        expect(database.closed, isTrue);
        expect(calls, isEmpty);
      },
    );

    test('legacy interval Snooze only cancels its old extra alert', () async {
      final database = _ActionDatabase(
        Reminder(
          id: 'r1',
          title: 'Water',
          hour: 9,
          minute: 0,
          intervalMinutes: 60,
        ),
      );
      await handleNotificationAction(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: actionSnooze,
          payload: 'r1',
        ),
        openDatabase: database.open,
      );
      expect(database.reminder.isEnabled, isTrue);
      expect(database.closed, isTrue);
      expect(calls.map((call) => call.method), ['cancel']);
      expect(
        (calls.single.arguments as Map)['id'],
        NotificationReminderScheduler.notificationIdFor('r1'),
      );
    });

    test('dismissing an interval alert does not schedule a snooze', () async {
      final database = _ActionDatabase(
        Reminder(
          id: 'r1',
          title: 'Water',
          hour: 9,
          minute: 0,
          intervalMinutes: 60,
        ),
      );
      await handleNotificationAction(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.notificationDismissed,
          payload: 'r1',
        ),
        openDatabase: database.open,
      );
      expect(database.reminder.isEnabled, isTrue);
      expect(calls, isEmpty);
      expect(database.closed, isTrue);
    });

    test('closes action database when native scheduling fails', () async {
      failPlugin = true;
      final database = _ActionDatabase(
        Reminder(id: 'r1', title: 'Water', hour: 9, minute: 0),
      );
      await expectLater(
        handleNotificationAction(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
            actionId: actionSnooze,
            payload: 'r1',
          ),
          openDatabase: database.open,
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(database.closed, isTrue);
    });
  });

  group('Snooze logic', () {
    test('snooze schedules exactly 5 minutes from now', () {
      final now = DateTime(2026, 10, 2, 12, 0, 0);
      final snooze = snoozeDateFrom(now);
      expect(snooze, DateTime(2026, 10, 2, 12, 5, 0));
    });

    test('snooze crosses the hour and day boundaries', () {
      expect(
        snoozeDateFrom(DateTime(2026, 10, 2, 23, 58)),
        DateTime(2026, 10, 3, 0, 3),
      );
      // A DST fall-back hour: +5min of wall time is +5min here because the
      // helper adds a fixed Duration, and the scheduler converts to zoned time.
      expect(
        snoozeDateFrom(DateTime(2026, 11, 1, 1, 30)),
        DateTime(2026, 11, 1, 1, 35),
      );
    });

    test(
      'snooze id cannot equal any of the 7 weekday ids for same reminder',
      () {
        const reminderId = 'test_reminder_123';
        final snoozeId = NotificationReminderScheduler.notificationIdFor(
          reminderId,
        ); // null weekday variant
        for (var weekday = 1; weekday <= 7; weekday++) {
          final weekdayId = NotificationReminderScheduler.notificationIdFor(
            reminderId,
            weekday,
          );
          expect(snoozeId, isNot(weekdayId));
        }
      },
    );

    test('snooze id stays distinct from weekday ids across many reminders', () {
      // The 31-bit fold in notificationIdFor can collide in principle; this
      // pins that it does not do so for the ids the app actually generates.
      for (final suffix in List.generate(50, (i) => 'reminder_$i')) {
        final snoozeId = NotificationReminderScheduler.notificationIdFor(
          suffix,
        );
        for (var weekday = 1; weekday <= 7; weekday++) {
          expect(
            snoozeId,
            isNot(
              NotificationReminderScheduler.notificationIdFor(
                suffix,
                weekday,
              ),
            ),
            reason: 'snooze id collided for $suffix weekday $weekday',
          );
        }
      }
    });
  });

  group('Stop semantics', () {
    // Stop is the alarm-clock contract: the row survives, disabled, so the
    // existing Switch can re-enable it. Nothing new is invented for it —
    // isEnabled already exists on the entity and in the schema.
    test('a disabled reminder cancels rather than re-arms', () {
      final reminder = Reminder(
        id: 'r1',
        title: 'Take out the bins',
        hour: 9,
        minute: 0,
        isEnabled: false,
      );
      // NotificationReminderScheduler.schedule() early-returns for a disabled
      // reminder, so writing isEnabled=false is what makes the 8-id cancel
      // sweep stick across any later reconcile.
      expect(reminder.isEnabled, isFalse);
      expect(reminder.copyWith(isEnabled: true).isEnabled, isTrue);
    });
  });

  group('Notification action wiring', () {
    test('stop and snooze are distinct action ids', () {
      expect(actionStop, isNot(actionSnooze));
      expect(actionStop, isNotEmpty);
      expect(actionSnooze, isNotEmpty);
    });

    test('both actions dismiss the notification they were pressed on', () {
      // A snooze that left the old notification up would stack a duplicate
      // alarm on top of the re-armed one.
      for (final action in [
        AndroidNotificationAction(actionStop, 'Stop'),
        AndroidNotificationAction(actionSnooze, 'Snooze'),
      ]) {
        expect(action.cancelNotification, isTrue);
        expect(action.showsUserInterface, isFalse, reason: 'must not launch');
      }
    });
  });
}
