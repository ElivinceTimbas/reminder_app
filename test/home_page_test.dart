// import 'package:flutter/material.dart';
// import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:flutter_test/flutter_test.dart';
// import 'package:reminder_app/data/repositories/notification_reminder_scheduler.dart';
// import 'package:reminder_app/domain/entities/library_sound.dart';
// import 'package:reminder_app/domain/entities/reminder.dart';
// import 'package:reminder_app/domain/repositories/reminder_repository.dart';
// import 'package:reminder_app/domain/repositories/reminder_scheduler.dart';
// import 'package:reminder_app/domain/repositories/sound_library.dart';
// import 'package:reminder_app/domain/usecases/cancel_recording.dart';
// import 'package:reminder_app/domain/usecases/delete_sound.dart';
// import 'package:reminder_app/domain/usecases/list_sounds.dart';
// import 'package:reminder_app/domain/usecases/pick_sound.dart';
// import 'package:reminder_app/domain/usecases/start_recording.dart';
// import 'package:reminder_app/domain/usecases/stop_recording.dart';
// import 'package:reminder_app/presentation/widgets/add_reminder_dialog.dart';

// /// The library the fake hands back, keyed by the sounds each test wants.
// List<LibrarySound> _library = const [];

// /// Stands in for the filesystem so the dialog's async library load resolves
// /// without `path_provider`, `record` or `file_picker` being registered in
// /// `flutter_test`.
// ///
// /// It implements the *domain* interface rather than extending the concrete
// /// library, so no `AudioRecorder` is built and the test no longer has to mock
// /// the record channel just to get a value onto the stack. Only [listSounds] is
// /// faked, because it is the only operation these tests reach — the rest throw
// /// rather than returning a plausible-looking lie. `flutter_test` has no plugin
// /// for any of them, so there is nothing honest to return.
// class _FakeSoundLibrary implements SoundLibrary {
//   @override
//   Future<List<LibrarySound>> listSounds() async => _library;

//   @override
//   dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
// }

// /// A sound in the library, at [path] inside the library folder. [path] is
// /// required rather than defaulted to the name: the dialog compares full paths,
// /// so a name-only path silently fails to select.
// LibrarySound _sound(String name, String path) => LibrarySound(
//   name: name,
//   path: path,
//   sizeBytes: 4096,
// );

// /// Pumps the real add/edit dialog with the real use cases over a fake library
// /// and a real scheduler. No cubit is needed: it is only read inside `_save`,
// /// and these tests stop short of saving. Pumping `HomePage` instead would need
// /// sqflite, which `flutter_test` has no plugin for — this covers the logic that
// /// actually has edge cases.
// Future<void> pumpDialog(
//   WidgetTester tester, {
//   Reminder? existing,
//   List<LibrarySound> sounds = const [],

// }) async {
//   _library = sounds;
//   final library = _FakeSoundLibrary();
//   // The scheduler stays real: the dialog's sound verdict is production
//   // behaviour (a FileProvider lookup that honestly fails in a test), and
//   // stubbing it would test the fake rather than the form. Provided as the
//   // domain interface, exactly as `app.dart` does it — there is no
//   // `ResolveSound` use case any more, just `soundResolution` on the seam.
//   final scheduler = NotificationReminderScheduler();
//   await tester.pumpWidget(
//     // Explicit type arguments throughout: `value: ListSounds(library)` alone
//     // would infer `RepositoryProvider<ListSounds>` from the *static* type of
//     // the value only if it were annotated — unannotated, inference picks the
//     // argument's type and `context.read<ListSounds>()` then throws.
//     MultiRepositoryProvider(
//       providers: [
//         RepositoryProvider<SoundLibrary>.value(value: library),
//         RepositoryProvider<ListSounds>.value(value: ListSounds(library)),
//         RepositoryProvider<PickSound>.value(value: PickSound(library)),
//         RepositoryProvider<DeleteSound>.value(
//           value: DeleteSound(library, reminder),
//         ),
//         RepositoryProvider<StartRecording>.value(
//           value: StartRecording(library),
//         ),
//         RepositoryProvider<StopRecording>.value(value: StopRecording(library)),
//         RepositoryProvider<CancelRecording>.value(
//           value: CancelRecording(library),
//         ),
//         RepositoryProvider<ReminderScheduler>.value(value: scheduler),
//       ],
//       child: MaterialApp(
//         home: existing == null
//             ? const AddReminderDialog()
//             : AddReminderDialog(existing: existing),
//       ),
//     ),
//   );
//   // initState kicks off the library load and the resolution lookup.
//   await tester.pumpAndSettle();
// }

