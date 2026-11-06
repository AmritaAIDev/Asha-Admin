import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/console_api.dart';
import '../../app/scope.dart';
import '../../theme/console_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';
import '../org/setup_widgets.dart';

/// A12 · Counselor detail. Deactivating is blocked while they are the only
/// primary of an Active organization (AC 4.4).
class CounselorDetailScreen extends StatefulWidget {
  const CounselorDetailScreen({super.key, required this.counselorId});
  final String counselorId;

  @override
  State<CounselorDetailScreen> createState() => _CounselorDetailScreenState();
}

typedef _Data = ({Counselor counselor, Map<String, Organization> blockingOrgs});

class _CounselorDetailScreenState extends State<CounselorDetailScreen> {
  int _version = 0;

  void _reload() => setState(() => _version++);

  Future<_Data> _load() async {
    final api = context.api;
    final c = await api.getCounselor(widget.counselorId);
    final orgs = <String, Organization>{};
    for (final a in c.blockingAssignments) {
      try {
        orgs[a.organizationId] = await api.getOrganization(a.organizationId);
      } catch (_) {}
    }
    return (counselor: c, blockingOrgs: orgs);
  }

  @override
  Widget build(BuildContext context) {
    return Loader<_Data>(
      key: ValueKey(_version),
      load: _load,
      builder: (context, d, _) => _Body(data: d, onChanged: _reload),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.data, required this.onChanged});
  final _Data data;
  final VoidCallback onChanged;

  Counselor get c => data.counselor;

