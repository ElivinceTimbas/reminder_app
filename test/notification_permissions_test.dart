import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reminder_app/data/datasources/reminder_local_data_source.dart';
import 'package:reminder_app/data/repositories/notification_reminder_scheduler.dart';
import 'package:reminder_app/data/repositories/sqflite_reminder_repository.dart';
import 'package:reminder_app/domain/entities/reminder.dart';
import 'package:reminder_app/domain/repositories/reminder_scheduler.dart';

class _UnusedStore extends Fake implements ReminderStore {
  bool written = false;
  @override
  Future<void> write(Map<String, Object?> row, {int? sortOrder}) async {
    written = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <String>[];
  var notifications = true;
  var exact = true;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    notifications = exact = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return switch (call.method) {
            'areNotificationsEnabled' => notifications,
            'canScheduleExactNotifications' => exact,
            'openAppNotificationSettings' => true,
            _ => null,
          };
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('distinguishes notification denial and exact alarm denial', () async {
    final scheduler = NotificationReminderScheduler();
    notifications = false;
    expect(
      await scheduler.checkPermissions(),
      NotificationPermissionStatus.notificationsDenied,
    );
    notifications = true;
    exact = false;
    expect(
      await scheduler.checkPermissions(),
      NotificationPermissionStatus.exactAlarmsDenied,
    );
    exact = true;
    expect(
      await scheduler.checkPermissions(),
      NotificationPermissionStatus.allowed,
    );
  });

  test(
    'request does not open alarm settings if notifications remain denied',
    () async {
      notifications = false;
      expect(
        await NotificationReminderScheduler().requestPermissions(),
        NotificationPermissionStatus.notificationsDenied,
      );
      expect(calls, contains('requestNotificationsPermission'));
      expect(calls, isNot(contains('requestExactAlarmsPermission')));
    },
  );

  test('recovery opens the appropriate settings screen', () async {
    final scheduler = NotificationReminderScheduler();
    exact = false;
    await scheduler.openNotificationSettings();
    expect(calls, contains('requestExactAlarmsPermission'));
    calls.clear();
    notifications = false;
    await scheduler.openNotificationSettings();
    expect(calls, contains('openAppNotificationSettings'));
  });

  test('denied permission prevents persistence and cancellation of existing alerts', () async {
    notifications = false;
    final store = _UnusedStore();
    final repository = SqfliteReminderRepository(
      database: store,
      scheduler: NotificationReminderScheduler(),
    );
    await expectLater(
      repository.upsert(Reminder(id: 'r1', title: 'Water', hour: 9, minute: 0)),
      throwsA(isA<ReminderSchedulingException>()),
    );
    expect(store.written, isFalse);
    expect(calls, isNot(contains('cancel')));
  });
}
