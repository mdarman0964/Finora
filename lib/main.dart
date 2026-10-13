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
  bool _english = false;

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
              english: _english,
              onToggleLanguage: () => setState(() => _english = !_english),
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
  const AuthGate({super.key, required this.onToggleTheme, required this.english, required this.onToggleLanguage});
  final VoidCallback onToggleTheme;
  final bool english;
  final VoidCallback onToggleLanguage;

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.userChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final user = snapshot.data;
          if (user == null) return const AuthPage();
          if (user.providerData.any((p) => p.providerId == 'password') && !user.emailVerified) {
            return const VerifyEmailPage();
          }
          return DashboardPage(onToggleTheme: onToggleTheme, english: english, onToggleLanguage: onToggleLanguage);
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
  bool _showPassword = false;
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
        return 'পাসওয়ার্ডে অন্তত ৮ অক্ষর, বড়/ছোট ইংরেজি অক্ষর, সংখ্যা ও বিশেষ চিহ্ন থাকতে হবে।';
      case 'invalid-email':
        return 'ইমেইল ঠিকানাটি সঠিক নয়।';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'ইমেইল বা পাসওয়ার্ড সঠিক নয়।';
      case 'network-request-failed':
        return 'ইন্টারনেট সংযোগ পরীক্ষা করে আবার চেষ্টা করুন।';
      case 'too-many-requests':
        return 'অনেকবার চেষ্টা করা হয়েছে। কিছুক্ষণ অপেক্ষা করে আবার চেষ্টা করুন।';
      case 'user-disabled':
        return 'এই অ্যাকাউন্টটি বন্ধ করা হয়েছে। অ্যাপ পরিচালকের সঙ্গে যোগাযোগ করুন।';
      default:
        return e.message ?? e.code;
    }
  }

  String? _validatePassword(String password) {
    if (password.length < 8) return 'পাসওয়ার্ড কমপক্ষে ৮ অক্ষরের হতে হবে।';
    if (!RegExp(r'[A-Z]').hasMatch(password)) return 'পাসওয়ার্ডে অন্তত একটি বড় ইংরেজি অক্ষর (A–Z) দিন।';
    if (!RegExp(r'[a-z]').hasMatch(password)) return 'পাসওয়ার্ডে অন্তত একটি ছোট ইংরেজি অক্ষর (a–z) দিন।';
    if (!RegExp(r'\d').hasMatch(password)) return 'পাসওয়ার্ডে অন্তত একটি সংখ্যা দিন।';
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) return 'পাসওয়ার্ডে অন্তত একটি বিশেষ চিহ্ন দিন (যেমন !@#)।';
    return null;
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
    if (_register) {
      final passwordError = _validatePassword(_password.text);
      if (passwordError != null) { setState(() => _error = passwordError); return; }
    } else if (_password.text.isEmpty) {
      setState(() => _error = 'পাসওয়ার্ড লিখুন.'); return;
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
        await result.user?.sendEmailVerification();
        await auth.signOut();
        if (mounted) setState(() => _error = 'অ্যাকাউন্ট তৈরি হয়েছে। লগইনের আগে ইমেইলে পাঠানো verification link খুলে ইমেইল যাচাই করুন।');
        return;
      } else {
        result = await auth.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        if (result.user != null && !result.user!.emailVerified) {
          // Avoid sending an email on every login attempt; this can trigger rate limits.
          await auth.signOut();
          if (mounted) setState(() => _error = 'আপনার ইমেইল এখনো যাচাই করা হয়নি। Inbox/Spam থেকে আগের verification link খুলুন, তারপর আবার লগইন করুন।');
          return;
        }
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
                      obscureText: !_showPassword,
                      decoration: InputDecoration(
                        labelText: _register ? 'পাসওয়ার্ড (৮+ অক্ষর, বড়/ছোট অক্ষর, সংখ্যা ও চিহ্ন)' : 'পাসওয়ার্ড',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                          icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                        ),
                      ),
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
  const DashboardPage({super.key, required this.onToggleTheme, required this.english, required this.onToggleLanguage});
  final VoidCallback onToggleTheme;
  final bool english;
  final VoidCallback onToggleLanguage;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _tab = 0;
  String? _syncedMessId;
  final _service = AccountingService();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, profileSnapshot) {
        final messId = profileSnapshot.data?.data()?['messId'] as String?;
        if (messId != null && _syncedMessId != messId) {
          _syncedMessId = messId;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            try {
              await _service.ensureCurrentMemberProfile(messId);
            } catch (_) {
              // Profile sync failures should not block the rest of the app.
            }
          });
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.english ? 'Finora' : 'Finora', style: const TextStyle(fontWeight: FontWeight.w800)),
            actions: [
              IconButton(
                onPressed: () => setState(() => _tab = 6),
                icon: const Icon(Icons.settings_outlined),
                tooltip: widget.english ? 'Settings' : 'সেটিংস',
              ),
            ],
          ),
          drawer: NavigationDrawer(
            selectedIndex: _tab,
            onDestinationSelected: (value) {
              Navigator.pop(context);
              setState(() => _tab = value);
            },
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.account_balance_wallet_rounded, size: 36),
                  const SizedBox(height: 8),
                  Text('Finora', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Text(user.displayName ?? user.email ?? 'সদস্য', maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              NavigationDrawerDestination(icon: const Icon(Icons.home_outlined), label: Text(widget.english ? 'Home & mess setup' : 'হোম ও মেস সেটআপ')),
              NavigationDrawerDestination(icon: const Icon(Icons.receipt_long_outlined), label: Text(widget.english ? 'Mess & personal ledger' : 'মেস ও ব্যক্তিগত খাতা')),
              NavigationDrawerDestination(icon: const Icon(Icons.restaurant_outlined), label: Text(widget.english ? 'Meals & meal rate' : 'মিল ও মিল রেট')),
              NavigationDrawerDestination(icon: const Icon(Icons.account_balance_wallet_outlined), label: Text(widget.english ? 'Member balances' : 'সদস্যদের ব্যালেন্স')),
              NavigationDrawerDestination(icon: const Icon(Icons.handshake_outlined), label: Text(widget.english ? 'Loans & repayments' : 'ধার-দেনা ও পরিশোধ')),
              NavigationDrawerDestination(icon: const Icon(Icons.bar_chart_outlined), label: Text(widget.english ? 'PDF / Excel reports' : 'PDF / Excel রিপোর্ট')),
              NavigationDrawerDestination(icon: const Icon(Icons.settings_outlined), label: Text(widget.english ? 'Settings' : 'সেটিংস')),
              const Divider(indent: 20, endIndent: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: Text(widget.english ? 'Change theme' : 'থিম পরিবর্তন'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onToggleTheme();
                  },
                ),
              ),

            ],
          ),
          body: IndexedStack(
            index: _tab < 7 ? _tab : 0,
            children: [
              OverviewPage(userName: user.displayName ?? 'সদস্য', messId: messId),
              LedgerPage(messId: messId, service: _service),
              MealsPage(messId: messId, service: _service),
              MemberBalancesPage(messId: messId, service: _service),
              LoansPage(service: _service),
              ReportsPage(messId: messId),
              SettingsPage(english: widget.english, onToggleLanguage: widget.onToggleLanguage, onToggleTheme: widget.onToggleTheme),
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
            selectedIndex: _tab < 6 ? _tab : 0,
            onDestinationSelected: (value) => setState(() => _tab = value),
            destinations: [
              NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: widget.english ? 'Home' : 'হোম'),
              NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: widget.english ? 'Ledger' : 'হিসাব'),
              NavigationDestination(icon: const Icon(Icons.restaurant_outlined), selectedIcon: const Icon(Icons.restaurant), label: widget.english ? 'Meals' : 'মিল'),
              NavigationDestination(icon: const Icon(Icons.account_balance_wallet_outlined), selectedIcon: const Icon(Icons.account_balance_wallet), label: widget.english ? 'Balances' : 'ব্যালেন্স'),
              NavigationDestination(icon: const Icon(Icons.handshake_outlined), selectedIcon: const Icon(Icons.handshake), label: widget.english ? 'Loans' : 'ধার-দেনা'),
              NavigationDestination(icon: const Icon(Icons.bar_chart_outlined), selectedIcon: const Icon(Icons.bar_chart), label: widget.english ? 'Reports' : 'রিপোর্ট'),
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


class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key});
  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}