  Future<void> _sendTest(BuildContext context) async {
    try {
      final run = await context.api.sendCounselorTest(c.id);
      if (!context.mounted) return;
      await showTestRunDialog(context, run, title: 'Test message sent');
      onChanged();
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  Future<void> _setActive(BuildContext context, bool active) async {
    if (!active) {
      final ok = await confirm(
        context,
        title: 'Deactivate ${c.fullName}?',
        message: 'They will stop receiving alerts for every organization. Past log rows keep their name.',
        confirmLabel: 'Deactivate',
        danger: true,
      );
      if (!ok || !context.mounted) return;
    }
    try {
      await context.api.setCounselorActive(c.id, active);
      if (!context.mounted) return;
      showToast(context, active ? '${c.fullName} is active again.' : '${c.fullName} is inactive.');
      onChanged();
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  /// Changes this counselor's role at one organization (or adds them).
  Future<void> _assign(BuildContext context, String orgId, CounselorRole role, {bool remove = false}) async {
    final api = context.api;
    try {
      final current = await api.listOrgCounselors(orgId);
      final list = <({String counselorId, CounselorRole role})>[];
      for (final a in current) {
        if (a.counselor.id == c.id) continue;
        // Only one primary: the old primary becomes a backup.
        final r = (!remove && role == CounselorRole.primary && a.role == CounselorRole.primary)
            ? CounselorRole.backup
            : a.role;
        list.add((counselorId: a.counselor.id, role: r));
      }
      if (!remove) list.add((counselorId: c.id, role: role));
      await api.saveOrgCounselors(orgId, list);
      if (!context.mounted) return;
      showToast(context, 'Saved.');
      onChanged();
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  Future<void> _changeRole(BuildContext context, Assignment a) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${c.fullName} at ${a.organizationName}', style: Tx.sectionTitle),
        children: [
          for (final r in CounselorRole.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r.name),
              child: Text(
                r == CounselorRole.primary
                    ? 'Primary — gets Medium and High alerts${a.role == r ? ' (current)' : ''}'
                    : 'Backup — gets alerts only if the primary is inactive${a.role == r ? ' (current)' : ''}',
                style: Tx.body1,
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'remove'),
            child: const Text(
              'Remove from this organization',
              style: TextStyle(color: C.danger, fontSize: 15),
            ),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'remove') {
      await _assign(context, a.organizationId, a.role, remove: true);
    } else {
      final role = CounselorRole.parse(choice);
      if (role != a.role) await _assign(context, a.organizationId, role);
    }
  }

  Future<void> _assignNew(BuildContext context) async {
    final api = context.api;
    List<Organization> orgs;
    try {
      orgs = (await api.listOrganizations()).results;
    } catch (e) {
      if (context.mounted) showApiError(context, e);
      return;
    }
    if (!context.mounted) return;
    final taken = c.assignments.map((a) => a.organizationId).toSet();
    final options = orgs.where((o) => !taken.contains(o.id)).toList();
    if (options.isEmpty) {
      showToast(context, '${c.fullName} already serves every organization.');
      return;
    }
    String orgId = options.first.id;
    CounselorRole role = CounselorRole.backup;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Assign to organization', style: Tx.sectionTitle),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LabeledField(
                  label: 'Organization',
                  child: DropdownButtonFormField<String>(
                    initialValue: orgId,
                    isExpanded: true,
                    items: [for (final o in options) DropdownMenuItem(value: o.id, child: Text(o.name))],
                    onChanged: (v) => setD(() => orgId = v ?? orgId),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Role', style: Tx.label),
                RadioGroup<CounselorRole>(
                  groupValue: role,
                  onChanged: (v) => setD(() => role = v ?? role),
                  child: Column(
                    children: [
                      for (final r in CounselorRole.values)
                        RadioListTile<CounselorRole>(
                          value: r,
                          contentPadding: EdgeInsets.zero,
                          title: Text(r.label),
                          subtitle: r == CounselorRole.primary
                              ? const Text('The current primary, if any, becomes a backup.')
                              : null,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Assign')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) await _assign(context, orgId, role);
  }

  @override
  Widget build(BuildContext context) {
    final blocking = c.blockingAssignments;
    final lt = c.lastTest;
    String testLine() {
      if (lt == null) return 'No test sent yet';
      String s(String? v) => v == null ? '—' : DeliveryStatus.parse(v).label.toLowerCase();
      return '${fmtDate(lt.at)} · SMS ${s(lt.sms)}${lt.whatsapp == null ? '' : ' · WhatsApp ${s(lt.whatsapp)}'}';
    }

    final contactCard = SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Contact', style: Tx.cardTitle),
          const SizedBox(height: 14),
          KeyValue('Mobile (SMS)', formatPhone(c.mobile)),
          KeyValue(
            'WhatsApp',
            c.whatsapp == null
                ? 'None'
                : (c.whatsappSameAsMobile ? 'Same as mobile' : formatPhone(c.whatsapp)),
          ),
          KeyValue('Email', c.email.isEmpty ? '—' : c.email),
          KeyValue('Languages', c.languages.isEmpty ? '—' : c.languages.join(', ')),
          if (c.notes.isNotEmpty) KeyValue('Notes', c.notes),
        ],
      ),
    );
    final consentCard = SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Consent and testing', style: Tx.cardTitle),
          const SizedBox(height: 14),
          KeyValue(
            'Consent to receive alerts',
            c.hasConsent ? 'Recorded on ${fmtDate(c.consentAt)}' : 'Not recorded — can’t be assigned',
            valueColor: c.hasConsent ? C.success : C.danger,
          ),
          KeyValue('Last test message', testLine()),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: c.fullName,
          crumbs: [const Crumb('Counselors', '/counselors'), Crumb(c.fullName)],
          chip: c.isActive
              ? const Pill('Active', bg: C.successBg, fg: C.success)
              : const Pill('Inactive', bg: C.neutralBg, fg: C.neutralInk),
          actions: [
            BusyButton(label: 'Send test message', outlined: true, onPressed: () => _sendTest(context)),
            FilledButton(
              onPressed: () => context.go('/counselors/${c.id}/edit'),
              child: const Text('Edit details'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth < 760) {
              return Column(children: [contactCard, const SizedBox(height: 16), consentCard]);
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: contactCard),
                  const SizedBox(width: 16),
                  Expanded(child: consentCard),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 28),
        SectionTitle(
          'Organizations',
          trailing: OutlinedButton.icon(
            onPressed: c.canBeAssigned ? () => _assignNew(context) : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Assign to organization'),
          ),
        ),
        const SizedBox(height: 14),
        ConsoleTable(
          minWidth: 700,
          columns: const [
            Col('Organization', flex: 3),
            Col('Role', flex: 3),
            Col('Organization status', flex: 3),
            Col('', flex: 2),
          ],
          empty: c.hasConsent ? 'Not assigned to any organization.' : 'Record consent before assigning.',
          rows: [
            for (final a in c.assignments)
              [
                LinkText(a.organizationName, onTap: () => context.go('/organizations/${a.organizationId}')),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: a.role.label),
                      if (a.role == CounselorRole.primary && a.isOnlyPrimary)
                        const TextSpan(
                          text: ' (only primary)',
                          style: TextStyle(color: C.muted),
                        ),
                    ],
                  ),
                  style: Tx.body1,
                ),
                Align(alignment: Alignment.centerLeft, child: OrgStatusChip(a.organizationStatus)),
                LinkText('Change role', onTap: () => _changeRole(context, a)),
              ],
          ],
        ),
        const SizedBox(height: 28),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.isActive ? 'Deactivate counselor' : 'Reactivate counselor', style: Tx.cardTitle),
              const SizedBox(height: 14),
              if (!c.isActive) ...[
                const Text('Inactive counselors get no alerts and can’t be assigned.', style: Tx.body2),
                const SizedBox(height: 14),
                BusyButton(label: 'Reactivate', onPressed: () => _setActive(context, true)),
              ] else if (blocking.isNotEmpty) ...[
                for (final a in blocking)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InfoBanner(_blockText(a), kind: BannerKind.warning),
                  ),
                Wrap(
                  spacing: 10,
                  children: [
                    FilledButton(
                      onPressed: () =>
                          context.go('/organizations/${blocking.first.organizationId}/counselors'),
                      child: const Text('Choose a new primary'),
                    ),
                    const FilledButton(onPressed: null, child: Text('Deactivate')),
                  ],
                ),
              ] else ...[
                const Text('They will stop receiving alerts for every organization.', style: Tx.body2),
                const SizedBox(height: 14),
                BusyButton(
                  label: 'Deactivate',
                  outlined: true,
                  danger: true,
                  onPressed: () => _setActive(context, false),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _blockText(Assignment a) {
    final org = data.blockingOrgs[a.organizationId];
    final backups = org?.backupCounselors.map((b) => b.fullName).toList() ?? const <String>[];
    final suggestion = backups.isEmpty
        ? 'Assign another counselor as primary'
        : 'Make ${backups.first} (backup) primary, or assign another counselor,';
    return '${c.fullName} is the only primary counselor for ${a.organizationName}. $suggestion before deactivating.';
  }
}
