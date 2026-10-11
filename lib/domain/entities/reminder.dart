import 'package:equatable/equatable.dart';

/// A single reminder: a title, a time of day, and an optional set of weekdays.
///
/// [weekdays] holds `DateTime.monday` (1) .. `DateTime.sunday` (7). An EMPTY
/// set means "remind once" — see [nextOccurrence].
///
/// Pure domain object, and pure *Dart*: no Flutter, no JSON, no sqflite, no
/// DateTime fields. The wall-clock time is a plain `hour`/`minute` pair — a
/// Material `TimeOfDay` is a presentation type and is rebuilt at the edge with
/// `TimeOfDay(hour: r.hour, minute: r.minute)`. Row conversion lives in
/// `ReminderRow` (data layer).
class Reminder extends Equatable {
  Reminder({
    required this.id,
    required this.title,
    required this.hour,
    required this.minute,
    this.weekdays = const {},
    this.soundPath,
    this.isEnabled = true,
  }) {
    if (hour < 0 || hour > 23) {
      throw RangeError.range(hour, 0, 23, 'hour');
    }
    if (minute < 0 || minute > 59) {
      throw RangeError.range(minute, 0, 59, 'minute');
    }
  }

  final String id;
  final String title;
  final int hour;
  final int minute;
  final Set<int> weekdays;
  final String? soundPath;
  final bool isEnabled;

  /// The next local `DateTime` this reminder should fire.
  ///
  /// Pass [from] to evaluate against a fixed instant (tests); defaults to now.
  DateTime nextOccurrence({DateTime? from}) {
    final now = from ?? DateTime.now();

    if (weekdays.isEmpty) {
      final todayAt = DateTime(now.year, now.month, now.day, hour, minute);
      return todayAt.isAfter(now)
          ? todayAt
          : todayAt.add(const Duration(days: 1));
    }

    return weekdays
        .map((day) => nextOccurrenceOn(day, from: now))
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// Next occurrence of [weekday] alone, at this reminder's time, at or after
  /// [from] (default: now). [weekdays] is ignored — this is the "one given day"
  /// primitive that [nextOccurrence] and the scheduler both build on.
  DateTime nextOccurrenceOn(int weekday, {DateTime? from}) {
    final now = from ?? DateTime.now();
    // Rebuilt per day rather than `todayAt.add(Duration(days: n))` so the wall
    // clock time survives a DST shift.
    for (var offset = 0; offset <= 7; offset++) {
      final candidate = DateTime(
        now.year,
        now.month,
        now.day + offset,
        hour,
        minute,
      );
      if (candidate.weekday == weekday && candidate.isAfter(now)) {
        return candidate;
      }
    }
    // Unreachable: 8 consecutive days cover every weekday. Kept so the function
    // is total rather than throwing. A bad `weekday` (0, 8) lands here too.
    return DateTime(now.year, now.month, now.day + 7, hour, minute);
  }

  /// [clearSoundPath] is the only way to null out [soundPath] — a plain
  /// `soundPath: null` means "unchanged".
  Reminder copyWith({
    String? id,
    String? title,
    int? hour,
    int? minute,
    Set<int>? weekdays,
    String? soundPath,
    bool clearSoundPath = false,
    bool? isEnabled,
  }) {
    return Reminder(
      id: id ?? this.id,
      title: title ?? this.title,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      weekdays: weekdays ?? this.weekdays,
      soundPath: clearSoundPath ? null : soundPath ?? this.soundPath,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    hour,
    minute,
    weekdays,
    soundPath,
    isEnabled,
  ];
}
