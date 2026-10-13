import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../domain/entities/library_sound.dart';
import '../../domain/repositories/sound_library.dart';

/// Shared imported and recorded sounds, including native playback previews.
class FileSystemSoundLibrary implements SoundLibrary {
  // ponytail: one global recorder — ceiling is a single concurrent recording.
  // Upgrade to per-reminder AudioRecorder instances if that ever matters.
  final AudioRecorder _recorder = AudioRecorder();

  static const _channel = MethodChannel('com.deimos.reminder_app/sounds');

  String? _lastRecordingPath;

  /// iOS notification sounds must live in Library/Sounds.
  Future<Directory> get soundsDirectory async {
    final root = Platform.isIOS
        ? await getLibraryDirectory()
        : await getApplicationSupportDirectory();
    final dir = Directory(
      '${root.path}/${Platform.isIOS ? 'Sounds' : 'sounds'}',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<void> preview(String path) =>
      _channel.invokeMethod<void>('preview', path);

  @override
  Future<void> stopPreview() => _channel.invokeMethod<void>('stopPreview');

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Every sound in the library, name-sorted (case-insensitive). Files only —
  /// a stray subdirectory is skipped rather than surfaced.
  ///
  /// No "is this the selected one" flag: the UI compares paths itself, and a
  /// list that had to be re-read just to highlight a row would be a worse deal
  /// than a string comparison.
  @override
  Future<List<LibrarySound>> listSounds() async {
    final dir = await soundsDirectory;
    final sounds = <LibrarySound>[];
    final entries = await dir.list().toList();
    if (Platform.isIOS) {
      final legacy = Directory(
        '${(await getApplicationSupportDirectory()).path}/sounds',
      );
      if (await legacy.exists()) entries.addAll(await legacy.list().toList());
    }
    for (final entry in entries) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      sounds.add(
        LibrarySound(
          name: name,
          path: entry.path,
          sizeBytes: await entry.length(),
        ),
      );
    }
    sounds.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return sounds;
  }

  /// Opens the system audio picker and returns the chosen file's path, or null
  /// if cancelled. Importing is the caller's next step — see `PickSound`.
  ///
  /// The picker is asked to open at the sounds library. Honest platform
  /// support: `file_picker`'s Android implementation builds
  /// `ACTION_GET_CONTENT` and hardcodes the media *audio* root as its initial
  /// URI — it ignores `initialDirectory` for `FileType.audio` — and SAF cannot
  /// browse app-private storage anyway. The iOS implementation uses
  /// `UIDocumentPickerViewController`, which has no directory API at all. So
  /// this only takes effect on macOS/Linux/Windows. It is set defensively:
  /// resolving the directory can throw on a platform without a documents dir,
  /// and a picker must never die over that.
  @override
  Future<String?> pickSoundFile() async {
    String? initialDirectory;
    try {
      initialDirectory = (await soundsDirectory).path;
    } on Object {
      initialDirectory = null;
    }
    final picked = await FilePicker.pickFile(
      type: FileType.audio,
      initialDirectory: initialDirectory,
    );
    return picked?.path;
  }

  /// Copies [sourcePath] into the library unless the library already holds those
  /// exact bytes. Returns the library path either way — the existing entry if
  /// it was already there, the fresh copy otherwise. iOS requires a PCM WAV
  /// shorter than 30 seconds; invalid imports throw [FormatException].
  ///
  /// Dedupe is by content, never by file name: two different sounds legitimately
  /// share a name like `beep.mp3`. Length is the cheap reject; the byte compare
  /// runs only on a length match, and sound files are short enough that a full
  /// compare is the laziest correct thing (no hashing dependency).
  @override
  Future<String> importSound(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Sound file does not exist', sourcePath);
    }
    final bytes = await source.readAsBytes();
    if (Platform.isIOS) {
      if (!sourcePath.toLowerCase().endsWith('.wav')) {
        throw const FormatException(
          'On iOS, import a PCM WAV sound shorter than 30 seconds, or record one here.',
        );
      }
      validateNotificationWav(bytes);
    }
    final dir = await soundsDirectory;

    for (final entry in await dir.list().toList()) {
      if (entry is! File) continue;
      if (await entry.length() != bytes.length) continue;
      if (listEquals(await entry.readAsBytes(), bytes)) return entry.path;
    }

    // Same name, different bytes: the dedupe above already ruled out a match,
    // so add a counter rather than clobbering the entry that is in use.
    final name = source.uri.pathSegments.last;
    var target = File('${dir.path}/$name');
    var suffix = 1;
    while (await target.exists()) {
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      target = File('${dir.path}/${stem}_$suffix$ext');
      suffix++;
    }
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  /// Removes a library entry.
  ///
  /// Refuses any path outside the library. [path] can come straight out of a
  /// persisted reminder row, so the traversal guard is not paranoia.
  @override
  Future<void> deleteSound(String path) async {
    final roots = [(await soundsDirectory).absolute.path];
    if (Platform.isIOS) {
      roots.add('${(await getApplicationSupportDirectory()).path}/sounds');
    }
    // `normalizePath()` is the load-bearing part: `absolute` alone does not
    // collapse `..`, so `<sounds>/../../outside/x.mp3` keeps the library prefix
    // and sails through a plain `startsWith`. This is the stdlib's path
    // normalizer (no `package:path` dependency) and it also resolves `.`.
    final target = File(path).absolute.uri.normalizePath().toFilePath();
    if (!roots.any(
      (root) => target.startsWith('$root${Platform.pathSeparator}'),
    )) {
      throw ArgumentError.value(path, 'path', 'Not inside the sounds library');
    }
    if (await File(target).exists()) await File(target).delete();
  }

  @override
  Future<String?> startRecording() async {
    if (!await _recorder.hasPermission()) return null;
    await stopPreview();
    final dir = await soundsDirectory;
    final extension = Platform.isIOS ? 'wav' : 'm4a';
    final path =
        '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.$extension';
    _lastRecordingPath = path;
    try {
      await _recorder.start(
        Platform.isIOS
            ? const RecordConfig(
                encoder: AudioEncoder.wav,
                sampleRate: 44100,
                numChannels: 1,
              )
            : const RecordConfig(),
        path: path,
      );
      return path;
    } catch (_) {
      await cancelRecording();
      rethrow;
    }
  }

  @override
  Future<String?> stopRecording() async {
    final path = await _recorder.stop();
    _lastRecordingPath = null;
    if (path == null) return null;
    if (Platform.isIOS) {
      try {
        validateNotificationWav(await File(path).readAsBytes());
      } catch (_) {
        await File(path).delete();
        rethrow;
      }
    }
    return path;
  }

  @override
  Future<void> cancelRecording() async {
    final path = _lastRecordingPath;
    _lastRecordingPath = null;
    await _recorder.cancel();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> dispose() async {
    await stopPreview();
    await cancelRecording();
    await _recorder.dispose();
  }
}

/// Rejects malformed, compressed, empty, or overlong notification WAV files.
void validateNotificationWav(Uint8List bytes) {
  const message =
      'Use a PCM WAV sound shorter than 30 seconds (8- or 16-bit, mono or stereo).';
  Never invalid() => throw const FormatException(message);
  if (bytes.length < 44) invalid();
  String tag(int start) =>
      String.fromCharCodes(bytes.sublist(start, start + 4));
  final data = ByteData.sublistView(bytes);
  if (tag(0) != 'RIFF' ||
      tag(8) != 'WAVE' ||
      data.getUint32(4, Endian.little) + 8 != bytes.length) {
    invalid();
  }
  int? bytesPerSecond;
  int? blockSize;
  int? audioSize;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final type = tag(offset);
    final size = data.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    if (start + size > bytes.length) invalid();
    if (type == 'fmt ') {
      if (bytesPerSecond != null) invalid();
      if (size < 16 || data.getUint16(start, Endian.little) != 1) invalid();
      final channels = data.getUint16(start + 2, Endian.little);
      final sampleRate = data.getUint32(start + 4, Endian.little);
      final bits = data.getUint16(start + 14, Endian.little);
      if ((channels != 1 && channels != 2) ||
          (bits != 8 && bits != 16) ||
          sampleRate == 0) {
        invalid();
      }
      blockSize = channels * bits ~/ 8;
      bytesPerSecond = data.getUint32(start + 8, Endian.little);
      if (bytesPerSecond != sampleRate * blockSize ||
          data.getUint16(start + 12, Endian.little) != blockSize) {
        invalid();
      }
    } else if (type == 'data') {
      if (audioSize != null) invalid();
      audioSize = size;
    }
    offset = start + size + size % 2;
  }
  if (offset != bytes.length ||
      bytesPerSecond == null ||
      blockSize == null ||
      audioSize == null ||
      audioSize == 0 ||
      audioSize % blockSize != 0 ||
      audioSize / bytesPerSecond >= 30) {
    invalid();
  }
}
