import 'package:flutter/material.dart';

import '../api/console_api.dart';
import '../app/scope.dart';
import '../theme/console_theme.dart';
import '../utils/validators.dart';
import 'common.dart';

/// Status cell text for a delivery-log row (A10/A11).
(String, Color) logStatus(LogRow r, DateTime now) {
  if (r.outcome.isSkipped) return (r.outcome.label, C.ink2);
  if (r.outcome == Outcome.lowRecorded) return ('Recorded only', C.ink2);
  if (r.channels.isEmpty) return ('—', C.ink2);
  final retry = r.channels.where((c) => c.status == DeliveryStatus.retrying).firstOrNull;
  if (retry != null) {
    final mins = retry.nextRetryAt?.difference(now).inMinutes.clamp(1, 60);
    return (mins == null ? 'Retrying' : 'Retrying · next in $mins min', C.warning);
  }
  final failed = r.channels.where((c) => c.status == DeliveryStatus.failed).toList();
  final delivered = r.channels.where((c) => c.status == DeliveryStatus.delivered).toList();
  final suffix = r.resolved ? ' · resent' : '';
  if (failed.length == r.channels.length) {
    if (r.channels.length > 1) {
      return ('Failed on ${r.channels.length == 2 ? 'both' : 'all'}$suffix', C.danger);
    }
    final err = failed.first.error;
    return (err == null ? 'Failed$suffix' : 'Failed · $err$suffix', C.danger);
  }
  if (failed.isNotEmpty) {
    return (
      '${delivered.map((c) => c.channel.label).join(' + ')} delivered · '
          '${failed.map((c) => c.channel.label).join(' + ')} failed',
      C.warning,
    );
  }
  if (delivered.length == r.channels.length) return ('Delivered', C.success);
  return ('Sending…', C.ink2);
}

/// Delivery log table with filters handled by the caller.
class LogTable extends StatelessWidget {
  const LogTable({super.key, required this.rows, required this.onResend, this.showOrganization = true});

  final List<LogRow> rows;
  final Future<void> Function(LogRow row) onResend;
  final bool showOrganization;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return ConsoleTable(
      minWidth: 1000,
      columns: [
        const Col('Time', flex: 3),
        const Col('Level', flex: 2),
        if (showOrganization) const Col('Organization', flex: 3),
        const Col('Student ref', flex: 2),
        const Col('Recipient', flex: 3),
        const Col('Channel', flex: 2),
        const Col('Status', flex: 4),
        const Col('Attempts', flex: 2),
      ],
      empty: 'No alerts match these filters.',
      rowColors: [for (final r in rows) r.needsAttention ? C.dangerRow : null],
      rows: [
        for (final r in rows)
          [
            Text(fmtDateTime(r.time), style: Tx.body2.copyWith(color: C.ink)),
            Align(alignment: Alignment.centerLeft, child: LevelChip(r.level)),
            if (showOrganization)
              Text(
                r.organizationName ?? 'Unrouted',
                style: Tx.body1.copyWith(color: r.organizationName == null ? C.muted : null),
              ),
            Text(r.studentRef ?? '—', style: Tx.mono),
            r.recipientName == null
                ? const Text('—', style: Tx.body1)
                : Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: r.recipientName),
                        if (r.recipientLabel != null)
                          TextSpan(
                            text: ' · ${r.recipientLabel}',
                            style: const TextStyle(color: C.muted),
                          ),
                      ],
                    ),
                    style: Tx.body1,
                  ),
            Text(r.channelsLabel, style: Tx.body1),
            Builder(
              builder: (_) {
                final (text, color) = logStatus(r, now);
                return Text(
                  text,
                  style: Tx.body1.copyWith(color: color, fontWeight: FontWeight.w500),
                );
              },
            ),
            Row(
              children: [
                Text(r.channels.isEmpty ? '0' : '${r.attempts}${r.anyFailed ? ' / 4' : ''}', style: Tx.body1),
                if (r.anyFailed && !r.resolved) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: BusyButton(
                      label: 'Resend',
                      outlined: true,
                      danger: r.needsAttention,
                      onPressed: () => onResend(r),
                    ),
                  ),
                ],
              ],
            ),
          ],
      ],
    );
  }
}

/// Asks, then re-queues every failed channel of [row] to the number on file now.
Future<bool> resendRow(BuildContext context, LogRow row) async {
  final failed = row.channels.where((c) => c.status == DeliveryStatus.failed).toList();
  final numbers = failed.map((c) => '${c.channel.label} ${formatPhone(c.phone)}').join(', ');
  final ok = await confirm(
    context,
    title: 'Resend to ${row.recipientName ?? 'recipient'}?',
    message:
        'This resends ${failed.map((c) => c.channel.label).join(' and ')} to the number on file now. '
        'Last attempt went to $numbers. If the number changed, update it on the organization’s '
        'Contacts tab or the counselor’s page first. Old rows keep the old number.',
    confirmLabel: 'Resend',
  );
  if (!ok || !context.mounted) return false;
  try {
    for (final c in failed) {
      await context.api.resendDelivery(c.deliveryId);
    }
    if (context.mounted) showToast(context, 'Resent. New rows were added to the log.');
    return true;
  } catch (e) {
    if (context.mounted) showApiError(context, e);
    return false;
  }
}
