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

  /// Version 1, one table, no migration runner (add them when a v2 actually
  /// exists).
  static Future<ReminderLocalDataSource> open({String? path}) async {
    final db = await openDatabase(
      path ?? '${await getDatabasesPath()}/$_fileName',
      version: 1,
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
            sortOrder INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_reminders_sort ON $_table (sortOrder)',
        );
      },
    );
    return ReminderLocalDataSource._(db);
  }

  // ponytail: nothing calls this — the app dies with the process, which closes
  // the handle. Wire it if a background isolate or a test ever outlives it.
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
    // 8th value: the sortOrder pin, or the id the COALESCE subquery matches on.
    final args = <Object?>[...row.values, sortOrder ?? row['id']];
    final order = sortOrder == null
        ? 'COALESCE((SELECT sortOrder FROM $_table WHERE id = ?), '
              '(SELECT COALESCE(MAX(sortOrder), -1) + 1 FROM $_table))'
        : '?';
    await _db.rawInsert(
      'INSERT OR REPLACE INTO $_table (${row.keys.join(', ')}, sortOrder) '
      'VALUES (${List.filled(row.length, '?').join(', ')}, $order)',
      args,
    );
  }

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
