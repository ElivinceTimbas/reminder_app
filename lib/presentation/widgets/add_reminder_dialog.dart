import 'dart:async';
import 'dart:io' show FileSystemException, Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/library_sound.dart';
import '../../domain/entities/reminder.dart';
import '../../domain/entities/sound_resolution.dart';
import '../../domain/repositories/reminder_scheduler.dart';
import '../../domain/repositories/sound_library.dart';
import '../../domain/usecases/cancel_recording.dart';
import '../../domain/usecases/delete_sound.dart';
import '../../domain/usecases/list_sounds.dart';
import '../../domain/usecases/pick_sound.dart';
import '../../domain/usecases/start_recording.dart';
import '../../domain/usecases/stop_recording.dart';
import '../bloc/reminder_cubit.dart';
import 'labels.dart';

class AddReminderDialog extends StatefulWidget {
  const AddReminderDialog({super.key, this.existing});

  final Reminder? existing;

  @override
  State<AddReminderDialog> createState() => _AddReminderDialogState();
}

/// Sunday-first, the order the chips are shown in — the same order as
/// [MaterialLocalizations.narrowWeekdays] and [_shortDays] behind
/// [weekdayAbbrev].
const _daysOfWeek = <int>[
  DateTime.sunday,
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
  DateTime.saturday,
];

/// Horizontal space one chip spends on chrome around its label: the 4 of
/// [FilterChip.padding] plus the 2 of gap on each side that this file puts
/// around it. Both are set explicitly, which is what makes them knowable here.
const _chipChrome = 12.0;

/// The dialog's own insets, kept next to the width math in [_availableWidth]
/// so the two cannot drift apart.
const _dialogInset = EdgeInsets.symmetric(horizontal: 20, vertical: 24);

/// `Dialog`'s own minimum width, from `Material`.
const _dialogMinWidth = 280.0;

class _AddReminderDialogState extends State<AddReminderDialog> {
  late final TextEditingController _titleController;
  late TimeOfDay _time;
  late Set<int> _weekdays;
  String? _soundPath;

  List<LibrarySound>? _sounds;

  SoundResolution? _resolution;

  bool _recording = false;

  CancelRecording? _cancelRecording;
  String? _message;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');

