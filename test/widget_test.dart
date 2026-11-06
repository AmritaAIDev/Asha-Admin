// Smoke tests for the console against the in-memory mock backend.
// Run: flutter test

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asha_admin/api/mock_console_api.dart';
import 'package:asha_admin/app/session.dart';
import 'package:asha_admin/main.dart';

Future<void> _pumpApp(WidgetTester tester, MockConsoleApi api, ConsoleSession session) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AshaAdminApp(api: api, session: session));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signed-out user lands on the login screen', (tester) async {
    final api = MockConsoleApi(latency: Duration.zero);
    final session = ConsoleSession(api);
    await session.restore();
    await _pumpApp(tester, api, session);

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Username or email'), findsOneWidget);
  });

  testWidgets('non-staff account sees the no-access message', (tester) async {
    final api = MockConsoleApi(latency: Duration.zero);
    final session = ConsoleSession(api);
    await session.restore();
    await _pumpApp(tester, api, session);

    await tester.enterText(find.byType(TextFormField).at(0), 'student');
    await tester.enterText(find.byType(TextFormField).at(1), kMockPassword);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.textContaining("doesn't have console access"), findsOneWidget);
  });

  testWidgets('staff sign-in opens the organizations list', (tester) async {
    final api = MockConsoleApi(latency: Duration.zero);
    final session = ConsoleSession(api);
    await session.restore();
    await _pumpApp(tester, api, session);

    await tester.enterText(find.byType(TextFormField).at(0), 'divya');
    await tester.enterText(find.byType(TextFormField).at(1), kMockPassword);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Organizations'), findsWidgets);
    expect(find.text('North Campus College'), findsOneWidget);
    expect(find.text('New organization'), findsOneWidget);

    // Unmount (disposes the router), then cancel the 30-minute idle timer so
    // the test doesn't end with a pending Timer.
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });
}
