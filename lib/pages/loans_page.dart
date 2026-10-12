import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/accounting_service.dart';

class LoansPage extends StatefulWidget {
  const LoansPage({super.key, required this.service});
  final AccountingService service;
  @override
  State<LoansPage> createState() => _LoansPageState();
}

class _LoansPageState extends State<LoansPage> {
  Future<void> _addLoan() async {
    final name = TextEditingController();
    final amount = TextEditingController();
    final notes = TextEditingController();
    String direction = 'lent';
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('ধার-দেনা যোগ করুন'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'ব্যক্তির নাম')),
          TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'টাকার পরিমাণ')),
          DropdownButtonFormField<String>(
            initialValue: direction,
            items: const [
              DropdownMenuItem(value: 'lent', child: Text('আমি ধার দিয়েছি')),
              DropdownMenuItem(value: 'borrowed', child: Text('আমি ধার নিয়েছি')),
            ],
            onChanged: (value) => setDialogState(() => direction = value ?? 'lent'),
          ),
          TextField(controller: notes, decoration: const InputDecoration(labelText: 'নোট (ঐচ্ছিক)')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('বাতিল')),
          FilledButton(onPressed: () async {
            try {
              final parsed = double.tryParse(amount.text.trim());
              if (name.text.trim().isEmpty || parsed == null || parsed <= 0) {
                throw ArgumentError('নাম ও সঠিক টাকার পরিমাণ দিন।');
              }
              await widget.service.addLoan(
                counterpartyName: name.text,
                direction: direction,
                principalMinor: (parsed * 100).round(),
                dueDate: null,
                notes: notes.text,
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString())),
                );
              }
            }
          }, child: const Text('সংরক্ষণ')),
        ],
      ),
    ));
    name.dispose(); amount.dispose(); notes.dispose();
  }

  Future<void> _repay(String id, int remaining) async {
    final amount = TextEditingController();
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('আংশিক পরিশোধ যোগ করুন'),
      content: TextField(controller: amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'বাকি ৳$remaining')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('বাতিল')),
        FilledButton(onPressed: () async {
          try {
            final parsed = double.tryParse(amount.text.trim());
            if (parsed == null || parsed <= 0) throw ArgumentError('সঠিক পরিমাণ দিন।');
            await widget.service.addLoanRepayment(loanId: id, amountMinor: (parsed * 100).round());
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(e.toString())),
              );
            }
          }
        }, child: const Text('পরিশোধ সংরক্ষণ')),
      ],
    ));
    amount.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: widget.service.loans(),
          builder: (context, snapshot) {
            final docs = snapshot.data?.docs ?? [];
            if (snapshot.hasError) return Center(child: Text('লোড করা যায়নি: ${snapshot.error}'));
            if (docs.isEmpty) return const Center(child: Text('এখনো কোনো ধার-দেনা নেই।'));
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data();
                final principal = data['principalMinor'] as int? ?? 0;
                final paid = data['paidMinor'] as int? ?? 0;
                final remaining = principal - paid;
                return Card(child: ListTile(
                  leading: Icon(data['direction'] == 'lent' ? Icons.call_made : Icons.call_received),
                  title: Text(data['counterpartyName'] as String? ?? 'নাম নেই'),
                  subtitle: Text('${data['direction'] == 'lent' ? 'ধার দিয়েছেন' : 'ধার নিয়েছেন'} • পরিশোধ ৳${(paid / 100).toStringAsFixed(2)} • বাকি ৳${(remaining / 100).toStringAsFixed(2)}'),
                  trailing: remaining > 0 ? IconButton(icon: const Icon(Icons.payments_outlined), onPressed: () => _repay(doc.id, remaining)) : const Icon(Icons.check_circle, color: Colors.green),
                ));
              },
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(onPressed: _addLoan, icon: const Icon(Icons.add), label: const Text('ধার-দেনা যোগ')),
      );
}