class _VerifyEmailPageState extends State<VerifyEmailPage> {
  bool _busy = false;
  String? _message;
  DateTime? _lastResendAt;

  Future<void> _checkVerification() async {
    setState(() { _busy = true; _message = null; });
    try {
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _message = 'আপনি লগইন অবস্থায় নেই। ইমেইল যাচাই করার পর আবার লগইন করুন।');
        return;
      }
      await user.reload();
      final refreshedUser = auth.currentUser;
      if (refreshedUser?.emailVerified == true) {
        await refreshedUser!.getIdToken(true);
        if (mounted) setState(() => _message = 'ইমেইল যাচাই সফল হয়েছে। অ্যাপ আপডেট হচ্ছে…');
      } else {
        if (mounted) setState(() => _message = 'এখনো verification status পাওয়া যায়নি। ইমেইলের লিঙ্কে ক্লিক করে কয়েক সেকেন্ড পর আবার চেষ্টা করুন।');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _message = e.code == 'too-many-requests'
            ? 'Firebase সাময়িকভাবে চেষ্টা সীমিত করেছে। কিছুক্ষণ অপেক্ষা করে আবার চেষ্টা করুন।'
            : 'Verification status পরীক্ষা করা যায়নি (${e.code})। ইন্টারনেট পরীক্ষা করে আবার চেষ্টা করুন।');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _message = 'নিরাপত্তার জন্য আগে লগইন করুন, তারপর verification link আবার পাঠাতে পারবেন।');
      return;
    }
    final last = _lastResendAt;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 60)) {
      final remaining = 60 - DateTime.now().difference(last).inSeconds;
      setState(() => _message = 'আবার ইমেইল পাঠানোর আগে $remaining সেকেন্ড অপেক্ষা করুন।');
      return;
    }
    setState(() { _busy = true; _message = null; });
    try {
      await user.sendEmailVerification();
      _lastResendAt = DateTime.now();
      if (mounted) setState(() => _message = 'নতুন verification link পাঠানো হয়েছে। Inbox ও Spam ফোল্ডার দেখুন।');
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _message = e.code == 'too-many-requests'
            ? 'Firebase সাময়িকভাবে চেষ্টা সীমিত করেছে। কিছুক্ষণ অপেক্ষা করে আবার চেষ্টা করুন।'
            : 'Verification email পাঠানো যায়নি (${e.code})।');
      }
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ইমেইল যাচাই')),
    body: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.mark_email_unread_outlined, size: 58),
          const SizedBox(height: 16),
          const Text('আপনার ইমেইলে পাঠানো verification link খুলুন। যাচাই করার পর নিচের বাটনে চাপ দিয়ে status refresh করুন।', textAlign: TextAlign.center),
          if (_message != null) ...[const SizedBox(height: 12), Text(_message!, textAlign: TextAlign.center)],
          const SizedBox(height: 18),
          FilledButton(onPressed: _busy ? null : _checkVerification, child: Text(_busy ? 'পরীক্ষা করা হচ্ছে…' : 'আমি ইমেইল যাচাই করেছি')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _busy ? null : _resend, child: Text(_busy ? 'অপেক্ষা করুন…' : 'Verification link আবার পাঠান')),
          TextButton(onPressed: _busy ? null : () => FirebaseAuth.instance.signOut(), child: const Text('লগআউট')),
        ],
      )),
    )),
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.english, required this.onToggleLanguage, required this.onToggleTheme});
  final bool english;
  final VoidCallback onToggleLanguage;
  final VoidCallback onToggleTheme;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    Text(english ? 'Settings' : 'সেটিংস', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
    const SizedBox(height: 12),
    Card(child: ListTile(
      leading: const Icon(Icons.language_outlined),
      title: Text(english ? 'Language' : 'ভাষা'),
      subtitle: Text(english ? 'Current: English' : 'বর্তমান: বাংলা'),
      trailing: SegmentedButton<bool>(
        segments: const [ButtonSegment(value: false, label: Text('বাংলা')), ButtonSegment(value: true, label: Text('English'))],
        selected: <bool>{english},
        onSelectionChanged: (values) { if (values.first != english) onToggleLanguage(); },
      ),
    )),
    Card(child: ListTile(leading: const Icon(Icons.dark_mode_outlined), title: Text(english ? 'Appearance' : 'থিম পরিবর্তন'), subtitle: Text(english ? 'Switch light/dark theme' : 'লাইট ও ডার্ক থিম বদলান'), trailing: const Icon(Icons.chevron_right), onTap: onToggleTheme)),
    Card(child: ListTile(
      leading: const Icon(Icons.info_outline_rounded),
      title: Text(english ? 'About Finora' : 'Finora সম্পর্কে'),
      subtitle: const Text('Version 1.0.0'),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutFinoraPage())),
    )),
    Card(child: ListTile(
      leading: const Icon(Icons.logout_rounded),
      title: Text(english ? 'Exit / Sign out' : 'এক্সিট / লগআউট'),
      subtitle: Text(english ? 'Sign out of this account' : 'এই অ্যাকাউন্ট থেকে লগআউট করুন'),
      onTap: () async {
        final confirm = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
          title: Text(english ? 'Sign out?' : 'লগআউট করবেন?'),
          content: Text(english ? 'You will need to sign in again.' : 'আবার ব্যবহার করতে পুনরায় লগইন করতে হবে।'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(english ? 'Cancel' : 'বাতিল')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(english ? 'Sign out' : 'লগআউট')),
          ],
        ));
        if (confirm == true) await FirebaseAuth.instance.signOut();
      },
    )),
  ]);
}
class AboutFinoraPage extends StatelessWidget {
  const AboutFinoraPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Finora সম্পর্কে')),
    body: ListView(padding: const EdgeInsets.all(24), children: const [
      Icon(Icons.account_balance_wallet_rounded, size: 60),
      SizedBox(height: 16),
      Text('Finora', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      SizedBox(height: 8),
      Text('Mess Manager & Personal Finance'),
      SizedBox(height: 18),
      ListTile(leading: Icon(Icons.person_outline), title: Text('Developed by Md Arman')),
      ListTile(leading: Icon(Icons.email_outlined), title: Text('mdarman0964@gmail.com')),
      ListTile(leading: Icon(Icons.info_outline), title: Text('Version 1.0.0')),
    ]),
  );
}
