import 'package:flutter/material.dart';

import '../../api/console_api.dart';
import '../../theme/console_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';

/// Sections of an organization page. The first five are the setup steps.
enum OrgSection {
  details('Details', 1),
  contacts('Contacts', 2),
  counselors('Counselors', 3),
  alerts('Alert channels', 4),
  review('Review & activate', 5),
  overview('Overview', 0),
  log('Log', 0);

  const OrgSection(this.label, this.step);
  final String label;

  /// 1–5 for setup steps, 0 otherwise.
  final int step;

  static const List<OrgSection> steps = [details, contacts, counselors, alerts, review];

  static OrgSection parse(String? v) =>
      OrgSection.values.firstWhere((s) => s.name == v, orElse: () => OrgSection.overview);

  OrgSection? get next {
    final i = steps.indexOf(this);
    return (i >= 0 && i < steps.length - 1) ? steps[i + 1] : null;
  }

  OrgSection? get previous {
    final i = steps.indexOf(this);
    return i > 0 ? steps[i - 1] : null;
  }
}

/// What a section asks the page to do after saving.
enum AfterSave { stay, next, exit }

/// Called by a section after it saved successfully.
typedef OnSaved = Future<void> Function(AfterSave after);

/// The 1–5 step bar at the top of a Draft organization.
class SetupStepper extends StatelessWidget {
  const SetupStepper({super.key, required this.current, required this.completedThrough, this.onTap});

  final OrgSection current;

  /// Steps 1..completedThrough show a tick.
  final int completedThrough;
  final void Function(OrgSection)? onTap;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Wrap(
        spacing: 28,
        runSpacing: 12,
        children: [
          for (final s in OrgSection.steps)
            _StepChip(
              section: s,
              isCurrent: s == current,
              done: s != current && s.step <= completedThrough,
              onTap: onTap == null || s.step > completedThrough + 1 ? null : () => onTap!(s),
            ),
        ],
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.section, required this.isCurrent, required this.done, this.onTap});
  final OrgSection section;
  final bool isCurrent;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget circle;
    if (done) {
      circle = const CircleAvatar(
        radius: 13,
        backgroundColor: C.primary,
        child: Icon(Icons.check, size: 15, color: Colors.white),
      );
    } else if (isCurrent) {
      circle = CircleAvatar(
        radius: 13,
        backgroundColor: C.accent,
        child: Text(
          '${section.step}',
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );
    } else {
      circle = Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: C.surfaceAlt,
          border: Border.all(color: C.borderStrong),
        ),
        child: Text('${section.step}', style: const TextStyle(color: C.ink2, fontSize: 13)),
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            circle,
            const SizedBox(width: 10),
            Text(
              section.label,
              style: TextStyle(
                fontSize: 15,
                color: isCurrent ? C.ink : C.ink2,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Footer under each section. In setup: Back/Cancel · Save draft · Save and
/// continue. On an Active or Inactive organization: Save changes.
class SectionFooter extends StatelessWidget {
  const SectionFooter({
    super.key,
    required this.setup,
    required this.onSave,
    this.onBack,
    this.backLabel = 'Back',
    this.continueLabel = 'Save and continue',
  });

  final bool setup;
  final Future<void> Function(AfterSave after) onSave;
  final VoidCallback? onBack;
  final String backLabel;
  final String continueLabel;

  @override
  Widget build(BuildContext context) {
    if (!setup) {
      return Align(
        alignment: Alignment.centerRight,
        child: BusyButton(label: 'Save changes', onPressed: () => onSave(AfterSave.stay)),
      );
    }
    return Row(
      children: [
        if (onBack != null) TextButton(onPressed: onBack, child: Text(backLabel)),
        const Spacer(),
        BusyButton(label: 'Save draft', outlined: true, onPressed: () => onSave(AfterSave.exit)),
        const SizedBox(width: 10),
        BusyButton(label: continueLabel, onPressed: () => onSave(AfterSave.next)),
      ],
    );
  }
}

/// Recipient × channel results of a test run (A8, counselor detail).
class TestResultsTable extends StatelessWidget {
  const TestResultsTable({super.key, required this.run});
  final TestRun run;

  static Widget statusText(ChannelResult? r) {
    if (r == null) return const Text('No WhatsApp number', style: Tx.body2);
    switch (r.status) {
      case DeliveryStatus.delivered:
        return const Text(
          'Delivered',
          style: TextStyle(color: C.success, fontWeight: FontWeight.w500),
        );
      case DeliveryStatus.failed:
        return Text(
          r.error == null ? 'Failed' : 'Failed: ${r.error}',
          style: const TextStyle(color: C.danger, fontWeight: FontWeight.w500),
        );
      case DeliveryStatus.retrying:
        return const Text('Retrying…', style: TextStyle(color: C.warning));
      case DeliveryStatus.queued:
      case DeliveryStatus.sent:
        return const Text('Sending…', style: Tx.body2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConsoleTable(
      minWidth: 760,
      columns: const [
        Col('Recipient', flex: 3),
        Col('Role', flex: 4),
        Col('Number', flex: 3),
        Col('SMS', flex: 2),
        Col('WhatsApp', flex: 4),
      ],
      empty: 'No recipients yet.',
      rows: [
        for (final r in run.recipients)
          [
            Text(r.name, style: Tx.body1.copyWith(fontWeight: FontWeight.w500)),
            Text(r.roleLabel, style: Tx.body1),
            Text(formatPhone(r.phone), style: Tx.body1),
            statusText(r.sms),
            statusText(r.whatsapp),
          ],
      ],
    );
  }
}

/// Explains failures in a test run in one line (A8 footnote).
String? testRunNote(TestRun run) {
  final waFailedOnly = run.recipients
      .where((r) => r.sms.status.reached && r.whatsapp?.status == DeliveryStatus.failed)
      .map((r) => r.name)
      .toList();
  final unreached = run.recipients.where((r) => !r.reached && !r.pending).map((r) => r.name).toList();
  if (unreached.isNotEmpty) {
    return '${unreached.join(', ')} got no test message. Fix the number, then send test alerts again.';
  }
  if (waFailedOnly.isNotEmpty) {
    return '${waFailedOnly.join(', ')} will still get SMS. Fix the WhatsApp number or leave it as is.';
  }
  return null;
}

Future<void> showTestRunDialog(BuildContext context, TestRun run, {String title = 'Test alerts sent'}) {
  final note = testRunNote(run);
  // A plain Dialog, not AlertDialog: AlertDialog sizes its content with
  // IntrinsicWidth, which the table's LayoutBuilder doesn't support.
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Tx.sectionTitle),
              const SizedBox(height: 6),
              const Text('Messages marked TEST. Results are saved in the delivery log.', style: Tx.body2),
              const SizedBox(height: 16),
              TestResultsTable(run: run),
              if (note != null) ...[const SizedBox(height: 12), Text(note, style: Tx.small)],
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
