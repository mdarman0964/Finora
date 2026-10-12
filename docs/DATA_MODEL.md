# Data model draft

All documents should include `createdAt`, `updatedAt`, and `createdBy` where appropriate; use server timestamps for audit fields. Store amounts as integer minor units and always keep an explicit currency code.

## MessTransaction
- `id`, `messId`
- `kind`: `deposit | messExpense | memberPaidExpense | refund | transfer`
- `amountMinor`, `currencyCode`, `categoryId`, `description`, `transactionDate`
- `paidByUid`, optional `receiptStoragePath`
- `splitStrategy`: `equal | fixed | percentage | meals | custom`
- `allocations` map of UID to amount, optional `approvedByUid`
- `status`: `draft | posted | reversed`

## MealEntry
`messId`, `uid`, `date`, `mealUnits`, `notes`, audit fields.

## PersonalTransaction
`ownerUid`, `kind: income | expense | loanGiven | loanReceived | repayment`, `amountMinor`, `currencyCode`, `categoryId`, `description`, `transactionDate`, optional receipt path, `sharedWithUids` (empty by default), `status`.

## Loan
`ownerUid`, `counterpartyName`, `direction: lent | borrowed`, `principalMinor`, `currencyCode`, `dueDate`, `notes`, child repayment records, and `status: open | partiallyPaid | settled | overdue`.

## Security note
This is a draft, not a production schema. Enforce authorization in Firestore rules, validate totals/splits in trusted code, and test rules with the Firebase Emulator before real data is enabled.


## Month closure protection

New mess transaction documents include `monthKey` in `YYYY-MM` format, and meal documents include both `dateKey` (`YYYY-MM-DD`) and `monthKey`. Firestore rules reject writes when a matching `monthClosures/{monthKey}` document exists. The accounting service also checks the closure before writing to show a clear Bengali error message; the server rules remain the enforcement boundary.


## Approval and custom split behaviour

Mess expenses (`messExpense` and `memberPaidExpense`) are created with `status: pending` and are excluded from balances until the mess owner approves them. Owner approval changes status to `posted`; rejection changes it to `rejected`. Deposits remain posted immediately. Supported split strategies are equal, meals, payer, fixed member allocations, and percentage weights in basis points (10000 = 100%). Fixed allocations are stored in minor currency units and must sum to the transaction amount; percentage weights must sum to 10000. Custom fixed/percentage splits are restricted to the mess owner by the service and Firestore rules.

PDF exports embed Noto Sans Bengali for offline Bengali labels and descriptions. The font is licensed under the SIL Open Font License; the license file is included next to the font.
