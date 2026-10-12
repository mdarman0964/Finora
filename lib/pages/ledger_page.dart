import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../services/accounting_service.dart';

class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key, required this.messId, required this.service});
  final String? messId;
  final AccountingService service;
  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  bool _personal = false;
  bool _isMessOwner = false;
  @override
  void initState() { super.initState(); _loadOwnerStatus(); }
  Future<void> _loadOwnerStatus() async { if (widget.messId == null) return; try { final owner = await widget.service.isMessOwner(widget.messId!); if (mounted) setState(() => _isMessOwner = owner); } catch (_) {} }
  Future<void> _reviewTransaction(String id, bool approve) async {
    try { await widget.service.reviewMessTransaction(messId: widget.messId!, transactionId: id, approve: approve); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? 'খরচ অনুমোদিত হয়েছে।' : 'খরচ বাতিল করা হয়েছে।'))); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('পর্যালোচনা করা যায়নি: $e'))); }
  }
  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('মেসের খাতা'), icon: Icon(Icons.groups_outlined)),
              ButtonSegment(value: true, label: Text('ব্যক্তিগত'), icon: Icon(Icons.person_outline)),
            ],
            selected: {_personal},
            onSelectionChanged: (values) => setState(() => _personal = values.first),
          ),
        ),
        Expanded(
          child: _personal
              ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: widget.service.personalTransactions(),
                  builder: (context, snapshot) => _transactionList(context, snapshot.data?.docs ?? []),
                )
              : widget.messId == null
                  ? const Center(child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('মেসের খাতা দেখতে আগে হোম পেজ থেকে মেস তৈরি করুন বা যোগ দিন.', textAlign: TextAlign.center),
                    ))
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: widget.service.messTransactions(widget.messId!),
                      builder: (context, snapshot) => _transactionList(context, snapshot.data?.docs ?? []),
                    ),
        ),
      ]);

  Widget _transactionList(BuildContext context, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) return const Center(child: Text('এখনো কোনো হিসাব যোগ করা হয়নি।'));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final data = docs[index].data();
        final kind = data['kind'] as String? ?? '';
        final isIncome = kind == 'deposit' || kind == 'income';
        final amount = ((data['amountMinor'] as num? ?? 0) / 100).toStringAsFixed(2);
        final date = data['transactionDate'];
        final dateText = date is Timestamp ? DateFormat('dd MMM yyyy').format(date.toDate()) : '';
        return Card(
          child: ListTile(
            leading: CircleAvatar(child: Icon(isIncome ? Icons.south_west : Icons.north_east)),
            title: Text(data['description'] as String? ?? data['category'] as String? ?? kind),
            subtitle: Text('$dateText • ${data['category'] ?? kind}'),
            trailing: SizedBox(width: _isMessOwner && data['status'] == 'pending' && !_personal ? 112 : 92,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${isIncome ? '+' : '-'}৳$amount', style: TextStyle(fontWeight: FontWeight.bold, color: isIncome ? Colors.green : Theme.of(context).colorScheme.error)),
                if (!_personal && data['status'] == 'pending') Text('অনুমোদনের অপেক্ষায়', style: Theme.of(context).textTheme.labelSmall),
                if (_isMessOwner && !_personal && data['status'] == 'pending') Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: 'অনুমোদন', visualDensity: VisualDensity.compact, icon: const Icon(Icons.check_circle_outline, color: Colors.green), onPressed: () => _reviewTransaction(docs[index].id, true)),
                  IconButton(tooltip: 'বাতিল', visualDensity: VisualDensity.compact, icon: const Icon(Icons.cancel_outlined, color: Colors.red), onPressed: () => _reviewTransaction(docs[index].id, false)),
                ]),
              ])),
            onTap: () async {
              final path = data['receiptStoragePath'] as String?;
              if (path == null || path.isEmpty) return;
              try {
                final bytes = await widget.service.receiptBytes(path);
                if (context.mounted) {
                  showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('রসিদের ছবি'),
                      content: Image.memory(bytes, errorBuilder: (_, __, ___) =>
                          const Text('ছবিটি দেখানো যাচ্ছে না।')),
                      actions: [TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('বন্ধ করুন'),
                      )],
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('রসিদ খোলা যায়নি: $e')));
              }
            },
          ),
        );
      },
    );
  }
}

