import 'package:flutter/material.dart';

import '../api/console_api.dart';
import '../app/scope.dart';
import '../theme/console_theme.dart';
import '../widgets/common.dart';
import '../widgets/sim_bubble.dart';

/// Message simulator: while SMS and WhatsApp are simulated, every alert and
/// test message lands here instead of a phone. Left: each number that got
/// something. Right: that number's messages as the phone would show them.
class SimulatorScreen extends StatefulWidget {
  const SimulatorScreen({super.key});

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen> {
  SimulatorStatus? _status;
  Object? _error;
  String? _phone; // selected number
  final List<SimMessage> _messages = []; // newest first, as loaded
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMessages = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final s = await context.api.getSimulator();
      if (!mounted) return;
      final keep = s.phones.any((p) => p.phone == _phone);
      setState(() {
        _status = s;
        _error = null;
        _phone = keep ? _phone : (s.phones.isEmpty ? null : s.phones.first.phone);
      });
      await _loadMessages(reset: true);
    } catch (e) {
      if (!mounted) return;
      context.session.handleAuthError(e);
      setState(() => _error = e);
    }
  }

  Future<void> _loadMessages({required bool reset}) async {
    final phone = _phone;
    if (phone == null) {
      setState(() => _messages.clear());
      return;
    }
    setState(() => _loadingMessages = true);
    try {
      final page = reset ? 1 : _page + 1;
      final res = await context.api.listSimMessages(phone: phone, page: page);
      if (!mounted || phone != _phone) return;
      setState(() {
        if (reset) _messages.clear();
        _messages.addAll(res.results);
        _page = page;
        _hasMore = res.hasMore;
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  void _select(String phone) {
    if (phone == _phone) return;
    setState(() => _phone = phone);
    _loadMessages(reset: true);
  }

  Future<void> _clear({String? phone}) async {
    final ok = await confirm(
      context,
      title: phone == null ? 'Clear the simulator?' : 'Clear this number?',
      message: phone == null
          ? 'Deletes every simulated message. The delivery log is not changed.'
          : 'Deletes the simulated messages for $phone. The delivery log is not changed.',
      confirmLabel: 'Clear',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      final n = await context.api.clearSimMessages(phone: phone);
      if (!mounted) return;
      showToast(context, '$n simulated message${n == 1 ? '' : 's'} deleted.');
      await _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Message simulator',
          subtitle:
              'SMS and WhatsApp are simulated until the real gateways are approved. Every alert and test '
              'message goes here instead of a phone: pick a number to see exactly what it would have received.',
          actions: [
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
            if (s != null && s.phones.isNotEmpty)
              OutlinedButton(onPressed: () => _clear(), child: const Text('Clear all')),
          ],
        ),
        const SizedBox(height: 20),
        if (_error != null)
          InfoBanner(
            errorText(_error!),
            kind: BannerKind.danger,
            action: OutlinedButton(onPressed: _refresh, child: const Text('Try again')),
          )
        else if (s == null)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          _ModeBanner(status: s),
          const SizedBox(height: 20),
          if (s.phones.isEmpty)
            const SectionCard(
              child: Text(
                'No simulated messages yet. Send a test alert from an organization or a counselor, '
                'or wait for a Medium or High alert.',
                style: Tx.body1,
              ),
            )
          else
            LayoutBuilder(
              builder: (context, box) {
                final list = _PhoneList(phones: s.phones, selected: _phone, onSelect: _select);
                final chat = _PhonePanel(
                  phone: s.phones.where((p) => p.phone == _phone).firstOrNull,
                  messages: _messages,
                  loading: _loadingMessages,
                  hasMore: _hasMore,
                  onOlder: () => _loadMessages(reset: false),
                  onClear: _phone == null ? null : () => _clear(phone: _phone),
                );
                if (box.maxWidth < 820) {
                  return Column(children: [list, const SizedBox(height: 16), chat]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 320, child: list),
                    const SizedBox(width: 20),
                    Expanded(child: chat),
                  ],
                );
              },
            ),
        ],
      ],
    );
  }
}

