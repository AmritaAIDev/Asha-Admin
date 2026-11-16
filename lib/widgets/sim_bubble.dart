import 'package:flutter/material.dart';

import '../api/console_api.dart';
import '../theme/console_theme.dart';
import 'common.dart';

const _wa = Color(0xFFDCF8C6);
const _sms = Color(0xFFF1F1F1);

String simLabelText(String label) => switch (label) {
  'primary' => 'Primary counselor',
  'backup' => 'Backup counselor',
  'contact' => 'Contact',
  _ => label,
};

/// One SMS / WhatsApp message drawn like a phone bubble.
class SimBubble extends StatelessWidget {
  const SimBubble(this.m, {super.key});
  final SimMessage m;

  @override
  Widget build(BuildContext context) {
    final wa = m.channel == Channel.whatsapp;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: m.delivered ? (wa ? _wa : _sms) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: m.delivered ? null : Border.all(color: C.danger, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Pill(
                    m.channel.label,
                    bg: wa ? const Color(0xFF25D366) : C.neutralInk,
                    fg: Colors.white,
                    bold: true,
                  ),
                  LevelChip(m.level),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(m.text, style: Tx.body1.copyWith(fontSize: 14.5)),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!m.delivered) ...[
                    const Icon(Icons.error_outline, size: 15, color: C.danger),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Not delivered · ${m.error ?? 'failed'}',
                        style: Tx.small.copyWith(color: C.danger, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(fmtDateTime(m.createdAt), style: Tx.small.copyWith(color: C.muted)),
                  if (m.delivered) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.done_all, size: 15, color: Color(0xFF34B7F1)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// MOCK alert messages shown after "Send test alerts": random examples of what
/// these numbers would get. Made up in the console: not sent, not saved.
class MockMessagesSection extends StatelessWidget {
  const MockMessagesSection({super.key, required this.messages});
  final List<SimMessage> messages;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      color: C.surfaceAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Pill('MOCK', bg: C.warningBg, fg: C.warning, bold: true),
              Text('Mock alert messages', style: Tx.cardTitle),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Random examples of what these numbers would get for a Medium or High alert. '
            'This is mock data: not sent, not saved.',
            style: Tx.body2,
          ),
          for (final m in messages) ...[
            const SizedBox(height: 16),
            Text(
              'To ${m.recipientName} · ${m.phone} · ${simLabelText(m.recipientLabel)}',
              style: Tx.small.copyWith(fontWeight: FontWeight.w600),
            ),
            SimBubble(m),
          ],
        ],
      ),
    );
  }
}
