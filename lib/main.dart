import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'data/datasources/reminder_local_data_source.dart';
import 'data/notification_actions.dart';
import 'data/repositories/file_system_sound_library.dart';
import 'data/repositories/notification_reminder_scheduler.dart';
import 'data/repositories/sqflite_reminder_repository.dart';

/// The composition root: the only place that knows a concrete implementation
/// exists. Everything below it is wired by type, not by name.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['Sour Gummy'],
      await rootBundle.loadString('assets/fonts/OFL.txt'),
    );
  });

  final scheduler = NotificationReminderScheduler();
  await scheduler.init(
    onDidReceiveNotificationResponse: handleNotificationAction,
  );

  final database = await ReminderLocalDataSource.open();

  runApp(
    App(
      dependencies: AppDependencies(
        reminders: SqfliteReminderRepository(
          database: database,
          scheduler: scheduler,
        ),
        scheduler: scheduler,
        sounds: FileSystemSoundLibrary(),
      ),
    ),
  );
}
