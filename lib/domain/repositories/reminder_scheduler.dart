import '../entities/reminder.dart';
import '../entities/sound_resolution.dart';

/// Turns a [Reminder] into real OS notifications, and back off again.
///
/// The scheduling *policy* is domain ([Reminder.nextOccurrence] /
/// [nextOccurrenceOn] supply the dates); the alarm scheduling *mechanism* is
/// not, and that is the only thing behind this interface.
abstract class ReminderScheduler {
  /// Schedules [reminder], replacing anything previously scheduled for it.
  /// A disabled reminder is only cancelled, never scheduled.
  Future<void> schedule(Reminder reminder);

  /// Cancels every notification that may have been scheduled for
  /// [reminderId], however many there are.
  Future<void> cancel(String reminderId);

  /// Whether the sound on [reminder] will actually be audible when the
  /// notification fires on this device. A platform round trip behind a
  /// three-valued answer, so the UI can say something honest instead of
  /// implying a runtime-imported sound plays everywhere.
  Future<SoundResolution> soundResolution(Reminder reminder);
}
