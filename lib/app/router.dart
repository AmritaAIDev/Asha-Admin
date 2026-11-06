import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/counselors/counselor_detail_screen.dart';
import '../screens/counselors/counselor_form_screen.dart';
import '../screens/counselors/counselors_screen.dart';
import '../screens/delivery_log_screen.dart';
import '../screens/login_screen.dart';
import '../screens/org/org_page.dart';
import '../screens/organizations_screen.dart';
import '../widgets/shell.dart';
import 'session.dart';

/// Routes. Everything except /login needs a signed-in staff account.
GoRouter createRouter(ConsoleSession session) {
  return GoRouter(
    initialLocation: '/organizations',
    refreshListenable: session,
    redirect: (context, state) {
      final atLogin = state.matchedLocation == '/login';
      if (!session.isSignedIn) {
        if (atLogin) return null;
        final from = state.uri.toString();
        return Uri(path: '/login', queryParameters: from == '/' ? null : {'from': from}).toString();
      }
      if (atLogin) {
        final from = state.uri.queryParameters['from'];
        return (from != null && from.startsWith('/') && !from.startsWith('/login')) ? from : '/organizations';
      }
      if (state.matchedLocation == '/') return '/organizations';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/organizations'),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginScreen(from: state.uri.queryParameters['from']),
      ),
      ShellRoute(
        builder: (context, state, child) => ConsoleShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/organizations', builder: (_, _) => const OrganizationsScreen()),
          GoRoute(path: '/organizations/new', builder: (_, _) => const OrgPage()),
          GoRoute(
            path: '/organizations/:id',
            builder: (_, s) => OrgPage(orgId: s.pathParameters['id']),
          ),
          GoRoute(
            path: '/organizations/:id/:section',
            builder: (_, s) => OrgPage(
              orgId: s.pathParameters['id'],
              section: s.pathParameters['section'],
              justCreatedCounselorId: s.uri.queryParameters['added'],
            ),
          ),
          GoRoute(path: '/counselors', builder: (_, _) => const CounselorsScreen()),
          GoRoute(
            path: '/counselors/new',
            builder: (_, s) => CounselorFormScreen(assignToOrgId: s.uri.queryParameters['assignTo']),
          ),
          GoRoute(
            path: '/counselors/:id',
            builder: (_, s) => CounselorDetailScreen(counselorId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/counselors/:id/edit',
            builder: (_, s) => CounselorFormScreen(counselorId: s.pathParameters['id']),
          ),
          GoRoute(
            path: '/log',
            builder: (_, s) => DeliveryLogScreen(organizationId: s.uri.queryParameters['org']),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Page not found'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/organizations'),
              child: const Text('Go to organizations'),
            ),
          ],
        ),
      ),
    ),
  );
}
