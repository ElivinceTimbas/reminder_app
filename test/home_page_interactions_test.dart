import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reminder_app/app/app.dart';
import 'package:reminder_app/app/theme/app_theme.dart';
import 'package:reminder_app/domain/entities/library_sound.dart';
import 'package:reminder_app/domain/entities/reminder.dart';
import 'package:reminder_app/domain/entities/sound_resolution.dart';
import 'package:reminder_app/domain/repositories/reminder_repository.dart';
import 'package:reminder_app/domain/repositories/reminder_scheduler.dart';
import 'package:reminder_app/domain/repositories/sound_library.dart';
import 'package:reminder_app/domain/usecases/cancel_recording.dart';
import 'package:reminder_app/domain/usecases/delete_sound.dart';
import 'package:reminder_app/domain/usecases/list_sounds.dart';
import 'package:reminder_app/domain/usecases/pick_sound.dart';
import 'package:reminder_app/domain/usecases/start_recording.dart';
import 'package:reminder_app/domain/usecases/stop_recording.dart';
import 'package:reminder_app/presentation/bloc/reminder_cubit.dart';
import 'package:reminder_app/presentation/pages/home_page.dart';
import 'package:reminder_app/presentation/widgets/add_reminder_dialog.dart';

class _MemoryReminders implements ReminderRepository {
  final rows = <Reminder>[];
  bool failWrites = false;
  bool failDeletes = false;

  @override
  Future<List<Reminder>> getAll() async => List.of(rows);

  @override
  Future<void> upsert(Reminder reminder, {int? sortOrder}) async {
    if (failWrites) {
      throw const ReminderSchedulingException('Could not save. Try again.');
    }
    final index = rows.indexWhere((row) => row.id == reminder.id);
    if (index >= 0) {
      rows[index] = reminder;
    } else {
      rows.insert((sortOrder ?? rows.length).clamp(0, rows.length), reminder);
    }
  }

  @override
  Future<int?> delete(String id) async {
    if (failDeletes) {
      throw const ReminderSchedulingException('Could not delete. Try again.');
    }
    final index = rows.indexWhere((row) => row.id == id);
    if (index < 0) return null;
    rows.removeAt(index);
    return index;
  }
}

class _Scheduler extends Fake
    implements ReminderScheduler, NotificationPermissions {
  NotificationPermissionStatus status = NotificationPermissionStatus.allowed;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<SoundResolution> soundResolution(Reminder reminder) async =>
      SoundResolution.none;

  @override
  Future<NotificationPermissionStatus> checkPermissions() async => status;

  @override
  Future<NotificationPermissionStatus> requestPermissions() async {
    requests++;
    return status = NotificationPermissionStatus.allowed;
  }

  @override
  Future<void> openNotificationSettings() async {
    settingsOpened++;
  }
}

class _Sounds extends Fake implements SoundLibrary {
  @override
  Future<List<LibrarySound>> listSounds() async => [];

  @override
  Future<void> stopPreview() async {}
}

class _PendingPreviewSounds extends _Sounds {
  final firstStop = Completer<void>();
  int stops = 0;
  final previews = <String>[];

  @override
  Future<List<LibrarySound>> listSounds() async => const [
    LibrarySound(name: 'recording.wav', path: '/recording.wav', sizeBytes: 100),
  ];

  @override
  Future<void> stopPreview() async {
    if (++stops == 1) await firstStop.future;
  }

  @override
  Future<void> preview(String path) async => previews.add(path);

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<String?> startRecording() async => '/new-recording.wav';

  @override
  Future<void> cancelRecording() async {}
}

Reminder _reminder(String id, String title) =>
    Reminder(id: id, title: title, hour: 9, minute: 15);

