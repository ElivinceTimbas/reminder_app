import 'dart:io' show Platform;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/reminder.dart';
import '../bloc/reminder_cubit.dart';
import '../widgets/add_reminder_dialog.dart';
import '../widgets/labels.dart';

@RoutePage()
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<ReminderCubit, ReminderState>(
      listenWhen: (previous, current) =>
          current.error != null && previous.error != current.error,

      listener: (context, state) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Something went wrong: ${state.error}')),
        ),
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        floatingActionButton: FloatingActionButton(
          tooltip: 'Add reminder',
          onPressed: () => _openEditor(context, null),
          child: const Icon(Icons.add),
        ),

        body: SafeArea(
          child: BlocBuilder<ReminderCubit, ReminderState>(
            builder: (context, state) {
              if (state.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              final theme = Theme.of(context);
              final colorScheme = theme.colorScheme;
              final swipeBackground = Container(
                color: colorScheme.errorContainer,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                alignment: AlignmentDirectional.centerEnd,
                child: Icon(
                  Icons.delete_outline,
                  color: colorScheme.onErrorContainer,
                ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),

                    child: Text(
                      "Bea's Reminder App",
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),

                    child: Text(
                      'Reminders',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: state.reminders.isEmpty
                        ? const Center(
                            child: Text('No reminders yet. Tap + to add one.'),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                            itemCount: state.reminders.length,
                            itemBuilder: (context, index) {
                              final reminder = state.reminders[index];

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Dismissible(
                                  key: ValueKey(reminder.id),
                                  direction: DismissDirection.endToStart,

                                  background: swipeBackground,
                                  secondaryBackground: swipeBackground,

                                  confirmDismiss: (_) async {
                                    final cubit = context.read<ReminderCubit>();
                                    final messenger = ScaffoldMessenger.of(
                                      context,
                                    );

                                    if (!await cubit.delete(reminder.id)) {
                                      return false;
                                    }
                                    messenger
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Deleted "${reminder.title}"',
                                          ),
                                          action: SnackBarAction(
                                            label: 'Undo',

                                            onPressed: () =>
                                                cubit.add(reminder),
                                          ),
                                        ),
                                      );
                                    return true;
                                  },
                                  child: _ReminderTile(reminder: reminder),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

Future<void> _openEditor(BuildContext context, Reminder? existing) async {
  final cubit = context.read<ReminderCubit>();
  final result = await showDialog<Reminder>(
    context: context,
    builder: (_) => AddReminderDialog(existing: existing),
  );
  if (result == null) return;
  await cubit.add(result);
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.reminder});

  final Reminder reminder;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final sound = reminder.soundPath;

    final silentOnThisPlatform = sound != null && Platform.isIOS;

    final time = TimeOfDay(hour: reminder.hour, minute: reminder.minute);
    final subtitle = [
      localizations.formatTimeOfDay(time),
      weekdaySummary(reminder.weekdays),
      if (sound != null) soundLabel(sound),
    ].join(' · ');

    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadiusGeometry.circular(16),
        side: BorderSide(width: 1),
      ),

      title: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: reminder.isEnabled ? 1 : 0.45,
        child: Text(
          reminder.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      leading: silentOnThisPlatform
          ? Tooltip(
              message:
                  'Custom sounds do not play on iOS — the notification '
                  'will use the default tone.',
              child: Icon(
                Icons.volume_off_outlined,
                color: colorScheme.error,
              ),
            )
          : null,
      trailing: Switch(
        value: reminder.isEnabled,
        onChanged: (_) =>
            context.read<ReminderCubit>().toggleEnabled(reminder.id),
      ),
      onTap: () => _openEditor(context, reminder),
    );
  }
}
