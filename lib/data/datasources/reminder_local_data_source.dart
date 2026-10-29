import 'package:sqflite/sqflite.dart';

/// Row-level persistence for reminders: the contract
/// [SqfliteReminderRepository] is written against.
///
/// Declared beside its only implementation rather than as a folder of its own
/// — the point is that the repository does not depend on SQL, and the point of
/// the interface is testable. It is not a domain contract, so it stays in data.
abstract class ReminderStore {
  /// All rows in stable list order.
  Future<List<Map<String, Object?>>> readAll();

  /// Insert or replace by primary key. [sortOrder] pins the list position, or
  /// is null to let the store keep the row's current position.
  Future<void> write(Map<String, Object?> row, {int? sortOrder});

  /// Completes only the same enabled Once schedule that was inspected.
  Future<bool> completeOnce(String id, int scheduleVersion);

  /// Re-enables a snoozed Once schedule unless it was edited or paused.
  Future<bool> reactivateOnce(String id, int scheduleVersion);

  /// Removes the row and returns the `sortOrder` it held, or null if there was
  /// no such row.
  Future<int?> delete(String id);
}

/// The sqflite side of the reminder store: schema, SQL, and nothing else.
///
/// It speaks rows, not `Reminder`s — that translation is `ReminderRow`'s job —
/// so the SQL here never has to know what a reminder is.
class ReminderLocalDataSource implements ReminderStore {
  ReminderLocalDataSource._(this._db);

  final Database _db;

  static const _fileName = 'reminder_app.db';
  static const _table = 'reminders';

  /// Interval fields are nullable so existing reminders retain their schedule.
  static Future<ReminderLocalDataSource> open({
    String? path,
    bool singleInstance = true,
  }) async {
    final db = await openDatabase(
      path ?? '${await getDatabasesPath()}/$_fileName',
      version: 3,
      singleInstance: singleInstance,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            hour INTEGER NOT NULL,
            minute INTEGER NOT NULL,
            weekdays TEXT NOT NULL DEFAULT '',
            soundPath TEXT,
            isEnabled INTEGER NOT NULL DEFAULT 1,
            isCompleted INTEGER NOT NULL DEFAULT 0,
            scheduleVersion INTEGER NOT NULL DEFAULT 0,
            intervalMinutes INTEGER,
            quietStartMinute INTEGER,
            quietEndMinute INTEGER,
            excludedWeekdays TEXT NOT NULL DEFAULT '',
            sortOrder INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_reminders_sort ON $_table (sortOrder)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN intervalMinutes INTEGER',
          );
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN quietStartMinute INTEGER',
          );
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN quietEndMinute INTEGER',
          );
          await db.execute(
            "ALTER TABLE $_table ADD COLUMN excludedWeekdays TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN isCompleted INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN scheduleVersion INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
    );
    return ReminderLocalDataSource._(db);
  }

  Future<void> close() => _db.close();

  /// All rows in stable list order.
  @override
  Future<List<Map<String, Object?>>> readAll() =>
      _db.query(_table, orderBy: 'sortOrder ASC');

  /// Insert or replace by primary key.
  ///
  /// [sortOrder] pins the list position (used to put an undone delete back where
  /// it was). Left null, the position is chosen in SQL: the row's current one if
  /// it already exists, otherwise the end of the list. One statement, one round
  /// trip — a SELECT-then-INSERT was two, and raced with a concurrent write.
  @override
  Future<void> write(Map<String, Object?> row, {int? sortOrder}) async {
    final values = Map<String, Object?>.of(row)
      ..remove('isCompleted')
      ..remove('scheduleVersion');
    // A new schedule invalidates completion attempts from other isolates.
    final args = <Object?>[
      ...values.values,
      row['id'],
      sortOrder ?? row['id'],
    ];
    final order = sortOrder == null
        ? 'COALESCE((SELECT sortOrder FROM $_table WHERE id = ?), '
              '(SELECT COALESCE(MAX(sortOrder), -1) + 1 FROM $_table))'
        : '?';
    await _db.rawInsert(
      'INSERT OR REPLACE INTO $_table '
      '(${values.keys.join(', ')}, isCompleted, scheduleVersion, sortOrder) '
      'VALUES (${List.filled(values.length, '?').join(', ')}, 0, '
      'COALESCE((SELECT scheduleVersion FROM $_table WHERE id = ?), 0) + 1, '
      '$order)',
      args,
    );
  }

  @override
  Future<bool> completeOnce(String id, int scheduleVersion) async =>
      await _db.update(
        _table,
        {'isEnabled': 0, 'isCompleted': 1},
        where:
            'id = ? AND scheduleVersion = ? AND isEnabled = 1 '
            'AND intervalMinutes IS NULL AND weekdays = ?',
        whereArgs: [id, scheduleVersion, ''],
      ) ==
      1;

  @override
  Future<bool> reactivateOnce(String id, int scheduleVersion) async =>
      await _db.rawUpdate(
        'UPDATE $_table SET isEnabled = 1, isCompleted = 0, '
        'scheduleVersion = scheduleVersion + 1 '
        'WHERE id = ? AND scheduleVersion = ? '
        'AND intervalMinutes IS NULL AND weekdays = ? '
        'AND (isEnabled = 1 OR isCompleted = 1)',
        [id, scheduleVersion, ''],
      ) ==
      1;

  /// Removes the row, handing back the `sortOrder` it held so an undone delete
  /// can put it back where it was instead of at the end of the list.
  ///
  /// Read and delete in one transaction: the order has to be read BEFORE the row
  /// is gone, and `DELETE ... RETURNING` needs SQLite 3.35 (Android 12 and
  /// later), so a transaction is the portable way to keep it to one write.
  @override
  Future<int?> delete(String id) => _db.transaction((txn) async {
    final rows = await txn.query(
      _table,
      columns: ['sortOrder'],
      where: 'id = ?',
      whereArgs: [id],
    );
    // The id is the primary key, so this is at most one row.
    final order = rows.isEmpty ? null : rows.first['sortOrder'] as int?;
    await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
    return order;
  });
}