    _time = existing == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay(hour: existing.hour, minute: existing.minute);
    _weekdays = {...?existing?.weekdays};
    _soundPath = existing?.soundPath;
    unawaited(_loadSounds());
    unawaited(_refreshResolution());
  }

  @override
  void dispose() {
    _titleController.dispose();

    final cancel = _cancelRecording;
    if (_recording && cancel != null) unawaited(cancel());
    super.dispose();
  }

  bool get _canSave => _titleController.text.trim().isNotEmpty;

  Reminder get _prospective => Reminder(
    id: widget.existing?.id ?? '',
    title: _titleController.text.trim(),
    hour: _time.hour,
    minute: _time.minute,
    weekdays: _weekdays,
    soundPath: _soundPath,
  );

  String? get _resolutionNote => switch (_resolution) {
    null => null,
    SoundResolution.none =>
      'No sound set — the notification plays the default system tone.',
    SoundResolution.custom => 'This sound will play when the reminder fires.',

    SoundResolution.unavailable =>
      Platform.isIOS
          ? 'iOS can only play sounds bundled with the app, so this one will '
                'not ring — the default tone plays instead.'
          : 'This sound could not be loaded — the default tone plays instead.',
  };

  Future<void> _pickTime() async {
    setState(() => _message = null);
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null && mounted) setState(() => _time = picked);
  }

  Future<void> _loadSounds() async {
    try {
      final sounds = await context.read<ListSounds>()();
      if (!mounted) return;
      setState(() => _sounds = sounds);
    } on FileSystemException catch (e) {
      if (!mounted) return;
      debugPrint('Could not read the sounds library: $e');
      setState(() {
        _sounds = const [];
        _message = 'Could not read the sounds library.';
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _sounds = const [];
        _message = 'Could not read the sounds library.';
      });
    }
  }

  Future<void> _refreshResolution() async {
    final soundPath = _soundPath;
    if (soundPath == null) {
      if (mounted) setState(() => _resolution = SoundResolution.none);
      return;
    }

    final resolution = await context.read<ReminderScheduler>().soundResolution(
      _prospective,
    );

    if (!mounted || _soundPath != soundPath) return;
    setState(() => _resolution = resolution);
  }

  void _setSoundPath(String? path) {
    setState(() {
      _soundPath = path;
      _message = null;
    });
    unawaited(_refreshResolution());
  }

  void _selectSound(LibrarySound sound) =>
      _setSoundPath(sound.path == _soundPath ? null : sound.path);

  Future<void> _importSound() async {
    setState(() => _message = null);
    final path = await context.read<PickSound>()();
    if (path == null || !mounted) return;
    _setSoundPath(path);
    await _loadSounds();
  }

  Future<void> _deleteSound(LibrarySound sound) async {
    setState(() => _message = null);
    try {
      await context.read<DeleteSound>()(sound);
    } on ArgumentError catch (e) {
      if (!mounted) return;
      debugPrint('deleteSound refused ${sound.path}: $e');
      setState(() => _message = 'Could not remove ${sound.name}.');
      return;
    } on FileSystemException catch (e) {
      if (!mounted) return;
      debugPrint('deleteSound failed for ${sound.path}: $e');
      setState(() => _message = 'Could not remove ${sound.name}.');
      return;
    }
    if (!mounted) return;

    if (_soundPath == sound.path) _setSoundPath(null);
    await _loadSounds();
  }

  Future<void> _toggleRecording() async {
    setState(() => _message = null);

    final start = context.read<StartRecording>();
    final stop = context.read<StopRecording>();
    final cancel = context.read<CancelRecording>();
    if (_recording) {
      final path = await stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _cancelRecording = null;
      });
      if (path != null) _setSoundPath(path);

      await _loadSounds();
      return;
    }

    if (!await context.read<SoundLibrary>().hasPermission()) {
      if (mounted) {
        setState(() => _message = 'Microphone permission was denied.');
      }
      return;
    }
    final path = await start();
    if (!mounted) return;
    if (path == null) {
      setState(() => _message = 'Could not start recording.');
      return;
    }
    setState(() {
      _recording = true;
      _cancelRecording = cancel;
    });
  }

  /// Chip labels for the current width: three letters when each chip's share of
  /// the row fits them, single letters when it does not.
  List<String> _weekdayLabels() {
    final abbreviations = _daysOfWeek.map(weekdayAbbrev).toList();
    if (_fitsRow(abbreviations)) return abbreviations;
    // `narrowWeekdays` is Sunday-first and `day % 7` maps 7 to 0, so it lines up
    // with [weekdayAbbrev].
    return _daysOfWeek
        .map((day) => MaterialLocalizations.of(context).narrowWeekdays[day % 7])
        .toList();
  }

  /// Width the content column gets inside the dialog: the screen less this
  /// dialog's own inset padding, never below the dialog's 280 minimum, less the
  /// 24 of content padding on each side.
  ///
  /// Not a `LayoutBuilder`: `AlertDialog` lays its content out under an
  /// `IntrinsicWidth`, which forbids building speculatively.
  double get _availableWidth =>
      math.max(
        _dialogMinWidth,
        MediaQuery.sizeOf(context).width - _dialogInset.horizontal,
      ) -
      48.0;

  /// The chips are equal columns, so the widest label is the one that decides.
  bool _fitsRow(List<String> labels) {
    final slot = _availableWidth / _daysOfWeek.length - _chipChrome;
    return labels.every((label) => _textWidth(label) <= slot);
  }

  double _textWidth(String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      textDirection: Directionality.of(context),
    )..layout();
    return painter.width;
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final soundPath = _soundPath;
    final base =
        widget.existing ??
        context.read<ReminderCubit>().draft(
          title: title,
          hour: _time.hour,
          minute: _time.minute,
          weekdays: _weekdays,
        );

    Navigator.pop(
      context,
      base.copyWith(
        title: title,
        hour: _time.hour,
        minute: _time.minute,
        weekdays: _weekdays,
        soundPath: soundPath,
        clearSoundPath: soundPath == null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final error = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.error,
    );
    final note = _resolutionNote;
    final sounds = _sounds;
    final labels = _weekdayLabels();

    return AlertDialog(
      title: Text(widget.existing == null ? 'Add reminder' : 'Edit reminder'),
      contentTextStyle: theme.textTheme.bodyMedium,
      insetPadding: _dialogInset,

      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // One `Expanded` per day: equal chips and equal gaps whatever the
                // label lengths. Padding and label padding are set explicitly,
                // tighter than the Material default, to keep all seven on one
                // line.
                for (var day in _daysOfWeek.indexed)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: FilterChip(
                        label: Text(
                          labels[day.$1],
                          textAlign: TextAlign.center,
                        ),
                        selected: _weekdays.contains(day.$2),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        labelPadding: EdgeInsets.zero,
                        side: BorderSide.none,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        showCheckmark: false,
                        onSelected: (on) => setState(() {
                          if (on) {
                            _weekdays.add(day.$2);
                          } else {
                            _weekdays.remove(day.$2);
                          }
                        }),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(weekdaySummary(_weekdays), style: muted),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule),
              label: Text(localizations.formatTimeOfDay(_time)),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Reminder'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            Text('Sound', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _importSound,
                  icon: const Icon(Icons.audio_file_outlined),
                  label: const Text('Import from device'),
                ),
                OutlinedButton.icon(
                  onPressed: _toggleRecording,
                  icon: Icon(_recording ? Icons.stop_circle : Icons.mic_none),
                  label: Text(_recording ? 'Stop recording' : 'Record'),
                ),
                if (_soundPath != null)
                  IconButton(
                    tooltip: 'Clear sound',
                    onPressed: () => _setSoundPath(null),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            if (_recording) Text('Recording…', style: error),
            const SizedBox(height: 8),

            if (sounds == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (sounds.isEmpty)
              Text('No sounds yet — import or record one.', style: muted)
            else
              for (final sound in sounds)
                _SoundTile(
                  key: ValueKey(sound.path),
                  sound: sound,
                  selected: sound.path == _soundPath,
                  onTap: () => _selectSound(sound),
                  onDelete: () => _deleteSound(sound),
                ),
            if (_soundPath != null) ...[
              const SizedBox(height: 8),
              Text(soundLabel(_soundPath!), style: muted),
            ],
            if (note != null)
              Text(
                note,
                style: _resolution == SoundResolution.unavailable
                    ? error
                    : muted,
              ),
            if (_message != null) Text(_message!, style: error),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _SoundTile extends StatelessWidget {
  const _SoundTile({
    super.key,
    required this.sound,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final LibrarySound sound;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // `ListTile.shape` drives both the border and the ink splash, so a rounded
    // outline is all it takes — no Card wrapper. A thin gap keeps the rounded
    // corners from touching the next tile.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        selected: selected,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        leading: Icon(
          selected ? Icons.volume_up : Icons.music_note_outlined,
          color: selected ? theme.colorScheme.primary : null,
        ),
        title: Text(sound.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(humanSize(sound.sizeBytes)),
        trailing: IconButton(
          tooltip: 'Remove from library',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
        onTap: onTap,
      ),
    );
  }
}
