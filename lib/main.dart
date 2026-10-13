import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'services/accounting_service.dart';
import 'pages/mess_pages.dart';

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

  Future<void> _signInWithGoogle() async {
    setState(() { _busy = true; _error = null; });
    try {
      const serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
      final googleUser = await GoogleSignIn(
        scopes: const ['email'],
        serverClientId: serverClientId.isEmpty ? null : serverClientId,
      ).signIn();
      if (googleUser == null) return;
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = result.user;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'displayName': user.displayName ?? '',
          'email': user.email,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _authMessage(e));
    } catch (e) {
      setState(() => _error = 'Google লগইন করা যায়নি। Google provider ও OAuth configuration পরীক্ষা করুন।\\n$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'operation-not-allowed':
        return 'এই লগইন পদ্ধতি Firebase Console → Authentication → Sign-in method-এ চালু করুন।';
      case 'email-already-in-use':
        return 'এই ইমেইলে আগে থেকেই অ্যাকাউন্ট আছে। লগইন করুন।';
      case 'weak-password':
        return 'আরও শক্তিশালী পাসওয়ার্ড দিন (কমপক্ষে ৬ অক্ষর)।';
      case 'invalid-email':
        return 'ইমেইল ঠিকানাটি সঠিক নয়।';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'ইমেইল বা পাসওয়ার্ড সঠিক নয়।';
      case 'network-request-failed':
        return 'ইন্টারনেট সংযোগ পরীক্ষা করে আবার চেষ্টা করুন।';
      default:
        return e.message ?? e.code;
    }
  }

  Future<void> _submit() async {
    if (_register && _name.text.trim().isEmpty) {
      setState(() => _error = 'আপনার নাম লিখুন।');
      return;
    }
    if (_email.text.trim().isEmpty || !_email.text.trim().contains('@')) {
      setState(() => _error = 'সঠিক ইমেইল ঠিকানা লিখুন।');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'পাসওয়ার্ড কমপক্ষে ৬ অক্ষরের হতে হবে।');
      return;
    }
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
      setState(() => _error = _authMessage(e));
    } catch (e) {
      setState(() => _error = 'কাজটি সম্পন্ন হয়নি। Firebase configuration ও ইন্টারনেট পরীক্ষা করুন.\\n$e');
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
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _signInWithGoogle,
                      icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                      label: const Text('Google দিয়ে চালিয়ে যান'),
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
              OverviewPage(userName: user.displayName ?? 'সদস্য', messId: messId),
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

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.userName, required this.messId});
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

