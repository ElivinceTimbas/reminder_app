import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'datasources/reminder_local_data_source.dart';
import 'ios_notification_sound.dart';
import 'models/reminder_row.dart';
import '../domain/entities/reminder.dart';
import '../domain/repositories/reminder_scheduler.dart';
import 'repositories/notification_reminder_scheduler.dart';

const _soundChannel = MethodChannel('com.deimos.reminder_app/sounds');

/// Action IDs for notification buttons
const actionStop = 'action_stop';
const actionSnooze = 'action_snooze';

/// Shared logic to handle notification actions. Called from both
/// foreground and background callbacks.
Future<void> handleNotificationAction(
  NotificationResponse response, {
  Future<ReminderLocalDataSource> Function({bool singleInstance})? openDatabase,
}) async {
  final actionId = response.actionId;
  final reminderId = response.payload;
  final dismissed =
      response.notificationResponseType ==
      NotificationResponseType.notificationDismissed;
  if (reminderId == null ||
      (!dismissed && actionId != actionStop && actionId != actionSnooze)) {
    return;
  }

  // Initialize timezone in this isolate (background isolates need this)
  tzdata.initializeTimeZones();
  try {
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone));
  } on Object {
    // Fallback to UTC if timezone can't be determined
  }

  // Always own this connection, even when invoked on the foreground isolate.
  final database = await (openDatabase ?? ReminderLocalDataSource.open)(
    singleInstance: false,
  );

  try {
    // If the notification was dismissed (not tapped with an action), treat it
    // as "Stop" for one-shot reminders: the fired occurrence is done.
    if (actionId == actionStop || dismissed) {
      await _handleStop(reminderId, database, dismissed: dismissed);
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
  ReminderLocalDataSource database, {
  required bool dismissed,
}) async {
  // Read all rows, find the one with this id
  final rows = await database.readAll();
  final target = rows.where((r) => r['id'] == reminderId).toList();
  if (target.isEmpty) return;

  final reminder = ReminderRow.fromRow(target.first);
  if (dismissed && (reminder.isInterval || reminder.weekdays.isNotEmpty)) {
    return;
  }
  // Stop = disable the reminder. A one-shot reminder becomes a disabled
  // one-shot (never to fire again), a repeating reminder is fully disabled.
  final disabledReminder = reminder.copyWith(isEnabled: false);
  await database.write(ReminderRow.toRow(disabledReminder), sortOrder: null);

  await NotificationReminderScheduler().cancel(reminderId);
}

Future<void> _handleSnooze(
  String reminderId,
  ReminderLocalDataSource database,
) async {
  final rows = await database.readAll();
  final target = rows.where((r) => r['id'] == reminderId).toList();
  if (target.isEmpty) return;

  final reminder = ReminderRow.fromRow(target.first);

  if (!reminder.isEnabled) return;

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
  if (reminder.isInterval &&
      (reminder.excludedWeekdays.contains(snoozeTime.weekday) ||
          reminder.isQuietMinute(snoozeTime.hour * 60 + snoozeTime.minute))) {
    // The next allowed recurring alert is already armed.
    return;
  }
  final snoozeZoned = tz.TZDateTime.from(snoozeTime, tz.local);

  final plugin = FlutterLocalNotificationsPlugin();
  final pending = await plugin.pendingNotificationRequests();
  if (pending.length >= (Platform.isIOS ? 64 : 500) &&
      !pending.any((item) => item.id == snoozeId)) {
    throw const ReminderSchedulingException(
      'No room to snooze. Existing reminders remain scheduled.',
    );
  }

  final details = await _buildSnoozeDetails(reminder);

  await plugin.zonedSchedule(
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
  return 'Reminder · custom sound could not be loaded';
}

bool _hasCustomSound(NotificationDetails details) =>
    details.android?.sound is AndroidNotificationSound ||
    details.iOS?.sound != null;

/// iOS uses Library/Sounds; Android background actions use the default tone
/// when the foreground FileProvider channel is unavailable.
Future<String?> _resolveSound(String path) async {
  if (!await File(path).exists()) return null;
  if (Platform.isIOS) return iosNotificationSoundName(path);
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
