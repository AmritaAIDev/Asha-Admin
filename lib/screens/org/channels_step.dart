import 'package:flutter/material.dart';

import '../../api/console_api.dart';
import '../../app/scope.dart';
import '../../theme/console_theme.dart';
import '../../widgets/common.dart';
import 'setup_widgets.dart';

/// A7 · Step 4 Alert channels: SMS, WhatsApp or both for Medium and High
/// (AC 1.8). Low is recorded only.
class ChannelsStep extends StatefulWidget {
  const ChannelsStep({super.key, required this.org, required this.setup, required this.onSaved, this.onBack});

  final Organization org;
  final bool setup;
  final OnSaved onSaved;
  final VoidCallback? onBack;

  @override
  State<ChannelsStep> createState() => _ChannelsStepState();
}

class _ChannelsStepState extends State<ChannelsStep> {
  late AlertChannels _ch = widget.org.channels;

  Future<void> _save(AfterSave after) async {
    if (!_ch.valid) {
      showToast(context, 'Choose at least one channel for Medium and for High.', error: true);
      return;
    }
    try {
      await context.api.updateChannels(widget.org.id, _ch);
      await widget.onSaved(after);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Widget _box(String label, bool value, ValueChanged<bool> onChanged) => InkWell(
    onTap: () => onChanged(!value),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
          Text(label, style: Tx.body1),
        ],
      ),
    ),
  );

  Widget _levelCard({
    required Widget chip,
    required String who,
    required Widget body,
    Color border = C.border,
    bool error = false,
  }) => Container(
    constraints: const BoxConstraints(minHeight: 220),
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: C.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: error ? C.danger : border, width: border == C.border && !error ? 1 : 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        chip,
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Who: ',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: who),
            ],
          ),
          style: Tx.body1,
        ),
        const SizedBox(height: 12),
        body,
        if (error)
          const Text('Choose at least one channel.', style: TextStyle(color: C.danger, fontSize: 13)),
      ],
    ),
  );

  Widget _preview(String level, Color bg, String channels) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$level · $channels', style: Tx.small),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Text(
            'Asha ${level.toUpperCase()} alert — ${widget.org.name}\n'
            'Student: [Student name] · Ref ASH-XXXX · [date] [time]\n'
            'Last 5 messages:\n'
            '1. Student [time]: [message]\n'
            '2. Asha [time]: [message]\n'
            '3. Student [time]: [message]\n'
            '4. Asha [time]: [message]\n'
            '5. Student [time]: [message]\n'
            'Please follow your safety SOP.',
            style: Tx.body1.copyWith(height: 1.55, fontSize: 14.5),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final o = widget.org;
    final primary = o.primaryCounselor?.fullName;
    final contacts = o.highRiskContacts.map((c) => c.fullName).join(', ');
    final mediumWho = primary == null ? 'primary counselor (not chosen yet)' : 'primary counselor ($primary)';
    final highWho = contacts.isEmpty
        ? '$mediumWho + High-risk contacts (none yet)'
        : 'primary counselor + $contacts';

    final cards = [
      _levelCard(
        chip: const Pill('Low risk', bg: C.neutralBg, fg: C.neutralInk, bold: true),
        who: 'nobody',
        body: const Text('Recorded in the system only. No notification in Phase 1.', style: Tx.body2),
      ),
      _levelCard(
        chip: const Pill('Medium risk', bg: C.mediumBg, fg: C.mediumInk, bold: true),
        who: mediumWho,
        error: !_ch.medium.any,
        body: Column(
          children: [
            _box(
              'SMS',
              _ch.medium.sms,
              (v) => setState(
                () => _ch = AlertChannels(
                  medium: _ch.medium.copyWith(sms: v),
                  high: _ch.high,
                ),
              ),
            ),
            _box(
              'WhatsApp',
              _ch.medium.whatsapp,
              (v) => setState(
                () => _ch = AlertChannels(
                  medium: _ch.medium.copyWith(whatsapp: v),
                  high: _ch.high,
                ),
              ),
            ),
          ],
        ),
      ),
      _levelCard(
        chip: const Pill('High risk', bg: C.dangerBg, fg: C.danger, bold: true),
        who: highWho,
        border: C.accent,
        error: !_ch.high.any,
        body: Column(
          children: [
            _box(
              'SMS',
              _ch.high.sms,
              (v) => setState(
                () => _ch = AlertChannels(
                  medium: _ch.medium,
                  high: _ch.high.copyWith(sms: v),
                ),
              ),
            ),
            _box(
              'WhatsApp',
              _ch.high.whatsapp,
              (v) => setState(
                () => _ch = AlertChannels(
                  medium: _ch.medium,
                  high: _ch.high.copyWith(whatsapp: v),
                ),
              ),
            ),
          ],
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          'How alerts are sent',
          subtitle:
              'Choose at least one channel for each level. Both is recommended: '
              'SMS is the fallback if WhatsApp fails.',
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth < 760) {
              return Column(
                children: [
                  for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 16), child: c),
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    Expanded(child: cards[i]),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Message preview', style: Tx.cardTitle),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, box) {
                  final previews = [
                    _preview('Medium', C.mediumBg, _ch.medium.label),
                    _preview('High', C.dangerBg, _ch.high.label),
                  ];
                  if (box.maxWidth < 760) {
                    return Column(
                      children: [
                        Row(children: [previews[0]]),
                        const SizedBox(height: 16),
                        Row(children: [previews[1]]),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [previews[0], const SizedBox(width: 16), previews[1]],
                  );
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'Medium and High alerts both include the student’s name and their last 5 messages with Asha, '
                'each cut to 120 characters. Over SMS this arrives as one long message in several parts.',
                style: Tx.small,
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        SectionFooter(setup: widget.setup, onSave: _save, onBack: widget.onBack),
      ],
    );
  }
}
