# HisabKhata Mess Manager

Flutter starter for shared mess accounting and private personal finance tracking.

## Project status
This is the initial scaffold: project plan, dashboard design notes, Flutter dashboard shell, and a GitHub Actions Android APK build workflow. Live Firebase data, authentication, receipt uploads, and real ledger persistence are planned next; the demo numbers shown in the first dashboard are placeholders.

## Planned stack
- Flutter / Dart (Android first, iOS-compatible direction)
- Firebase Authentication
- Cloud Firestore for shared mess records and private personal ledgers
- Firebase Storage for receipt images
- GitHub Actions for APK builds

## Build APK
The workflow `.github/workflows/android-apk.yml` runs on pushes to `main` and can be started manually from **Actions → Build Android APK → Run workflow**. Download `hisabkhata-mess-manager-apk` from the successful run's artifacts.

## Accounting and privacy principles
- Distinguish deposits into mess cash from expenses paid directly by a member.
- Never double-count the same expense as both a cash expense and a member-paid expense.
- Meal rate = eligible food expense / total counted meals.
- Non-food shared costs use a manager-selected split rule.
- Personal ledgers are private by default; sharing is explicit and revocable.
- Firebase Security Rules must enforce permissions; UI checks alone are not security.

## Local development
Install Flutter stable and Android SDK, then run `flutter pub get`, `flutter test`, and `flutter run`.
