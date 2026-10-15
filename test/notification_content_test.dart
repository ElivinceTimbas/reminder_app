import 'package:flutter_test/flutter_test.dart';
import 'package:reminder_app/data/notification_content.dart';
import 'package:reminder_app/domain/entities/reminder.dart';

void main() {
  test('only ordinary reminders expose Snooze', () {
    for (final interval in [null, 60]) {
      final details = reminderNotificationDetails(
        Reminder(
          id: 'r1',
          title: 'Water',
          hour: 9,
          minute: 0,
          intervalMinutes: interval,
        ),
      );
      if (details.iOS != null) {
        expect(
          details.iOS!.categoryIdentifier,
          interval == null ? 'reminder_actions' : 'interval_reminder_actions',
        );
      } else {
        expect(
          details.android!.actions!.map((action) => action.id),
          interval == null ? [actionStop, actionSnooze] : [actionStop],
        );
      }
    }
  });

  test(
    'snoozed and normal alerts have distinct copy without false sound warnings',
    () {
      expect(reminderNotificationTitle, "Bea's Reminders");
      expect(reminderNotificationMessage('Drink water'), 'Drink water');
      expect(
        reminderNotificationMessage('Drink water', snoozed: true),
        'Drink water (snoozed)',
      );
    },
  );

  test('sound fallback retains the due message in both notification paths', () {
    for (final snoozed in [false, true]) {
      final body = reminderNotificationMessage(
        'Drink water',
        snoozed: snoozed,
        customSoundUnavailable: true,
      );
      expect(
        body,
        startsWith(
          reminderNotificationMessage('Drink water', snoozed: snoozed),
        ),
      );
      expect(
        body,
        contains('Custom sound unavailable; using the default tone.'),
      );
    }
  });
}
