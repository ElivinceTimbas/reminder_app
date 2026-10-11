import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../domain/entities/library_sound.dart';
import '../../domain/repositories/sound_library.dart';

/// The sounds library on disk, plus the `record` and `file_picker` plugins.
///
/// The library is a first-class folder (`<support>/sounds`): a sound picked
/// from anywhere is copied in once, re-picking the same sound reuses the entry,
/// and the folder is the picker's starting point where the platform supports
/// one. Recordings land in it too, so a take is a reusable library entry rather
/// than an orphan file in the documents root.
///
/// No playback/preview. If the UI agent needs one, add a `just_audio` (or
/// `audioplayers`) player rather than blocking on this class.
class FileSystemSoundLibrary implements SoundLibrary {
  // ponytail: one global recorder — ceiling is a single concurrent recording.
  // Upgrade to per-reminder AudioRecorder instances if that ever matters.
  final AudioRecorder _recorder = AudioRecorder();

  String? _lastRecordingPath;

  /// The sounds library, created on demand.
  ///
  /// The application *support* directory, not documents: on Android documents
  /// is `Context.getDir("flutter")` = `/data/user/0/<pkg>/app_flutter`, which
  /// only a `<root-path>` FileProvider root can reach, and that root has to
  /// hardcode `data/user/0/<pkg>` — broken by a secondary-user profile or any
  /// `applicationIdSuffix`. Support is `filesDir` = `/data/user/0/<pkg>/files`,
  /// which `<files-path>` maps directly, so the XML stays narrow and
  /// runtime-derived. Documents buys nothing here: on Android it is app-private
  /// anyway, and on iOS neither directory is user-visible (this app sets no
  /// `UIFileSharingEnabled`) and both are included in the device backup.
  /// (See `res/xml/reminder_file_paths.xml` for the other half of that trade.)
  Future<Directory> get soundsDirectory async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/sounds');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

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
    for (final entry in await dir.list().toList()) {
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
  /// it was already there, the fresh copy otherwise. Throws only if
  /// [sourcePath] does not exist.
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
    final root = (await soundsDirectory).absolute.path;
    // `normalizePath()` is the load-bearing part: `absolute` alone does not
    // collapse `..`, so `<sounds>/../../outside/x.mp3` keeps the library prefix
    // and sails through a plain `startsWith`. This is the stdlib's path
    // normalizer (no `package:path` dependency) and it also resolves `.`.
    final target = File(path).absolute.uri.normalizePath().toFilePath();
    if (target != root &&
        !target.startsWith('$root${Platform.pathSeparator}')) {
      throw ArgumentError.value(path, 'path', 'Not inside the sounds library');
    }
    if (await File(target).exists()) await File(target).delete();
  }

  /// Starts recording into the library (`<sounds>/recording_<millis>.m4a`).
  /// Returns that path, or null if permission was refused.
  ///
  /// No content dedupe here, unlike [importSound]: a fresh take is genuinely a
  /// new sound even when it is silent.
  @override
  Future<String?> startRecording() async {
    if (!await _recorder.hasPermission()) return null;
    final dir = await soundsDirectory;
    final path =
        '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    _lastRecordingPath = path;
    return path;
  }

  /// Stops recording. Returns the file path, or null if nothing was captured.
  @override
  Future<String?> stopRecording() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    _lastRecordingPath = path;
    return path;
  }

  /// Abandons the current take and deletes it.
  @override
  Future<void> cancelRecording() async {
    final path = _lastRecordingPath;
    _lastRecordingPath = null;
    await _recorder.cancel();
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    }
  }

  /// Releases the native recorder. Nothing calls it: the app has no teardown
  /// point (the process dies with the native handle), and the dialog already
  /// abandons any in-flight take. Kept as the seam for a test or a future
  /// background-isolate recorder.
  Future<void> dispose() => _recorder.dispose();
}
