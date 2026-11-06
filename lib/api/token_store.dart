// Where the console keeps its JWTs. Separate keys from the student app
// (Asha_Frontend uses asha_access_token / asha_refresh_token), so a staff
// member who also uses the student app in the same browser never mixes the
// two sessions.

import 'package:shared_preferences/shared_preferences.dart';

abstract class TokenStore {
  Future<String?> get access;
  Future<String?> get refresh;
  Future<void> save({required String access, required String refresh});
  Future<void> clear();
}

class PrefsTokenStore implements TokenStore {
  static const _kAccess = 'asha_console_access_token';
  static const _kRefresh = 'asha_console_refresh_token';

  Future<SharedPreferences> _prefs() async {
    final p = await SharedPreferences.getInstance();
    try {
      // Another tab may have rotated the refresh token (see Asha_Frontend AuthStorage).
      await p.reload();
    } catch (_) {}
    return p;
  }

  @override
  Future<String?> get access async => (await _prefs()).getString(_kAccess);

  @override
  Future<String?> get refresh async => (await _prefs()).getString(_kRefresh);

  @override
  Future<void> save({required String access, required String refresh}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAccess, access);
    await p.setString(_kRefresh, refresh);
  }

  @override
  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kAccess);
    await p.remove(_kRefresh);
  }
}
