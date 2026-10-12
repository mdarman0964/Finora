# HisabKhata Mess Manager

Flutter app for shared mess accounting and private personal finance tracking.

## Current implementation

- Email/password registration and login through Firebase Authentication
- Create a mess and invite members using a random invite code
- Shared mess transaction stream backed by Cloud Firestore
- Private personal income/expense ledger
- Optional receipt photo upload to Firebase Storage; mess receipts are readable by mess members
- Private loans, partial repayments, and settled status
- On-device PDF and Excel (.xlsx) report export with the platform share sheet
- Bengali-first interface, dark/light theme, and setup guidance when Firebase is not configured
- GitHub Actions Android APK workflow with Firebase values supplied as repository secrets

## Firebase setup

Online features require your own Firebase project. Follow [docs/FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md), enable Email/Password authentication, create Firestore and Storage, add GitHub Actions secrets, and deploy [firestore.rules](firestore.rules) and [storage.rules](storage.rules).

No Firebase project credentials or admin keys are committed. Without the required Dart compile-time values, the app intentionally shows a Firebase setup screen rather than pretending online storage is active.

## Build APK

The workflow `.github/workflows/android-apk.yml` runs on pushes to `main` and can be started from **Actions → Build Android APK → Run workflow**. Download `hisabkhata-mess-manager-apk` from a successful run's artifacts.

## Accounting and privacy principles

- Distinguish deposits into mess cash from expenses paid directly by a member.
- Avoid double-counting the same expense as both a cash expense and a member-paid expense.
- Meal rate = eligible food expense / total counted meals (meal counting and rate calculation are not implemented yet).
- Non-food shared-cost allocation rules, approvals, monthly closing, and detailed meal management remain follow-up work.
- Personal ledgers and loans are private by default.
- Firebase Security Rules enforce access to private records and shared mess records. Test rules with Firebase Emulator and multiple accounts before storing real financial data.

## Local development

Install Flutter stable and Android SDK, then run:

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```
