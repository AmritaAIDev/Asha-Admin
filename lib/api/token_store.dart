// Where the console keeps its JWTs (interface only; no Flutter imports so the
// HTTP client can be exercised from plain Dart). The browser implementation
// is PrefsTokenStore in prefs_token_store.dart.

abstract class TokenStore {
  Future<String?> get access;
  Future<String?> get refresh;
  Future<void> save({required String access, required String refresh});
  Future<void> clear();
}

/// Keeps tokens in memory only (tests, scripts).
class MemoryTokenStore implements TokenStore {
  String? _access;
  String? _refresh;

  @override
  Future<String?> get access async => _access;

  @override
  Future<String?> get refresh async => _refresh;

  @override
  Future<void> save({required String access, required String refresh}) async {
    _access = access;
    _refresh = refresh;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }
}
