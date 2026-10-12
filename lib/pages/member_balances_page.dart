import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/accounting_service.dart';
import '../services/balance_calculator.dart';
import '../services/settlement_calculator.dart';

class MemberBalancesPage extends StatelessWidget {
  const MemberBalancesPage({super.key, required this.messId, required this.service});
  final String? messId;
  final AccountingService service;

  @override
  Widget build(BuildContext context) {
    if (messId == null) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('সদস্যদের ব্যালেন্স দেখতে আগে মেস তৈরি করুন অথবা যোগ দিন।', textAlign: TextAlign.center),
      ));
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: service.messStream(messId!),
      builder: (context, messSnapshot) {
        if (messSnapshot.hasError) return Center(child: Text('মেসের তথ্য লোড করা যায়নি: ${messSnapshot.error}'));
        if (!messSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        final mess = messSnapshot.data!.data() ?? <String, dynamic>{};
        final memberUids = (mess['memberUids'] as List<dynamic>? ?? const [])
            .whereType<String>().toList();
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: service.messTransactions(messId!),
          builder: (context, transactionSnapshot) {
            if (transactionSnapshot.hasError) return Center(child: Text('হিসাব লোড করা যায়নি: ${transactionSnapshot.error}'));
            if (!transactionSnapshot.hasData) return const Center(child: CircularProgressIndicator());
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: service.mealCounts(messId!),
              builder: (context, mealSnapshot) {
                if (mealSnapshot.hasError) return Center(child: Text('মিলের তথ্য লোড করা যায়নি: ${mealSnapshot.error}'));
                if (!mealSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                final transactionRows = transactionSnapshot.data!.docs.map((doc) => doc.data()).toList();
                final mealRows = mealSnapshot.data!.docs.map((doc) => doc.data()).toList();
                return FutureBuilder<Map<String, dynamic>?>(
                  future: service.latestMonthClosure(messId!),
                  builder: (context, closureSnapshot) {
                    if (closureSnapshot.hasError) {
                      return Center(child: Text('মাসের closing balance লোড করা যায়নি: ${closureSnapshot.error}'));
                    }
                    if (closureSnapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final closure = closureSnapshot.data;
                    Map<String, int> balanceMap;
                    if (closure == null) {
                      balanceMap = BalanceCalculator.calculate(
                        memberUids: memberUids,
                        transactions: transactionRows,
                        meals: mealRows,
                      );
                    } else {
                      final rawSnapshot = closure['balanceSnapshot'];
                      final openingBalances = <String, int>{
                        if (rawSnapshot is Map)
                          for (final entry in rawSnapshot.entries)
                            if (entry.key is String && entry.value is num)
                              entry.key as String: (entry.value as num).toInt(),
                      };
                      final monthKey = closure['monthKey'] as String? ?? '';
                      final parts = monthKey.split('-');
                      if (parts.length == 2) {
                        final year = int.tryParse(parts[0]);
                        final month = int.tryParse(parts[1]);
                        if (year != null && month != null && month >= 1 && month <= 12) {
                          final cutoff = DateTime(year, month + 1);
                          final laterTransactions = transactionRows.where((row) {
                            final date = row['transactionDate'];
                            return date is Timestamp && !date.toDate().isBefore(cutoff);
                          }).toList();
                          balanceMap = BalanceCalculator.carryForward(
                            openingBalances: openingBalances,
                            memberUids: memberUids,
                            laterTransactions: laterTransactions,
                            meals: mealRows,
                          );
                        } else {
                          balanceMap = BalanceCalculator.carryForward(
                            openingBalances: openingBalances,
                            memberUids: memberUids,
                            laterTransactions: const [],
                            meals: mealRows,
                          );
                        }
                      } else {
                        balanceMap = BalanceCalculator.carryForward(
                          openingBalances: openingBalances,
                          memberUids: memberUids,
                          laterTransactions: const [],
                          meals: mealRows,
                        );
                      }
                    }
                    final balances = balanceMap.entries.toList()
                      ..sort((a, b) => b.value.compareTo(a.value));
                    final money = NumberFormat.currency(locale: 'en_BD', symbol: '৳', decimalDigits: 2);
                    return FutureBuilder<Map<String, Map<String, dynamic>>>(
                      future: service.getMemberProfiles(messId!, memberUids),
                      builder: (context, profileSnapshot) {
                    final profiles = profileSnapshot.data ?? const <String, Map<String, dynamic>>{};
                    final settlements = SettlementCalculator.calculate(Map.fromEntries(balances));
                    final totalBalance = balances.fold<int>(0, (total, entry) => total + entry.value);
                    String memberLabel(String uid) {
                      final profile = profiles[uid] ?? const <String, dynamic>{};
                      final name = (profile['displayName'] as String? ?? '').trim();
                      final email = (profile['email'] as String? ?? '').trim();
                      if (name.isNotEmpty && name != email) return name;
                      if (email.isNotEmpty) return email;
                      return 'সদস্য • ${uid.length > 8 ? uid.substring(0, 8) : uid}';
                    }

                    return ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        Text('সদস্যভিত্তিক ব্যালেন্স', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text(mess['name'] as String? ?? 'তোমার মেস'),
                        const SizedBox(height: 12),
                        const Card(child: ListTile(
                          leading: Icon(Icons.info_outline),
                          title: Text('ব্যালেন্স কীভাবে পড়বেন?'),
                          subtitle: Text('ইতিবাচক ব্যালেন্স = সদস্য টাকা পাবে। ঋণাত্মক ব্যালেন্স = সদস্যের টাকা দিতে হবে। হিসাব জমা, খরচ, নির্বাচিত ভাগের নিয়ম ও মিলের এন্ট্রি থেকে তৈরি হয়।'),
                        )),
                        const SizedBox(height: 8),
                        if (profileSnapshot.connectionState == ConnectionState.waiting)
                          const LinearProgressIndicator(),
                        if (balances.isEmpty)
                          const Card(child: Padding(
                            padding: EdgeInsets.all(18),
                            child: Text('এখনও কোনো সদস্য বা হিসাব পাওয়া যায়নি।'),
                          )),
                        for (final entry in balances)
                          Card(
                            child: ListTile(
                              leading: CircleAvatar(child: Text(memberLabel(entry.key).trim().isNotEmpty
                                  ? memberLabel(entry.key).trim().substring(0, 1).toUpperCase()
                                  : '?')),
                              title: Text(memberLabel(entry.key)),
                              subtitle: Text(entry.value > 0 ? 'পাবেন' : entry.value < 0 ? 'দিতে হবে' : 'হিসাব সমান'),
                              trailing: Text(
                                money.format(entry.value / 100),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: entry.value > 0 ? Colors.green : entry.value < 0 ? Theme.of(context).colorScheme.error : null,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text('টাকা সমন্বয়ের পরামর্শ', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        if (totalBalance != 0)
                          Card(child: ListTile(
                            leading: const Icon(Icons.account_balance_wallet_outlined),
                            title: const Text('এখনই চূড়ান্ত লেনদেনের পরামর্শ দেওয়া যাচ্ছে না'),
                            subtitle: Text('সদস্যদের ব্যালেন্সের মোট ${money.format(totalBalance / 100)}। মেসের তহবিলে অবশিষ্ট টাকা বা অনিবন্ধিত হিসাব থাকতে পারে। আগে তহবিল/হিসাব মিলিয়ে নিন।'),
                          ))
                        else if (settlements.isEmpty)
                          const Card(child: ListTile(
                            leading: Icon(Icons.check_circle_outline),
                            title: Text('সবার হিসাব সমান'),
                            subtitle: Text('এখন কোনো টাকা আদান-প্রদানের প্রয়োজন নেই।'),
                          ))
                        else
                          for (final transfer in settlements)
                            Card(child: ListTile(
                              leading: const Icon(Icons.swap_horiz),
                              title: Text('${memberLabel(transfer.fromUid)} → ${memberLabel(transfer.toUid)}'),
                              subtitle: const Text('টাকা দেবেন → টাকা পাবেন'),
                              trailing: Text(money.format(transfer.amountMinor / 100), style: const TextStyle(fontWeight: FontWeight.bold)),
                            )),
                        const SizedBox(height: 8),
                        const Text('নোট: ব্যালেন্স ও সমন্বয়ের পরামর্শ প্রাথমিক হিসাব। সদস্যদের এন্ট্রি এবং মেসের হাতে থাকা নগদ মিলিয়ে তারপর টাকা পরিশোধ করুন।'),
                      ],
                    );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