Future<void> _pumpHome(
  WidgetTester tester,
  _MemoryReminders repository, {
  _Scheduler? scheduler,
  SoundLibrary? sounds,
}) async {
  final notifications = scheduler ?? _Scheduler();
  final d = AppDependencies(
    reminders: repository,
    scheduler: notifications,
    sounds: sounds ?? _Sounds(),
  );
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SoundLibrary>.value(value: d.sounds),
        RepositoryProvider<ReminderScheduler>.value(value: notifications),
        RepositoryProvider<ListSounds>.value(value: d.listSounds),
        RepositoryProvider<PickSound>.value(value: d.pickSound),
        RepositoryProvider<DeleteSound>.value(value: d.deleteSound),
        RepositoryProvider<StartRecording>.value(value: d.startRecording),
        RepositoryProvider<StopRecording>.value(value: d.stopRecording),
        RepositoryProvider<CancelRecording>.value(value: d.cancelRecording),
      ],
      child: BlocProvider(
        create: (_) => ReminderCubit(
          loadReminders: d.loadReminders,
          addReminder: d.addReminder,
          deleteReminder: d.deleteReminder,
          toggleReminder: d.toggleReminder,
          permissions: notifications,
        )..load(),
        child: MaterialApp(theme: AppTheme.light, home: const HomePage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _screen(WidgetTester tester, Size size, {double scale = 1}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  testWidgets('pending preview cannot start after recording begins', (
    tester,
  ) async {
    _screen(tester, const Size(800, 1400));
    final sounds = _PendingPreviewSounds();
    final repository = _MemoryReminders()
      ..rows.add(
        Reminder(
          id: 'recorded',
          title: 'Recorded reminder',
          hour: 9,
          minute: 0,
          soundPath: '/recording.wav',
        ),
      );
    await _pumpHome(tester, repository, sounds: sounds);
    await tester.tap(find.text('Recorded reminder'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Preview sound'));
    await tester.tap(find.byTooltip('Preview sound'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Record'));
    await tester.pumpAndSettle();
    expect(find.text('Stop recording'), findsOneWidget);
    sounds.firstStop.complete();
    await tester.pumpAndSettle();
    expect(sounds.previews, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('create, edit and toggle a reminder through the main page', (
    tester,
  ) async {
    final repository = _MemoryReminders();
    await _pumpHome(tester, repository);
    expect(find.text('No reminders yet'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Water the plants');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AddReminderDialog), findsNothing);
    expect(repository.rows.single.title, 'Water the plants');
    final originalId = repository.rows.single.id;
    await tester.tap(find.text('Water the plants'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Water the balcony plants');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(repository.rows.single.id, originalId);
    expect(find.text('Water the balcony plants'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(repository.rows.single.isEnabled, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('failed save preserves entered title and allows retry', (
    tester,
  ) async {
    final repository = _MemoryReminders()..failWrites = true;
    await _pumpHome(tester, repository);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Keep this draft');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AddReminderDialog), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep this draft',
    );
    expect(repository.rows, isEmpty);
    expect(find.text('Could not save. Try again.'), findsWidgets);
    repository.failWrites = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AddReminderDialog), findsNothing);
    expect(repository.rows.single.title, 'Keep this draft');
  });

  for (final swipe in [false, true]) {
    testWidgets(
      '${swipe ? 'swipe' : 'button'} delete and Undo restore a reminder',
      (tester) async {
        final repository = _MemoryReminders()
          ..rows.add(_reminder('one', 'Water plants'));
        await _pumpHome(tester, repository);
        if (swipe) {
          await tester.drag(find.byType(Dismissible), const Offset(-700, 0));
        } else {
          await tester.tap(find.byTooltip('Delete Water plants'));
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        expect(repository.rows, isEmpty);
        expect(find.byKey(const ValueKey('one')), findsNothing);
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(repository.rows.single.id, 'one');
        expect(find.text('Water plants'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('delete toast counts down across its top edge for four seconds', (
    tester,
  ) async {
    final repository = _MemoryReminders()
      ..rows.add(_reminder('one', 'Water plants'));
    await _pumpHome(tester, repository);
    await tester.tap(find.byTooltip('Delete Water plants'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    final toast = find.byType(SnackBar);
    final progress = find.byType(LinearProgressIndicator);
    double remaining() => tester.widget<LinearProgressIndicator>(progress).value!;
    expect(tester.widget<SnackBar>(toast).duration, const Duration(seconds: 4));
    expect(remaining(), closeTo(1, 0.001));
    final surface = tester.getRect(
      find.descendant(of: toast, matching: find.byType(Material)).first,
    );
    final bar = tester.getRect(progress);
    expect(bar.left, closeTo(surface.left, 0.01));
    expect(bar.right, closeTo(surface.right, 0.01));
    expect(bar.top, closeTo(surface.top, 0.01));

    await tester.pump(const Duration(seconds: 2));
    expect(remaining(), closeTo(0.5, 0.01));
    await tester.pump(const Duration(milliseconds: 1900));
    expect(remaining(), closeTo(0.025, 0.01));
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    expect(toast, findsNothing);
    expect(progress, findsNothing);
    expect(repository.rows, isEmpty);
  });

  testWidgets('a second deletion resets the countdown and Undo restores it', (
    tester,
  ) async {
    final repository = _MemoryReminders()
      ..rows.addAll([
        _reminder('one', 'Water plants'),
        _reminder('two', 'Take vitamins'),
      ]);
    await _pumpHome(tester, repository);
    await tester.tap(find.byTooltip('Delete Water plants'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(0.5, 0.01),
    );

    await tester.tap(find.byTooltip('Delete Take vitamins'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Deleted “Water plants”'), findsNothing);
    expect(find.text('Deleted “Take vitamins”'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(1, 0.001),
    );
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(repository.rows.single.id, 'two');
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps the full four-second Undo window', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final repository = _MemoryReminders()
      ..rows.add(_reminder('one', 'Water plants'));
    await _pumpHome(tester, repository);
    await tester.tap(find.byTooltip('Delete Water plants'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    final progress = find.byType(LinearProgressIndicator);
    expect(tester.widget<LinearProgressIndicator>(progress).value, 1);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<LinearProgressIndicator>(progress).value, 1);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(
      tester.widget<LinearProgressIndicator>(progress).value,
      closeTo(0.5, 0.01),
    );
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed swipe delete keeps the reminder and shows recovery text',
    (tester) async {
      final repository = _MemoryReminders()
        ..rows.add(_reminder('one', 'Water plants'))
        ..failDeletes = true;
      await _pumpHome(tester, repository);
      await tester.drag(find.byType(Dismissible), const Offset(-700, 0));
      await tester.pumpAndSettle();
      expect(repository.rows, hasLength(1));
      expect(find.text('Water plants'), findsOneWidget);
      expect(find.text('Could not delete. Try again.'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
    },
  );

  testWidgets('permission banner enables alerts and clears after success', (
    tester,
  ) async {
    final scheduler = _Scheduler()
      ..status = NotificationPermissionStatus.notificationsDenied;
    await _pumpHome(tester, _MemoryReminders(), scheduler: scheduler);
    expect(
      find.text('Notifications are off. Enable them to receive reminders.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Enable alerts'));
    await tester.pumpAndSettle();
    expect(scheduler.requests, 1);
    expect(find.text('Enable alerts'), findsNothing);
  });

  testWidgets(
    'returning from settings refreshes permissions and background changes',
    (tester) async {
      final scheduler = _Scheduler()
        ..status = NotificationPermissionStatus.exactAlarmsDenied;
      final repository = _MemoryReminders()
        ..rows.add(_reminder('one', 'Water plants'));
      await _pumpHome(tester, repository, scheduler: scheduler);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(scheduler.settingsOpened, 1);
      scheduler.status = NotificationPermissionStatus.allowed;
      repository.rows[0] = repository.rows[0].copyWith(isEnabled: false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Open settings'), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    },
  );

  for (final size in [const Size(320, 640), const Size(1024, 768)]) {
    testWidgets('main page at $size and 2x text remains scrollable and usable', (
      tester,
    ) async {
      _screen(tester, size, scale: 2);
      final repository = _MemoryReminders()
        ..rows.add(
          _reminder(
            'one',
            'A long reminder title that should wrap without losing its meaning',
          ),
        );
      final scheduler = _Scheduler()
        ..status = NotificationPermissionStatus.notificationsDenied;
      await _pumpHome(tester, repository, scheduler: scheduler);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.byType(Switch), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(repository.rows.single.isEnabled, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
