import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/console_api.dart';
import '../../app/scope.dart';
import '../../theme/console_theme.dart';
import '../../widgets/common.dart';
import 'setup_widgets.dart';

/// A8 · Step 5 Review & activate. Test messages go to every recipient; Activate
/// is enabled once each recipient got at least one channel (AC 1.9).
class ReviewStep extends StatefulWidget {
  const ReviewStep({
    super.key,
    required this.org,
    required this.setup,
    required this.onActivated,
    required this.onGoTo,
    this.onBack,
    this.onKeepDraft,
  });

  final Organization org;
  final bool setup;
  final Future<void> Function() onActivated;
  final void Function(OrgSection) onGoTo;
  final VoidCallback? onBack;
  final VoidCallback? onKeepDraft;

  @override
  State<ReviewStep> createState() => _ReviewStepState();
}

class _ReviewStepState extends State<ReviewStep> {
  Readiness? _ready;
  TestRun? _test;
  Object? _error;
  bool _sending = false;
  Timer? _poll;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = context.api;
      final results = await Future.wait([api.getReadiness(widget.org.id), api.latestOrgTest(widget.org.id)]);
      if (!mounted) return;
      setState(() {
        _ready = results[0] as Readiness;
        _test = results[1] as TestRun?;
        _error = null;
      });
      _schedulePoll();
    } catch (e) {
      if (!mounted) return;
      context.session.handleAuthError(e);
      setState(() => _error = e);
    }
  }

  /// Delivery reports arrive via provider webhooks, so poll for ~2 minutes
  /// while any message is still sending.
  void _schedulePoll() {
    _poll?.cancel();
    if (_test?.pending == true && _polls < 40) {
      _poll = Timer(const Duration(seconds: 3), () {
        _polls++;
        _load();
      });
    }
  }

  Future<void> _sendTests() async {
    setState(() => _sending = true);
    try {
      final run = await context.api.sendOrgTestAlerts(widget.org.id);
      _polls = 0;
      if (!mounted) return;
      setState(() => _test = run);
      await _load();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _activate() async {
    final ok = await confirm(
      context,
      title: 'Activate ${widget.org.name}?',
      message:
          'Students who registered with code ${widget.org.code} will trigger real alerts when '
          'Asha detects Medium or High risk.',
      confirmLabel: 'Activate',
    );
    if (!ok || !mounted) return;
    try {
      await context.api.activate(widget.org.id);
      await widget.onActivated();
    } on ApiException catch (e) {
      if (!mounted) return;
      showApiError(context, e);
      await _load();
    }
  }

  Widget _item(bool ok, String text, {OrgSection? fix}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(ok ? Icons.check : Icons.close, size: 18, color: ok ? C.success : C.danger),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: Tx.body1)),
        if (!ok && fix != null) LinkText('Fix', onTap: () => widget.onGoTo(fix)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return InfoBanner(
        errorText(_error!),
        kind: BannerKind.danger,
        action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
      );
    }
    final r = _ready;
    if (r == null) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final checklist = SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ready to activate?', style: Tx.sectionTitle),
          const SizedBox(height: 14),
          _item(r.detailsComplete, 'Details complete · code ${r.code}', fix: OrgSection.details),
          _item(
            r.highRiskContactCount > 0,
            r.highRiskContactCount > 0
                ? '${r.highRiskContactCount} contact${r.highRiskContactCount == 1 ? '' : 's'} receive${r.highRiskContactCount == 1 ? 's' : ''} High-risk alerts'
                : 'No contact receives High-risk alerts',
            fix: OrgSection.contacts,
          ),
          _item(
            r.primaryCounselorName != null,
            r.primaryCounselorName == null
                ? 'No primary counselor'
                : 'Primary counselor: ${r.primaryCounselorName}',
            fix: OrgSection.counselors,
          ),
          _item(r.channelsSet, 'Channels set for Medium and High', fix: OrgSection.alerts),
          _item(
            r.testsAllReached,
            !r.testRun
                ? 'Send test alerts (recipients changed or no test yet)'
                : (r.testsAllReached
                      ? 'Test alert reached every recipient on at least one channel'
                      : 'A recipient got no test message on any channel'),
          ),
        ],
      ),
    );

    final active = widget.org.status == OrgStatus.active;
    final explain = SectionCard(
      color: C.successBg,
      borderColor: C.successBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(active ? 'This organization is active' : 'What activating does', style: Tx.sectionTitle),
          const SizedBox(height: 12),
          Text(
            'From now on, students who registered with code ${widget.org.code} trigger real alerts when '
            'Asha detects Medium or High risk.',
            style: Tx.body1,
          ),
          const SizedBox(height: 12),
          const Text('You can deactivate it at any time from the organization page.', style: Tx.body1),
        ],
      ),
    );

    final test = _test;
    final note = test == null ? null : testRunNote(test);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth < 760) return Column(children: [checklist, const SizedBox(height: 16), explain]);
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: checklist),
                  const SizedBox(width: 16),
                  Expanded(child: explain),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 28),
        SectionTitle(
          'Test alerts',
          subtitle: 'Sends a message marked TEST to every recipient. Results are saved in the delivery log.',
          trailing: OutlinedButton(
            onPressed: _sending ? null : _sendTests,
            child: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(test == null ? 'Send test alerts' : 'Send test alerts again'),
          ),
        ),
        const SizedBox(height: 16),
        if (test == null)
          const InfoBanner('No test sent yet. Send test alerts before activating.')
        else ...[
          TestResultsTable(run: test),
          const SizedBox(height: 10),
          Text('Last sent ${fmtDateTime(test.runAt)}.${note == null ? '' : ' $note'}', style: Tx.small),
        ],
        const SizedBox(height: 28),
        if (widget.org.status != OrgStatus.active)
          Row(
            children: [
              if (widget.onBack != null) TextButton(onPressed: widget.onBack, child: const Text('Back')),
              const Spacer(),
              if (widget.setup && widget.onKeepDraft != null) ...[
                OutlinedButton(onPressed: widget.onKeepDraft, child: const Text('Keep as draft')),
                const SizedBox(width: 10),
              ],
              BusyButton(
                label: 'Activate organization',
                color: C.accent,
                onPressed: r.canActivate ? _activate : null,
              ),
            ],
          ),
      ],
    );
  }
}
