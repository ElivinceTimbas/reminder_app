import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/entities/reminder.dart';
import '../../domain/entities/sound_resolution.dart';
import '../../domain/repositories/reminder_scheduler.dart';
import '../notification_actions.dart';

/// Where a custom sound ends up on each platform. Mirrors the native
/// `getSoundUri` (Android `MainActivity.kt`) and `bundleSoundNamed`
/// (iOS `AppDelegate.swift`) handlers.
const _soundChannel = MethodChannel('com.deimos.reminder_app/sounds');

/// [ReminderScheduler] on top of `flutter_local_notifications`.
///
/// Android exact alarms use [AndroidScheduleMode.exactAllowWhileIdle] plus a
/// user-granted `SCHEDULE_EXACT_ALARM`. The `USE_EXACT_ALARM` permission is NOT
/// used: Google Play restricts it to alarm-clock / calendar-class apps, and it
/// is subject to store review. `SCHEDULE_EXACT_ALARM` is a runtime-granted
/// permission, which is the right trade for a reminder app.
///
/// Custom sounds: Android plays them for real (see [_details]); iOS plays the
/// system tone. See [SoundResolution].
class NotificationReminderScheduler implements ReminderScheduler {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Resolved FileProvider URI per sound path. A URI is a pure function of the
  /// path (authority + encoded segments), so a path that resolves is asked once
  /// and never again; see [_resolve] for the ones that don't.
  final Map<String, String?> _soundUris = {};