// /// The library row showing [name], and whether it is the selected one.
// ({ListTile tile, bool selected}) rowFor(WidgetTester tester, String name) {
//   final finder = find.widgetWithText(ListTile, name);
//   final tile = tester.widget<ListTile>(finder);
//   return (tile: tile, selected: tile.selected);
// }

// /// The seven chip labels, in Monday-first order.
// List<String?> chipLabels(WidgetTester tester) => [
//   for (var i = 0; i < 7; i++)
//     (tester.widget<FilterChip>(find.byType(FilterChip).at(i)).label as Text)
//         .data,
// ];

// void main() {
//   testWidgets('title guard, day chips and the once/repeating summary', (
//     tester,
//   ) async {
//     await pumpDialog(tester);

//     expect(find.byType(FilterChip), findsNWidgets(7));
//     // Pins the chip order to the DateTime.weekday values behind it: chip 0 is
//     // Sunday (weekday 7), chip 6 is Saturday (weekday 6). The exact list, not a
//     // membership check, so an off-by-one between the label table and the `% 7`
//     // index fails here rather than only surfacing in the summary below.
//     expect(chipLabels(tester), [
//       'Sun',
//       'Mon',
//       'Tue',
//       'Wed',
//       'Thu',
//       'Fri',
//       'Sat',
//     ]);
//     expect(find.text('Once'), findsOneWidget);

//     FilledButton save() =>
//         tester.widget<FilledButton>(find.byType(FilledButton));
//     expect(save().onPressed, isNull, reason: 'no title yet');

//     await tester.enterText(find.byType(TextField), '   ');
//     await tester.pump();
//     expect(save().onPressed, isNull, reason: 'whitespace is not a title');

//     await tester.enterText(find.byType(TextField), 'Water the plants');
//     await tester.pump();
//     expect(save().onPressed, isNotNull);

//     // The chips wrap inside the dialog, so each one is scrolled into view
//     // before it is tapped. They now lead the form, so chip 0 is already on
//     // screen and `ensureVisible` is a no-op for it.
//     Future<void> tapChip(int index) async {
//       await tester.ensureVisible(find.byType(FilterChip).at(index));
//       await tester.tap(find.byType(FilterChip).at(index));
//     }

//     // Monday (chip 1) + Wednesday (chip 3), then untoggle Monday, then untoggle
//     // Wednesday.
//     await tapChip(1);
//     await tapChip(3);
//     await tester.pumpAndSettle();
//     // Summary uses the same short names as the chips, so chip 1 and the first
//     // word here are the same string "Mon" — a Monday-first chip order leaking
//     // in would print "Wed, Fri".
//     expect(find.text('Mon, Wed'), findsOneWidget);
//     expect(find.text('Once'), findsNothing);

//     await tapChip(1);
//     await tester.pumpAndSettle();
//     expect(
//       tester.widget<FilterChip>(find.byType(FilterChip).at(1)).selected,
//       isFalse,
//     );
//     expect(find.text('Mon, Wed'), findsNothing);

//     await tapChip(3);
//     await tester.pumpAndSettle();
//     expect(find.text('Once'), findsOneWidget);
//   });

//   testWidgets('chips share the row equally on a phone, shortened if needed', (
//     tester,
//   ) async {
//     tester.view.physicalSize = const Size(360, 900);
//     tester.view.devicePixelRatio = 1;
//     addTearDown(tester.view.resetPhysicalSize);
//     addTearDown(tester.view.resetDevicePixelRatio);

//     await pumpDialog(tester);

