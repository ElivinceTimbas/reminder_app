import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/repositories/reminder_repository.dart';
import '../domain/repositories/reminder_scheduler.dart';
import '../domain/repositories/sound_library.dart';
import '../domain/usecases/add_reminder.dart';
import '../domain/usecases/cancel_recording.dart';
import '../domain/usecases/delete_reminder.dart';
import '../domain/usecases/delete_sound.dart';
import '../domain/usecases/list_sounds.dart';
import '../domain/usecases/load_reminders.dart';
import '../domain/usecases/pick_sound.dart';
import '../domain/usecases/start_recording.dart';
import '../domain/usecases/stop_recording.dart';
import '../domain/usecases/toggle_reminder.dart';
import '../presentation/bloc/reminder_cubit.dart';
import 'router/routes.dart';
import 'theme/app_theme.dart';

/// The whole object graph, wired by hand in [main] and passed in here.
///
/// No DI container: the graph is three implementations, ten stateless use
/// cases, and a cubit. A locator would be more code than the wiring. What the
/// use cases get is computed once, here, so every provider hands out the same
/// instance for the life of the app.
class AppDependencies {
  AppDependencies({
    required ReminderRepository reminders,
    required this.scheduler,
    required SoundLibrary sounds,
  }) : sounds = sounds,
       loadReminders = LoadReminders(reminders),
       addReminder = AddReminder(reminders),
       deleteReminder = DeleteReminder(reminders),
       toggleReminder = ToggleReminder(reminders),
       listSounds = ListSounds(sounds),
       pickSound = PickSound(sounds),
       deleteSound = DeleteSound(sounds),
       startRecording = StartRecording(sounds),
       stopRecording = StopRecording(sounds),
       cancelRecording = CancelRecording(sounds);

  /// Exposed as the domain interface, not just wrapped in use cases, because
  /// the dialog asks the library a question (`hasPermission`) rather than
  /// asking it to do something.
  final SoundLibrary sounds;

  /// Provided for the same reason: the dialog asks the scheduler a question
  /// (`soundResolution`). See the note on that read in `add_reminder_dialog`.
  final ReminderScheduler scheduler;

  final LoadReminders loadReminders;
  final AddReminder addReminder;
  final DeleteReminder deleteReminder;
  final ToggleReminder toggleReminder;
  final ListSounds listSounds;
  final PickSound pickSound;
  final DeleteSound deleteSound;
  final StartRecording startRecording;
  final StopRecording stopRecording;
  final CancelRecording cancelRecording;
}

class App extends StatelessWidget {
  const App({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    final d = dependencies;
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SoundLibrary>.value(value: d.sounds),
        RepositoryProvider<ListSounds>.value(value: d.listSounds),
        RepositoryProvider<PickSound>.value(value: d.pickSound),
        RepositoryProvider<DeleteSound>.value(value: d.deleteSound),
        RepositoryProvider<StartRecording>.value(value: d.startRecording),
        RepositoryProvider<StopRecording>.value(value: d.stopRecording),
        RepositoryProvider<CancelRecording>.value(value: d.cancelRecording),
        RepositoryProvider<ReminderScheduler>.value(value: d.scheduler),
      ],
      child: BlocProvider(
        create: (_) => ReminderCubit(
          loadReminders: d.loadReminders,
          addReminder: d.addReminder,
          deleteReminder: d.deleteReminder,
          toggleReminder: d.toggleReminder,
        )..load(),
        child: MaterialApp.router(
          routerConfig: appRouter.config(),
          theme: AppTheme.light,
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
