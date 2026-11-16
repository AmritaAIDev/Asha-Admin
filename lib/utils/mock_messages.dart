// MOCK alert messages shown after "Send test alerts": random examples of what
// the organization's numbers would get. Same text layout as the backend
// (organizations/alerts/message.py). Made up in the console: never sent, never saved.
//
// Pure Dart: no Flutter imports.

import 'dart:math';

import '../models/alerts.dart';
import '../models/simulator.dart';

const _students = ['Meera S.', 'Arjun K.', 'Fathima N.', 'Rohan P.', 'Diya M.', 'Karthik R.'];

const _studentLines = [
  "I haven't slept properly in days, exams are too much.",
  'Everything feels pointless right now.',
  "I don't know who to talk to about this.",
  "My parents keep fighting and I can't focus on anything.",
  'I feel like nobody would notice if I disappeared.',
  "I've stopped going to classes this week.",
  'I just want everything to stop for a while.',
  "I can't stop crying since yesterday.",
];
const _ashaLines = [
  "Thank you for telling me. I'm here with you. Can you tell me more?",
  'That sounds really heavy. Are you safe right now?',
  "You don't have to go through this alone. Who is with you today?",
  "I'm glad you reached out. What has been the hardest part?",
  'Would you be open to talking to a counselor at your college?',
];

/// [count] random MOCK alert messages to the people in a test run [run]
/// (the organization being set up). Primary counselor: Medium or High;
/// everyone else: High (backups and contacts only get High alerts).
/// WhatsApp only for people who have a WhatsApp number.
List<SimMessage> mockMessagesForTest(TestRun run, String orgName, {int count = 5, Random? random}) {
  final rnd = random ?? Random();
  final people = run.recipients;
  if (people.isEmpty) return const [];
  final now = DateTime.now();
  return List.generate(count, (i) {
    final p = people[rnd.nextInt(people.length)];
    final role = p.roleLabel.toLowerCase();
    final label = role.startsWith('primary') ? 'primary' : (role.startsWith('backup') ? 'backup' : 'contact');
    final level = label == 'primary' && rnd.nextBool() ? AlertLevel.medium : AlertLevel.high;
    final at = now.subtract(Duration(minutes: rnd.nextInt(5)));
    return SimMessage(
      id: 'mock-$i-${rnd.nextInt(1 << 30)}',
      createdAt: at,
      channel: p.whatsapp != null && rnd.nextBool() ? Channel.whatsapp : Channel.sms,
      phone: p.phone,
      recipientName: p.name,
      recipientLabel: label,
      organizationName: orgName,
      level: level,
      text: _alertText(rnd, level, orgName, at),
      delivered: true,
    );
  });
}

String _two(int v) => v.toString().padLeft(2, '0');
String _hhmm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _alertText(Random rnd, AlertLevel level, String org, DateTime at) {
  const refChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final ref = 'ASH-${List.generate(4, (_) => refChars[rnd.nextInt(refChars.length)]).join()}';
  final student = _students[rnd.nextInt(_students.length)];
  final student1 = List.of(_studentLines)..shuffle(rnd);
  final asha1 = List.of(_ashaLines)..shuffle(rnd);
  final lines = <String>[
    'Asha ${level.name.toUpperCase()} alert — $org',
    'Student: $student · Ref $ref · ${_two(at.day)} ${_months[at.month - 1]} ${at.year} ${_hhmm(at)}',
    'Last 5 messages:',
  ];
  for (var i = 0; i < 5; i++) {
    final fromStudent = i.isEven; // Student, Asha, Student, Asha, Student
    final t = at.subtract(Duration(minutes: (4 - i) * 2));
    final text = fromStudent ? student1[i ~/ 2] : asha1[i ~/ 2];
    lines.add('${i + 1}. ${fromStudent ? 'Student' : 'Asha'} ${_hhmm(t)}: $text');
  }
  lines.add('Please follow your safety SOP.');
  return lines.join('\n');
}