//     // One row: every chip shares the same vertical offset.
//     final chips = [
//       for (var i = 0; i < 7; i++) tester.getRect(find.byType(FilterChip).at(i)),
//     ];
//     expect(chips.map((chip) => chip.top).toSet(), hasLength(1));
//     // And the last chip ends inside the dialog, not past its edge.
//     expect(
//       chips.last.right,
//       lessThanOrEqualTo(360 - 20),
//       reason: 'the row overflows the dialog',
//     );
//     // Equal chips and equal gaps, whatever the label widths. Compared with a
//     // tolerance: the widths come out of seven `Expanded`s, so they differ by
//     // floating point dust.
//     const tolerance = 0.01;
//     expect(
//       chips.last.width - chips.first.width,
//       lessThan(tolerance),
//       reason: 'the chips are not equally wide',
//     );
//     final gaps = <double>[
//       for (var i = 1; i < chips.length; i++) chips[i].left - chips[i - 1].right,
//     ];
//     for (final gap in gaps) {
//       expect(gap - gaps.first, lessThan(tolerance), reason: 'uneven gaps');
//     }
//     // The summary keeps the long names — only the chips shorten.
//     expect(find.text('Once'), findsOneWidget);
//     expect(chipLabels(tester), ['S', 'M', 'T', 'W', 'T', 'F', 'S']);
//   });

//   testWidgets('an empty library says so instead of looking broken', (
//     tester,
//   ) async {
//     await pumpDialog(tester);

//     expect(find.text('No sounds yet — import or record one.'), findsOneWidget);
//     // Nothing is selected, so the note only claims the default tone.
//     expect(
//       find.text(
//         'No sound set — the notification plays the default system tone.',
//       ),
//       findsOneWidget,
//     );
//     expect(find.byType(ListTile), findsNothing);
//   });

//   testWidgets(
//     'tapping a library entry selects it, tapping it again clears it',
//     (
//       tester,
//     ) async {
//       final bell = _sound('bell.wav', '/sounds/bell.wav');
//       final beep = _sound('beep.mp3', '/sounds/beep.mp3');
//       await pumpDialog(tester, sounds: [bell, beep]);

//       expect(rowFor(tester, 'bell.wav').selected, isFalse);
//       expect(rowFor(tester, 'beep.mp3').selected, isFalse);

//       Future<void> tap(String name) async {
//         await tester.ensureVisible(find.widgetWithText(ListTile, name));
//         await tester.tap(find.widgetWithText(ListTile, name));
//         await tester.pumpAndSettle();
//       }

//       await tap('beep.mp3');
//       expect(rowFor(tester, 'beep.mp3').selected, isTrue);
//       expect(rowFor(tester, 'bell.wav').selected, isFalse);
//       // The selected path is echoed under the list, so the choice is visible
//       // even when the row itself has scrolled away.
//       expect(
//         find.descendant(
//           of: find.byType(SingleChildScrollView),
//           matching: find.text('beep.mp3'),
//         ),
//         findsNWidgets(2),
//       );

//       // Selecting another entry moves the selection rather than stacking it.
//       await tap('bell.wav');
//       expect(rowFor(tester, 'bell.wav').selected, isTrue);
//       expect(rowFor(tester, 'beep.mp3').selected, isFalse);

//       // Same entry again: deselected, equivalent to the clear button.
//       await tap('bell.wav');
//       expect(rowFor(tester, 'bell.wav').selected, isFalse);
//       expect(find.byIcon(Icons.close), findsNothing);
//       expect(
//         find.text(
//           'No sound set — the notification plays the default system tone.',
//         ),
//         findsOneWidget,
//       );
//     },
//   );

//   testWidgets('an existing reminder opens with its sound selected', (
//     tester,
//   ) async {
//     final reminder = Reminder(
//       id: 'r1',
//       title: 'Standup',
//       hour: 9,
//       minute: 15,
//       soundPath: '/sounds/bell.wav',
//     );
//     await pumpDialog(
//       tester,
//       existing: reminder,
//       sounds: [
//         _sound('beep.mp3', '/sounds/beep.mp3'),
//         _sound('bell.wav', '/sounds/bell.wav'),
//       ],
//     );

//     expect(rowFor(tester, 'bell.wav').selected, isTrue);
//     expect(find.byIcon(Icons.close), findsOneWidget);
//     // The edit form opens at the reminder's own time, now built from the
//     // entity's plain hour/minute rather than a `TimeOfDay` getter.
//     expect(find.text('9:15 AM'), findsOneWidget);
//   });
// }
