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
