import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/reminder.dart';
import '../../domain/repositories/reminder_scheduler.dart';
import '../../domain/usecases/add_reminder.dart';
import '../../domain/usecases/delete_reminder.dart';
import '../../domain/usecases/load_reminders.dart';
import '../../domain/usecases/toggle_reminder.dart';

class ReminderState extends Equatable {
  const ReminderState({
    this.reminders = const [],
    this.isLoading = false,
    this.error,
    this.permissionStatus = NotificationPermissionStatus.unknown,
  });

  final List<Reminder> reminders;
  final bool isLoading;
  final Object? error;
  final NotificationPermissionStatus permissionStatus;

  /// Deliberately sticky, like [Reminder.copyWith]: a null [error] means
  /// "unchanged" and [clearError] is the only way to drop it, so a successful
  /// mutation cannot silently wipe a failure the UI has not shown yet.
  ReminderState copyWith({
    List<Reminder>? reminders,
    bool? isLoading,
    Object? error,
    bool clearError = false,
    NotificationPermissionStatus? permissionStatus,
  }) {
    return ReminderState(
      reminders: reminders ?? this.reminders,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
      permissionStatus: permissionStatus ?? this.permissionStatus,
    );
  }

  @override
  List<Object?> get props => [reminders, isLoading, error, permissionStatus];
}

/// Owns the reminder list. Every mutation goes through a use case, so this
/// class never sees a database or a notification plugin — it only decides what
/// the list should look like afterwards and what to do when a call throws.
class ReminderCubit extends Cubit<ReminderState> {
  // Public fields: a private one could only be set by an initializing formal,
  // which would force callers to name the args `_load:` — illegal from another
  // library. Matching names keep the public constructor and need no
  // `prefer_initializing_formals` ignores.
  ReminderCubit({
    required this.loadReminders,
    required this.addReminder,
    required this.deleteReminder,
    required this.toggleReminder,
    this.uuid = const Uuid(),
    this.permissions,
  }) : super(const ReminderState());

  final LoadReminders loadReminders;
  final AddReminder addReminder;
  final DeleteReminder deleteReminder;
  final ToggleReminder toggleReminder;
  final Uuid uuid;
  final NotificationPermissions? permissions;

  // Undo memory: the sortOrder the last row [delete] removed was stored at, so
  // the undo SnackBar's `add` puts it back where it was instead of at the
  // bottom of the list.
  //
  // It has to be the stored value rather than the row's index in
  // state.reminders: the store pins by sortOrder, and deleting a row leaves the
  // survivors' orders untouched, so the index only equals the order while
  // nothing has been deleted from the front.
  // ponytail: one slot, keyed by id, consumed on the matching add. Ceiling: a
  // second delete before the first is undone overwrites it (pinned by a test in
  // test/use_cases_test.dart). A map keyed by id if more than one undo is ever
  // live at a time.
  String? _undoId;
  int? _undoOrder;

  /// A blank reminder with a fresh id. Use for the add dialog.
  Reminder draft({
    String title = '',
    int hour = 9,
    int minute = 0,
    Set<int> weekdays = const {},
  }) => Reminder(
    id: uuid.v4(),
    title: title,
    hour: hour,
    minute: minute,
    weekdays: weekdays,
  );

  Future<void> load({Object? initialError}) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final reminders = await loadReminders();
      if (!isClosed) {
        emit(
          state.copyWith(
            reminders: reminders,
            isLoading: false,
            error: initialError,
          ),
        );
      }
    } on Object catch (e) {
      if (!isClosed) emit(state.copyWith(isLoading: false, error: e));
    }
  }

  /// Saves a reminder. Any id is accepted, so this covers all three writes:
  /// a new draft from [draft], an edited row passed straight back in, and a row
  /// [delete] just removed — which is how the UI's undo restores the row's list
  /// position.
  ///
  /// No `sortOrder` on the edit path, and that is deliberate: the store keeps an
  /// existing row's position when the pin is null, so an edited reminder cannot
  /// jump to the bottom. The only caller that ever passes a pin is the undo.
  Future<bool> add(Reminder reminder) => _mutate(
    () => addReminder(reminder, sortOrder: _takeUndoOrder(reminder.id)),
  );

  Future<void> toggleEnabled(String id) async {
    final reminder = state.reminders.where((r) => r.id == id).firstOrNull;
    if (reminder == null) return;
    await _mutate(() => toggleReminder(reminder));
  }

  /// Removes a reminder and cancels its notifications. Reports failure on
  /// [ReminderState.error] like every other mutation, and returns whether the
  /// row is actually gone so a dismissible UI can let it spring back.
  Future<bool> delete(String id) async {
    try {
      // The store's own sortOrder, asked for in the same call as the delete:
      // this list's index for [id] is a guess, and a wrong guess puts the
      // restored row back in the wrong place.
      final order = await deleteReminder(id);
      if (isClosed) return true;
      _undoId = id;
      _undoOrder = order;
      emit(
        state.copyWith(
          reminders: state.reminders.where((r) => r.id != id).toList(),
          clearError: true,
        ),
      );
      return true;
    } on Object catch (e) {
      await _reloadAfterFailure(e);
      return false;
    }
  }

  /// Run the write (which saves AND reconciles the schedule), then refresh the
  /// list from the store.
  Future<bool> _mutate(Future<void> Function() write) async {
    try {
      await write();
      final reminders = await loadReminders();
      if (!isClosed) {
        emit(state.copyWith(reminders: reminders, clearError: true));
      }
      return true;
    } on Object catch (e) {
      await _reloadAfterFailure(e);
      return false;
    }
  }

  Future<void> _reloadAfterFailure(Object error) async {
    // A schedule failure can persist a disabled draft. Reload that truth.
    try {
      final reminders = await loadReminders();
      if (!isClosed) emit(state.copyWith(reminders: reminders, error: error));
    } on Object {
      if (!isClosed) emit(state.copyWith(error: error));
    }
    await refreshPermissions();
  }

  Future<void> refreshPermissions() async {
    if (permissions == null) return;
    try {
      final status = await permissions!.checkPermissions();
      if (!isClosed) emit(state.copyWith(permissionStatus: status));
    } on Object catch (e) {
      if (!isClosed) emit(state.copyWith(error: e));
    }
  }

  Future<void> requestPermissions() async {
    if (permissions == null) return;
    try {
      final status = await permissions!.requestPermissions();
      if (!isClosed) emit(state.copyWith(permissionStatus: status));
    } on Object catch (e) {
      if (!isClosed) emit(state.copyWith(error: e));
    }
  }

  Future<void> openNotificationSettings() async {
    try {
      await permissions?.openNotificationSettings();
      await refreshPermissions();
    } on Object catch (e) {
      if (!isClosed) emit(state.copyWith(error: e));
    }
  }

  /// The stashed position for [id], once.
  int? _takeUndoOrder(String id) {
    if (_undoId != id) return null;
    final order = _undoOrder;
    _undoId = _undoOrder = null;
    return order;
  }
}
