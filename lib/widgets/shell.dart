import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/config.dart';
import '../app/scope.dart';
import '../theme/console_theme.dart';

/// Green sidebar + scrolling content area, as in the console designs.
class ConsoleShell extends StatelessWidget {
  const ConsoleShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final content = Column(
      children: [
        if (AppConfig.useMock) const _MockBanner(),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20, vertical: 36),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1180), child: child),
            ),
          ),
        ),
      ],
    );

    if (wide) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 240, child: _Sidebar(location: location)),
            Expanded(child: content),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: C.sidebar,
        foregroundColor: Colors.white,
        title: const Text('Asha admin console', style: TextStyle(fontFamily: Tx.display)),
      ),
      drawer: Drawer(
        backgroundColor: C.sidebar,
        child: _Sidebar(location: location, inDrawer: true),
      ),
      body: content,
    );
  }
}

class _MockBanner extends StatelessWidget {
  const _MockBanner();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: C.warningBg,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: const Text(
      'Sample data mode (USE_MOCK=true). Nothing is saved or sent; reload resets everything.',
      style: TextStyle(color: C.mediumInk, fontSize: 13, fontWeight: FontWeight.w500),
    ),
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.location, this.inDrawer = false});
  final String location;
  final bool inDrawer;

  @override
  Widget build(BuildContext context) {
    final user = context.session.user;
    Widget item(String label, IconData icon, String path) {
      final selected = location.startsWith(path);
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: selected ? C.background : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (inDrawer) Navigator.of(context).pop();
              context.go(path);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: selected ? C.primary : Colors.white),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? C.primary : Colors.white,
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      color: C.sidebar,
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Asha', style: Tx.brand),
                SizedBox(height: 2),
                Text(
                  'ADMIN CONSOLE',
                  style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          item('Organizations', Icons.apartment_outlined, '/organizations'),
          item('Counselors', Icons.people_outline, '/counselors'),
          item('Delivery log', Icons.receipt_long_outlined, '/log'),
          const Spacer(),
          const Divider(color: Colors.white24),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Signed in as', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                const SizedBox(height: 4),
                Text(
                  user?.username ?? '—',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: () => context.session.signOut(),
                  child: const Text(
                    'Log out',
                    style: TextStyle(
                      color: Colors.white,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
