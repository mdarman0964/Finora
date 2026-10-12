/// Pure member balance calculations for the shared mess ledger.
///
/// A positive balance means the member should receive money; a negative
/// balance means the member owes money. Amounts are integer minor units.
class BalanceCalculator {
  const BalanceCalculator._();

  static Map<String, int> calculate({
    required List<String> memberUids,
    required List<Map<String, dynamic>> transactions,
    required List<Map<String, dynamic>> meals,
  }) {
    final members = <String>{...memberUids.where((uid) => uid.isNotEmpty)};
    for (final row in transactions) {
      final payer = row['paidByUid'];
      if (payer is String && payer.isNotEmpty) members.add(payer);
    }
    final balances = {for (final uid in members) uid: 0};

    for (final row in transactions) {
      if (row['status'] != null && row['status'] != 'posted') continue;
      final kind = row['kind'] as String? ?? '';
      final amount = (row['amountMinor'] as num?)?.toInt() ?? 0;
      final payer = row['paidByUid'] as String? ?? '';
      if (amount <= 0) continue;

      if (kind == 'deposit') {
        if (balances.containsKey(payer)) balances[payer] = balances[payer]! + amount;
        continue;
      }
      if (kind != 'messExpense' && kind != 'memberPaidExpense') continue;

      // Only expenses paid directly by a member create a payer credit.
      if (kind == 'memberPaidExpense' && balances.containsKey(payer)) {
        balances[payer] = balances[payer]! + amount;
      }

      final strategy = row['splitStrategy'] as String? ?? 'equal';
      final allocations = _allocate(
        amount: amount,
        memberUids: members.toList()..sort(),
        strategy: strategy,
        payerUid: payer,
        monthMeals: _mealWeightsFor(row['transactionDate'], meals),
      );
      for (final entry in allocations.entries) {
        balances[entry.key] = balances[entry.key]! - entry.value;
      }
    }
    return Map.unmodifiable(balances);
  }

  static Map<String, int> _mealWeightsFor(
    dynamic transactionDate,
    List<Map<String, dynamic>> meals,
  ) {
    final date = _dateOf(transactionDate);
    if (date == null) return const {};
    final month = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
    final weights = <String, int>{};
    for (final row in meals) {
      final uid = row['memberUid'];
      final day = row['dateKey'] as String? ?? '';
      final count = (row['count'] as num?)?.toInt() ?? 0;
      if (uid is String && uid.isNotEmpty && day.startsWith(month) && count > 0) {
        weights[uid] = (weights[uid] ?? 0) + count;
      }
    }
    return weights;
  }

  static DateTime? _dateOf(dynamic value) {
    if (value is DateTime) return value;
    // Firestore Timestamp intentionally handled without importing Firestore:
    // it exposes toDate() but remains optional for pure unit tests.
    if (value != null) {
      try {
        final dynamic converted = value.toDate();
        if (converted is DateTime) return converted;
      } catch (_) {
        // Unsupported or missing date; caller falls back to equal splitting.
      }
    }
    return null;
  }

  static Map<String, int> _allocate({
    required int amount,
    required List<String> memberUids,
    required String strategy,
    required String payerUid,
    required Map<String, int> monthMeals,
  }) {
    if (memberUids.isEmpty) return const {};
    if (strategy == 'payer' && memberUids.contains(payerUid)) {
      return {payerUid: amount};
    }

    Map<String, int> weights;
    if (strategy == 'meals' && monthMeals.values.any((value) => value > 0)) {
      weights = {for (final uid in memberUids) uid: monthMeals[uid] ?? 0};
    } else {
      // Unknown strategies and months without meal records use equal shares.
      weights = {for (final uid in memberUids) uid: 1};
    }
    final totalWeight = weights.values.fold<int>(0, (sum, value) => sum + value);
    if (totalWeight <= 0) {
      weights = {for (final uid in memberUids) uid: 1};
    }
    final normalizedTotal = weights.values.fold<int>(0, (sum, value) => sum + value);
    final result = <String, int>{};
    final remainders = <MapEntry<String, int>>[];
    var assigned = 0;
    for (final uid in memberUids) {
      final numerator = amount * weights[uid]!;
      final share = numerator ~/ normalizedTotal;
      result[uid] = share;
      assigned += share;
      remainders.add(MapEntry(uid, numerator % normalizedTotal));
    }
    remainders.sort((a, b) {
      final byRemainder = b.value.compareTo(a.value);
      return byRemainder != 0 ? byRemainder : a.key.compareTo(b.key);
    });
    for (var i = 0; i < amount - assigned; i++) {
      final uid = remainders[i % remainders.length].key;
      result[uid] = result[uid]! + 1;
    }
    return result;
  }
}
