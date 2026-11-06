// Plain-Dart checks for validators, JSON models and the mock backend rules.
// Runs without Flutter:   dart run tool/check_logic.dart
// (Also safe under `flutter pub get` projects; no extra packages needed.)

import 'dart:io';

import 'package:asha_admin/api/console_api.dart';
import 'package:asha_admin/api/mock_console_api.dart';
import 'package:asha_admin/utils/validators.dart';

int _failures = 0;
int _passes = 0;

void check(bool ok, String what) {
  if (ok) {
    _passes++;
  } else {
    _failures++;
    stderr.writeln('FAIL: $what');
  }
}

Future<ApiException?> expectError(Future<Object?> f) async {
  try {
    await f;
    return null;
  } on ApiException catch (e) {
    return e;
  }
}

Future<void> main() async {
  // ── Validators ──
  check(normalizeMobile('+91 98450 67890') == '+919845067890', 'mobile with +91 and spaces');
  check(normalizeMobile('098450-67890') == '+919845067890', 'mobile with leading 0');
  check(normalizeMobile('919845067890') == '+919845067890', 'mobile with 91');
  check(normalizeMobile('98450 6789') == null, '9 digits rejected');
  check(normalizeMobile('5845067890') == null, 'must start 6-9');
  check(normalizeMobile('984506789012') == null, '12 digits not starting 91 rejected');
  check(normalizeMobile('+1 9845067890') == null, 'non-+91 country code rejected');
  check(formatPhone('+919845067890') == '+91 98450 67890', 'formatPhone');
  check(validateOrgCode('cni-blr') == null, 'lowercase code ok after uppercasing');
  check(validateOrgCode('AB') != null, 'code too short');
  check(validateOrgCode('ABCDEFGHIJKLM') != null, 'code too long');
  check(validateOrgCode('CNI BLR') != null, 'space rejected');
  check(validateEmail('') == null, 'empty email ok');
  check(validateEmail('a@b') != null, 'bad email');
  check(validateEmail('priya.r@college.edu') == null, 'good email');

  // ── JSON round trips ──
  final api = MockConsoleApi(latency: Duration.zero);
  final orgs = await api.listOrganizations();
  check(orgs.count == 3, 'seeded 3 orgs');
  for (final o in orgs.results) {
    final back = Organization.fromJson(o.toJson());
    check(back.code == o.code && back.status == o.status, 'org round trip ${o.code}');
    check(back.primaryCounselor?.fullName == o.primaryCounselor?.fullName, 'primary round trip');
  }
  final rows = await api.listLog(const LogFilter(range: LogRange.all));
  for (final r in rows.results) {
    final back = LogRow.fromJson(r.toJson());
    check(
      back.outcome == r.outcome && back.channels.length == r.channels.length,
      'log row round trip ${r.id}',
    );
  }
  final err = ApiException.fromBody(400, {
    'detail': 'x',
    'code': 'validation_error',
    'errors': {
      'code': ['taken'],
    },
    'missing': ['primary_counselor'],
  });
  check(err.fieldError('code') == 'taken' && err.extra['missing'] is List, 'ApiException parse');

  // ── Auth ──
  check((await expectError(api.signIn('divya', 'wrong')))?.code == 'invalid_credentials', 'bad password');
  check((await expectError(api.signIn('student', kMockPassword)))?.code == 'not_staff', 'non-staff');
  final user = await api.signIn('divya@asha.org', kMockPassword);
  check(user.isStaff && user.username == 'divya', 'staff sign in');
  for (var i = 0; i < 5; i++) {
    await expectError(api.signIn('x', 'nope'));
  }
  check(
    (await expectError(api.signIn('divya', kMockPassword)))?.code == 'login_locked',
    'locked after 5 wrong passwords',
  );

  // ── Storyboard B: create City Nursing Institute ──
  final api2 = MockConsoleApi(latency: Duration.zero);
  final dup = await expectError(
    api2.createOrganization(
      const OrgDetailsInput(
        name: 'City Nursing Institute',
        code: 'ncc-01',
        type: OrgType.college,
        city: 'Bengaluru',
        state: 'Karnataka',
      ),
    ),
  );
  check(
    dup?.fieldError('code') == 'NCC-01 is already used by North Campus College.',
    'duplicate code message',
  );
  final cni = await api2.createOrganization(
    const OrgDetailsInput(
      name: 'City Nursing Institute',
      code: 'cni-blr',
      type: OrgType.college,
      city: 'Bengaluru',
      state: 'Karnataka',
    ),
  );
  check(cni.status == OrgStatus.draft && cni.code == 'CNI-BLR', 'created as Draft, code uppercased');

  final badContact = await expectError(
    api2.saveContacts(cni.id, const [
      OrgContact(fullName: 'Meera Shetty', title: 'Student welfare officer', mobile: '98450 6789'),
    ]),
  );
  check(badContact?.fieldError('contacts.0.mobile') == mobileError, 'contact mobile error keyed by index');

  await api2.saveContacts(cni.id, const [
    OrgContact(
      fullName: 'Dr. Kavya Rao',
      title: 'Principal',
      mobile: '+91 98450 67890',
      whatsapp: '+91 98450 67890',
      receivesHighAlerts: true,
    ),
    OrgContact(fullName: 'Meera Shetty', title: 'Student welfare officer', mobile: '98450 67891'),
  ]);

  final all = (await api2.listCounselors()).results;
  final rahul = all.firstWhere((c) => c.fullName == 'Rahul Iyer');
  final priya = all.firstWhere((c) => c.fullName == 'Priya Raghavan');
  final prithvi = all.firstWhere((c) => c.fullName == 'Prithvi Gowda');
  check(!prithvi.hasConsent, 'Prithvi has no consent');
  check(
    (await expectError(
          api2.saveOrgCounselors(cni.id, [(counselorId: prithvi.id, role: CounselorRole.backup)]),
        ))?.code ==
        'consent_missing',
    'no-consent counselor cannot be assigned',
  );
  check(
    (await expectError(
          api2.saveOrgCounselors(cni.id, [
            (counselorId: rahul.id, role: CounselorRole.primary),
            (counselorId: priya.id, role: CounselorRole.primary),
          ]),
        ))?.code ==
        'one_primary',
    'two primaries rejected',
  );
  await api2.saveOrgCounselors(cni.id, [
    (counselorId: rahul.id, role: CounselorRole.primary),
    (counselorId: priya.id, role: CounselorRole.backup),
  ]);

  var ready = await api2.getReadiness(cni.id);
  check(
    ready.missing.contains('test_alerts') && !ready.missing.contains('primary_counselor'),
    'readiness only missing test',
  );
  check((await expectError(api2.activate(cni.id)))?.code == 'not_ready', 'activate blocked before test');

  final run = await api2.sendOrgTestAlerts(cni.id);
  check(run.recipients.length == 3, 'test goes to primary, backup and High-risk contact');
  final kavya = run.recipients.firstWhere((r) => r.name == 'Dr. Kavya Rao');
  check(
    kavya.sms.status == DeliveryStatus.delivered && kavya.whatsapp?.status == DeliveryStatus.failed,
    'Kavya: SMS delivered, WhatsApp failed (number ends in 0)',
  );
  check(run.allReached, 'every recipient reached on at least one channel');
  ready = await api2.getReadiness(cni.id);
  check(ready.canActivate, 'ready after test');
  final active = await api2.activate(cni.id);
  check(active.status == OrgStatus.active, 'activated');

  // Changing recipients makes the old test stale.
  final noHigh = await expectError(
    api2.saveContacts(cni.id, const [
      OrgContact(fullName: 'Dr. Kavya Rao', title: 'Principal', mobile: '+919845067890'),
    ]),
  );
  check(noHigh?.code == 'high_risk_contact_required', 'active org keeps a High-risk contact');
  check(
    (await expectError(
          api2.saveOrgCounselors(cni.id, [(counselorId: priya.id, role: CounselorRole.backup)]),
        ))?.code ==
        'primary_required',
    'active org keeps a primary',
  );

  // ── Storyboard F: leaving counselor ──
  final anjali = all.firstWhere((c) => c.fullName == 'Anjali Menon');
  final blocked = await expectError(api2.setCounselorActive(anjali.id, false));
  check(blocked?.code == 'only_primary', 'only primary of Active org cannot be deactivated');
  final nccId = (await api2.getCounselor(anjali.id)).assignments.first.organizationId;
  final joseph = all.firstWhere((c) => c.fullName == 'Joseph Varghese');
  await api2.saveOrgCounselors(nccId, [
    (counselorId: joseph.id, role: CounselorRole.primary),
    (counselorId: anjali.id, role: CounselorRole.backup),
  ]);
  final off = await api2.setCounselorActive(anjali.id, false);
  check(!off.isActive, 'deactivated once Joseph is primary');

  // ── Storyboard E: failed High alert, resend ──
  check(await api2.countNeedsAttention() == 1, 'one High alert needs attention');
  final failedRows = (await api2.listLog(
    const LogFilter(range: LogRange.all, needsAttentionOnly: true),
  )).results;
  check(failedRows.length == 1 && failedRows.first.attempts == 4, 'failed row has 4 attempts');
  final sms = failedRows.first.channels.firstWhere((c) => c.channel == Channel.sms);
  await api2.resendDelivery(sms.deliveryId);
  check(await api2.countNeedsAttention() == 0, 'banner clears after a delivered resend');
  final skipped = (await api2.listLog(const LogFilter(range: LogRange.all, status: 'skipped'))).results;
  check(skipped.every((r) => r.outcome.isSkipped) && skipped.isNotEmpty, 'skipped filter');

  stdout.writeln('$_passes passed, $_failures failed');
  if (_failures > 0) exit(1);
}
