import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'firebase_options.dart';
import 'services/accounting_service.dart';
import 'services/balance_calculator.dart';
import 'services/settlement_calculator.dart';
import 'services/report_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FinoraApp());
}

class FinoraApp extends StatefulWidget {
  const FinoraApp({super.key});

  @override
  State<FinoraApp> createState() => _FinoraAppState();
}

class _FinoraAppState extends State<FinoraApp> {
  late final Future<void> _boot = _initialize();
  ThemeMode _themeMode = ThemeMode.light;

  Future<void> _initialize() async {
    if (FirebaseOptionsConfig.isConfigured) {
      await Firebase.initializeApp(options: FirebaseOptionsConfig.current);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Finora',
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF138A62)),
          scaffoldBackgroundColor: const Color(0xFFF5F7F6),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF38C793),
            brightness: Brightness.dark,
          ),
        ),
        home: FutureBuilder<void>(
          future: _boot,
          builder: (context, snapshot) {
            if (!FirebaseOptionsConfig.isConfigured || snapshot.hasError) {
              return FirebaseSetupPage(error: snapshot.error?.toString());
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            return AuthGate(
              onToggleTheme: () => setState(() {
                _themeMode = _themeMode == ThemeMode.light
                    ? ThemeMode.dark
                    : ThemeMode.light;
              }),
            );
          },
        ),
      );
}

class FirebaseSetupPage extends StatelessWidget {
  const FirebaseSetupPage({super.key, this.error});
  final String? error;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 62),
                    const SizedBox(height: 16),
                    Text('Firebase সেটআপ প্রয়োজন',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    const Text(
                      'লগইন, অনলাইন সিঙ্ক, রসিদ সংরক্ষণ এবং রিপোর্ট চালু করতে Firebase project-এর configuration যোগ করতে হবে। কোনো API key এই repository-তে hard-code করা হয়নি.',
                      textAlign: TextAlign.center,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      SelectableText(error!, style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      )),
                    ],
                    const SizedBox(height: 18),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('পরবর্তী ধাপ', style: TextStyle(fontWeight: FontWeight.bold)),
                            SizedBox(height: 8),
                            Text('1. Firebase Console-এ Android app যোগ করুন।'),
                            Text('2. Authentication-এ Email/Password চালু করুন।'),
                            Text('3. Firestore Database ও Storage তৈরি করুন।'),
                            Text('4. docs/FIREBASE_SETUP.md অনুযায়ী build secrets দিন।'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const SelectableText('https://console.firebase.google.com/'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.onToggleTheme});
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.data == null) return const AuthPage();
          return DashboardPage(onToggleTheme: onToggleTheme);
        },
      );
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      final auth = FirebaseAuth.instance;
      UserCredential result;
      if (_register) {
        result = await auth.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        await result.user?.updateDisplayName(_name.text.trim());
      } else {
        result = await auth.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      final user = result.user;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'displayName': user.displayName ?? _name.text.trim(),
          'email': user.email,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.account_balance_wallet_rounded, size: 56),
                    const SizedBox(height: 12),
                    Text('Finora', textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const Text('Mess Manager & Personal Finance', textAlign: TextAlign.center),
                    const SizedBox(height: 28),
                    if (_register) ...[
                      TextField(controller: _name, decoration: const InputDecoration(labelText: 'নাম', border: OutlineInputBorder())),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'ইমেইল', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'পাসওয়ার্ড (কমপক্ষে ৬ অক্ষর)', border: OutlineInputBorder()),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy ? const CircularProgressIndicator() : Text(_register ? 'অ্যাকাউন্ট তৈরি করুন' : 'লগইন'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => setState(() { _register = !_register; _error = null; }),
                      child: Text(_register ? 'আগে থেকেই অ্যাকাউন্ট আছে? লগইন' : 'নতুন অ্যাকাউন্ট তৈরি করুন'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.onToggleTheme});
  final VoidCallback onToggleTheme;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _tab = 0;
  final _service = AccountingService();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, profileSnapshot) {
        final messId = profileSnapshot.data?.data()?['messId'] as String?;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Finora', style: TextStyle(fontWeight: FontWeight.w800)),
            actions: [
              IconButton(
                onPressed: () => showAboutDialog(
                  context: context,
                  applicationName: 'Finora',
                  applicationVersion: '1.0.0',
                  applicationIcon: const Icon(Icons.account_balance_wallet_rounded, size: 36),
                  children: const [
                    SizedBox(height: 12),
                    Text('Developed by Md Arman'),
                    SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.email_outlined, size: 18),
                        SizedBox(width: 8),
                        Flexible(child: SelectableText('mdarman0964@gmail.com')),
                      ],
                    ),
                  ],
                ),
                icon: const Icon(Icons.info_outline_rounded),
                tooltip: 'অ্যাপ সম্পর্কে',
              ),
              IconButton(onPressed: widget.onToggleTheme, icon: const Icon(Icons.dark_mode_outlined), tooltip: 'থিম বদলান'),
              IconButton(onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout_rounded), tooltip: 'লগআউট'),
            ],
          ),
          body: IndexedStack(
            index: _tab,
            children: [
              _OverviewPage(userName: user.displayName ?? 'সদস্য', messId: messId),
              LedgerPage(messId: messId, service: _service),
              MealsPage(messId: messId, service: _service),
              MemberBalancesPage(messId: messId, service: _service),
              LoansPage(service: _service),
              ReportsPage(messId: messId),
            ],
          ),
          floatingActionButton: _tab == 1
              ? FloatingActionButton.extended(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AddTransactionDialog(messId: messId, service: _service),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('হিসাব যোগ করুন'),
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (value) => setState(() => _tab = value),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'হোম'),
              NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'হিসাব'),
              NavigationDestination(icon: Icon(Icons.restaurant_outlined), selectedIcon: Icon(Icons.restaurant), label: 'মিল'),
              NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'ব্যালেন্স'),
              NavigationDestination(icon: Icon(Icons.handshake_outlined), selectedIcon: Icon(Icons.handshake), label: 'ধার-দেনা'),
              NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'রিপোর্ট'),
            ],
          ),
        );
      },
    );
  }
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({required this.userName, required this.messId});
  final String userName;
  final String? messId;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text('স্বাগতম, $userName 👋', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          const Text('তোমার মেসের হিসাব ও ব্যক্তিগত অর্থের সারাংশ'),
          const SizedBox(height: 18),
          if (messId == null) const MessSetupCard() else MessSummaryCard(messId: messId!),
          const SizedBox(height: 14),
          const Card(child: ListTile(
            leading: Icon(Icons.lock_outline_rounded),
            title: Text('ব্যক্তিগত হিসাব ব্যক্তিগতই থাকবে'),
            subtitle: Text('ব্যক্তিগত আয়-ব্যয় অন্য মেস সদস্যদের কাছে প্রকাশ করা হয় না।'),
          )),
          const Card(child: ListTile(
            leading: Icon(Icons.sync_rounded),
            title: Text('লাইভ সিঙ্ক'),
            subtitle: Text('একই মেসের সদস্যরা অনলাইনে একই খাতা দেখতে পারবেন।'),
          )),
        ],
      );
}

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

