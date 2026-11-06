import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'api/console_api.dart';
import 'api/http_console_api.dart';
import 'api/mock_console_api.dart';
import 'api/token_store.dart';
import 'app/config.dart';
import 'app/router.dart';
import 'app/scope.dart';
import 'app/session.dart';
import 'theme/console_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  final ConsoleApi api = AppConfig.useMock
      ? MockConsoleApi()
      : HttpConsoleApi(baseUrl: AppConfig.normalizedBaseUrl, tokens: PrefsTokenStore());
  final session = ConsoleSession(api);
  await session.restore();

  runApp(AshaAdminApp(api: api, session: session));
}

class AshaAdminApp extends StatefulWidget {
  const AshaAdminApp({super.key, required this.api, required this.session});
  final ConsoleApi api;
  final ConsoleSession session;

  @override
  State<AshaAdminApp> createState() => _AshaAdminAppState();
}

class _AshaAdminAppState extends State<AshaAdminApp> {
  late final GoRouter _router = createRouter(widget.session);

  bool _onKey(KeyEvent _) {
    widget.session.touch();
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConsoleScope(
      api: widget.api,
      session: widget.session,
      child: MaterialApp.router(
        title: 'Asha admin console',
        debugShowCheckedModeBanner: false,
        theme: buildConsoleTheme(),
        routerConfig: _router,
        builder: (context, child) => Listener(
          // Any click, tap or scroll counts as activity for the idle sign-out.
          onPointerDown: (_) => widget.session.touch(),
          onPointerSignal: (_) => widget.session.touch(),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
