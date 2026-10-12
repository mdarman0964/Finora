import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/accounting_service.dart';

class MessSetupCard extends StatefulWidget {
  const MessSetupCard({super.key});
  @override
  State<MessSetupCard> createState() => _MessSetupCardState();
}

class _MessSetupCardState extends State<MessSetupCard> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _message;
  final _service = AccountingService();

  Future<void> _create() async {
    setState(() { _busy = true; _message = null; });
    try {
      final code = await _service.createMess(_name.text);
      setState(() => _message = 'মেস তৈরি হয়েছে। ইনভাইট কোড: $code');
    } catch (e) {
      setState(() => _message = e.toString());
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _join() async {
    setState(() { _busy = true; _message = null; });
    try {
      await _service.joinMess(_code.text);
      setState(() => _message = 'মেসে যোগ দেওয়া হয়েছে।');
    } catch (e) {
      setState(() => _message = e.toString());
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  void dispose() { _name.dispose(); _code.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('মেস তৈরি করুন অথবা যোগ দিন', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 10),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'নতুন মেসের নাম', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy ? null : _create, child: const Text('নতুন মেস তৈরি')),
            const Divider(height: 26),
            TextField(controller: _code, decoration: const InputDecoration(labelText: 'মেস ইনভাইট কোড', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _busy ? null : _join, child: const Text('কোড দিয়ে মেসে যোগ দিন')),
            if (_message != null) SelectableText(_message!),
          ]),
        ),
      );
}

class MessSummaryCard extends StatelessWidget {
  const MessSummaryCard({super.key, required this.messId});
  final String messId;

  Future<void> _editSplitRule(BuildContext context, String current) async {
    var selected = current;
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('খরচ ভাগের নিয়ম'),
        content: DropdownButtonFormField<String>(
          initialValue: selected,
          items: const [
            DropdownMenuItem(value: 'equal', child: Text('সব সদস্যের মধ্যে সমান ভাগ')),
            DropdownMenuItem(value: 'meals', child: Text('মিলের সংখ্যার অনুপাতে')),
            DropdownMenuItem(value: 'payer', child: Text('যিনি খরচ করেছেন তাঁর হিসাবে')),
          ],
          onChanged: (value) => setDialogState(() => selected = value ?? 'equal'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('বাতিল')),
          FilledButton(onPressed: () async {
            try {
              await AccountingService().updateDefaultSplitStrategy(messId, selected);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            } catch (e) {
              if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(e.toString())));
            }
          }, child: const Text('সংরক্ষণ')),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: AccountingService().messStream(messId),
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.groups_rounded, size: 30),
                const SizedBox(height: 8),
                Text(data?['name'] as String? ?? 'তোমার মেস', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 5),
                const Text('সদস্যদের আমন্ত্রণ জানাতে এই কোড শেয়ার করো:'),
                SelectableText(data?['inviteCode'] as String? ?? 'লোড হচ্ছে…',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                if (data?['ownerUid'] == FirebaseAuth.instance.currentUser?.uid)
                  Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                    onPressed: () => _editSplitRule(context, data?['defaultSplitStrategy'] as String? ?? 'equal'),
                    icon: const Icon(Icons.tune), label: const Text('খরচ ভাগের নিয়ম নির্ধারণ'),
                  )),
                Text('বর্তমান নিয়ম: ${_splitLabel(data?['defaultSplitStrategy'] as String? ?? 'equal')}'),
              ]),
            ),
          );
        },
      );
}

String _splitLabel(String value) => switch (value) {
  'meals' => 'মিলের অনুপাতে',
  'payer' => 'খরচকারীর হিসাবে',
  _ => 'সমান ভাগ',
};
