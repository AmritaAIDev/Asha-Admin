import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/console_api.dart';
import 'config.dart';

/// Who is signed in, plus the idle sign-out timer. The router listens to this.
class ConsoleSession extends ChangeNotifier {
  ConsoleSession(this.api, {this.idleTimeout = AppConfig.idleTimeout});

  final ConsoleApi api;
  final Duration idleTimeout;

  AdminUser? _user;
  bool _restoring = true;
  Timer? _idle;

  /// Set when the session ended on its own (idle, expired) so the login
  /// screen can say why.
  String? signedOutReason;

  AdminUser? get user => _user;
  bool get isSignedIn => _user != null;
  bool get restoring => _restoring;

  Future<void> restore() async {
    try {
      _user = await api.restoreSession();
    } catch (_) {
      _user = null;
    }
    _restoring = false;
    if (_user != null) _armIdle();
    notifyListeners();
  }

  Future<void> signIn(String login, String password) async {
    _user = await api.signIn(login, password);
    signedOutReason = null;
    _armIdle();
    notifyListeners();
  }

  Future<void> signOut({String? reason}) async {
    _idle?.cancel();
    _user = null;
    signedOutReason = reason;
    notifyListeners();
    await api.signOut();
  }

  /// Called on any pointer or key event.
  void touch() {
    if (_user != null) _armIdle();
  }

  /// Call when an API call fails with 401 after the automatic refresh.
  void handleAuthError(Object error) {
    if (error is ApiException && error.isAuth && _user != null) {
      signOut(reason: 'Your session has ended. Please sign in again.');
    }
  }

  void _armIdle() {
    _idle?.cancel();
    _idle = Timer(idleTimeout, () {
      signOut(reason: 'You were signed out after 30 minutes without activity.');
    });
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }
}
