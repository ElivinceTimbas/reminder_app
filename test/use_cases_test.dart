import 'package:flutter_test/flutter_test.dart';
import 'package:reminder_app/data/datasources/reminder_local_data_source.dart';
import 'package:reminder_app/data/models/reminder_row.dart';
import 'package:reminder_app/data/repositories/sqflite_reminder_repository.dart';
import 'package:reminder_app/domain/entities/reminder.dart';
import 'package:reminder_app/domain/entities/sound_resolution.dart';
import 'package:reminder_app/domain/repositories/reminder_scheduler.dart';
import 'package:reminder_app/domain/usecases/add_reminder.dart';
import 'package:reminder_app/domain/usecases/delete_reminder.dart';
import 'package:reminder_app/domain/usecases/load_reminders.dart';
import 'package:reminder_app/domain/usecases/toggle_reminder.dart';
import 'package:reminder_app/presentation/bloc/reminder_cubit.dart';

/// Records the order of the two stores, which is the whole point: a reminder
/// row and its notifications are one fact and the row has to land first.
///
/// [seeded] starts it with existing rows as `id -> stored sortOrder`, so a test
/// can begin from a list whose stored orders carry the gaps earlier deletions
/// left behind. [rows] and [_orders] are the fake's `sortOrder` column: [readAll]
/// sorts by it and [delete] hands it back, so the ordering rules under test are
/// the real ones, gaps and all.
class _FakeStore implements ReminderStore {
  _FakeStore([Map<String, int>? seeded, List<String>? callLog])
    : calls = callLog ?? [] {
    for (final entry in (seeded ?? const <String, int>{}).entries) {
      rows.add(ReminderRow.toRow(_reminder(id: entry.key, title: entry.key)));
      _orders[entry.key] = entry.value;
    }
  }

  final List<String> calls;
  final List<Map<String, Object?>> rows = [];
  final List<int?> orders = [];
  final Map<String, int> _orders = {};

  /// Flipped by the failure test; there is no sqflite to make fail for real.
  bool failWrites = false;
  bool failDelete = false;

  @override
  Future<List<Map<String, Object?>>> readAll() async {
    calls.add('readAll');
    return [...rows]..sort((a, b) => _order(a).compareTo(_order(b)));
  }

  int _order(Map<String, Object?> row) => _orders[row['id']! as String]!;

  @override
  Future<void> write(Map<String, Object?> row, {int? sortOrder}) async {
    calls.add('write');
    if (failWrites) throw StateError('disk full');
    final id = row['id']! as String;
    rows
      ..removeWhere((r) => r['id'] == id)
      ..add(row);
    // The one INSERT's COALESCE, in Dart: the pin, else the row's current
    // order, else the end of the list.
    _orders[id] =
        sortOrder ??
        _orders[id] ??
        _orders.values.fold(-1, (a, b) => a > b ? a : b) + 1;
    orders.add(sortOrder);
  }

  @override
  Future<int?> delete(String id) async {
    calls.add('delete');
    if (failDelete) throw StateError('delete failed');
    rows.removeWhere((r) => r['id'] == id);
    return _orders.remove(id);
  }
}

class _FakeScheduler implements ReminderScheduler {
  _FakeScheduler(this.calls);

  final List<String> calls;

  bool failSchedule = false;
  bool failCancel = false;

  @override
  Future<void> schedule(Reminder reminder) async {
    calls.add('schedule');
    if (failSchedule) throw StateError('schedule failed');
  }

  @override
  Future<void> cancel(String reminderId) async {
    calls.add('cancel');
    if (failCancel) throw StateError('cancel failed');
  }

  @override
  Future<SoundResolution> soundResolution(Reminder reminder) async =>
      SoundResolution.none;
}

Reminder _reminder({String id = 'r1', String title = 'Water plants'}) =>
    Reminder(id: id, title: title, hour: 9, minute: 0);

