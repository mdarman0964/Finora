/// Produces a deterministic, minimal set of transfers for zero-sum balances.
/// Positive balances are creditors; negative balances are debtors.
class Settlement {
  const Settlement({
    required this.fromUid,
    required this.toUid,
    required this.amountMinor,
  });

  final String fromUid;
  final String toUid;
  final int amountMinor;
}

class SettlementCalculator {
  const SettlementCalculator._();

  static List<Settlement> calculate(Map<String, int> balances) {
    final total = balances.values.fold<int>(0, (sum, amount) => sum + amount);
    // Never suggest transfers while the ledger has an unexplained remainder
    // (for example, unallocated cash still sitting in the shared mess fund).
    if (total != 0) return const [];

    final debtors = balances.entries
        .where((entry) => entry.value < 0)
        .map((entry) => MapEntry(entry.key, -entry.value))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final creditors = balances.entries
        .where((entry) => entry.value > 0)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final transfers = <Settlement>[];
    var debtorIndex = 0;
    var creditorIndex = 0;
    while (debtorIndex < debtors.length && creditorIndex < creditors.length) {
      final debtor = debtors[debtorIndex];
      final creditor = creditors[creditorIndex];
      final amount = debtor.value < creditor.value ? debtor.value : creditor.value;
      if (amount > 0) {
        transfers.add(Settlement(
          fromUid: debtor.key,
          toUid: creditor.key,
          amountMinor: amount,
        ));
      }
      final debtorLeft = debtor.value - amount;
      final creditorLeft = creditor.value - amount;
      if (debtorLeft == 0) {
        debtorIndex++;
      } else {
        debtors[debtorIndex] = MapEntry(debtor.key, debtorLeft);
      }
      if (creditorLeft == 0) {
        creditorIndex++;
      } else {
        creditors[creditorIndex] = MapEntry(creditor.key, creditorLeft);
      }
    }
    return List.unmodifiable(transfers);
  }
}
