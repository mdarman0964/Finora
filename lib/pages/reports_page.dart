import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../services/accounting_service.dart';
import '../services/balance_calculator.dart';
import '../services/report_service.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.messId});
  final String? messId;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  bool _personal = false;
  bool _busy = false;
  String? _message;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  final _reports = ReportService();

  Future<List<Map<String, dynamic>>> _fetchRows() async {
    final user = FirebaseAuth.instance.currentUser!;
    final query = _personal
        ? FirebaseFirestore.instance.collection('users').doc(user.uid).collection('personalTransactions')
        : widget.messId == null
            ? null
            : FirebaseFirestore.instance.collection('messes').doc(widget.messId).collection('transactions');
    if (query == null) return [];
    final result = await query.orderBy('transactionDate', descending: true).get();
    return result.docs.map((doc) => doc.data()).where((row) {
      if (row['status'] != null && row['status'] != 'posted') return false;
      final date = row['transactionDate'];
      if (date is! Timestamp) return false;
      final value = date.toDate();
      return value.year == _selectedMonth.year && value.month == _selectedMonth.month;
    }).toList();
  }

  Future<void> _closeSelectedMonth() async {
    if (_personal || widget.messId == null) {
      setState(() => _message = 'মেসের মাস বন্ধ করতে মেসের হিসাব নির্বাচন করুন।');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('মাসের হিসাব বন্ধ করবেন?'),
        content: Text(
          '${DateFormat('MMMM yyyy').format(_selectedMonth)} মাসের হিসাবের ব্যালেন্স snapshot সংরক্ষণ হবে। একই মাস দ্বিতীয়বার বন্ধ করা যাবে না।',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('বাতিল')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('হিসাব বন্ধ করুন')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() { _busy = true; _message = null; });
    try {
      final messRef = FirebaseFirestore.instance.collection('messes').doc(widget.messId);
      final messSnapshot = await messRef.get();
      final mess = messSnapshot.data();
      if (mess == null) throw StateError('মেসের তথ্য পাওয়া যায়নি।');
      if (mess['ownerUid'] != FirebaseAuth.instance.currentUser?.uid) {
        throw StateError('শুধু মেসের মালিক মাসের হিসাব বন্ধ করতে পারবেন।');
      }

      final transactionSnapshot = await messRef.collection('transactions').get();
      final mealSnapshot = await messRef.collection('meals').get();
      final selectedKey = '${_selectedMonth.year.toString().padLeft(4, '0')}-${_selectedMonth.month.toString().padLeft(2, '0')}';
      final cutoff = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
      final allThroughMonth = transactionSnapshot.docs.map((doc) => doc.data()).where((row) {
        final date = row['transactionDate'];
        return date is Timestamp && date.toDate().isBefore(cutoff);
      }).toList();
      final mealsThroughMonth = mealSnapshot.docs.map((doc) => doc.data()).where((row) {
        final dateKey = row['dateKey'] as String? ?? '';
        return dateKey.compareTo(selectedKey) <= 0;
      }).toList();
      final memberUids = (mess['memberUids'] as List<dynamic>? ?? const []).whereType<String>().toList();
      final balances = BalanceCalculator.calculate(
        memberUids: memberUids,
        transactions: allThroughMonth,
        meals: mealsThroughMonth,
      );
      final selectedTransactions = allThroughMonth.where((row) {
        final date = row['transactionDate'] as Timestamp;
        final value = date.toDate();
        return value.year == _selectedMonth.year && value.month == _selectedMonth.month
            && (row['status'] == null || row['status'] == 'posted');
      }).toList();
      var totalMeals = 0;
      for (final row in mealsThroughMonth) {
        if ((row['dateKey'] as String? ?? '').startsWith(selectedKey)) {
          totalMeals += (row['count'] as num?)?.toInt() ?? 0;
        }
      }
      var eligibleExpense = 0;
      var income = 0;
      var expense = 0;
      for (final row in selectedTransactions) {
        final amount = (row['amountMinor'] as num?)?.toInt() ?? 0;
        final kind = row['kind'] as String? ?? '';
        if (kind == 'deposit' || kind == 'income') {
          income += amount;
        } else if (kind == 'messExpense' || kind == 'memberPaidExpense') {
          expense += amount;
          if (row['mealEligible'] == true) eligibleExpense += amount;
        }
      }
      await AccountingService().closeMessMonth(
        messId: widget.messId!,
        month: _selectedMonth,
        balanceSnapshot: balances,
        totalMeals: totalMeals,
        mealEligibleExpenseMinor: eligibleExpense,
        incomeMinor: income,
        expenseMinor: expense,
      );
      if (mounted) setState(() => _message = '$selectedKey মাসের closing balance সংরক্ষণ হয়েছে। পরবর্তী মাসের ব্যালেন্সে এই snapshot থেকে carry-forward করা হবে।');
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(bool excel) async {
    setState(() { _busy = true; _message = null; });
    try {
      final rows = await _fetchRows();
      if (rows.isEmpty) throw StateError('রিপোর্টে কোনো হিসাব নেই।');
      final monthSuffix = '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';
      final title = '${_personal ? 'personal-finance-report' : 'mess-ledger-report'}-$monthSuffix';
      final file = excel
          ? await _reports.exportExcel(rows, title: title)
          : await _reports.exportPdf(rows, title: title);
      await _reports.shareFile(file);
      setState(() => _message = 'রিপোর্ট তৈরি হয়েছে: ${file.path.split('/').last}');
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text('রিপোর্ট এক্সপোর্ট', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('লেনদেন থেকে PDF বা Excel (.xlsx) রিপোর্ট তৈরি করে শেয়ার করুন।'),
          const SizedBox(height: 18),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('মেসের হিসাব')),
              ButtonSegment(value: true, label: Text('ব্যক্তিগত হিসাব')),
            ],
            selected: {_personal},
            onSelectionChanged: (values) => setState(() => _personal = values.first),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<DateTime>(
            initialValue: _selectedMonth,
            decoration: const InputDecoration(labelText: 'রিপোর্টের মাস', border: OutlineInputBorder()),
            items: List.generate(12, (index) {
              final now = DateTime.now();
              final month = DateTime(now.year, now.month - index);
              return DropdownMenuItem(value: month, child: Text(DateFormat('MMMM yyyy').format(month)));
            }),
            onChanged: _busy ? null : (value) { if (value != null) setState(() => _selectedMonth = value); },
          ),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: _busy ? null : () => _export(false), icon: const Icon(Icons.picture_as_pdf), label: const Text('PDF তৈরি করুন')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _busy ? null : () => _export(true), icon: const Icon(Icons.table_chart), label: const Text('Excel (.xlsx) তৈরি করুন')),
          if (!_personal && widget.messId != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _closeSelectedMonth,
              icon: const Icon(Icons.lock_clock_outlined),
              label: const Text('নির্বাচিত মাস বন্ধ ও carry-forward'),
            ),
          ],
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (_message != null) SelectableText(_message!),
          const SizedBox(height: 18),
          const Card(child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('রিপোর্টে লেনদেনের তালিকা থাকে'),
            subtitle: Text('রিপোর্টে নির্বাচিত মাসের অনুমোদিত লেনদেন, মোট আয় ও মোট খরচ থাকবে।'),
          )),
        ],
      );
}
