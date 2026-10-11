import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'datasources/reminder_local_data_source.dart';
import 'models/reminder_row.dart';
import '../domain/entities/reminder.dart';
import 'repositories/notification_reminder_scheduler.dart';

const _soundChannel = MethodChannel('com.deimos.reminder_app/sounds');

/// Action IDs for notification buttons
const actionStop = 'action_stop';
const actionSnooze = 'action_snooze';

/// Shared logic to handle notification actions. Called from both
/// foreground and background callbacks.
Future<void> handleNotificationAction(NotificationResponse response) async {
  final actionId = response.actionId;
  if (actionId == null) return;

  // Initialize timezone in this isolate (background isolates need this)
  tzdata.initializeTimeZones();
  try {
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone));
  } on Object {
    // Fallback to UTC if timezone can't be determined
  }

  // Open database in this isolate
  final database = await ReminderLocalDataSource.open();

  try {
    final reminderId = response.payload;
    if (reminderId == null) return;

    // If the notification was dismissed (not tapped with an action), treat it
    // as "Stop" for one-shot reminders: the fired occurrence is done.
    final dismissed = response.notificationResponseType ==
        NotificationResponseType.notificationDismissed;
    if (actionId == actionStop || dismissed) {
      await _handleStop(reminderId, database);
      return;
    } else if (actionId == actionSnooze) {
      await _handleSnooze(reminderId, database);
    }
  } finally {
    await database.close();
  }
}

/// Top-level background callback for notification actions.
/// This is invoked when the app is killed or in background.
@pragma('vm:entry-point')
Future<void> onDidReceiveBackgroundNotificationResponse(
  NotificationResponse response,
) async {
  await handleNotificationAction(response);
}

Future<void> _handleStop(
  String reminderId,
  ReminderLocalDataSource database,
) async {
  // Read all rows, find the one with this id
  final rows = await database.readAll();
  final target = rows.where((r) => r['id'] == reminderId).toList();
  if (target.isEmpty) return;

  final reminder = ReminderRow.fromRow(target.first);
  // Stop = disable the reminder. A one-shot reminder becomes a disabled
  // one-shot (never to fire again), a repeating reminder is fully disabled.
  final disabledReminder = reminder.copyWith(isEnabled: false);
  await database.write(ReminderRow.toRow(disabledReminder), sortOrder: null);

  // Cancel all scheduled notifications for this reminder (8 ids sweep)
  await Future.wait([
    for (final weekday in [null, ...List.generate(7, (i) => i + 1)])
      FlutterLocalNotificationsPlugin().cancel(
        id: NotificationReminderScheduler.notificationIdFor(
          reminderId,
          weekday,
        ),
      ),
  ]);
}

Future<void> _handleSnooze(
  String reminderId,
  ReminderLocalDataSource database,
) async {
  final rows = await database.readAll();
  final target = rows.where((r) => r['id'] == reminderId).toList();
  if (target.isEmpty) return;

  final reminder = ReminderRow.fromRow(target.first);

  // Snooze re-triggers the alarm for today's occurrence only, 5 minutes later.
  //
  // `matchDateTimeComponents` is deliberately absent: that is what makes this a
  // single extra firing instead of a new recurring series. The reminder's own
  // weekday entries stay armed and untouched, so a snoozed Mon/Wed reminder
  // rings once in 5 minutes and then again next Monday and Wednesday as usual.
  //
  // Snooze id must not collide with those weekday ids — the null-weekday
  // variant is free, since a recurring reminder only ever uses 1..7 and a
  // one-shot reminder is not re-armed here.
  final snoozeId = NotificationReminderScheduler.notificationIdFor(
    reminderId,
  ); // null weekday variant

  final snoozeTime = snoozeDateFrom(DateTime.now());
  final snoozeZoned = tz.TZDateTime.from(snoozeTime, tz.local);

  final details = await _buildSnoozeDetails(reminder);

  await FlutterLocalNotificationsPlugin().zonedSchedule(
    id: snoozeId,
    title: reminder.title,
    body: _snoozeBody(reminder, details),
    scheduledDate: snoozeZoned,
    notificationDetails: details,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    payload: reminderId,
  );
}

Future<NotificationDetails> _buildSnoozeDetails(Reminder reminder) async {
  final resolved = reminder.soundPath == null
      ? null
      : await _resolveSound(reminder.soundPath!);
  if (resolved == null) {
    return NotificationDetails(
      android: const AndroidNotificationDetails(
        'reminders',
        'Reminders',
        channelDescription: 'Scheduled reminder alerts',
        importance: Importance.max,
        priority: Priority.high,
        fullScreenIntent: true,
        actions: [
          AndroidNotificationAction(
            actionStop,
            'Stop',
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            actionSnooze,
            'Snooze',
            cancelNotification: true,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(
        categoryIdentifier: 'reminder_actions',
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
  }

  final signature = await _signature(reminder.soundPath!);
  if (Platform.isIOS) {
    return NotificationDetails(
      iOS: DarwinNotificationDetails(
        sound: resolved,
        categoryIdentifier: 'reminder_actions',
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
  }
  return NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders_$signature',
      'Reminders',
      channelDescription: 'Scheduled reminder alerts',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      sound: UriAndroidNotificationSound(resolved),
      actions: [
        AndroidNotificationAction(
          actionStop,
          'Stop',
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          actionSnooze,
          'Snooze',
          cancelNotification: true,
        ),
      ],
    ),
  );
}

String _snoozeBody(Reminder reminder, NotificationDetails details) {
  if (reminder.soundPath == null || _hasCustomSound(details)) {
    return 'Reminder';
  }
  return Platform.isIOS
      ? 'Reminder · custom sound is not bundled on iOS'
      : 'Reminder · custom sound could not be loaded';
}

bool _hasCustomSound(NotificationDetails details) =>
    details.android?.sound is AndroidNotificationSound ||
    details.iOS?.sound != null;

/// Resolves [path] to a platform sound, or null to fall back to the default.
///
/// ALWAYS null when the app was killed to deliver this action: the sound
/// channel is registered on the live `MainActivity` (Android,
/// `configureFlutterEngine`) / `AppDelegate` (iOS), and a background isolate
/// has no Activity — the plugin spawns a bare engine with only its own
/// receivers. So `getSoundUri` has no handler, `invokeMethod` throws, and a
/// snoozed custom sound degrades to the system tone while the soundless case
/// sounds identical. A snoozed sound is therefore best-effort by construction,
/// not by accident — see the note on [_handleSnooze].
Future<String?> _resolveSound(String path) async {
  if (!await File(path).exists()) return null;
  if (Platform.isIOS) {
    try {
      return await _soundChannel.invokeMethod<String>(
        'bundleSoundNamed',
        _fileName(path),
      );
    } on Object {
      return null;
    }
  }
  return await _androidSoundUri(path);
}

Future<String?> _androidSoundUri(String path) async {
  try {
    return await _soundChannel.invokeMethod<String>('getSoundUri', path);
  } on Object {
    return null;
  }
}

Future<String> _signature(String path) async {
  var hash = 0x811c9dc5;
  for (final byte in await File(path).readAsBytes()) {
    hash = (hash ^ byte) * 0x01000193 & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Pure helper to calculate snooze time (exactly 5 minutes from now)
/// Extracted for unit testing without platform dependencies.
DateTime snoozeDateFrom(DateTime now) => now.add(const Duration(minutes: 5));

String _fileName(String path) => path.split(RegExp(r'[/\\]')).last;
