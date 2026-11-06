import 'package:flutter/widgets.dart';

import '../api/console_api.dart';
import 'session.dart';

/// Gives every screen the API client and the session.
class ConsoleScope extends InheritedWidget {
  const ConsoleScope({super.key, required this.api, required this.session, required super.child});

  final ConsoleApi api;
  final ConsoleSession session;

  /// Uses getInheritedWidgetOfExactType (no rebuild dependency) because the
  /// api and session never change, and so screens can call it from initState —
  /// dependOnInheritedWidgetOfExactType asserts there.
  static ConsoleScope of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ConsoleScope>();
    assert(scope != null, 'ConsoleScope missing above $context');
    return scope!;
  }

  @override
  bool updateShouldNotify(ConsoleScope oldWidget) => api != oldWidget.api || session != oldWidget.session;
}

extension ConsoleContext on BuildContext {
  ConsoleApi get api => ConsoleScope.of(this).api;
  ConsoleSession get session => ConsoleScope.of(this).session;
}
