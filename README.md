# Bea's Reminders

A Flutter app for one-time and recurring reminders, with local SQLite storage,
OS notifications, and a shared library of imported or recorded sounds.

## Development

Use a Flutter SDK that includes Dart 3.13.4 or later within Dart 3.

```sh
flutter pub get
flutter run
flutter analyze
flutter test
```

Build native changes with `flutter build apk --debug` or
`flutter build ios --simulator --debug`. Native playback and notification changes
require rebuilding the app; hot reload alone cannot apply them.

## Alerts and sounds

- Enable **Repeat at an interval** in the reminder editor for intervals from
  15 minutes to 24 hours. The selected time aligns the daily repeating pattern.
  Quiet hours can cross midnight; selected weekdays are skipped entirely.
  Skipping alerts preserves the original timing, including while the app is closed.
- Schedules that exceed device notification capacity are rejected before
  replacing an existing reminder. Space is reserved for Snooze. On iOS, shorter
  intervals may require longer quiet hours or fewer active days.
- Snooze respects quiet hours and excluded weekdays; if five minutes later is
  blocked, the next regular allowed alert remains scheduled.
- Enable notifications from the in-app alert notice. Android also needs exact
  alarm access. The notice links to settings if permission has been denied.
- Failed scheduling keeps a paused reminder visible for retry. A failed save
  keeps the editor open and retains its inputs.
- Imported and recorded sounds can be previewed. Sounds referenced by saved
  reminders cannot be deleted, including reminders that are paused.
- iOS imports accept PCM WAV files shorter than 30 seconds (8- or 16-bit,
  mono or stereo). Files are stored in `Library/Sounds` for notification playback.
  Existing unsupported files remain available for preview, with default-tone
  fallback for alerts.
- Sour Gummy is bundled for offline use. Its license is in `assets/fonts/OFL.txt`.

## Verification

Run tests, analysis, and validation builds only when explicitly requested.
The latest interval regression cases have been added but have not been run.

Widget tests cover small and large layouts, enlarged text, recording lifecycle,
permission recovery, and create/edit/delete/undo flows. Callback tests cover
Stop/Snooze and database connection ownership. Device checks are still needed for
actual sound output, OS notification delivery, and manufacturer-specific behavior.

See [AGENTS.md](AGENTS.md) for architecture and contributor responsibilities.
