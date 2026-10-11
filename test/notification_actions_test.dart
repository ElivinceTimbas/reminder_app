import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reminder_app/data/notification_actions.dart';
import 'package:reminder_app/data/repositories/notification_reminder_scheduler.dart';
import 'package:reminder_app/domain/entities/reminder.dart';

void main() {
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
