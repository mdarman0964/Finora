import 'package:flutter/material.dart';

void main() => runApp(const HisabKhataApp());

class HisabKhataApp extends StatefulWidget {
  const HisabKhataApp({super.key});

  @override
  State<HisabKhataApp> createState() => _HisabKhataAppState();
}

class _HisabKhataAppState extends State<HisabKhataApp> {
  ThemeMode _themeMode = ThemeMode.light;
  bool _bangla = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HisabKhata Mess Manager',
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF138A62),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F6),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF38C793),
          brightness: Brightness.dark,
        ),
      ),
      home: DashboardPage(
        bangla: _bangla,
        onLanguage: () => setState(() => _bangla = !_bangla),
        onTheme: () => setState(() {
          _themeMode =
              _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
        }),
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.bangla,
    required this.onLanguage,
    required this.onTheme,
  });

  final bool bangla;
  final VoidCallback onLanguage;
  final VoidCallback onTheme;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _tab = 0;

  String t(String bn, String en) => widget.bangla ? bn : en;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'HisabKhata',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  Text(t('মেস ম্যানেজার', 'Mess Manager'),
                      style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ),
            IconButton(
              tooltip: t('ভাষা পরিবর্তন', 'Change language'),
              onPressed: widget.onLanguage,
              icon: const Icon(Icons.translate_rounded),
            ),
            IconButton(
              tooltip: t('থিম পরিবর্তন', 'Toggle theme'),
              onPressed: widget.onTheme,
              icon: const Icon(Icons.dark_mode_outlined),
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _home(context),
          _placeholder(
            context,
            Icons.receipt_long_rounded,
            t('দৈনন্দিন হিসাব', 'Daily ledger'),
            t('মেসের জমা, খরচ ও রসিদ এখানে থাকবে।',
                'Mess deposits, expenses and receipts will appear here.'),
          ),
          _placeholder(
            context,
            Icons.bar_chart_rounded,
            t('রিপোর্ট', 'Reports'),
            t('দৈনিক, সাপ্তাহিক ও মাসিক রিপোর্ট।',
                'Daily, weekly and monthly reports.'),
          ),
          _placeholder(
            context,
            Icons.settings_rounded,
            t('সেটিংস', 'Settings'),
            t('ভাষা, থিম, গোপনীয়তা ও মেস সেটিংস।',
                'Language, theme, privacy and mess settings.'),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.space_dashboard_outlined),
            selectedIcon: const Icon(Icons.space_dashboard_rounded),
            label: t('হোম', 'Home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long_rounded),
            label: t('হিসাব', 'Ledger'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.insert_chart_outlined_rounded),
            selectedIcon: const Icon(Icons.insert_chart_rounded),
            label: t('রিপোর্ট', 'Reports'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings_rounded),
            label: t('সেটিংস', 'Settings'),
          ),
        ],
      ),
    );
  }

  Widget _home(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        Text(
          t('আসসালামু আলাইকুম 👋', 'Welcome back 👋'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          t('আজকের মেসের সারাংশ', "Today's mess overview"),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primary.withOpacity(0.78),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_rounded,
                      color: Colors.white70),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t('মেসের বর্তমান ব্যালেন্স', 'Current mess balance'),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                t('৳ ১২,৪৫০', '৳ 12,450'),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                t('ডেমো তথ্য • বাস্তব হিসাব সংযুক্ত নয়',
                    'Demo data • live accounting not connected'),
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _summary(
                context,
                Icons.trending_down_rounded,
                t('আজকের খরচ', "Today's expense"),
                t('৳ ৭০০', '৳ 700'),
                t('২টি লেনদেন', '2 transactions'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _summary(
                context,
                Icons.restaurant_rounded,
                t('আজকের মিল', "Today's meals"),
                '18',
                t('৬ জন সদস্য', '6 members'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => _addRecordSheet(context),
          icon: const Icon(Icons.add_rounded),
          label: Text(t('হিসাব যোগ করুন', 'Add record')),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          t('দ্রুত প্রবেশ', 'Quick access'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.65,
          children: [
            _quickTile(context, Icons.receipt_long_rounded,
                t('মেসের হিসাব', 'Mess ledger'), () => setState(() => _tab = 1)),
            _quickTile(context, Icons.person_rounded,
                t('ব্যক্তিগত হিসাব', 'Personal finance'),
                () => _featureMessage(context, t('ব্যক্তিগত হিসাব', 'Personal finance'))),
            _quickTile(context, Icons.restaurant_menu_rounded,
                t('মিল ম্যানেজমেন্ট', 'Meal management'),
                () => _featureMessage(context, t('মিল ম্যানেজমেন্ট', 'Meal management'))),
            _quickTile(context, Icons.handshake_rounded,
                t('ধার-দেনা', 'Loans'),
                () => _featureMessage(context, t('ধার-দেনা', 'Loans'))),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              t('সাম্প্রতিক লেনদেন', 'Recent transactions'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _tab = 1),
              child: Text(t('সব দেখুন', 'View all')),
            ),
          ],
        ),
        _transaction(
          context,
          Icons.shopping_basket_rounded,
          t('সকালের বাজার', 'Morning groceries'),
          t('আজ • আরমান', 'Today • Arman'),
          t('− ৳ ৪৫০', '− ৳ 450'),
        ),
        _transaction(
          context,
          Icons.payments_rounded,
          t('মেসে টাকা জমা', 'Mess deposit'),
          t('আজ • রহিম', 'Today • Rahim'),
          t('+ ৳ ১,০০০', '+ ৳ 1,000'),
          positive: true,
        ),
      ],
    );
  }

  Widget _summary(
    BuildContext context,
    IconData icon,
    String title,
    String value,
    String note,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            Text(title, style: theme.textTheme.bodySmall),
            const SizedBox(height: 5),
            Text(value,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(note,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ],
        ),
      ),
    );
  }

  Widget _quickTile(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 26),
              Text(label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _transaction(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    String amount, {
    bool positive = false,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(icon, color: theme.colorScheme.onSecondaryContainer),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: Text(
          amount,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: positive
                ? theme.colorScheme.primary
                : theme.colorScheme.error,
          ),
        ),
      ),
    );
  }

  Widget _placeholder(
    BuildContext context,
    IconData icon,
    String title,
    String description,
  ) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: theme.colorScheme.primary),
            const SizedBox(height: 15),
            Text(title,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              t('পরবর্তী ধাপে এই মডিউলটি তৈরি হবে।',
                  'This module will be implemented in a later phase.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  void _addRecordSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('কোন হিসাব যোগ করবেন?', 'What would you like to add?'),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _actionChoice(
              sheetContext,
              Icons.shopping_basket_rounded,
              t('মেসের খরচ', 'Mess expense'),
              t('বাজার, ভাড়া, গ্যাস ইত্যাদি', 'Groceries, rent, gas, etc.'),
            ),
            _actionChoice(
              sheetContext,
              Icons.account_balance_wallet_rounded,
              t('মেসে টাকা জমা', 'Mess deposit'),
              t('সদস্যের জমা বা অবদান', 'Member contribution'),
            ),
            _actionChoice(
              sheetContext,
              Icons.person_rounded,
              t('ব্যক্তিগত আয়-ব্যয়', 'Personal income/expense'),
              t('ডিফল্টভাবে শুধু নিজের জন্য', 'Private to you by default'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionChoice(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () {
        Navigator.pop(context);
        _featureMessage(context, title);
      },
    );
  }

  void _featureMessage(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t('$feature ফিচারটি পরবর্তী ধাপে তৈরি হবে।',
            '$feature will be implemented in a later phase.')),
      ),
    );
  }
}
