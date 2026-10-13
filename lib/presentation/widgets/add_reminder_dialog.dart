import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
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

const _daysOfWeek = [7, 1, 2, 3, 4, 5, 6];

class _AddReminderDialogState extends State<AddReminderDialog>
    with WidgetsBindingObserver {
  late final TextEditingController _titleController;
  late final SoundLibrary _library;
  late final CancelRecording _cancelRecording;
  late TimeOfDay _time;
  late Set<int> _weekdays;
  bool _useInterval = false;
  int _intervalMinutes = 60;
  bool _quietHours = false;
  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 7, minute: 0);
  Set<int> _excludedDays = {};
  String? _soundPath;
  Reminder? _draft;
  List<LibrarySound>? _sounds;
  SoundResolution? _resolution;
  bool _recording = false;
  bool _busy = false;
  bool _saving = false;
  bool _soundExpanded = false;
  int _recordingEpoch = 0;
  Timer? _recordingLimit;
  int _previewEpoch = 0;
  String? _previewPath;
  String? _message;
  VoidCallback? _retry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _library = context.read<SoundLibrary>();
    _cancelRecording = context.read<CancelRecording>();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _time = existing == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay(hour: existing.hour, minute: existing.minute);
    _weekdays = {...?existing?.weekdays};
    _useInterval = existing?.isInterval ?? false;
    _intervalMinutes = existing?.intervalMinutes ?? 60;
    _excludedDays = {...?existing?.excludedWeekdays};
    _quietHours = existing?.quietStartMinute != null;
    if (_quietHours) {
      _quietStart = TimeOfDay(
        hour: existing!.quietStartMinute! ~/ 60,
        minute: existing.quietStartMinute! % 60,
      );
      _quietEnd = TimeOfDay(
        hour: existing.quietEndMinute! ~/ 60,
        minute: existing.quietEndMinute! % 60,
      );
    }
    _soundPath = existing?.soundPath;
    _soundExpanded = _soundPath != null;
    unawaited(_loadSounds());
    unawaited(_refreshResolution());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _recordingEpoch++;
      unawaited(
        _stopPreview().catchError((Object error) {
          debugPrint('Could not stop preview: $error');
        }),
      );
      if (_recording && !_busy) unawaited(_cancelForBackground());
    }
  }

  Future<void> _cancelForBackground() async {
    _recordingLimit?.cancel();
    setState(() => _busy = true);
    try {
      await _cancelRecording();
      if (mounted) {
        setState(() {
          _recording = false;
          _message = 'Recording canceled when the app entered the background.';
        });
      }
    } catch (_) {
      _showError('Could not stop recording. Try Stop recording again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingEpoch++;
    _previewEpoch++;
    _recordingLimit?.cancel();
    _titleController.dispose();
    if (_recording && !_busy) {
      unawaited(
        _cancelRecording().catchError((Object error) {
          debugPrint('Could not cancel recording: $error');
        }),
      );
    }
    unawaited(
      _library.stopPreview().catchError((Object error) {
        debugPrint('Could not stop preview: $error');
      }),
    );
    super.dispose();
  }

  bool get _canSave =>
      _titleController.text.trim().isNotEmpty &&
      !_busy &&
      !_saving &&
      !_recording &&
      _intervalError == null;
  bool get _soundEnabled => !_busy && !_saving && !_recording;

  Reminder get _prospective =>
      _buildDraft(includeInterval: _intervalError == null);

  String? get _intervalError {
    if (!_useInterval) return null;
    try {
      final draft = _buildDraft();
      final count =
          draft.intervalTimes.length *
          (_excludedDays.isEmpty ? 1 : 7 - _excludedDays.length);
      if (defaultTargetPlatform == TargetPlatform.iOS && count > 63) {
        return 'This schedule needs $count alerts. Choose a longer interval, longer quiet hours, or fewer active days. iOS allows 64 alerts; one is kept for Snooze.';
      }
      return null;
    } on ArgumentError catch (error) {
      return error.message.toString();
    }
  }

  Reminder _buildDraft({bool includeInterval = true}) => Reminder(
    id: widget.existing?.id ?? '',
    title: _titleController.text.trim(),
    hour: _time.hour,
    minute: _time.minute,
    weekdays: _weekdays,
    soundPath: _soundPath,
    intervalMinutes: includeInterval && _useInterval ? _intervalMinutes : null,
    quietStartMinute: includeInterval && _useInterval && _quietHours
        ? _quietStart.hour * 60 + _quietStart.minute
        : null,
    quietEndMinute: includeInterval && _useInterval && _quietHours
        ? _quietEnd.hour * 60 + _quietEnd.minute
        : null,
    excludedWeekdays: includeInterval && _useInterval
        ? {..._excludedDays}
        : const {},
  );

  void _showError(String message, [VoidCallback? retry]) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _retry = retry;
    });
  }

  String _errorMessage(Object error, String fallback) => switch (error) {
    FormatException(:final message) => message,
    StateError(:final message) => message,
    _ => fallback,
  };

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null && mounted) setState(() => _time = picked);
  }

  Future<void> _pickQuietTime(bool start) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _quietStart : _quietEnd,
    );
    if (picked != null && mounted) {
      setState(() {
        if (start) {
          _quietStart = picked;
        } else {
          _quietEnd = picked;
        }
      });
    }
  }

  void _toggleDay(int day) => setState(() {
    final days = _useInterval ? _excludedDays : _weekdays;
    days.contains(day) ? days.remove(day) : days.add(day);
  });

  Future<void> _loadSounds() async {
    try {
      final sounds = await context.read<ListSounds>()();
      if (mounted) setState(() => _sounds = sounds);
    } catch (_) {
      if (mounted) setState(() => _sounds = const []);
      _showError('Could not read your sounds. Try again.', _loadSounds);
    }
  }

  Future<void> _refreshResolution() async {
    final path = _soundPath;
    try {
      final result = path == null
          ? SoundResolution.none
          : await context.read<ReminderScheduler>().soundResolution(
              _prospective,
            );
      if (mounted && _soundPath == path) setState(() => _resolution = result);
    } catch (_) {
      if (mounted && _soundPath == path) {
        setState(() => _resolution = SoundResolution.unavailable);
      }
    }
  }

  void _setSoundPath(String? path) {
    setState(() {
      _soundPath = path;
      _resolution = null;
      _message = null;
      _retry = null;
    });
    unawaited(_refreshResolution());
  }

  Future<void> _importSound() async {
    if (!_soundEnabled) return;
    final pick = context.read<PickSound>();
    setState(() {
      _busy = true;
      _message = null;
      _retry = null;
    });
    try {
      await _stopPreview();
      if (!mounted) return;
      final path = await pick();
      if (!mounted || path == null) return;
      _setSoundPath(path);
      await _loadSounds();
    } catch (error) {
      _showError(
        _errorMessage(error, 'Could not import this sound. Try again.'),
        _importSound,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSound(LibrarySound sound) async {
    if (!_soundEnabled) return;
    final delete = context.read<DeleteSound>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete sound?'),
        content: Text(
          'Permanently remove “${soundLabel(sound.path)}” from your library? Canceling the reminder editor will not undo this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_soundEnabled) return;
    setState(() => _busy = true);
    try {
      await _stopPreview();
      await delete(sound);
      if (!mounted) return;
      if (_soundPath == sound.path) _setSoundPath(null);
      await _loadSounds();
    } catch (error) {
      _showError(
        _errorMessage(error, 'Could not remove this sound. Try again.'),
        () => _deleteSound(sound),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleRecording() async {
    if (_busy || _saving) return;
    final start = context.read<StartRecording>();
    final stop = context.read<StopRecording>();
    final epoch = _recordingEpoch;
    final wasRecording = _recording;
    setState(() {
      _busy = true;
      _message = null;
      _retry = null;
    });
    try {
      await _stopPreview();
      if (wasRecording) {
        _recordingLimit?.cancel();
        final path = await stop();
        _recording = false;
        if (!mounted) return;
        if (path == null) {
          _showError(
            'No recording was saved. Try recording again.',
            _toggleRecording,
          );
        } else {
          _setSoundPath(path);
          await _loadSounds();
        }
      } else {
        if (!mounted || epoch != _recordingEpoch) return;
        final permitted = await _library.hasPermission();
        if (!mounted || epoch != _recordingEpoch) return;
        if (!permitted) {
          _showError(
            'Microphone access is off. Enable it in device settings, then try again.',
            _toggleRecording,
          );
          return;
        }
        final path = await start();
        if (!mounted || epoch != _recordingEpoch) {
          await _cancelRecording();
          return;
        }
        if (path == null) {
          _showError('Could not start recording. Try again.', _toggleRecording);
          return;
        }
        setState(() => _recording = true);
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          _recordingLimit = Timer(const Duration(seconds: 29), () {
            if (mounted && _recording && !_busy) unawaited(_toggleRecording());
          });
        }
      }
    } catch (error) {
      if (wasRecording && error is FormatException) _recording = false;
      // A native start can fail after acquiring the microphone. Release it.
      if (!wasRecording || !mounted) {
        try {
          await _cancelRecording();
        } catch (_) {
          /* The next start also resets native recording. */
        }
      }
      _showError(
        _errorMessage(
          error,
          wasRecording
              ? 'Could not stop recording. Try again.'
              : 'Could not start recording. Try again.',
        ),
        _toggleRecording,
      );
    } finally {
      if (!mounted && _recording) {
        try {
          await _cancelRecording();
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopPreview() async {
    final epoch = ++_previewEpoch;
    await _library.stopPreview();
    if (mounted && epoch == _previewEpoch) {
      setState(() => _previewPath = null);
    }
  }

  Future<void> _preview(LibrarySound sound) async {
    if (!_soundEnabled) return;
    final wasPlaying = _previewPath == sound.path;
    final stopped = _stopPreview();
    final epoch = _previewEpoch;
    try {
      await stopped;
      if (wasPlaying || !mounted || epoch != _previewEpoch || !_soundEnabled) {
        return;
      }
      setState(() => _previewPath = sound.path);
      await _library.preview(sound.path);
    } catch (error) {
      debugPrint('Could not preview sound: $error');
      if (mounted && epoch == _previewEpoch) {
        _showError(
          'Could not preview this sound. Try again.',
          () => _preview(sound),
        );
      }
    } finally {
      if (mounted && epoch == _previewEpoch) {
        setState(() => _previewPath = null);
      }
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final cubit = context.read<ReminderCubit>();
    final base =
        widget.existing ??
        (_draft ??= cubit.draft(
          title: _titleController.text.trim(),
          hour: _time.hour,
          minute: _time.minute,
          weekdays: _weekdays,
        ));
    final reminder = base.copyWith(
      title: _titleController.text.trim(),
      hour: _time.hour,
      minute: _time.minute,
      weekdays: {..._weekdays},
      soundPath: _soundPath,
      clearSoundPath: _soundPath == null,
      intervalMinutes: _useInterval ? _intervalMinutes : null,
      clearInterval: !_useInterval,
      quietStartMinute: _quietHours && _useInterval
          ? _quietStart.hour * 60 + _quietStart.minute
          : null,
      quietEndMinute: _quietHours && _useInterval
          ? _quietEnd.hour * 60 + _quietEnd.minute
          : null,
      clearQuietHours: !_quietHours || !_useInterval,
      excludedWeekdays: _useInterval ? {..._excludedDays} : const {},
    );
    setState(() {
      _saving = true;
      _message = null;
      _retry = null;
    });
    final saved = await cubit.add(reminder);
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) {
      Navigator.pop(context);
    } else {
      _showError(
        cubit.state.error?.toString() ??
            'Could not save this reminder. Try again.',
        _save,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        constraints: const BoxConstraints(maxWidth: 560),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(widget.existing == null ? 'Add reminder' : 'Edit reminder'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _titleController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Reminder',
                    hintText: 'What would you like to remember?',
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 20),
                Text(
                  _useInterval ? 'Daily timing' : 'Time',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: _saving ? null : _pickTime,
                  icon: const Icon(Icons.schedule),
                  label: Text(
                    MaterialLocalizations.of(context).formatTimeOfDay(_time),
                  ),
                ),
                if (_intervalError == null)
                  Text(nextDateLabel(context, _prospective), style: muted),
                const SizedBox(height: 20),
                Text('Repeat', style: theme.textTheme.titleSmall),
                SwitchListTile.adaptive(
                  activeTrackColor: theme.colorScheme.primary,
                  activeThumbColor: theme.colorScheme.onPrimary,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Repeat at an interval'),
                  subtitle: const Text(
                    'Remind me regularly throughout the day',
                  ),
                  value: _useInterval,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _useInterval = value),
                ),
                if (_useInterval) ...[
                  DropdownButtonFormField<int>(
                    initialValue: _intervalMinutes,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Remind me every',
                    ),
                    items: [
                      for (final value in [
                        15,
                        20,
                        30,
                        45,
                        60,
                        90,
                        120,
                        180,
                        240,
                        360,
                        480,
                        720,
                        1440,
                      ])
                        DropdownMenuItem(
                          value: value,
                          child: Text(intervalLabel(value)),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _intervalMinutes = value!),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Repeats every ${intervalLabel(_intervalMinutes)}, aligned to ${_time.format(context)} each day. Skipped alerts do not change the timing.',
                    style: muted,
                  ),
                  SwitchListTile.adaptive(
                    activeTrackColor: theme.colorScheme.primary,
                    activeThumbColor: theme.colorScheme.onPrimary,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Quiet hours'),
                    subtitle: const Text(
                      'Do not send reminders during this time',
                    ),
                    value: _quietHours,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _quietHours = value),
                  ),
                  if (_quietHours)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => _pickQuietTime(true),
                          child: Text('From ${_quietStart.format(context)}'),
                        ),
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => _pickQuietTime(false),
                          child: Text('Until ${_quietEnd.format(context)}'),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Text('Skip these days', style: theme.textTheme.titleSmall),
                  Text(
                    'Selected days will not receive reminders.',
                    style: muted,
                  ),
                ],
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final day in _daysOfWeek)
                      Semantics(
                        label: _useInterval
                            ? 'Exclude ${weekdayName(day)}'
                            : weekdayName(day),
                        selected: (_useInterval ? _excludedDays : _weekdays)
                            .contains(day),
                        button: true,
                        excludeSemantics: true,
                        onTap: _saving ? null : () => _toggleDay(day),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          child: FilterChip(
                            label: Text(weekdayAbbrev(day)),
                            tooltip: weekdayName(day),
                            selected: (_useInterval ? _excludedDays : _weekdays)
                                .contains(day),
                            showCheckmark: false,
                            materialTapTargetSize: MaterialTapTargetSize.padded,
                            onSelected: _saving ? null : (_) => _toggleDay(day),
                          ),
                        ),
                      ),
                  ],
                ),
                Text(
                  _useInterval
                      ? (_excludedDays.isEmpty
                            ? 'Active every day'
                            : 'No reminders on ${weekdaySummary(_excludedDays)}')
                      : (_weekdays.isEmpty
                            ? 'Once · choose days to repeat'
                            : weekdaySummary(_weekdays)),
                  style: muted,
                ),
                if (_intervalError != null)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _intervalError!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sound'),
                  subtitle: Text(
                    _soundPath == null
                        ? 'Default system tone'
                        : soundLabel(_soundPath!),
                  ),
                  trailing: Icon(
                    _soundExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  onTap: () => setState(() => _soundExpanded = !_soundExpanded),
                ),
                AnimatedSize(
                  duration: motion,
                  alignment: Alignment.topCenter,
                  child: !_soundExpanded
                      ? const SizedBox.shrink()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (defaultTargetPlatform == TargetPlatform.iOS)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Use a WAV sound shorter than 30 seconds. Recordings stop automatically after 29 seconds.',
                                  style: muted,
                                ),
                              ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                  ),
                                  onPressed: _soundEnabled
                                      ? _importSound
                                      : null,
                                  icon: const Icon(Icons.audio_file_outlined),
                                  label: const Text('Import'),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                  ),
                                  onPressed: _busy || _saving
                                      ? null
                                      : _toggleRecording,
                                  icon: Icon(
                                    _recording
                                        ? Icons.stop_circle
                                        : Icons.mic_none,
                                  ),
                                  label: Text(
                                    _recording ? 'Stop recording' : 'Record',
                                  ),
                                ),
                                if (_soundPath != null)
                                  IconButton(
                                    tooltip: 'Use default tone',
                                    onPressed: _soundEnabled
                                        ? () => _setSoundPath(null)
                                        : null,
                                    icon: const Icon(Icons.close),
                                  ),
                              ],
                            ),
                            if (_recording)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  'Recording… Stop recording before saving.',
                                ),
                              ),
                            if (_sounds == null)
                              const LinearProgressIndicator()
                            else if (_sounds!.isEmpty)
                              Text(
                                'No sounds yet — import or record one.',
                                style: muted,
                              )
                            else
                              for (final sound in _sounds!)
                                _SoundTile(
                                  sound: sound,
                                  selected: sound.path == _soundPath,
                                  playing: sound.path == _previewPath,
                                  onTap: _soundEnabled
                                      ? () => _setSoundPath(
                                          sound.path == _soundPath
                                              ? null
                                              : sound.path,
                                        )
                                      : null,
                                  onPreview: _soundEnabled
                                      ? () => _preview(sound)
                                      : null,
                                  onDelete: _soundEnabled
                                      ? () => _deleteSound(sound)
                                      : null,
                                ),
                            if (_resolution != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(switch (_resolution!) {
                                  SoundResolution.none => 'The notification uses the default system tone.',
                                  SoundResolution.custom =>
                                    'This sound will play with your reminder.',
                                  SoundResolution.unavailable => 'This sound is unavailable. The default tone will play instead.',
                                }, style: muted),
                              ),
                          ],
                        ),
                ),
                if (_busy || _saving)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _message!,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                          if (_retry != null)
                            TextButton(
                              onPressed: _busy || _saving ? null : _retry,
                              child: const Text('Try again'),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _canSave ? _save : null,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class _SoundTile extends StatelessWidget {
  const _SoundTile({
    required this.sound,
    required this.selected,
    required this.playing,
    required this.onTap,
    required this.onPreview,
    required this.onDelete,
  });
  final LibrarySound sound;
  final bool selected;
  final bool playing;
  final VoidCallback? onTap;
  final VoidCallback? onPreview;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Material(
      color: selected
          ? Theme.of(context).colorScheme.secondaryContainer
          : Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          ListTile(
            selected: selected,
            title: Text(soundLabel(sound.path)),
            subtitle: Text(humanSize(sound.sizeBytes)),
            trailing: Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
            ),
            onTap: onTap,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: playing ? 'Stop preview' : 'Preview sound',
                onPressed: onPreview,
                icon: Icon(playing ? Icons.stop : Icons.play_arrow),
              ),
              IconButton(
                tooltip: 'Remove from library',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
