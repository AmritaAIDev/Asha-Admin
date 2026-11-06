import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/console_api.dart';
import '../../app/scope.dart';
import '../../theme/console_theme.dart';
import '../../widgets/common.dart';
import '../delivery_log_screen.dart';
import 'channels_step.dart';
import 'contacts_step.dart';
import 'counselors_step.dart';
import 'details_step.dart';
import 'overview_tab.dart';
import 'review_step.dart';
import 'setup_widgets.dart';

/// /organizations/new and /organizations/:id/:section.
///
/// A Draft shows the 5-step setup (A3–A8). An Active or Inactive organization
/// shows tabs (A9): Overview, Details, Contacts, Counselors, Alert channels, Log.
class OrgPage extends StatefulWidget {
  const OrgPage({super.key, this.orgId, this.section, this.justCreatedCounselorId});

  /// Null for a new organization.
  final String? orgId;
  final String? section;
  final String? justCreatedCounselorId;

  @override
  State<OrgPage> createState() => _OrgPageState();
}

class _OrgPageState extends State<OrgPage> {
  Organization? _org;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.orgId != null) _load();
  }

  @override
  void didUpdateWidget(OrgPage old) {
    super.didUpdateWidget(old);
    if (old.orgId != widget.orgId && widget.orgId != null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final org = await context.api.getOrganization(widget.orgId!);
      if (mounted) setState(() => _org = org);
    } catch (e) {
      if (!mounted) return;
      context.session.handleAuthError(e);
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _path(OrgSection s, [String? id]) => '/organizations/${id ?? _org!.id}/${s.name}';

  void _go(OrgSection s) => context.go(_path(s));

  /// Where a Draft reopens: the step after the last one saved.
  OrgSection _resumeStep(Organization o) {
    final step = (o.setupStep + 1).clamp(1, 5);
    return OrgSection.steps[step - 1];
  }

  Future<void> _afterSave(OrgSection current, AfterSave after) async {
    final org = _org!;
    final setup = org.status == OrgStatus.draft;
    if (setup && current.step > 0) {
      try {
        await context.api.saveSetupStep(org.id, current.step);
      } catch (_) {}
    }
    if (!mounted) return;
    switch (after) {
      case AfterSave.stay:
        showToast(context, 'Saved.');
        await _load();
      case AfterSave.exit:
        showToast(context, '${org.name} saved as Draft.');
        context.go('/organizations');
      case AfterSave.next:
        await _load();
        if (mounted && current.next != null) _go(current.next!);
    }
  }

  Future<void> _deactivate() async {
    final org = _org!;
    final ok = await confirm(
      context,
      title: 'Deactivate ${org.name}?',
      message:
          'Alerts stop for every student linked with code ${org.code}. Risk events are still recorded '
          'and appear in the log as skipped. You can activate it again later.',
      confirmLabel: 'Deactivate',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await context.api.deactivate(org.id);
      if (!mounted) return;
      showToast(context, '${org.name} is inactive. Alerts are off.');
      await _load();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _sendTests() async {
    try {
      final run = await context.api.sendOrgTestAlerts(_org!.id);
      if (mounted) await showTestRunDialog(context, run);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── New organization ──
    if (widget.orgId == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: 'New organization',
            crumbs: [Crumb('Organizations', '/organizations'), Crumb('New organization')],
          ),
          const SizedBox(height: 28),
          const SetupStepper(current: OrgSection.details, completedThrough: 0),
          const SizedBox(height: 24),
          DetailsStep(
            org: null,
            setup: true,
            onSaved: (_) async {},
            onCancel: () => context.go('/organizations'),
            onCreated: (org, after) async {
              await context.api.saveSetupStep(org.id, 1);
              if (!context.mounted) return;
              if (after == AfterSave.next) {
                context.go(_path(OrgSection.contacts, org.id));
              } else {
                showToast(context, '${org.name} saved as Draft.');
                context.go('/organizations');
              }
            },
          ),
        ],
      );
    }

    if (_org == null) {
      if (_error != null) {
        return InfoBanner(
          errorText(_error!),
          kind: BannerKind.danger,
          action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
        );
      }
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final org = _org!;
    final setup = org.status == OrgStatus.draft;
    var section = OrgSection.parse(widget.section);
    if (setup && (section == OrgSection.overview || section == OrgSection.log)) {
      section = _resumeStep(org);
    }

    final header = PageHeader(
      title: org.name,
      crumbs: [const Crumb('Organizations', '/organizations'), Crumb(org.name)],
      chip: setup
          ? const Pill('Draft', bg: C.warningBg, fg: C.warning)
          : OrgStatusChip(org.status, long: true),
      actions: setup
          ? const []
          : [
              if (org.status == OrgStatus.active)
                BusyButton(label: 'Deactivate', outlined: true, danger: true, onPressed: _deactivate)
              else
                BusyButton(label: 'Activate', color: C.accent, onPressed: () async => _go(OrgSection.review)),
              BusyButton(label: 'Send test alerts', onPressed: _sendTests),
            ],
    );

    final body = KeyedSubtree(
      key: ValueKey('${org.id}-${section.name}-${org.status.name}'),
      child: _sectionBody(org, section, setup),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 24),
        if (setup)
          SetupStepper(current: section, completedThrough: org.setupStep, onTap: _go)
        else
          _Tabs(current: section, onTap: _go),
        const SizedBox(height: 24),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        body,
      ],
    );
  }

  Widget _sectionBody(Organization org, OrgSection section, bool setup) {
    VoidCallback? back(OrgSection s) => s.previous == null ? null : () => _go(s.previous!);
    switch (section) {
      case OrgSection.details:
        return DetailsStep(
          org: org,
          setup: setup,
          onSaved: (a) => _afterSave(OrgSection.details, a),
          onCreated: (_, _) async {},
          onCancel: setup ? () => context.go('/organizations') : null,
        );
      case OrgSection.contacts:
        return ContactsStep(
          org: org,
          setup: setup,
          onSaved: (a) => _afterSave(OrgSection.contacts, a),
          onBack: back(OrgSection.contacts),
        );
      case OrgSection.counselors:
        return CounselorsStep(
          org: org,
          setup: setup,
          justCreatedId: widget.justCreatedCounselorId,
          onSaved: (a) => _afterSave(OrgSection.counselors, a),
          onBack: back(OrgSection.counselors),
        );
      case OrgSection.alerts:
        return ChannelsStep(
          org: org,
          setup: setup,
          onSaved: (a) => _afterSave(OrgSection.alerts, a),
          onBack: back(OrgSection.alerts),
        );
      case OrgSection.review:
        return ReviewStep(
          org: org,
          setup: setup,
          onGoTo: _go,
          onBack: setup ? back(OrgSection.review) : () => _go(OrgSection.overview),
          onKeepDraft: () {
            showToast(context, '${org.name} kept as Draft.');
            context.go('/organizations');
          },
          onActivated: () async {
            if (!mounted) return;
            showToast(context, '${org.name} is active. Alerts are on.');
            await _load();
            if (mounted) _go(OrgSection.overview);
          },
        );
      case OrgSection.overview:
        return OverviewTab(org: org);
      case OrgSection.log:
        return DeliveryLogView(fixedOrganizationId: org.id);
    }
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.current, required this.onTap});
  final OrgSection current;
  final void Function(OrgSection) onTap;

  static const _tabs = [
    OrgSection.overview,
    OrgSection.details,
    OrgSection.contacts,
    OrgSection.counselors,
    OrgSection.alerts,
    OrgSection.log,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: C.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final t in _tabs)
              InkWell(
                onTap: () => onTap(t),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: t == current ? C.accent : Colors.transparent, width: 2.5),
                    ),
                  ),
                  child: Text(
                    t.label,
                    style: TextStyle(
                      fontSize: 15,
                      color: t == current ? C.ink : C.ink2,
                      fontWeight: t == current ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
