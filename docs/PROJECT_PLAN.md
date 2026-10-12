# Project plan — HisabKhata Mess Manager

## Product goal
A standalone Flutter app for Android first, designed to remain iOS-compatible. Premium Material 3 UI, Bangla/English, dark/light themes, shared multi-member mess records, and private personal finance.

## Roles
- **Owner/admin:** creates a mess, manages membership and permissions, exports mess reports.
- **Manager:** records mess transactions, meals, expense split rules, and monthly close.
- **Member:** sees shared mess records and adds permitted records.
- **Personal record owner:** controls explicit sharing of their personal transactions.

## Modules
1. Authentication and profile
2. Create/join mess, invitation code, member roles
3. Dashboard and daily mess ledger
4. Deposits, expenses, categories, receipts
5. Meal management and meal-rate calculation
6. Member balances and configurable expense splitting
7. Private personal income/expense ledger
8. Loans, partial repayments, due dates and reminders
9. Daily/weekly/monthly reports; PDF and Excel exports
10. Receipt image storage
11. Notifications
12. Settings: Bangla/English, dark/light, currency, privacy
13. Month-end close, archive, optional balance carry-forward

## Accounting rules
Keep cash deposits, expenses paid from mess cash, and expenses paid directly by a member as distinct events. Avoid counting the same expense twice.

Meal rate = manager-approved eligible food expense / total counted meals.

Supported split strategies: equal, fixed per-member amount, percentage, by meal count, and custom per-member amounts. Validate that allocations total the expense amount; percentages total 100%; reject negative allocations; handle rounding deterministically.

A member balance should separately show deposits, direct eligible mess expenses paid personally, assigned liabilities (meal share + non-food split), and repayments/transfers where enabled. Positive/negative display semantics must be confirmed with automated tests before production.

## Suggested Firestore collections
- `users/{uid}`
- `messes/{messId}`
- `messes/{messId}/members/{uid}`
- `messes/{messId}/transactions/{transactionId}`
- `messes/{messId}/mealEntries/{entryId}`
- `messes/{messId}/monthlyClosures/{yyyyMM}`
- `users/{uid}/personalTransactions/{transactionId}`
- `users/{uid}/loans/{loanId}`
- `users/{uid}/sharedRecords/{shareId}`

## Phases
### Phase 1 — Scaffold
Flutter app shell, dashboard, navigation, theme/language controls, documentation, and APK CI.
### Phase 2 — Core app
Authentication, create/join mess, invitations, roles, Firestore repositories, add/list/edit/reverse transactions, calculation tests.
### Phase 3 — Personal finance
Private ledger, categories/templates, receipt capture/upload, explicit record sharing.
### Phase 4 — Meals, loans, reports
Meal-rate calculations, loans/repayments/reminders, PDF/Excel export, month-end close.
### Phase 5 — Hardening
Firestore rules tests, offline/sync conflict handling, accessibility, audit history, signed release APK, privacy policy.

## MVP acceptance criteria
- Authenticated members can access the same mess from separate phones.
- Members cannot read private ledgers unless explicit sharing grants access.
- Deposits and expenses cannot be double-counted.
- Balances, split allocations, and meal rates have automated tests.
- A signed release APK can be built with protected GitHub Actions secrets.
