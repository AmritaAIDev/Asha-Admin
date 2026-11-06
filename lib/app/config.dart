// Build-time settings. Pass with --dart-define, e.g.
//   flutter run -d chrome --dart-define=USE_MOCK=true
//   flutter build web --dart-define=API_BASE_URL=https://asha-be.amritaai.org

abstract final class AppConfig {
  /// Django base URL (no trailing slash). Same host as Asha_Frontend uses.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// true = in-memory sample data (no backend needed). Shows a banner.
  static const bool useMock = bool.fromEnvironment('USE_MOCK', defaultValue: false);

  /// Sign out after this long without mouse/keyboard activity (AC 1.1).
  static const Duration idleTimeout = Duration(minutes: 30);

  static String get normalizedBaseUrl =>
      apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;
}
