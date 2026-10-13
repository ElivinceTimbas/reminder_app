import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reminder_app/data/repositories/file_system_sound_library.dart';
import 'package:reminder_app/domain/entities/library_sound.dart';
import 'package:reminder_app/domain/entities/reminder.dart';
import 'package:reminder_app/domain/repositories/reminder_repository.dart';
import 'package:reminder_app/domain/repositories/sound_library.dart';
import 'package:reminder_app/domain/usecases/delete_sound.dart';

import 'fixtures/wav.dart';

class _Sounds implements SoundLibrary {
  final deleted = <String>[];
  int stopped = 0;
  @override
  Future<void> deleteSound(String path) async => deleted.add(path);
  @override
  Future<void> stopPreview() async => stopped++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Reminders implements ReminderRepository {
  _Reminders(this.reminders);
  final List<Reminder> reminders;
  @override
  Future<List<Reminder>> getAll() async => reminders;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('iOS notification WAV validation', () {
    test('accepts PCM WAV shorter than 30 seconds', () {
      expect(() => validateNotificationWav(wav(seconds: 29)), returnsNormally);
    });
    test('rejects the 30-second boundary and longer recordings', () {
      for (final seconds in [30, 31]) {
        expect(
          () => validateNotificationWav(wav(seconds: seconds)),
          throwsFormatException,
        );
      }
    });
    test('rejects empty and non-PCM audio', () {
      expect(
        () => validateNotificationWav(wav(seconds: 0)),
        throwsFormatException,
      );
      expect(
        () => validateNotificationWav(wav(encoding: 3)),
        throwsFormatException,
      );
    });
    test('rejects truncated files and inconsistent PCM headers', () {
      final valid = wav();
      expect(
        () => validateNotificationWav(valid.sublist(0, valid.length - 2)),
        throwsFormatException,
      );
      final inconsistent = wav();
      ByteData.sublistView(inconsistent).setUint32(28, 1, Endian.little);
      expect(
        () => validateNotificationWav(inconsistent),
        throwsFormatException,
      );
    });
    test('accepts metadata chunks before audio', () {
      final original = wav();
      final bytes = Uint8List(original.length + 12);
      bytes.setRange(0, 36, original);
      bytes.setRange(36, 40, 'JUNK'.codeUnits);
      ByteData.sublistView(bytes).setUint32(40, 4, Endian.little);
      bytes.setRange(48, bytes.length, original.sublist(36));
      ByteData.sublistView(bytes).setUint32(4, bytes.length - 8, Endian.little);
      expect(() => validateNotificationWav(bytes), returnsNormally);
    });
  });
  group('shared sound deletion', () {
    const sound = LibrarySound(
      name: 'tone.wav',
      path: '/sounds/tone.wav',
      sizeBytes: 100,
    );
    test(
      'blocks deletion even when the referencing reminder is disabled',
      () async {
        final sounds = _Sounds();
        final reminders = _Reminders([
          Reminder(
            id: '1',
            title: 'Medicine',
            hour: 8,
            minute: 0,
            soundPath: sound.path,
            isEnabled: false,
          ),
        ]);
        await expectLater(
          DeleteSound(sounds, reminders)(sound),
          throwsStateError,
        );
        expect(sounds.deleted, isEmpty);
      },
    );
    test('stops preview and deletes an unreferenced sound', () async {
      final sounds = _Sounds();
      await DeleteSound(sounds, _Reminders([]))(sound);
      expect(sounds.stopped, 1);
      expect(sounds.deleted, [sound.path]);
    });
  });
}
