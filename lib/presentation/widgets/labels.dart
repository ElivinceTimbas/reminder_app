library;

const _shortDays = <String>[
  'Sun',
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
];

String weekdayAbbrev(int weekday) => _shortDays[weekday % 7];

String weekdaySummary(Set<int> weekdays) => weekdays.isEmpty
    ? 'Once'
    : (weekdays.toList()..sort()).map(weekdayAbbrev).join(', ');

String soundLabel(String path) => path.split(RegExp(r'[/\\]')).last;

String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
