import 'package:flutter_test/flutter_test.dart';
import 'package:finora/services/balance_calculator.dart';

void main() {
  const members = ['member-a', 'member-b'];

  test('fixed custom allocations are used exactly', () {
    final balances = BalanceCalculator.calculate(
      memberUids: members,
      transactions: [
        {
          'kind': 'messExpense', 'status': 'posted', 'amountMinor': 1000,
          'paidByUid': 'member-a', 'memberUidsAtPosting': members,
          'splitStrategy': 'fixed',
          'allocations': {'member-a': 700, 'member-b': 300},
          'transactionDate': DateTime(2026, 10, 1),
        },
      ],
      meals: const [],
    );
    expect(balances['member-a'], -700);
    expect(balances['member-b'], -300);
  });

  test('percentage weights allocate the full amount', () {
    final balances = BalanceCalculator.calculate(
      memberUids: members,
      transactions: [
        {
          'kind': 'messExpense', 'status': 'posted', 'amountMinor': 1000,
          'paidByUid': 'member-a', 'memberUidsAtPosting': members,
          'splitStrategy': 'percentage',
          'splitWeights': {'member-a': 2500, 'member-b': 7500},
          'transactionDate': DateTime(2026, 10, 1),
        },
      ],
      meals: const [],
    );
    expect(balances['member-a'], -250);
    expect(balances['member-b'], -750);
  });

  test('pending expenses do not affect balances', () {
    final balances = BalanceCalculator.calculate(
      memberUids: members,
      transactions: [
        {
          'kind': 'messExpense', 'status': 'pending', 'amountMinor': 1000,
          'paidByUid': 'member-a', 'memberUidsAtPosting': members,
          'splitStrategy': 'equal', 'transactionDate': DateTime(2026, 10, 1),
        },
      ],
      meals: const [],
    );
    expect(balances['member-a'], 0);
    expect(balances['member-b'], 0);
  });
}