class _DeniedScheduler extends _FakeScheduler
    implements NotificationPermissions {
  _DeniedScheduler(super.calls);

  @override
  Future<NotificationPermissionStatus> checkPermissions() async =>
      NotificationPermissionStatus.notificationsDenied;
  @override
  Future<NotificationPermissionStatus> requestPermissions() =>
      checkPermissions();
  @override
  Future<void> openNotificationSettings() async {}
}

void main() {
  test(
    'failed deletion pauses the row when permissions prevent restoring alerts',
    () async {
      final store = _FakeStore({'r1': 0})..failDelete = true;
      final repository = SqfliteReminderRepository(
        database: store,
        scheduler: _DeniedScheduler([]),
      );
      await expectLater(
        repository.delete('r1'),
        throwsA(isA<ReminderSchedulingException>()),
      );
      expect((await repository.getAll()).single.isEnabled, isFalse);
    },
  );
  // The write-then-schedule invariant and the undo sortOrder pin are the only
  // two pieces of logic here that are not a straight pass-through, so they are
  // the only two worth a test.
  group('SqfliteReminderRepository keeps the row and the schedule in step', () {
    test(
      'upsert writes the row before it schedules the notification',
      () async {
        final calls = <String>[];
        final store = _FakeStore(null, calls);
        final repository = SqfliteReminderRepository(
          database: store,
          scheduler: _FakeScheduler(calls),
        );

        await repository.upsert(_reminder());

        expect(
          calls,
          ['write', 'schedule'],
          reason:
              'reversed, a crash between the two leaves a notification for a '
              'row that does not exist',
        );
      },
    );

    test(
      'delete cancels notifications before removing the row',
      () async {
        final calls = <String>[];
        final store = _FakeStore(null, calls);
        final repository = SqfliteReminderRepository(
          database: store,
          scheduler: _FakeScheduler(calls),
        );

        await repository.delete('r1');

        expect(calls, ['readAll', 'cancel', 'delete']);
      },
    );

    // Was three writers (add / update / toggle). `UpdateReminder` went away as a
    // strict subset of `AddReminder(…, sortOrder: null)`, so the set is two —
    // but the assertion is unchanged and still the point: every writer in the
    // app funnels through this one path and none of them can skip the half it
    // did not implement.
    test('both writers share that one path', () async {
      final calls = <String>[];
      final store = _FakeStore(null, calls);
      final repository = SqfliteReminderRepository(
        database: store,
        scheduler: _FakeScheduler(calls),
      );
      final add = AddReminder(repository);
      final toggle = ToggleReminder(repository);

      await add(_reminder(id: 'a'));
      await toggle(_reminder(id: 'b'));

      // Two writes, two schedules, in that interleaved order.
      expect(
        calls,
        [
          'write',
          'schedule',
          'write',
          'schedule',
        ],
      );
    });

    test(
      'toggle flips isEnabled rather than saving the row unchanged',
      () async {
        final store = _FakeStore();
        final repository = SqfliteReminderRepository(
          database: store,
          scheduler: _FakeScheduler(<String>[]),
        );

        await ToggleReminder(repository)(_reminder());

        expect((await repository.getAll()).single.isEnabled, isFalse);
      },
    );

    test(
      'failed scheduling cancels partial alerts and persists a disabled draft',
      () async {
        final calls = <String>[];
        final store = _FakeStore(null, calls);
        final scheduler = _FakeScheduler(calls)..failSchedule = true;
        final repository = SqfliteReminderRepository(
          database: store,
          scheduler: scheduler,
        );
        await expectLater(
          repository.upsert(_reminder()),
          throwsA(isA<ReminderSchedulingException>()),
        );
        expect(calls, ['write', 'schedule', 'cancel', 'write']);
        expect((await repository.getAll()).single.isEnabled, isFalse);
      },
    );

    test('failed cleanup reports that old alerts may still fire', () async {
      final store = _FakeStore();
      final scheduler = _FakeScheduler([])
        ..failSchedule = true
        ..failCancel = true;
      final repository = SqfliteReminderRepository(
        database: store,
        scheduler: scheduler,
      );
      await expectLater(
        repository.upsert(_reminder()),
        throwsA(
          isA<ReminderSchedulingException>().having(
            (e) => e.message,
            'message',
            contains('may still fire'),
          ),
        ),
      );
      expect((await repository.getAll()).single.isEnabled, isFalse);
    });

    test('failed cancellation retains the row for deletion retry', () async {
      final store = _FakeStore({'r1': 0});
      final scheduler = _FakeScheduler([])..failCancel = true;
      final repository = SqfliteReminderRepository(
        database: store,
        scheduler: scheduler,
      );
      await expectLater(repository.delete('r1'), throwsStateError);
      expect((await repository.getAll()).single.id, 'r1');
    });

    test('cubit reloads disabled persisted draft and returns false after scheduling failure', () async {
      final store = _FakeStore();
      final scheduler = _FakeScheduler([])..failSchedule = true;
      final repository = SqfliteReminderRepository(
        database: store,
        scheduler: scheduler,
      );
      final cubit = ReminderCubit(
        loadReminders: LoadReminders(repository),
        addReminder: AddReminder(repository),
        deleteReminder: DeleteReminder(repository),
        toggleReminder: ToggleReminder(repository),
      );
      addTearDown(cubit.close);
      expect(await cubit.add(_reminder()), isFalse);
      expect(cubit.state.reminders.single.isEnabled, isFalse);
      expect(cubit.state.error, isA<ReminderSchedulingException>());
    });

    test('failed database deletion restores the previous schedule', () async {
      final calls = <String>[];
      final store = _FakeStore({'r1': 0}, calls)..failDelete = true;
      final repository = SqfliteReminderRepository(
        database: store,
        scheduler: _FakeScheduler(calls),
      );
      await expectLater(repository.delete('r1'), throwsStateError);
      expect(calls, ['readAll', 'cancel', 'delete', 'write', 'schedule']);
      expect((await repository.getAll()).single.isEnabled, isTrue);
    });

    test('getAll maps rows back to entities', () async {
      final store = _FakeStore();
      final repository = SqfliteReminderRepository(
        database: store,
        scheduler: _FakeScheduler(<String>[]),
      );

      await AddReminder(repository)(
        _reminder().copyWith(weekdays: {1, 5}, soundPath: '/sounds/beep.mp3'),
      );

      final loaded = await LoadReminders(repository)();
      expect(loaded, hasLength(1));
      expect(loaded.single.weekdays, {1, 5});
      expect(loaded.single.soundPath, '/sounds/beep.mp3');
      expect(loaded.single.title, 'Water plants');
    });
  });

  group('ReminderCubit undo memory', () {
    /// The cubit over fakes — which is only possible now that it takes use
    /// cases. It needs no binding, no sqflite and no notification plugin.
    ({ReminderCubit cubit, _FakeStore store, List<String> scheduled}) build({
      Map<String, int>? seeded,
    }) {
      final store = _FakeStore(seeded);
      final scheduled = <String>[];
      final repository = SqfliteReminderRepository(
        database: store,
        scheduler: _FakeScheduler(scheduled),
      );
      return (
        cubit: ReminderCubit(
          loadReminders: LoadReminders(repository),
          addReminder: AddReminder(repository),
          deleteReminder: DeleteReminder(repository),
          toggleReminder: ToggleReminder(repository),
        ),
        store: store,
        scheduled: scheduled,
      );
    }

    test('an undone delete is re-inserted at the position it left', () async {
      final h = build();
      for (final id in ['a', 'b', 'c']) {
        await h.cubit.add(_reminder(id: id, title: id));
      }
      expect(h.cubit.state.reminders.map((r) => r.id), ['a', 'b', 'c']);
      h.store.orders.clear();

      expect(await h.cubit.delete('b'), isTrue);
      expect(h.cubit.state.reminders.map((r) => r.id), ['a', 'c']);

      // The SnackBar's Undo re-adds the row it was handed, not the one the
      // list happens to be showing. The stashed sortOrder is what puts it back
      // between 'a' and 'c' instead of at the bottom. Nothing was deleted from
      // the front here, so the stored order (1) and the deleted index (1) agree
      // — this is the case that was never broken, and it is why the gap below
      // needs its own test.
      await h.cubit.add(_reminder(id: 'b', title: 'b'));

      expect(h.store.orders, [
        1,
      ], reason: 'the pin is the deleted row\'s order');
      expect(h.cubit.state.reminders.map((r) => r.id), ['a', 'b', 'c']);
    });

    test(
      'the pin is the stored sortOrder, not the index the row had in the list',
      () async {
        // The reported reproduction, against the real ordering rules: A and B
        // were deleted earlier and never undone, so the list reads C,D,E,F at
        // indices 0..3 while the stored orders are 2,3,4,5. D's index (1) is
        // not D's order (3), and reusing 1 drops the restored row to the top.
        final h = build(seeded: {'C': 2, 'D': 3, 'E': 4, 'F': 5});
        await h.cubit.load();
        expect(h.cubit.state.reminders.map((r) => r.id), ['C', 'D', 'E', 'F']);
        h.store.orders.clear();

        expect(await h.cubit.delete('D'), isTrue);
        expect(h.cubit.state.reminders.map((r) => r.id), ['C', 'E', 'F']);

        await h.cubit.add(_reminder(id: 'D', title: 'D'));

        expect(
          h.store.orders,
          [3],
          reason: 'the pin is the stored sortOrder, not the index 1',
        );
        expect(
          h.cubit.state.reminders.map((r) => r.id),
          ['C', 'D', 'E', 'F'],
          reason: 'D goes back to where it was, not to the top',
        );
      },
    );

    test('a second delete before the first undo overwrites the one slot', () async {
      final h = build();
      for (final id in ['a', 'b', 'c']) {
        await h.cubit.add(_reminder(id: id, title: id));
      }

      await h.cubit.delete('a');
      await h.cubit.delete('b');
      h.store.orders.clear();

      // 'b' is the remembered row now, so undoing 'a' finds no pin and the store
      // puts it at the end. That is the documented ceiling (see the
      // `// ponytail:` note on the undo memory), asserted here so lifting it is
      // a deliberate edit of this test rather than a silent behaviour change.
      await h.cubit.add(_reminder(id: 'a', title: 'a'));

      expect(h.store.orders, [null], reason: 'the slot now belongs to b');
      expect(h.cubit.state.reminders.map((r) => r.id), ['c', 'a']);

      // 'b' is still undoable, and that one is right.
      await h.cubit.add(_reminder(id: 'b', title: 'b'));
      expect(h.store.orders, [null, 1]);
      expect(h.cubit.state.reminders.map((r) => r.id), ['b', 'c', 'a']);
    });

    test('the stashed position is used once, not on every later add', () async {
      final h = build();
      await h.cubit.add(_reminder(id: 'a', title: 'a'));
      await h.cubit.add(_reminder(id: 'b', title: 'b'));
      await h.cubit.delete('a');
      h.store.orders.clear();

      await h.cubit.add(_reminder(id: 'a', title: 'a'));
      expect(h.store.orders, [0]);

      await h.cubit.add(_reminder(id: 'z', title: 'z'));
      expect(h.store.orders, [0, null], reason: 'the undo slot is consumed');
    });

    test(
      'a failed write surfaces on error and leaves the error sticky',
      () async {
        final h = build();
        await h.cubit.add(_reminder(id: 'a', title: 'a'));
        h.store.failWrites = true;

        // `cubit.add` is the edit path now too: the write throws before the undo
        // slot is consulted, so this still exercises exactly the same
        // failure branch `_mutate` has always had.
        await h.cubit.add(_reminder(id: 'a', title: 'renamed'));

        expect(h.cubit.state.error, isStateError);
        expect(h.cubit.state.reminders.single.title, 'a');
      },
    );
  });
}
