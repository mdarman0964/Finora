import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/accounting_service.dart';

class MealsPage extends StatefulWidget {
  const MealsPage({super.key, required this.messId, required this.service});
  final String? messId;
  final AccountingService service;
  @override
  State<MealsPage> createState() => _MealsPageState();
}

class _MealsPageState extends State<MealsPage> {
  final _count = TextEditingController(text: '3');
  bool _saving = false;
  bool _loadedToday = false;
  String? _message;
  String _monthKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
  String _dayKey(DateTime date) => '${_monthKey(date)}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final count = int.tryParse(_count.text.trim());
    if (count == null || count < 0 || count > 20) {
      setState(() => _message = 'মিলের সংখ্যা ০ থেকে ২০-এর মধ্যে দিন.');
      return;
    }
    if (widget.messId == null) {
      setState(() => _message = 'আগে মেস তৈরি করুন অথবা মেসে যোগ দিন।');
      return;
    }
    setState(() { _saving = true; _message = null; });
    try {
      await widget.service.addMealCount(messId: widget.messId!, count: count);
      if (mounted) { setState(() => _message = 'আজকের মিলের হিসাব সংরক্ষণ হয়েছে।'); }
    } catch (e) {
      if (mounted) {
        setState(() => _message = e.toString());
      }
    } finally { if (mounted) { setState(() => _saving = false); } }
  }

  @override
  void dispose() { _count.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (widget.messId == null) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24), child: Text('মিলের হিসাব রাখতে আগে মেস তৈরি করুন বা যোগ দিন.', textAlign: TextAlign.center),
      ));
    }
    final now = DateTime.now();
    final month = _monthKey(now);
    final today = _dayKey(now);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.service.mealCounts(widget.messId!),
      builder: (context, mealSnapshot) {
        final meals = mealSnapshot.data?.docs ?? [];
        final monthMeals = meals.where((d) => (d.data()['dateKey'] as String? ?? '').startsWith(month)).toList();
        final totalMeals = monthMeals.fold<int>(0, (total, d) => total + ((d.data()['count'] as num?)?.toInt() ?? 0));
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final todayDoc = meals.where((d) => d.data()['memberUid'] == uid && d.data()['dateKey'] == today).toList();
        if (!_loadedToday && mealSnapshot.hasData) {
          if (todayDoc.isNotEmpty) _count.text = '${todayDoc.first.data()['count'] ?? 0}';
          _loadedToday = true;
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: widget.service.messTransactions(widget.messId!),
          builder: (context, transactionSnapshot) {
            final eligibleMinor = (transactionSnapshot.data?.docs ?? []).fold<int>(0, (total, doc) {
              final data = doc.data(); final date = data['transactionDate']; final kind = data['kind'];
              if (data['mealEligible'] == true && (kind == 'messExpense' || kind == 'memberPaidExpense') && date is Timestamp && _monthKey(date.toDate()) == month) {
                return total + ((data['amountMinor'] as num?)?.toInt() ?? 0);
              }
              return total;
            });
            final rate = totalMeals == 0 ? 0.0 : eligibleMinor / 100 / totalMeals;
            return ListView(padding: const EdgeInsets.all(18), children: [
              Text('মিল ও মিল রেট', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6), Text('${DateFormat('MMMM yyyy').format(now)} • মাসিক হিসাব'),
              const SizedBox(height: 14),
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('আজকের মিল', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 8),
                TextField(controller: _count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'আজ কতটি মিল খেয়েছেন?', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                FilledButton(onPressed: _saving ? null : _save, child: _saving ? const CircularProgressIndicator() : const Text('মিল সংরক্ষণ করুন')),
                if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!)),
              ]))),
              const SizedBox(height: 12),
              GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, childAspectRatio: 1.45, crossAxisSpacing: 10, mainAxisSpacing: 10, children: [
                _MetricCard(label: 'মোট মিল', value: '$totalMeals', icon: Icons.restaurant),
                _MetricCard(label: 'যোগ্য খাবার খরচ', value: '৳${(eligibleMinor / 100).toStringAsFixed(2)}', icon: Icons.shopping_basket_outlined),
                _MetricCard(label: 'প্রতি মিল রেট', value: '৳${rate.toStringAsFixed(2)}', icon: Icons.calculate_outlined),
                _MetricCard(label: 'এই মাসে সদস্য এন্ট্রি', value: '${monthMeals.length}', icon: Icons.groups_outlined),
              ]),
              const SizedBox(height: 12),
              const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('মিল রেটের নিয়ম'), subtitle: Text('এই মাসের মিলের হিসাবে চিহ্নিত খাবার-সংক্রান্ত মেস খরচ ÷ এই মাসের মোট মিল। অন্য খরচ এখানে ধরা হয় না.'))),
            ]);
          },
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon});
  final String label; final String value; final IconData icon;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(icon), const SizedBox(height: 8), Text(label, maxLines: 2, overflow: TextOverflow.ellipsis), const SizedBox(height: 4), Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
  ])));
}
