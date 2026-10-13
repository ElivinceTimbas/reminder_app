import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reminder_app/data/ios_notification_sound.dart';

import 'fixtures/wav.dart';

void main() {
  late Directory library;
  setUp(() async {
    library = await Directory.systemTemp.createTemp('reminder-sound-test-');
    await Directory(p.join(library.path, 'Sounds')).create();
  });
  tearDown(() => library.delete(recursive: true));

  test(
    'resolves validated sound without a foreground native channel',
    () async {
      final sound = File(p.join(library.path, 'Sounds', 'bell.wav'));
      await sound.writeAsBytes(wav());
      expect(
        await iosNotificationSoundName(
          sound.path,
          libraryDirectory: () async => library,
        ),
        'bell.wav',
      );
    },
  );

  test('does not substitute a same-named sound from another folder', () async {
    await File(p.join(library.path, 'Sounds', 'bell.wav')).writeAsBytes(wav());
    final legacy = File(p.join(library.path, 'bell.wav'));
    await legacy.writeAsBytes(wav(seconds: 2));
    expect(
      await iosNotificationSoundName(
        legacy.path,
        libraryDirectory: () async => library,
      ),
      isNull,
    );
  });

  test('missing and invalid files fall back to the system tone', () async {
    final sound = File(p.join(library.path, 'Sounds', 'bell.wav'));
    expect(
      await iosNotificationSoundName(
        sound.path,
        libraryDirectory: () async => library,
      ),
      isNull,
    );
    await sound.writeAsBytes(wav(seconds: 30));
    expect(
      await iosNotificationSoundName(
        sound.path,
        libraryDirectory: () async => library,
      ),
      isNull,
    );
  });
}
