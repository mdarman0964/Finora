import 'package:flutter_test/flutter_test.dart';
import 'package:finora/main.dart';
import 'package:finora/services/balance_calculator.dart';
import 'package:finora/services/settlement_calculator.dart';

void main() {
  testWidgets('shows setup guidance when Firebase values are not configured',
      (WidgetTester tester) async {
    await tester.pumpWidget(const FinoraApp());
    await tester.pump();
    expect(find.text('Firebase সেটআপ প্রয়োজন'), findsOneWidget);
    expect(find.text('https://console.firebase.google.com/'), findsOneWidget);
  });


  group('SettlementCalculator', () {
    test('minimizes transfers while preserving the exact total', () {
      final transfers = SettlementCalculator.calculate({
        'a': 700,
        'b': -500,
        'c': -200,
      });

      expect(transfers.length, 2);
      expect(transfers.map((t) => t.amountMinor).reduce((a, b) => a + b), 700);
      expect(transfers.every((t) => t.amountMinor > 0), isTrue);
      expect(transfers.map((t) => t.fromUid).toSet(), {'b', 'c'});
      expect(transfers.map((t) => t.toUid).toSet(), {'a'});
    });

    test('does not suggest settlement when balances do not net to zero', () {
      expect(SettlementCalculator.calculate({'a': 100, 'b': -50}), isEmpty);
    });

    test('returns no transfers when everyone is even', () {
      expect(SettlementCalculator.calculate({'a': 0, 'b': 0}), isEmpty);
    });
  });

  group('BalanceCalculator', () {
    test('splits equally and distributes leftover minor units deterministically', () {
      final balances = BalanceCalculator.calculate(
        memberUids: ['c', 'a', 'b'],
        transactions: [
          {
            'kind': 'messExpense',
            'amountMinor': 100,
            'paidByUid': 'a',
            'splitStrategy': 'equal',
            'transactionDate': DateTime(2026, 10, 10),
            'status': 'posted',
          },
        ],
        meals: const [],
      );

      expect(balances, {'a': -34, 'b': -33, 'c': -33});
      expect(balances.values.fold<int>(0, (sum, value) => sum + value), -100);
    });

    test('credits member-paid expenses to payer and assigns meal-weighted shares', () {
      final balances = BalanceCalculator.calculate(
        memberUids: ['a', 'b'],
        transactions: [
          {
            'kind': 'memberPaidExpense',
            'amountMinor': 900,
            'paidByUid': 'a',
            'splitStrategy': 'meals',
            'transactionDate': DateTime(2026, 10, 10),
            'status': 'posted',
          },
        ],
        meals: [
          {'memberUid': 'a', 'dateKey': '2026-10-01', 'count': 1},
          {'memberUid': 'b', 'dateKey': '2026-10-01', 'count': 2},
        ],
      );

      expect(balances, {'a': 600, 'b': -600});
      expect(balances.values.fold<int>(0, (sum, value) => sum + value), 0);
    });

    test('records deposits as member credits and payer strategy assigns expense to payer', () {
      final balances = BalanceCalculator.calculate(
        memberUids: ['a', 'b'],
        transactions: [
          {'kind': 'deposit', 'amountMinor': 500, 'paidByUid': 'a'},
          {
            'kind': 'messExpense',
            'amountMinor': 300,
            'paidByUid': 'b',
            'splitStrategy': 'payer',
          },
        ],
        meals: const [],
      );

      expect(balances, {'a': 500, 'b': -300});
    });

    test('carries a closed balance forward without counting old entries twice', () {
      final balances = BalanceCalculator.carryForward(
        openingBalances: {'a': 500, 'b': -500},
        memberUids: ['a', 'b'],
        laterTransactions: [
          {
            'kind': 'memberPaidExpense',
            'amountMinor': 200,
            'paidByUid': 'a',
            'splitStrategy': 'equal',
            'transactionDate': DateTime(2026, 11, 2),
            'status': 'posted',
          },
        ],
        meals: const [],
      );

      expect(balances, {'a': 600, 'b': -600});
    });

    test('falls back to equal split when meal counts are missing', () {
      final balances = BalanceCalculator.calculate(
        memberUids: ['a', 'b'],
        transactions: [
          {
            'kind': 'messExpense',
            'amountMinor': 500,
            'paidByUid': 'a',
            'splitStrategy': 'meals',
          },
        ],
        meals: const [],
      );

      expect(balances, {'a': -250, 'b': -250});
    });
  });
}
