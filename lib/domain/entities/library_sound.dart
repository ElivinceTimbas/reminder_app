/// One file in the sounds library, ready to render as a list row.
///
/// A domain entity because the sound library is a domain concept the UI reads
/// and the scheduler consumes; it is plain data, so it needs no layer above it.
class LibrarySound {
  const LibrarySound({
    required this.name,
    required this.path,
    required this.sizeBytes,
  });

  /// File name, extension included.
  final String name;

  /// Absolute path inside the sounds library. This is the value that belongs
  /// in `Reminder.soundPath`.
  final String path;

  final int sizeBytes;
}
