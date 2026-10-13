/// What the OS will actually do with a `Reminder.soundPath`.
///
/// Lives in domain because it is a domain question — "will this sound play?"
/// — not a plugin answer: the *implementation* of the question is a platform
/// channel round trip (see `NotificationReminderScheduler.soundResolution`),
/// but the three possible answers are vocabulary the domain owns and the UI
/// renders.
enum SoundResolution {
  /// No sound on the reminder: the default channel / system tone.
  none,

  /// A custom sound that this platform will actually play.
  custom,

  /// A sound path is set but the file is missing or unsupported on this device.
  unavailable,
}
