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

- Notifications use **Bea's Reminders** as the title and the reminder text below
  it. Snoozed alerts append “(snoozed)”. **Turn off** pauses the
  reminder; **Snooze 5 min** is available only for non-interval reminders.
- The main notification icon uses the launcher bell: Android uses a monochrome
  version as required for its small icon; iOS uses the bundled launcher artwork.
  Notification branding changes require rebuilding the installed app. Alerts
  already scheduled keep their stored text until the reminder is saved again;
  interval reminders are refreshed automatically when the app starts.
- Enable **Repeat at an interval** in the reminder editor for intervals from
  15 minutes to 24 hours. The selected time aligns the daily repeating pattern.
  With **Active hours**, the range's start anchors the interval instead (start
  included, end excluded): 9 AM–5 PM hourly means 9 AM, 10 AM, …, 4 PM.
  Turn them off for all-day reminders. Select the weekdays that should receive alerts.
  Overnight ranges are supported; each alert must fall on a selected calendar day.
  Existing interval schedules are refreshed on startup to apply this timing and
  remove leftover snoozes; one-time and weekly schedules are left in place.
- Schedules that exceed device notification capacity are rejected before
  replacing an existing reminder. Weekly reminders reserve space for Snooze. On iOS, shorter
  intervals may require shorter active hours or fewer active days.
- Interval reminders never snooze; dismissing or ignoring an alert leaves only
  the regular interval schedule armed.
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
