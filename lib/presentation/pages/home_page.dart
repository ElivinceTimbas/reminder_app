import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/reminder.dart';
import '../../domain/repositories/reminder_scheduler.dart';
import '../bloc/reminder_cubit.dart';
import '../widgets/add_reminder_dialog.dart';
import '../widgets/labels.dart';

@RoutePage()
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(context.read<ReminderCubit>().refreshPermissions());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final cubit = context.read<ReminderCubit>();
      unawaited(cubit.refreshPermissions());
      unawaited(cubit.load());
    }
  }

  Future<void> _delete(Reminder reminder) async {
    final cubit = context.read<ReminderCubit>();
    final messenger = ScaffoldMessenger.of(context);
    if (!await cubit.delete(reminder.id) || !mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          persist: false,
          content: Text('Deleted “${reminder.title}”'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => cubit.add(reminder),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<ReminderCubit, ReminderState>(
      listenWhen: (previous, current) =>
          current.error != null && previous.error != current.error,
      listener: (context, state) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(state.error.toString()))),
      child: Scaffold(
        backgroundColor: theme.colorScheme.surfaceContainer,
        floatingActionButton: FloatingActionButton.extended(
          tooltip: 'Add reminder',
          onPressed: () => _openEditor(context, null),
          icon: const Icon(Icons.add),
          label: const Text('Add reminder'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: BlocBuilder<ReminderCubit, ReminderState>(
                builder: (context, state) {
                  if (state.isLoading && state.reminders.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Bea's Reminder App",
                                style: theme.textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'A little help remembering what matters.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (state.permissionStatus ==
                                      NotificationPermissionStatus
                                          .notificationsDenied ||
                                  state.permissionStatus ==
                                      NotificationPermissionStatus
                                          .exactAlarmsDenied)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: _PermissionNotice(
                                    status: state.permissionStatus,
                                  ),
                                ),
                              const SizedBox(height: 24),
                              Text(
                                'Reminders',
                                style: theme.textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (state.reminders.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(24, 24, 24, 104),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.notifications_none, size: 48),
                                SizedBox(height: 16),
                                Text(
                                  'No reminders yet',
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Tap Add reminder to plan your first one.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
                          sliver: SliverList.builder(
                            itemCount: state.reminders.length,
                            itemBuilder: (context, index) {
                              final reminder = state.reminders[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Dismissible(
                                  key: ValueKey(reminder.id),
                                  direction: DismissDirection.endToStart,
                                  movementDuration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 200),
                                  background: Container(
                                    alignment: AlignmentDirectional.centerEnd,
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.errorContainer,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Icon(
                                      Icons.delete_outline,
                                      color: theme.colorScheme.onErrorContainer,
                                    ),
                                  ),
                                  confirmDismiss: (_) async {
                                    await _delete(reminder);
                                    // State removes the row after persistence succeeds.
                                    return false;
                                  },
                                  child: _ReminderTile(
                                    reminder: reminder,
                                    onDelete: () => _delete(reminder),
                                  ),
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
        ),
      ),
    );
  }
}

Future<void> _openEditor(BuildContext context, Reminder? existing) =>
    showDialog<void>(
      context: context,
      builder: (_) => AddReminderDialog(existing: existing),
    );

class _PermissionNotice extends StatefulWidget {
  const _PermissionNotice({required this.status});
  final NotificationPermissionStatus status;

  @override
  State<_PermissionNotice> createState() => _PermissionNoticeState();
}

class _PermissionNoticeState extends State<_PermissionNotice> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ReminderCubit>();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.status == NotificationPermissionStatus.exactAlarmsDenied
                ? 'Allow precise alarms so reminders arrive on time.'
                : 'Notifications are off. Enable them to receive reminders.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy ? null : () => _run(cubit.requestPermissions),
                child: const Text('Enable alerts'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(cubit.openNotificationSettings),
                child: const Text('Open settings'),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

class _ReminderTile extends StatefulWidget {
  const _ReminderTile({required this.reminder, required this.onDelete});
  final Reminder reminder;
  final VoidCallback onDelete;

  @override
  State<_ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends State<_ReminderTile> {
  bool _toggling = false;

  Future<void> _toggle() async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      await context.read<ReminderCubit>().toggleEnabled(widget.reminder.id);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reminder = widget.reminder;
    final theme = Theme.of(context);
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay(hour: reminder.hour, minute: reminder.minute));
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openEditor(context, reminder),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      reminder.title,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  Semantics(
                    label: 'Enable ${reminder.title}',
                    child: Switch(
                      value: reminder.isEnabled,
                      onChanged: _toggling ? null : (_) => _toggle(),
                    ),
                  ),
                ],
              ),
              Text(
                reminder.isInterval ? scheduleLabel(reminder) : time,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                reminder.isInterval
                    ? (reminder.excludedWeekdays.isEmpty
                          ? 'Every day'
                          : 'Except ${weekdaySummary(reminder.excludedWeekdays)}')
                    : weekdaySummary(reminder.weekdays),
                style: theme.textTheme.bodyMedium,
              ),
              if (reminder.isInterval && reminder.quietStartMinute != null)
                Text(
                  quietHoursLabel(context, reminder),
                  style: theme.textTheme.bodyMedium,
                ),
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                child: Align(
                  key: ValueKey(reminder.isEnabled),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    nextDateLabel(context, reminder),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      reminder.soundPath == null
                          ? 'Default tone'
                          : soundLabel(reminder.soundPath!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete ${reminder.title}',
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
