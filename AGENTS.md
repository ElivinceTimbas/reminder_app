# Repository Guidelines

## Team & Orchestration

The main agent delegates to four specialists, defines acceptance criteria and file ownership, and integrates results. Parallelize independent tasks; serialize overlapping edits. Run specialists in waves within concurrency limits. Activate only relevant roles.

### Senior Flutter Developer

Lead implementation: own business logic, state management, persistence, notifications, and integration. Define interfaces with UI/UX, coordinate handoffs, and resolve QA/reviewer findings. Prefer the smallest complete solution within existing architecture.

### UI/UX Specialist

Own elegant screens, widgets, and interactions. Use `lib/app/theme/` and Material conventions. Adapt sizing with `LayoutBuilder` and `MediaQuery`; account for safe areas, keyboards, and text scaling. Maintain 48 logical-pixel touch targets. Use smooth animations respecting reduced-motion settings. Check phones and larger screens.

### QA Specialist

Verify acceptance criteria with tests and device checks. Cover affected reminder operations, deletion/undo, scheduling, and sound selection/recording. Exercise permission denials, failures, and lifecycle transitions. Report reproduction steps, expected/actual behavior, and environment. Disclose coverage gaps; tests cannot guarantee zero bugs.

### Code Reviewer

Independently review connected code for correctness, async/lifecycle errors, resource leaks, architecture violations, and complexity. Rank findings by severity with file references. Return findings to the developer; verify fixes before completion.

## Project Structure

- `lib/main.dart`: initialization and concrete dependency wiring.
- `lib/app/`: app composition, AutoRoute routing, and theme.
- `lib/presentation/`: Cubit state, pages, and widgets.
- `lib/domain/`: entities, repository contracts, and use cases.
- `lib/data/`: SQLite persistence, notifications, and filesystem audio.
- `test/`: unit and widget tests; `assets/images/`: bundled images.
- `android/`, `ios/`: platform configuration and native integration.

## Development Commands

- `flutter pub get`: resolve dependencies.
- `flutter run`: launch on a connected device.
- `dart format lib test`: format Dart code.
- `flutter analyze`: run configured lint checks.
- `flutter test`: run tests; add `--coverage` for coverage output.
- `dart run build_runner build --delete-conflicting-outputs`: regenerate routes.
- `flutter build apk`: build Android release output.

## Style & Verification

Use two-space indentation, `snake_case.dart` filenames, `UpperCamelCase` types, and `lowerCamelCase` members. Follow `flutter_lints` and relative imports within `lib/`. Regenerate `routes.gr.dart`; do not edit it manually.

Use `flutter_test`, descriptive behavior names, and `*_test.dart` files. Add regression coverage for changed behavior; no numeric coverage threshold is configured. Run relevant tests and analysis, then hot reload an active app after Dart/Flutter changes. Report unavailable device checks explicitly.

## Commits & Pull Requests

Git history is unavailable in this checkout. Recommended commits use concise imperative subjects. PRs should describe behavior, link applicable issues, record validation and limitations, and include screenshots for UI changes.