  /// Notification ids must fit a signed 32-bit int. Derive a stable positive
  /// one from a uuid by folding its hex digits, then mix in the weekday so each
  /// day of a repeating reminder gets its own id.
  ///
  /// ponytail: 31 bits. A collision silently cross-cancels two reminders'
  /// notifications, but the birthday bound on 31 bits is ~77k reminders — fine
  /// for one person's list. Switch to a stored int column if reminders ever
  /// become shared or synced.
  static int notificationIdFor(String reminderId, [int? weekday]) {
    var hash = weekday ?? 0;
    for (final unit in reminderId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return hash == 0 ? 1 : hash;
  }

  /// Plugin + timezone bootstrap. Composition-root business, not domain: kept
  /// off [ReminderScheduler] so nothing that merely schedules a reminder has to
  /// know the plugin has to be initialised first.
  Future<void> init({
    Function(NotificationResponse)? onDidReceiveNotificationResponse,
  }) async {
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone));
    } on Object {
      // Desktop/test or an unknown zone: UTC default is a valid fallback.
    }

    // Register iOS notification categories with actions
    final darwinNotificationCategories = <DarwinNotificationCategory>[
      DarwinNotificationCategory(
        'reminder_actions',
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.plain(
            'action_stop',
            'Stop',
          ),
          DarwinNotificationAction.plain(
            'action_snooze',
            'Snooze',
          ),
        ],
      ),
    ];

    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Permissions are requested explicitly below so the prompt timing is
          // ours, not a side effect of initialize().
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
          notificationCategories: darwinNotificationCategories,
        ),
      ),
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          onDidReceiveBackgroundNotificationResponse,
    );

    await requestPermissions();
  }

  /// Android 13+ runtime notification permission + exact alarms; iOS alert /
  /// sound / badge. Safe to call repeatedly.
  Future<void> requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestFullScreenIntentPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, sound: true, badge: true);
  }

  @override
  Future<SoundResolution> soundResolution(Reminder reminder) async {
    if (reminder.soundPath == null) return SoundResolution.none;
    return await _resolve(reminder.soundPath!) == null
        ? SoundResolution.unavailable
        : SoundResolution.custom;
  }

  @override
  Future<void> schedule(Reminder reminder) async {
    await cancel(reminder.id);
    if (!reminder.isEnabled) return;

    // Resolved once: the channel id is baked into the notification, and a
    // repeating reminder schedules up to 7 copies that must all agree.
    final details = await _details(reminder);
    final body = _body(reminder, details);

    if (reminder.weekdays.isEmpty) {
      await _plugin.zonedSchedule(
        id: notificationIdFor(reminder.id),
        title: reminder.title,
        body: body,
        scheduledDate: _toZoned(reminder.nextOccurrence()),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: reminder.id,
      );
      return;
    }

    final days = reminder.weekdays.toList()..sort();
    for (final weekday in days) {
      // The native trigger must be the *next* matching instance, otherwise the
      // plugin rejects a date in the past.
      final first = reminder.nextOccurrenceOn(weekday);
      await _plugin.zonedSchedule(
        id: notificationIdFor(reminder.id, weekday),
        title: reminder.title,
        body: body,
        scheduledDate: _toZoned(first),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: reminder.id,
      );
    }
  }

  /// Cancels every id this service may have scheduled for [reminderId]: the
  /// one-shot id plus all 7 weekday ids. Sweeping all 8 — not just the current
  /// weekday set — is what stops a shrunken set from leaving orphans behind.
  /// Concurrent: they are independent channel calls.
  @override
  Future<void> cancel(String reminderId) => Future.wait([
    for (final weekday in [null, ...List.generate(7, (i) => i + 1)])
      _plugin.cancel(id: notificationIdFor(reminderId, weekday)),
  ]);

  tz.TZDateTime _toZoned(DateTime local) => tz.TZDateTime.from(local, tz.local);

  String _body(Reminder reminder, NotificationDetails details) {
    // The title is the message. Only when a sound was asked for and will not
    // play do we say so, because silence would imply the choice was applied.
    if (reminder.soundPath == null || _hasCustomSound(details)) {
      return 'Reminder';
    }
    // iOS is the honest case: `UNNotificationSound(named:)` resolves against
    // the app bundle, which is read-only and code-signed, so a sound copied
    // into Documents at runtime can never be a notification sound there.
    return Platform.isIOS
        ? 'Reminder · custom sound is not bundled on iOS'
        : 'Reminder · custom sound could not be loaded';
  }

  bool _hasCustomSound(NotificationDetails details) =>
      details.android?.sound is AndroidNotificationSound ||
      details.iOS?.sound != null;

  /// Builds the notification details, resolving [Reminder.soundPath] into
  /// something the OS will really play.
  ///
  /// Android: the sound is handed to the OS as a `FileProvider` `content://`
  /// URI (`UriAndroidNotificationSound`), which is what the audio system needs
  /// on API 24+. It is attached to a channel id derived from the *content* of
  /// the sound file, because Android freezes a channel's sound when the channel
  /// is first created and ignores a later change — so each distinct sound needs
  /// its own channel. Hashing the bytes rather than the library path matters:
  /// re-importing a different file under the same name reuses the path, and a
  /// path-hashed id would keep serving the cached sound forever.
  ///
  /// iOS: `UNNotificationSound(named:)` only resolves inside the app bundle, so
  /// we ask the app delegate whether a file of that name is bundled. If it is,
  /// it plays. If it is not, we fall back to the system tone instead of
  /// inventing a name that would silently not play.
  Future<NotificationDetails> _details(Reminder reminder) async {
    final resolved = reminder.soundPath == null
        ? null
        : await _resolve(reminder.soundPath!);
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

    // Branch per platform rather than handing the same string to both: on
    // Android `resolved` is a content:// URI, on iOS a bundle resource name.
    // Neither platform reads the other's block, but the honest value is cheap.
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

  /// The platform-specific sound name/URI for [path], or null if this platform
  /// cannot play it.
  ///
  /// Android returns a `content://` FileProvider URI; iOS returns a bundle
  /// resource name (or null — see [_details]). Both are passed straight to the
  /// plugin, which forwards them to `Uri.parse(sound)` /
  /// `UNNotificationSound soundNamed:`.
  Future<String?> _resolve(String path) async {
    if (!await File(path).exists()) return null;
    if (Platform.isIOS) {
      // Never cached: a bundle lookup is a cheap dictionary hit, and the
      // answer depends on the app build, not on the process.
      try {
        return await _soundChannel.invokeMethod<String>(
          'bundleSoundNamed',
          _fileName(path),
        );
      } on Object {
        // No AppDelegate handler (unit tests, desktop): nothing is bundled.
        return null;
      }
    }
    // Only hits are cached, and that is deliberate: a null is not proof the URI
    // stays unobtainable. The FileProvider root is an allowlist, so today it can
    // also be a stale reminder row pointing at a file the user has since deleted
    // and re-imported under a fresh name — and `_details` is where a channel is
    // built, i.e. once per new sound, so a re-ask is rare, not per schedule. If
    // that ever shows up in a profile, cache the negative with a sentinel and
    // have the sound library's delete evict the path.
    return _soundUris[path] ??= await _androidSoundUri(path);
  }

  Future<String?> _androidSoundUri(String path) async {
    try {
      return await _soundChannel.invokeMethod<String>('getSoundUri', path);
    } on Object {
      // FileProvider throws IllegalArgumentException when the path is outside
      // the configured roots; a null result falls back to the default tone.
      return null;
    }
  }

  /// 32-bit FNV-1a over the sound's bytes, as 8 hex chars. Not cryptographic:
  /// it only has to change when the content changes and be short enough to sit
  /// inside a channel id. `package:crypto` would be a new dependency for this.
  Future<String> _signature(String path) async {
    var hash = 0x811c9dc5;
    for (final byte in await File(path).readAsBytes()) {
      hash = (hash ^ byte) * 0x01000193 & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _fileName(String path) => path.split(RegExp(r'[/\\]')).last;
}
