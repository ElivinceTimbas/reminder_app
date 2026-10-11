import '../entities/reminder.dart';

/// The reminder store, as the domain sees it.
///
/// A reminder row and the OS notifications for it are ONE fact — a row whose
/// notification was never scheduled (or vice versa) is a bug, not a state. So
/// the write operations here cover both halves, and every writer in the app
/// goes through them, which is what keeps the invariant implemented exactly
/// once (in `SqfliteReminderRepository`) instead of once per use case.
abstract class ReminderRepository {
  /// All reminders in stable list order.
  Future<List<Reminder>> getAll();

  /// Inserts or replaces [reminder] and reconciles the OS notification
  /// schedule for it, in that order: write first, then schedule.
  ///
  /// The ordering is about which way the damage lands. A crash between the two
  /// leaves a row whose notification was never scheduled — permanent, not
  /// transient: nothing rescans rows at startup (`getAll` is read-only), so that
  /// reminder stays silent until it is next edited. The other order would leave
  /// a notification for a row that no longer exists, which the OS can fire on a
  /// date no user can see or cancel in the app. An unscheduled row is strictly
  /// better than an orphan notification, and never the reverse.
  ///
  /// Any id is accepted, so an existing reminder can be passed straight back in
  /// to restore it. [sortOrder] pins the list position (used to put an undone
  /// delete back where it was); left null the position is chosen by the store.
  Future<void> upsert(Reminder reminder, {int? sortOrder});

  /// Removes the row and cancels every notification scheduled for [id], and
  /// returns the list position it held — the same value [upsert] takes back to
  /// put a restored row back where it was, and null if there was no such row.
  ///
  /// Handed back rather than read separately because the position only exists
  /// in the store: the index a row happens to have in a loaded list is not it
  /// once earlier deletes have left gaps.
  Future<int?> delete(String id);
}
