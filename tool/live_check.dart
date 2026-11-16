// Runs the console's real HTTP client against a running backend, through the
// storyboard flow. Needs a staff account, a running worker, and SMS / WhatsApp
// on the simulator provider (the default).
//
//   dart run tool/live_check.dart http://localhost:8000 <staff-username> <password>
//
// It creates an organization with a random code and counselors with random
// numbers, so it is safe to run against a local or staging database only.

import 'dart:io';
import 'dart:math';

import 'package:asha_admin/api/console_api.dart';
import 'package:asha_admin/api/http_console_api.dart';
import 'package:asha_admin/api/token_store.dart';

int _fail = 0;

void check(bool ok, String what) {
  stdout.writeln('${ok ? 'ok  ' : 'FAIL'}  $what');
  if (!ok) _fail++;
}

Future<ApiException?> err(Future<Object?> f) async {
  try {
    await f;
    return null;
  } on ApiException catch (e) {
    return e;
  }
}

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln('usage: dart run tool/live_check.dart <base-url> <staff-user> <password>');
    exit(2);
  }
  final api = HttpConsoleApi(baseUrl: args[0], tokens: MemoryTokenStore());
  final rnd = Random();
  String mobile() => '+9198${List.generate(7, (_) => rnd.nextInt(10)).join()}1';
  final code = 'LC-${rnd.nextInt(90000) + 10000}';

  check(
    (await err(api.signIn(args[1], 'wrong-password')))?.code == 'invalid_credentials',
    'wrong password rejected',
  );
  final me = await api.signIn(args[1], args[2]);
  check(me.isStaff, 'staff sign-in (${me.username})');

  final org = await api.createOrganization(
    OrgDetailsInput(
      name: 'Live Check College',
      code: code.toLowerCase(),
      type: OrgType.college,
      city: 'Bengaluru',
      state: 'Karnataka',
    ),
  );
  check(org.status == OrgStatus.draft && org.code == code, 'created Draft $code');
  final dup = await err(
    api.createOrganization(
      OrgDetailsInput(name: 'X', code: code, type: OrgType.college, city: 'B', state: 'K'),
    ),
  );
  check(dup?.fieldError('code')?.contains('already used') ?? false, 'duplicate code → field error');

  final badContact = await err(
    api.saveContacts(org.id, const [OrgContact(fullName: 'A', title: 'B', mobile: '123')]),
  );
  check(badContact?.fieldError('contacts.0.mobile') != null, 'contact error keyed contacts.0.mobile');
  await api.saveContacts(org.id, [
    OrgContact(fullName: 'Dr. Kavya Rao', title: 'Principal', mobile: mobile(), receivesHighAlerts: true),
  ]);

  final noConsent = await err(
    api.createCounselor(CounselorInput(fullName: 'No Consent', mobile: mobile(), consent: false)),
  );
  check(noConsent?.fieldError('consent') != null, 'counselor needs consent');
  final rahul = await api.createCounselor(
    CounselorInput(fullName: 'Rahul Iyer', mobile: mobile(), languages: ['Tamil'], consent: true),
  );
  check(rahul.hasConsent, 'counselor created with consent_at');
  final assigned = await api.saveOrgCounselors(org.id, [
    (counselorId: rahul.id, role: CounselorRole.primary),
  ]);
  check(assigned.single.role == CounselorRole.primary, 'assigned as primary');

  await api.updateChannels(org.id, const AlertChannels());
  await api.saveSetupStep(org.id, 4);
  var ready = await api.getReadiness(org.id);
  check(ready.missing.length == 1 && ready.missing.single == 'test_alerts', 'readiness: only test missing');
  check((await err(api.activate(org.id)))?.statusCode == 422, 'activate blocked before test');

  await api.sendOrgTestAlerts(org.id);
  TestRun? run;
  for (var i = 0; i < 20; i++) {
    run = await api.latestOrgTest(org.id);
    if (run != null && !run.pending) break;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  check(run != null && run.allReached, 'test alerts delivered (worker running)');
  ready = await api.getReadiness(org.id);
  check(ready.canActivate, 'ready to activate');
  final active = await api.activate(org.id);
  check(active.status == OrgStatus.active && active.primaryCounselor?.fullName == 'Rahul Iyer', 'activated');

  final blocked = await err(api.setCounselorActive(rahul.id, false));
  check(blocked?.code == 'only_primary', 'only primary cannot be deactivated');

  final list = await api.listOrganizations(search: code);
  check(list.results.length == 1 && list.results.single.highRiskContacts.length == 1, 'list + search');
  final log = await api.listLog(
    LogFilter(organizationId: org.id, level: AlertLevel.test, range: LogRange.day),
  );
  check(log.results.length == 2, 'delivery log has the 2 test rows');
  final c = await api.getCounselor(rahul.id);
  check(
    c.lastTest != null && c.assignments.single.organizationName == 'Live Check College',
    'counselor detail',
  );

  final sim = await api.getSimulator();
  final simRahul = sim.phones.where((p) => p.phone == rahul.mobile).firstOrNull;
  check(sim.enabled && simRahul != null && simRahul.name == 'Rahul Iyer', 'simulator lists Rahul\'s number');
  final simMsgs = (await api.listSimMessages(phone: rahul.mobile)).results;
  check(
    simMsgs.length == 1 && simMsgs.single.channel == Channel.sms && simMsgs.single.text.startsWith('TEST'),
    'simulator shows the TEST SMS (no WhatsApp number, so no WhatsApp)',
  );
  check(await api.clearSimMessages(phone: rahul.mobile) == 1, 'simulator clear for one number');

  await api.deactivate(org.id);
  await api.signOut();
  stdout.writeln(_fail == 0 ? '\nAll checks passed.' : '\n$_fail check(s) failed.');
  exit(_fail == 0 ? 0 : 1);
}
