import 'dart:io';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/entities/reminder.dart';

const actionStop = 'action_stop';
const actionSnooze = 'action_snooze';
const reminderNotificationTitle = "Bea's Reminders";
const reminderNotificationIcon = 'ic_stat_reminder';
const stopNotificationLabel = 'Turn off';
const snoozeNotificationLabel = 'Snooze 5 min';

String reminderNotificationMessage(
  String reminderTitle, {
  bool snoozed = false,
  bool customSoundUnavailable = false,
}) {
  final message = snoozed ? '$reminderTitle (snoozed)' : reminderTitle;
  return customSoundUnavailable
      ? '$message Custom sound unavailable; using the default tone.'
      : message;
}

NotificationDetails reminderNotificationDetails(
  Reminder reminder, {
  String? sound,
  String androidChannelId = 'reminders',
  bool snoozed = false,
}) {
  if (Platform.isIOS) {
    return NotificationDetails(
      iOS: DarwinNotificationDetails(
        sound: sound,
        categoryIdentifier: reminder.isInterval
            ? 'interval_reminder_actions'
            : 'reminder_actions',
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
  }
  final body = reminderNotificationMessage(
    reminder.title,
    snoozed: snoozed,
    customSoundUnavailable: reminder.soundPath != null && sound == null,
  );
  return NotificationDetails(
    android: AndroidNotificationDetails(
      androidChannelId,
      'Reminder alerts',
      channelDescription: "Scheduled and snoozed alerts from Bea's Reminders",
      icon: reminderNotificationIcon,
      color: const Color(0xFFC75B86),
      category: AndroidNotificationCategory.reminder,
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      sound: sound == null ? null : UriAndroidNotificationSound(sound),
      styleInformation: BigTextStyleInformation(body),
      actions: [
        const AndroidNotificationAction(
          actionStop,
          stopNotificationLabel,
          cancelNotification: true,
        ),
        if (!reminder.isInterval)
          const AndroidNotificationAction(
            actionSnooze,
            snoozeNotificationLabel,
            cancelNotification: true,
          ),
      ],
    ),
  );
}
