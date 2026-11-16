// Build-time settings. Pass with --dart-define, e.g.
//   flutter run -d chrome --web-port 6003 --dart-define=USE_MOCK=true
//   flutter build web --release --base-href /console/
//
// Which backend the console talks to (same rules as Asha_Frontend's
// ApiService.baseUrl, so both apps always hit the same Django):
//   1. --dart-define=API_BASE_URL=...            always wins
//   2. served under /console/ (Caddy tunnel, GCP Nginx, local Caddy :5500)
//                                                → the page's own origin
//   3. opened from localhost (flutter run)       → http://localhost:8000
//   4. otherwise                                 → _committedBaseUrl

import 'package:flutter/foundation.dart' show kIsWeb;

abstract final class AppConfig {
  // Flip like Asha_Frontend when deploying (only one uncommented):
  // static const String _committedBaseUrl = 'http://localhost:8000';
  static const String _committedBaseUrl = 'https://asha-be.amritaai.org';

  static const String _definedBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// true = in-memory sample data (no backend needed). Shows a banner.
  static const bool useMock = bool.fromEnvironment('USE_MOCK', defaultValue: false);

  /// Sign out after this long without mouse/keyboard activity (AC 1.1).
  static const Duration idleTimeout = Duration(minutes: 30);

  static String get apiBaseUrl {
    final defined = _strip(_definedBaseUrl);
    if (defined.isNotEmpty) return defined;
    if (kIsWeb) {
      final page = Uri.base;
      // Same door as the API (Caddy / Nginx serve /console/ next to /api/).
      if (page.path.startsWith('/console')) return page.origin;
      // `flutter run` on this machine: never point a dev build at production.
      if (page.host == 'localhost' || page.host == '127.0.0.1') return 'http://localhost:8000';
    }
    return _committedBaseUrl;
  }

  static String _strip(String v) => v.endsWith('/') ? v.substring(0, v.length - 1) : v;
}
