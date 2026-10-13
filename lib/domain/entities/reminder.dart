import 'package:equatable/equatable.dart';

/// A single reminder: a title, a time of day, and an optional set of weekdays.
///
/// [weekdays] holds `DateTime.monday` (1) .. `DateTime.sunday` (7). An EMPTY
/// set means "remind once" unless [intervalMinutes] is set.
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
    this.intervalMinutes,
    this.quietStartMinute,
    this.quietEndMinute,
    this.excludedWeekdays = const {},
  }) {
    if (hour < 0 || hour > 23) {
      throw RangeError.range(hour, 0, 23, 'hour');
    }
    if (minute < 0 || minute > 59) {
      throw RangeError.range(minute, 0, 59, 'minute');
    }
    if (intervalMinutes != null &&
        (intervalMinutes! < 15 ||
            intervalMinutes! > 1440 ||
            1440 % intervalMinutes! != 0)) {
      throw ArgumentError('Choose an interval that divides evenly into a day.');
    }
    if ((quietStartMinute == null) != (quietEndMinute == null) ||
        (quietStartMinute != null &&
            (quietStartMinute! < 0 ||
                quietStartMinute! >= 1440 ||
                quietEndMinute! < 0 ||
                quietEndMinute! >= 1440 ||
                quietStartMinute == quietEndMinute))) {
      throw ArgumentError('Quiet hours need different start and end times.');
    }
    if (excludedWeekdays.any((day) => day < 1 || day > 7) ||
        excludedWeekdays.length == 7) {
      throw ArgumentError('Keep at least one weekday active.');
    }
    if (intervalMinutes != null && intervalTimes.isEmpty) {
      throw ArgumentError(
        'Quiet hours exclude every alert. Shorten quiet hours or change the start time.',
      );
    }
  }

  final String id;
  final String title;
  final int hour;
  final int minute;
  final Set<int> weekdays;
  final String? soundPath;
  final bool isEnabled;
  final int? intervalMinutes;
  final int? quietStartMinute;
  final int? quietEndMinute;
  final Set<int> excludedWeekdays;

  bool get isInterval => intervalMinutes != null;

  bool isQuietMinute(int value) {
    final start = quietStartMinute;
    final end = quietEndMinute;
    if (start == null || end == null) return false;
    return start < end
        ? value >= start && value < end
        : value >= start || value < end;
  }

  /// Daily wall-clock slots; quiet periods skip alerts without shifting cadence.
  List<int> get intervalTimes {
    final interval = intervalMinutes;
    if (interval == null) return const [];
    return [
      for (var offset = 0; offset < 1440; offset += interval)
        if (!isQuietMinute((hour * 60 + minute + offset) % 1440))
          (hour * 60 + minute + offset) % 1440,
    ]..sort();
  }

  DateTime nextIntervalSlot(int minuteOfDay, {int? weekday, DateTime? from}) {
    final now = from ?? DateTime.now();
    for (var offset = 0; offset <= 14; offset++) {
      final date = DateTime(
        now.year,
        now.month,
        now.day + offset,
        minuteOfDay ~/ 60,
        minuteOfDay % 60,
      );
      // Skip nonexistent local times rather than shifting the recurring slot.
      if (date.hour == minuteOfDay ~/ 60 &&
          date.minute == minuteOfDay % 60 &&
          date.isAfter(now) &&
          !excludedWeekdays.contains(date.weekday) &&
          (weekday == null || date.weekday == weekday)) {
        return date;
      }
    }
    throw StateError('No active interval day.');
  }

  /// The next local `DateTime` this reminder should fire.
  ///
  /// Pass [from] to evaluate against a fixed instant (tests); defaults to now.
  DateTime nextOccurrence({DateTime? from}) {
    final now = from ?? DateTime.now();

    if (isInterval) {
      return intervalTimes
          .map((slot) => nextIntervalSlot(slot, from: now))
          .reduce((a, b) => a.isBefore(b) ? a : b);
    }

    if (weekdays.isEmpty) {
      final todayAt = DateTime(now.year, now.month, now.day, hour, minute);
      return todayAt.isAfter(now)
          ? todayAt
          : DateTime(now.year, now.month, now.day + 1, hour, minute);
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
    int? intervalMinutes,
    bool clearInterval = false,
    int? quietStartMinute,
    int? quietEndMinute,
    bool clearQuietHours = false,
    Set<int>? excludedWeekdays,
  }) {
    return Reminder(
      id: id ?? this.id,
      title: title ?? this.title,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      weekdays: weekdays ?? this.weekdays,
      soundPath: clearSoundPath ? null : soundPath ?? this.soundPath,
      isEnabled: isEnabled ?? this.isEnabled,
      intervalMinutes: clearInterval
          ? null
          : intervalMinutes ?? this.intervalMinutes,
      quietStartMinute: clearQuietHours
          ? null
          : quietStartMinute ?? this.quietStartMinute,
      quietEndMinute: clearQuietHours
          ? null
          : quietEndMinute ?? this.quietEndMinute,
      excludedWeekdays: excludedWeekdays ?? this.excludedWeekdays,
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
    intervalMinutes,
    quietStartMinute,
    quietEndMinute,
    excludedWeekdays,
  ];
}
