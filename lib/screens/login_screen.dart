import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/console_api.dart';
import '../app/config.dart';
import '../app/scope.dart';
import '../theme/console_theme.dart';
import '../widgets/common.dart';

/// A1 · Admin login. Staff accounts only (AC 1.1).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.from});

  /// Where to go after signing in.
  final String? from;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.session.signIn(_login.text, _password.text);
      if (!mounted) return;
      context.go(widget.from ?? '/organizations');
    } on ApiException catch (e) {
      setState(() => _error = e.detail);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _forgot() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forgot password', style: Tx.sectionTitle),
        content: const SizedBox(
          width: 420,
          child: Text(
            'Ask an Asha super-admin to reset your password. Staff passwords can’t be reset '
            'from the console yet.',
            style: Tx.body1,
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final reason = context.session.signedOutReason;
    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!wide) ...[
                  const Text(
                    'Asha',
                    style: TextStyle(
                      fontFamily: Tx.display,
                      fontSize: 30,
                      color: C.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Text(
                    'ADMIN CONSOLE',
                    style: TextStyle(color: C.ink2, letterSpacing: 1.4, fontSize: 12),
                  ),
                  const SizedBox(height: 32),
                ],
                if (AppConfig.useMock) ...[
                  const InfoBanner(
                    'Sample data mode: sign in with any username and password demo1234.',
                    kind: BannerKind.warning,
                  ),
                  const SizedBox(height: 20),
                ],
                const Text('Sign in', style: Tx.pageTitle),
                const SizedBox(height: 6),
                const Text('Use your Asha staff username or email.', style: Tx.body2),
                const SizedBox(height: 24),
                if (reason != null && _error == null) ...[InfoBanner(reason), const SizedBox(height: 16)],
                if (_error != null) ...[
                  InfoBanner(_error!, kind: BannerKind.danger),
                  const SizedBox(height: 16),
                ],
                LabeledField(
                  label: 'Username or email',
                  child: TextFormField(
                    controller: _login,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your username or email.' : null,
                  ),
                ),
                const SizedBox(height: 20),
                LabeledField(
                  label: 'Password',
                  child: TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) => (v ?? '').isEmpty ? 'Enter your password.' : null,
                    decoration: InputDecoration(
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: LinkText('Forgot password?', onTap: _forgot),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Sign in'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'After 5 wrong attempts sign-in is paused for 15 minutes. '
                  'You’ll be signed out after 30 minutes without activity.',
                  style: Tx.small,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Container(
              width: 420,
              color: C.sidebar,
              padding: const EdgeInsets.fromLTRB(56, 64, 56, 56),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Asha',
                    style: TextStyle(
                      fontFamily: Tx.display,
                      fontSize: 36,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'ADMIN CONSOLE',
                    style: TextStyle(color: Colors.white70, letterSpacing: 1.4, fontSize: 13),
                  ),
                  Spacer(),
                  Text(
                    'Make sure the right counselor hears in time.',
                    style: TextStyle(
                      fontFamily: Tx.display,
                      fontSize: 38,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Set up organizations and counselors who receive Asha’s Medium and High risk alerts '
                    'by SMS and WhatsApp.',
                    style: TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
                  ),
                  Spacer(),
                  Text(
                    'Staff accounts only. Activity in this console is logged.',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          Expanded(child: form),
        ],
      ),
    );
  }
}