class AddTransactionDialog extends StatefulWidget {
  const AddTransactionDialog({super.key, required this.messId, required this.service});
  final String? messId;
  final AccountingService service;
  @override
  State<AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<AddTransactionDialog> {
  final _amount = TextEditingController();
  final _category = TextEditingController(text: 'বাজার');
  final _description = TextEditingController();
  String _kind = 'messExpense';
  bool _personal = false;
  bool _busy = false;
  File? _receipt;
  String? _error;
  bool _mealEligible = false;
  bool _isMessOwner = false;
  String _splitStrategy = 'equal';
  Future<List<Map<String, String>>>? _membersFuture;
  final Map<String, TextEditingController> _allocationControllers = {};
  @override
  void initState() { super.initState(); if (widget.messId != null) _membersFuture = _loadMembers(); }
  Future<List<Map<String, String>>> _loadMembers() async {
    final snapshot = await FirebaseFirestore.instance.collection('messes').doc(widget.messId).get();
    final configuredSplit = snapshot.data()?['defaultSplitStrategy'] as String?;
    final owner = await widget.service.isMessOwner(widget.messId!);
    if (mounted) setState(() { _isMessOwner = owner; if (configuredSplit != null && {'equal', 'meals', 'payer'}.contains(configuredSplit)) _splitStrategy = configuredSplit; });
    final uids = (snapshot.data()?['memberUids'] as List<dynamic>? ?? const []).whereType<String>().toList()..sort();
    final profiles = await widget.service.getMemberProfiles(widget.messId!, uids);
    return uids.map((uid) { final name = (profiles[uid]?['displayName'] as String? ?? '').trim(); return {'uid': uid, 'name': name.isEmpty ? uid : name}; }).toList();
  }
  Future<void> _pickReceipt() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (image != null && mounted) setState(() => _receipt = File(image.path));
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'সঠিক টাকার পরিমাণ লিখুন।');
      return;
    }
    if (!_personal && widget.messId == null) { setState(() => _error = 'আগে একটি মেস তৈরি করুন অথবা যোগ দিন।'); return; }
    Map<String, int>? allocations; Map<String, int>? splitWeights;
    if (!_personal && (_kind == 'messExpense' || _kind == 'memberPaidExpense')) {
      if (_splitStrategy == 'fixed') { allocations = {}; for (final entry in _allocationControllers.entries) { final value = entry.value.text.trim().isEmpty ? 0 : double.tryParse(entry.value.text.trim()); if (value == null || value < 0) { setState(() => _error = 'প্রতিটি সদস্যের জন্য সঠিক টাকার অঙ্ক লিখুন।'); return; } allocations[entry.key] = (value * 100).round(); } if (allocations.values.fold<int>(0, (total, value) => total + value) != (amount * 100).round()) { setState(() => _error = 'সদস্যদের নির্দিষ্ট অঙ্কের যোগফল মোট খরচের সমান হতে হবে।'); return; } }
      else if (_splitStrategy == 'percentage') { splitWeights = {}; for (final entry in _allocationControllers.entries) { final value = entry.value.text.trim().isEmpty ? 0 : double.tryParse(entry.value.text.trim()); if (value == null || value < 0 || value > 100) { setState(() => _error = 'প্রতিটি সদস্যের শতাংশ ০ থেকে ১০০-এর মধ্যে দিন।'); return; } splitWeights[entry.key] = (value * 100).round(); } if (splitWeights.values.fold<int>(0, (total, value) => total + value) != 10000) { setState(() => _error = 'শতাংশের যোগফল ঠিক ১০০% হতে হবে।'); return; } }
    }
    setState(() { _busy = true; _error = null; });
    try {
      String? receiptPath;
      if (_receipt != null) {
        receiptPath = await widget.service.uploadReceipt(
          _receipt!, scope: _personal ? 'personal' : 'mess',
          messId: _personal ? null : widget.messId,
        );
      }
      final minor = (amount * 100).round();
      if (_personal) {
        await widget.service.addPersonalTransaction(
          kind: _kind == 'deposit' ? 'income' : 'expense',
          amountMinor: minor,
          category: _category.text,
          description: _description.text,
          transactionDate: DateTime.now(),
          receiptPath: receiptPath,
        );
      } else {
        await widget.service.addMessTransaction(
          messId: widget.messId!,
          kind: _kind,
          amountMinor: minor,
          category: _category.text,
          description: _description.text,
          transactionDate: DateTime.now(),
          receiptPath: receiptPath,
          mealEligible: _mealEligible,
          splitStrategy: (_kind == 'messExpense' || _kind == 'memberPaidExpense') ? _splitStrategy : null,
          allocations: allocations,
          splitWeights: splitWeights,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() { _amount.dispose(); _category.dispose(); _description.dispose(); for (final controller in _allocationControllers.values) { controller.dispose(); } super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('নতুন হিসাব'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ব্যক্তিগত হিসাব'),
              value: _personal,
              onChanged: (value) => setState(() { _personal = value; _kind = value ? 'expense' : 'messExpense'; }),
            ),
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'ধরন'),
              items: (_personal
                  ? const {'expense': 'ব্যক্তিগত খরচ', 'deposit': 'ব্যক্তিগত আয়'}
                  : const {'messExpense': 'মেসের খরচ', 'memberPaidExpense': 'সদস্য নিজে খরচ করেছে', 'deposit': 'মেসে টাকা জমা'})
                  .entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
              onChanged: (value) => setState(() => _kind = value ?? 'messExpense'),
            ),
            if (!_personal && (_kind == 'messExpense' || _kind == 'memberPaidExpense')) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(initialValue: _splitStrategy, decoration: const InputDecoration(labelText: 'খরচ ভাগের নিয়ম', border: OutlineInputBorder()), items: [
                const DropdownMenuItem(value: 'equal', child: Text('সমান ভাগ')), const DropdownMenuItem(value: 'meals', child: Text('মিল অনুযায়ী')), const DropdownMenuItem(value: 'payer', child: Text('যিনি দিয়েছেন')),
                DropdownMenuItem(enabled: _isMessOwner, value: 'fixed', child: const Text('সদস্যভিত্তিক নির্দিষ্ট টাকা (ম্যানেজার)')), DropdownMenuItem(enabled: _isMessOwner, value: 'percentage', child: const Text('সদস্যভিত্তিক শতাংশ (ম্যানেজার)')),
              ], onChanged: _busy ? null : (value) => setState(() => _splitStrategy = value ?? 'equal')),
              if (_splitStrategy == 'fixed' || _splitStrategy == 'percentage') FutureBuilder<List<Map<String, String>>>(future: _membersFuture, builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator());
                if (snapshot.hasError || snapshot.data == null || snapshot.data!.isEmpty) return const Text('সদস্যদের তালিকা পাওয়া যায়নি।');
                final members = snapshot.data!; for (final member in members) { _allocationControllers.putIfAbsent(member['uid']!, () => TextEditingController()); }
                return Column(children: [const SizedBox(height: 8), for (final member in members) Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: _allocationControllers[member['uid']], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: "${member['name']} — ${_splitStrategy == 'fixed' ? 'টাকা' : 'শতাংশ'}", suffixText: _splitStrategy == 'fixed' ? '৳' : '%', border: const OutlineInputBorder()))) ]);
              }),
            ],
            const SizedBox(height: 10),
            TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'টাকার পরিমাণ (৳)', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: _category, decoration: const InputDecoration(labelText: 'ক্যাটাগরি', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: _description, decoration: const InputDecoration(labelText: 'বিবরণ (ঐচ্ছিক)', border: OutlineInputBorder())),
            if (!_personal && (_kind == 'messExpense' || _kind == 'memberPaidExpense'))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _mealEligible,
                onChanged: (value) => setState(() => _mealEligible = value ?? false),
                title: const Text('মিলের রেটের হিসাবে ধরুন'),
                subtitle: const Text('খাবার/বাজারের যোগ্য খরচ হলে টিক দিন'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _busy ? null : _pickReceipt,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(_receipt == null ? 'রসিদের ছবি যোগ করুন' : 'ছবি নির্বাচন করা হয়েছে')),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('বাতিল')),
          FilledButton(onPressed: _busy ? null : _save, child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator()) : const Text('সংরক্ষণ')),
        ],
      );
}
