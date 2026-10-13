import 'package:flutter/material.dart';

import '../../domain/entities/reminder.dart';

const _shortDays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const _fullDays = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

String weekdayAbbrev(int weekday) => _shortDays[weekday % 7];
String weekdayName(int weekday) => _fullDays[weekday % 7];

String intervalLabel(int minutes) => minutes % 60 == 0
    ? '${minutes ~/ 60} ${minutes == 60 ? 'hour' : 'hours'}'
    : '$minutes minutes';

String scheduleLabel(Reminder reminder) => reminder.isInterval
    ? 'Every ${intervalLabel(reminder.intervalMinutes!)}'
    : weekdaySummary(reminder.weekdays);

String quietHoursLabel(BuildContext context, Reminder reminder) {
  final start = reminder.quietStartMinute;
  final end = reminder.quietEndMinute;
  if (!reminder.isInterval || start == null || end == null) return '';
  return 'Quiet ${TimeOfDay(hour: start ~/ 60, minute: start % 60).format(context)}–${TimeOfDay(hour: end ~/ 60, minute: end % 60).format(context)}';
}

String weekdaySummary(Set<int> weekdays) => weekdays.isEmpty
    ? 'Once'
    : weekdays.length == 7
    ? 'Every day'
    : (weekdays.toList()..sort()).map(weekdayAbbrev).join(', ');

String nextDateLabel(BuildContext context, Reminder reminder, {DateTime? now}) {
  if (!reminder.isEnabled) return 'Paused';
  final current = now ?? DateTime.now();
  final next = reminder.nextOccurrence(from: current);
  final today = DateTime(current.year, current.month, current.day);
  final tomorrow = DateTime(current.year, current.month, current.day + 1);
  final nextDay = DateTime(next.year, next.month, next.day);
  final day = nextDay == today
      ? 'Today'
      : nextDay == tomorrow
      ? 'Tomorrow'
      : weekdayName(next.weekday);
  final date =
      '$day · ${MaterialLocalizations.of(context).formatMediumDate(next)}';
  return reminder.isInterval
      ? 'Next: $date · ${TimeOfDay.fromDateTime(next).format(context)}'
      : date;
}

String soundLabel(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final timestamp = RegExp(r'^(?:recording|rec)[_-](\d{13,16})')
      .firstMatch(name);
  if (timestamp == null) return name;
  final raw = int.tryParse(timestamp.group(1)!);
  if (raw == null) return name;
  final date = timestamp.group(1)!.length > 13
      ? DateTime.fromMicrosecondsSinceEpoch(raw)
      : DateTime.fromMillisecondsSinceEpoch(raw);
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return 'Recording · ${date.month}/${date.day}/${date.year} $hour:$minute';
}

String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
