# attendance_parser

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Using the Online Check flow

This app can fetch and parse your attendance directly from the student portal.

- Tap "Check Online", enter your username/password in the dialog.
- A portal login page opens inside the app. The app auto-fills username/password and focuses the captcha field.
- Type the captcha, then tap the Login icon in the app bar.
- The app automatically navigates to "Attendance Display for Students", fills the required fields (End Date = today), submits, and intercepts the generated PDF in memory.
- Your attendance stats are calculated and shown in the home screen.

If a post-login confirmation dialog appears, the app attempts to close it automatically and continue. If the site changes, let us know the new dialog text and we’ll adapt the selectors.

## Windows build warnings (Firebase) explained

On Windows builds you may see MSVC/CMake link warnings similar to LNK4099 or PDB-not-found originating from Firebase. These occur because Firebase is only configured for Android/iOS in this project and desktop builds don’t ship Firebase debug symbols. They are benign and do not impact the app: Firebase initialization is guarded to run only on Android/iOS, and local notifications work cross‑platform without Firebase.

Options to reduce/suppress warnings:

- Build a Release configuration (warnings are typically reduced in Release).
- Ignore the specific warning code (e.g., `/ignore:4099`) in the Windows linker flags if you maintain a custom CMake/VS configuration.
- Keep Firebase dependencies scoped to mobile usage (as already done in code). Removing Firebase packages entirely is optional but not required for desktop.

## Tests

Run the widget tests to verify the app boots and renders the home screen title. The default counter test was replaced with a smoke test that pumps `AttendanceApp`.
