import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/console_api.dart';
import '../../app/scope.dart';
import '../../theme/console_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';
import '../../widgets/log_view.dart';

/// A9 · Overview of an Active or Inactive organization.
class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key, required this.org});
  final Organization org;

  Widget _card(String title, List<Widget> children) => SectionCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Tx.cardTitle),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );

  String _person(PersonRef p) => p.mobile == null ? p.fullName : '${p.fullName} · ${formatPhone(p.mobile)}';

  @override
  Widget build(BuildContext context) {
    final cards = [
      _card('Details', [
        KeyValue('Code students enter', org.code, mono: true),
        KeyValue('Type', org.type.label),
        KeyValue('Location', org.location),
      ]),
      _card('Counselors', [
        org.primaryCounselor == null
            ? const KeyValue('Primary', 'Not assigned', valueColor: C.danger)
            : KeyValue('Primary', _person(org.primaryCounselor!)),
        for (final b in org.backupCounselors) KeyValue('Backup', _person(b)),
      ]),
      _card('High-risk contacts', [
        if (org.highRiskContacts.isEmpty) const Text('None', style: TextStyle(color: C.danger)),
        for (final c in org.highRiskContacts) KeyValue('Contact', _person(c)),
      ]),
      _card('Alert channels', [
        KeyValue('Medium risk → counselor', org.channels.medium.label),
        KeyValue('High risk → counselor + contacts', org.channels.high.label),
        const KeyValue('Low risk', 'Recorded only'),
      ]),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final cols = box.maxWidth >= 1000 ? 4 : (box.maxWidth >= 620 ? 2 : 1);
            const gap = 16.0;
            final w = (box.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final c in cards) SizedBox(width: w, child: c)],
            );
          },
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            const Expanded(child: Text('Recent alerts', style: Tx.sectionTitle)),
            LinkText('View full log', onTap: () => context.go('/organizations/${org.id}/log')),
          ],
        ),
        const SizedBox(height: 12),
        _RecentAlerts(orgId: org.id, activatedAt: org.activatedAt),
        const SizedBox(height: 24),
        InfoBanner(
          org.status == OrgStatus.active
              ? 'Deactivating stops all alerts for students linked with code ${org.code}. '
                    'Risk events are still recorded and appear in the log as skipped.'
              : 'This organization is inactive: alerts are off. Risk events are recorded and appear in the log '
                    'as skipped. Activate it again from the button above.',
        ),
      ],
    );
  }
}

class _RecentAlerts extends StatefulWidget {
  const _RecentAlerts({required this.orgId, this.activatedAt});
  final String orgId;
  final DateTime? activatedAt;

  @override
  State<_RecentAlerts> createState() => _RecentAlertsState();
}

class _RecentAlertsState extends State<_RecentAlerts> {
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    return Loader<ApiPage<LogRow>>(
      key: ValueKey(_version),
      load: () => context.api.listLog(LogFilter(organizationId: widget.orgId, range: LogRange.month)),
      builder: (context, page, _) {
        final rows = page.results.where((r) => r.level != AlertLevel.test).take(5).toList();
        if (rows.isEmpty) {
          final recent =
              widget.activatedAt != null &&
              DateTime.now().difference(widget.activatedAt!) < const Duration(hours: 1);
          return ConsoleTable(
            columns: const [
              Col('Time'),
              Col('Level'),
              Col('Student ref'),
              Col('Recipients'),
              Col('Delivery'),
            ],
            rows: const [],
            empty: recent ? 'No alerts yet. Activated just now.' : 'No alerts in the last 30 days.',
          );
        }
        return LogTable(
          rows: rows,
          showOrganization: false,
          onResend: (r) async {
            if (await resendRow(context, r) && mounted) setState(() => _version++);
          },
        );
      },
    );
  }
}