class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key, required this.messId, required this.service});
  final String? messId;
  final AccountingService service;
  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  bool _personal = false;

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
            trailing: Text('${isIncome ? '+' : '-'}৳$amount',
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: isIncome ? Colors.green : Theme.of(context).colorScheme.error)),
            onTap: () async {
              final path = data['receiptStoragePath'] as String?;
              if (path == null || path.isEmpty) return;
              try {
                final url = await widget.service.receiptUrl(path);
                if (context.mounted) {
                  showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('রসিদের ছবি'),
                      content: Image.network(url, errorBuilder: (_, __, ___) =>
                          SelectableText(url)),
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
    if (!_personal && widget.messId == null) {
      setState(() => _error = 'আগে একটি মেস তৈরি করুন অথবা যোগ দিন।');
      return;
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
  void dispose() { _amount.dispose(); _category.dispose(); _description.dispose(); super.dispose(); }

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
                final balances = BalanceCalculator.calculate(
                  memberUids: memberUids,
                  transactions: transactionSnapshot.data!.docs.map((doc) => doc.data()).toList(),
                  meals: mealSnapshot.data!.docs.map((doc) => doc.data()).toList(),
                ).entries.toList()
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
  }
}

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
            subtitle: Text('বর্তমান সংস্করণে মাসভিত্তিক ফিল্টার ও meal-rate summary পরবর্তী ধাপে যোগ হবে।'),
          )),
        ],
      );
}