class _ModeBanner extends StatelessWidget {
  const _ModeBanner({required this.status});
  final SimulatorStatus status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (!s.enabled) {
      return InfoBanner(
        'The simulator is off: SMS uses “${s.smsProvider}” and WhatsApp uses “${s.whatsappProvider}”. '
        'Messages below are from earlier.',
        kind: BannerKind.warning,
      );
    }
    final parts = <String>[
      if (s.smsProvider == 'simulator' && s.whatsappProvider == 'simulator')
        'Simulation is on for SMS and WhatsApp. No real message is sent.'
      else
        'Simulation is on for ${s.smsProvider == 'simulator' ? 'SMS' : 'WhatsApp'} only.',
      if (s.failures)
        'Failure rules are on: a number ending in 0 is “not on WhatsApp”; ending in 00 also fails on SMS.',
      'Messages are kept for ${s.keepDays} days.',
    ];
    return InfoBanner(parts.join(' '));
  }
}

class _PhoneList extends StatelessWidget {
  const _PhoneList({required this.phones, required this.selected, required this.onSelect});
  final List<SimPhone> phones;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
            child: Text('${phones.length} number${phones.length == 1 ? '' : 's'}', style: Tx.label),
          ),
          for (final p in phones)
            Material(
              color: p.phone == selected ? C.surfaceAlt : Colors.transparent,
              child: InkWell(
                onTap: () => onSelect(p.phone),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      _Avatar(p.name.isEmpty ? p.phone : p.name),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name.isEmpty ? p.phone : p.name,
                              style: Tx.body1.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(p.phone, style: Tx.small),
                            if (p.organizationName.isNotEmpty)
                              Text(p.organizationName, style: Tx.small, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_shortTime(p.lastAt), style: Tx.small),
                          const SizedBox(height: 4),
                          Pill('${p.count}', bg: C.neutralBg, fg: C.neutralInk),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    final words = name.replaceAll(RegExp(r'[^A-Za-z ]'), ' ').trim().split(RegExp(r'\s+'));
    final initials = words.where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    return CircleAvatar(
      radius: 18,
      backgroundColor: C.primary,
      child: initials.isEmpty
          ? const Icon(Icons.phone_android, size: 18, color: Colors.white)
          : Text(
              initials,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
    );
  }
}

/// One number's messages, oldest at the top like a phone.
class _PhonePanel extends StatelessWidget {
  const _PhonePanel({
    required this.phone,
    required this.messages,
    required this.loading,
    required this.hasMore,
    required this.onOlder,
    required this.onClear,
  });

  final SimPhone? phone;
  final List<SimMessage> messages; // newest first
  final bool loading;
  final bool hasMore;
  final VoidCallback onOlder;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final p = phone;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEFEAE2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: C.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: C.primary,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.phone_android, color: Colors.white70, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p == null ? 'Pick a number' : (p.name.isEmpty ? p.phone : p.name),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (p != null)
                        Text(
                          [
                            p.phone,
                            if (p.label.isNotEmpty) simLabelText(p.label),
                            if (p.organizationName.isNotEmpty) p.organizationName,
                          ].join(' · '),
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                    ],
                  ),
                ),
                if (onClear != null)
                  TextButton(
                    onPressed: onClear,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasMore)
                  Center(
                    child: TextButton(
                      onPressed: loading ? null : onOlder,
                      child: const Text('Show older messages'),
                    ),
                  ),
                if (loading && messages.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (messages.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No messages for this number.', style: Tx.body2, textAlign: TextAlign.center),
                  ),
                for (final m in messages.reversed) SimBubble(m),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _shortTime(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  if (t.year == now.year && t.month == now.month && t.day == now.day) return '$hh:$mm';
  return fmtDate(t);
}
