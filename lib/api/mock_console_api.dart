// In-memory backend for building and demoing the console before the Django
// endpoints exist (run with --dart-define=USE_MOCK=true).
//
// It enforces the same rules the real API must enforce (see
// docs/BACKEND_CHANGES.md), so it is also an executable spec:
//   * organization code unique, 3–12 of A–Z 0–9 -
//   * counselor needs consent before assignment; exactly one primary
//   * activation needs a High-risk contact, a primary, channels and a passing test
//   * the only primary of an Active organization cannot be deactivated
//
// Demo sign-in: any username with password "demo1234". Username "student"
// shows the non-staff error. 5 wrong passwords lock sign-in for 15 minutes.
//
// Simulated delivery: WhatsApp fails ("number not on WhatsApp") when the
// number ends in 0; SMS fails ("number unreachable") when it ends in 00.
//
// Pure Dart: no Flutter imports.

import 'dart:async';

import '../utils/validators.dart';
import 'console_api.dart';

const String kMockPassword = 'demo1234';

class _Org {
  _Org({
    required this.id,
    required this.name,
    required this.code,
    required this.type,
    required this.city,
    required this.state,
    this.notes = '',
    this.status = OrgStatus.draft,
    this.setupStep = 1,
    required this.createdAt,
    this.activatedAt,
  });

  final String id;
  String name;
  String code;
  OrgType type;
  String city;
  String state;
  String notes;
  OrgStatus status;
  AlertChannels channels = const AlertChannels();
  int setupStep;
  final DateTime createdAt;
  DateTime? activatedAt;
  List<OrgContact> contacts = [];
  List<({String counselorId, CounselorRole role})> assignments = [];
  TestRun? lastTest;
  String? lastTestFingerprint;
}

class _Counselor {
  _Counselor({
    required this.id,
    required this.fullName,
    required this.mobile,
    this.whatsapp,
    this.email = '',
    this.languages = const [],
    this.notes = '',
    this.consentAt,
  });

  final String id;
  String fullName;
  String mobile;
  String? whatsapp;
  String email;
  List<String> languages;
  String notes;
  DateTime? consentAt;
  bool isActive = true;
  LastTest? lastTest;
}

/// A log row plus who it was sent to, so Resend can use the current number.
class _Row {
  _Row(this.row, {this.recipientKind, this.recipientId});
  LogRow row;
  final String? recipientKind; // counselor | contact
  final String? recipientId;
}

class MockConsoleApi implements ConsoleApi {
  MockConsoleApi({this.latency = const Duration(milliseconds: 250), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _seed();
  }

  final Duration latency;
  final DateTime Function() _clock;

  final Map<String, _Org> _orgs = {};
  final Map<String, _Counselor> _counselors = {};
  final List<_Row> _log = [];
  int _seq = 100;
  AdminUser? _user;
  int _failedLogins = 0;
  DateTime? _lockedUntil;

  String _id(String prefix) => '$prefix-${_seq++}';
  DateTime get _now => _clock();

  Future<T> _delay<T>(T Function() body) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return body();
  }

  ApiException _err(
    int status,
    String code,
    String detail, {
    Map<String, List<String>> fields = const {},
    Map<String, dynamic> extra = const {},
  }) => ApiException(statusCode: status, code: code, detail: detail, fieldErrors: fields, extra: extra);

  ApiException _notFound() => _err(404, 'not_found', 'Not found.');

  // ── Auth ──────────────────────────────────────────────────────────────

  @override
  Future<AdminUser> signIn(String login, String password) => _delay(() {
    final now = _now;
    if (_lockedUntil != null && now.isBefore(_lockedUntil!)) {
      final mins = _lockedUntil!.difference(now).inMinutes + 1;
      throw _err(
        429,
        'login_locked',
        'Too many wrong attempts. Try again in $mins minutes.',
        extra: {'retry_after': _lockedUntil!.difference(now).inSeconds},
      );
    }
    if (password != kMockPassword) {
      _failedLogins++;
      if (_failedLogins >= 5) {
        _lockedUntil = now.add(const Duration(minutes: 15));
        _failedLogins = 0;
      }
      throw _err(401, 'invalid_credentials', 'Invalid username/email or password.');
    }
    _failedLogins = 0;
    if (login.trim().toLowerCase() == 'student') {
      throw _err(403, 'not_staff', kNoConsoleAccess);
    }
    final name = login.contains('@') ? login.split('@').first : login.trim();
    _user = AdminUser(id: 'admin-1', username: name.isEmpty ? 'admin' : name, isStaff: true);
    return _user!;
  });

  @override
  Future<AdminUser?> restoreSession() => _delay(() => _user);

  @override
  Future<void> signOut() => _delay(() {
    _user = null;
  });

  // ── Organizations ─────────────────────────────────────────────────────

  Organization _orgOut(_Org o) {
    final counselors = o.assignments
        .map((a) => (c: _counselors[a.counselorId], role: a.role))
        .where((x) => x.c != null)
        .toList();
    final primary = counselors.where((x) => x.role == CounselorRole.primary).firstOrNull;
    final backups = counselors.where((x) => x.role == CounselorRole.backup);
    final high = o.contacts.where((c) => c.receivesHighAlerts);
    return Organization(
      id: o.id,
      name: o.name,
      code: o.code,
      type: o.type,
      city: o.city,
      state: o.state,
      notes: o.notes,
      status: o.status,
      channels: o.channels,
      primaryCounselor: primary == null
          ? null
          : PersonRef(id: primary.c!.id, fullName: primary.c!.fullName, mobile: primary.c!.mobile),
      backupCounselors: backups
          .map((x) => PersonRef(id: x.c!.id, fullName: x.c!.fullName, mobile: x.c!.mobile))
          .toList(),
      highRiskContacts: high
          .map((c) => PersonRef(id: c.id ?? '', fullName: c.fullName, mobile: c.mobile))
          .toList(),
      counselorCount: counselors.length,
      contactCount: o.contacts.length,
      setupStep: o.setupStep,
      createdAt: o.createdAt,
      activatedAt: o.activatedAt,
    );
  }

  _Org _org(String id) => _orgs[id] ?? (throw _notFound());

  @override
  Future<ApiPage<Organization>> listOrganizations({String? search, OrgStatus? status, int page = 1}) =>
      _delay(() {
        final q = (search ?? '').trim().toLowerCase();
        final list =
            _orgs.values
                .where((o) => status == null || o.status == status)
                .where(
                  (o) => q.isEmpty || o.name.toLowerCase().contains(q) || o.code.toLowerCase().contains(q),
                )
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name));
        return _paginate(list.map(_orgOut).toList(), page);
      });

  ApiPage<T> _paginate<T>(List<T> all, int page, {int size = 20}) {
    final start = (page - 1) * size;
    final slice = start >= all.length ? <T>[] : all.sublist(start, (start + size).clamp(0, all.length));
    return ApiPage(results: slice, count: all.length, hasMore: start + size < all.length);
  }

  @override
  Future<Organization> getOrganization(String id) => _delay(() => _orgOut(_org(id)));

  Map<String, List<String>> _validateDetails(OrgDetailsInput input, {String? exceptId}) {
    final errors = <String, List<String>>{};
    void add(String f, String? m) {
      if (m != null) errors[f] = [m];
    }

    add('name', validateRequired(input.name, 'Organization name', min: 2, max: 120));
    add('code', validateOrgCode(input.code));
    add('city', validateRequired(input.city, 'City', max: 80));
    add('state', validateRequired(input.state, 'State', max: 80));
    final code = normalizeOrgCode(input.code);
    final clash = _orgs.values.where((o) => o.code == code && o.id != exceptId).firstOrNull;
    if (clash != null && !errors.containsKey('code')) {
      errors['code'] = ['$code is already used by ${clash.name}.'];
    }
    return errors;
  }

  @override
  Future<Organization> createOrganization(OrgDetailsInput input) => _delay(() {
    final errors = _validateDetails(input);
    if (errors.isNotEmpty) {
      throw _err(400, 'validation_error', errors.values.first.first, fields: errors);
    }
    final o = _Org(
      id: _id('org'),
      name: input.name.trim(),
      code: normalizeOrgCode(input.code),
      type: input.type,
      city: input.city.trim(),
      state: input.state.trim(),
      notes: input.notes.trim(),
      createdAt: _now,
    );
    _orgs[o.id] = o;
    return _orgOut(o);
  });

  @override
  Future<Organization> updateOrganization(String id, OrgDetailsInput input) => _delay(() {
    final o = _org(id);
    final errors = _validateDetails(input, exceptId: id);
    if (errors.isNotEmpty) {
      throw _err(400, 'validation_error', errors.values.first.first, fields: errors);
    }
    o
      ..name = input.name.trim()
      ..code = normalizeOrgCode(input.code)
      ..type = input.type
      ..city = input.city.trim()
      ..state = input.state.trim()
      ..notes = input.notes.trim();
    return _orgOut(o);
  });

  @override
  Future<Organization> updateChannels(String id, AlertChannels channels) => _delay(() {
    final o = _org(id);
    final errors = <String, List<String>>{
      if (!channels.medium.any) 'medium': ['Choose at least one channel for Medium risk.'],
      if (!channels.high.any) 'high': ['Choose at least one channel for High risk.'],
    };
    if (errors.isNotEmpty) {
      throw _err(400, 'validation_error', errors.values.first.first, fields: errors);
    }
    o.channels = channels;
    return _orgOut(o);
  });

  @override
  Future<void> saveSetupStep(String id, int step) => _delay(() {
    final o = _org(id);
    if (step > o.setupStep) o.setupStep = step.clamp(1, 5);
  });

  @override
  Future<List<OrgContact>> listContacts(String orgId) => _delay(() => List.of(_org(orgId).contacts));

  @override
  Future<List<OrgContact>> saveContacts(String orgId, List<OrgContact> contacts) => _delay(() {
    final o = _org(orgId);
    final errors = <String, List<String>>{};
    final out = <OrgContact>[];
    for (var i = 0; i < contacts.length; i++) {
      final c = contacts[i];
      final mobile = normalizeMobile(c.mobile);
      final nameErr = validateRequired(c.fullName, 'Full name');
      final roleErr = validateRequired(c.title, 'Role', max: 80);
      final waErr = c.whatsapp == null ? null : validateMobile(c.whatsapp);
      final emailErr = validateEmail(c.email);
      for (final e in [
        ('full_name', nameErr),
        ('title', roleErr),
        ('mobile', mobile == null ? mobileError : null),
        ('whatsapp', waErr),
        ('email', emailErr),
      ]) {
        if (e.$2 != null) errors['contacts.$i.${e.$1}'] = [e.$2!];
      }
      out.add(
        OrgContact(
          id: c.id ?? _id('contact'),
          fullName: c.fullName.trim(),
          title: c.title.trim(),
          mobile: mobile ?? c.mobile,
          whatsapp: c.whatsapp == null ? null : normalizeMobile(c.whatsapp),
          email: c.email.trim(),
          receivesHighAlerts: c.receivesHighAlerts,
        ),
      );
    }
    if (errors.isNotEmpty) {
      throw _err(400, 'validation_error', errors.values.first.first, fields: errors);
    }
    if (o.status == OrgStatus.active && !out.any((c) => c.receivesHighAlerts)) {
      throw _err(
        409,
        'high_risk_contact_required',
        'An Active organization needs at least one contact who receives High-risk alerts. '
            'Tick another contact first, or deactivate the organization.',
      );
    }
    o.contacts = out;
    return List.of(out);
  });

  Counselor _counselorOut(_Counselor c) {
    final assignments = <Assignment>[];
    for (final o in _orgs.values) {
      for (final a in o.assignments.where((a) => a.counselorId == c.id)) {
        assignments.add(
          Assignment(
            organizationId: o.id,
            organizationName: o.name,
            organizationStatus: o.status,
            role: a.role,
            isOnlyPrimary: a.role == CounselorRole.primary,
          ),
        );
      }
    }
    assignments.sort((a, b) => a.organizationName.compareTo(b.organizationName));
    return Counselor(
      id: c.id,
      fullName: c.fullName,
      mobile: c.mobile,
      whatsapp: c.whatsapp,
      email: c.email,
      languages: List.of(c.languages),
      notes: c.notes,
      consentAt: c.consentAt,
      isActive: c.isActive,
      assignments: assignments,
      lastTest: c.lastTest,
    );
  }

  @override
  Future<List<OrgCounselor>> listOrgCounselors(String orgId) => _delay(() {
    final o = _org(orgId);
    return o.assignments
        .where((a) => _counselors.containsKey(a.counselorId))
        .map((a) => OrgCounselor(counselor: _counselorOut(_counselors[a.counselorId]!), role: a.role))
        .toList();
  });

  @override
  Future<List<OrgCounselor>> saveOrgCounselors(
    String orgId,
    List<({String counselorId, CounselorRole role})> assignments,
  ) => _delay(() {
    final o = _org(orgId);
    final ids = <String>{};
    for (final a in assignments) {
      final c = _counselors[a.counselorId];
      if (c == null) throw _notFound();
      if (!ids.add(a.counselorId)) {
        throw _err(400, 'validation_error', '${c.fullName} is listed twice.');
      }
      if (c.consentAt == null) {
        throw _err(400, 'consent_missing', "${c.fullName} can't be assigned: consent not recorded.");
      }
      if (!c.isActive) {
        throw _err(400, 'counselor_inactive', "${c.fullName} is inactive and can't be assigned.");
      }
    }
    final primaries = assignments.where((a) => a.role == CounselorRole.primary).length;
    if (primaries > 1) {
      throw _err(400, 'one_primary', 'Choose exactly one primary counselor.');
    }
    if (o.status == OrgStatus.active && primaries == 0) {
      throw _err(
        409,
        'primary_required',
        'An Active organization needs a primary counselor. Choose one before saving.',
      );
    }
    o.assignments = List.of(assignments);
    return o.assignments
        .map((a) => OrgCounselor(counselor: _counselorOut(_counselors[a.counselorId]!), role: a.role))
        .toList();
  });

  /// Everyone a test (and a High alert) goes to: primary, backups and
  /// High-risk contacts.
  List<({String kind, String id, String name, String role, String phone, String? whatsapp})> _recipients(
    _Org o,
  ) {
    final out = <({String kind, String id, String name, String role, String phone, String? whatsapp})>[];
    final sorted = List.of(o.assignments)..sort((a, b) => a.role.index.compareTo(b.role.index));
    for (final a in sorted) {
      final c = _counselors[a.counselorId];
      if (c == null || !c.isActive) continue;
      out.add((
        kind: 'counselor',
        id: c.id,
        name: c.fullName,
        role: '${a.role.label} counselor',
        phone: c.mobile,
        whatsapp: c.whatsapp,
      ));
    }
    for (final c in o.contacts.where((c) => c.receivesHighAlerts)) {
      out.add((
        kind: 'contact',
        id: c.id ?? '',
        name: c.fullName,
        role: '${c.title} · High-risk contact',
        phone: c.mobile,
        whatsapp: c.whatsapp,
      ));
    }
    return out;
  }

  String _fingerprint(_Org o) => _recipients(o).map((r) => '${r.id}|${r.phone}|${r.whatsapp}').join(';');

  ChannelResult _simulate(Channel ch, String phone) {
    final d = mobileDigits(phone) ?? '';
    final id = _id('dlv');
    if (ch == Channel.sms && d.endsWith('00')) {
      return ChannelResult(status: DeliveryStatus.failed, error: 'number unreachable', deliveryId: id);
    }
    if (ch == Channel.whatsapp && d.endsWith('0')) {
      return ChannelResult(status: DeliveryStatus.failed, error: 'number not on WhatsApp', deliveryId: id);
    }
    return ChannelResult(status: DeliveryStatus.delivered, deliveryId: id);
  }

  LogChannel _logChannel(Channel ch, ChannelResult r, String phone) => LogChannel(
    deliveryId: r.deliveryId ?? _id('dlv'),
    channel: ch,
    status: r.status,
    attempts: r.status == DeliveryStatus.failed ? 4 : 1,
    error: r.error,
    phone: phone,
  );

  @override
  Future<Readiness> getReadiness(String orgId) => _delay(() => _readiness(_org(orgId)));

  Readiness _readiness(_Org o) {
    final org = _orgOut(o);
    final details = o.name.isNotEmpty && o.code.isNotEmpty && o.city.isNotEmpty && o.state.isNotEmpty;
    final testFresh = o.lastTest != null && o.lastTestFingerprint == _fingerprint(o);
    final allReached = testFresh && o.lastTest!.allReached;
    return Readiness(
      detailsComplete: details,
      code: o.code,
      highRiskContactCount: org.highRiskContacts.length,
      primaryCounselorName: org.primaryCounselor?.fullName,
      channelsSet: o.channels.valid,
      testRun: testFresh,
      testsAllReached: allReached,
      missing: [
        if (!details) 'details',
        if (org.highRiskContacts.isEmpty) 'high_risk_contact',
        if (org.primaryCounselor == null) 'primary_counselor',
        if (!o.channels.valid) 'channels',
        if (!allReached) 'test_alerts',
      ],
    );
  }

  TestRun _runTest(
    List<({String kind, String id, String name, String role, String phone, String? whatsapp})> recipients, {
    String? orgId,
    String? orgName,
  }) {
    final now = _now;
    final results = <TestRecipient>[];
    for (final r in recipients) {
      final sms = _simulate(Channel.sms, r.phone);
      final wa = r.whatsapp == null ? null : _simulate(Channel.whatsapp, r.whatsapp!);
      results.add(TestRecipient(name: r.name, roleLabel: r.role, phone: r.phone, sms: sms, whatsapp: wa));
      _log.insert(
        0,
        _Row(
          LogRow(
            id: _id('row'),
            time: now,
            level: AlertLevel.test,
            outcome: Outcome.test,
            organizationId: orgId,
            organizationName: orgName,
            recipientName: r.name,
            recipientLabel: r.kind == 'contact' ? 'contact' : r.role.split(' ').first.toLowerCase(),
            channels: [
              _logChannel(Channel.sms, sms, r.phone),
              if (wa != null) _logChannel(Channel.whatsapp, wa, r.whatsapp!),
            ],
          ),
          recipientKind: r.kind,
          recipientId: r.id,
        ),
      );
      if (r.kind == 'counselor') {
        _counselors[r.id]?.lastTest = LastTest(at: now, sms: sms.status.name, whatsapp: wa?.status.name);
      }
    }
    return TestRun(runAt: now, recipients: results);
  }

  @override
  Future<TestRun> sendOrgTestAlerts(String orgId) => _delay(() {
    final o = _org(orgId);
    final recipients = _recipients(o);
    if (recipients.isEmpty) {
      throw _err(
        400,
        'no_recipients',
        'Add a High-risk contact and a primary counselor before sending test alerts.',
      );
    }
    final run = _runTest(recipients, orgId: o.id, orgName: o.name);
    o.lastTest = run;
    o.lastTestFingerprint = _fingerprint(o);
    return run;
  });

  @override
  Future<TestRun?> latestOrgTest(String orgId) => _delay(() => _org(orgId).lastTest);

  @override
  Future<Organization> activate(String orgId) => _delay(() {
    final o = _org(orgId);
    final r = _readiness(o);
    if (!r.canActivate) {
      throw _err(
        422,
        'not_ready',
        "This organization can't be activated yet.",
        extra: {'missing': r.missing},
      );
    }
    o.status = OrgStatus.active;
    o.activatedAt = _now;
    o.setupStep = 5;
    return _orgOut(o);
  });

  @override
  Future<Organization> deactivate(String orgId) => _delay(() {
    final o = _org(orgId);
    o.status = OrgStatus.inactive;
    return _orgOut(o);
  });

  // ── Counselors ────────────────────────────────────────────────────────

  _Counselor _c(String id) => _counselors[id] ?? (throw _notFound());

  @override
  Future<ApiPage<Counselor>> listCounselors({String? search, bool? active, int page = 1}) => _delay(() {
    final q = (search ?? '').trim().toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    final list =
        _counselors.values
            .where((c) => active == null || c.isActive == active)
            .where(
              (c) =>
                  q.isEmpty ||
                  c.fullName.toLowerCase().contains(q) ||
                  (qDigits.length >= 3 && c.mobile.contains(qDigits)),
            )
            .toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));
    return _paginate(list.map(_counselorOut).toList(), page);
  });

  @override
  Future<Counselor> getCounselor(String id) => _delay(() => _counselorOut(_c(id)));

  Map<String, List<String>> _validateCounselor(CounselorInput input, {String? exceptId}) {
    final errors = <String, List<String>>{};
    void add(String f, String? m) {
      if (m != null) errors[f] = [m];
    }

    add('full_name', validateRequired(input.fullName, 'Full name'));
    add('mobile', validateMobile(input.mobile));
    if (input.whatsapp != null) add('whatsapp', validateMobile(input.whatsapp));
    add('email', validateEmail(input.email));
    final mobile = normalizeMobile(input.mobile);
    final clash = _counselors.values.where((c) => c.mobile == mobile && c.id != exceptId).firstOrNull;
    if (clash != null && !errors.containsKey('mobile')) {
      errors['mobile'] = ['${clash.fullName} already uses this mobile number.'];
    }
    return errors;
  }

  @override
  Future<Counselor> createCounselor(CounselorInput input) => _delay(() {
    final errors = _validateCounselor(input);
    if (!input.consent) {
      errors['consent'] = ['Record the counselor’s consent before saving.'];
    }
    if (errors.isNotEmpty) {
      throw _err(400, 'validation_error', errors.values.first.first, fields: errors);
    }
    final c = _Counselor(
      id: _id('counselor'),
      fullName: input.fullName.trim(),
      mobile: normalizeMobile(input.mobile)!,
      whatsapp: input.whatsapp == null ? null : normalizeMobile(input.whatsapp),
      email: input.email.trim(),
      languages: List.of(input.languages),
      notes: input.notes.trim(),
      consentAt: _now,
    );
    _counselors[c.id] = c;
    return _counselorOut(c);
  });

  @override
  Future<Counselor> updateCounselor(String id, CounselorInput input) => _delay(() {
    final c = _c(id);
    final errors = _validateCounselor(input, exceptId: id);
    if (errors.isNotEmpty) {
      throw _err(400, 'validation_error', errors.values.first.first, fields: errors);
    }
    c
      ..fullName = input.fullName.trim()
      ..mobile = normalizeMobile(input.mobile)!
      ..whatsapp = input.whatsapp == null ? null : normalizeMobile(input.whatsapp)
      ..email = input.email.trim()
      ..languages = List.of(input.languages)
      ..notes = input.notes.trim();
    if (input.consent && c.consentAt == null) c.consentAt = _now;
    return _counselorOut(c);
  });

  @override
  Future<Counselor> setCounselorActive(String id, bool active) => _delay(() {
    final c = _c(id);
    if (!active) {
      final blocking = _counselorOut(c).blockingAssignments;
      if (blocking.isNotEmpty) {
        final names = blocking.map((a) => a.organizationName).join(', ');
        throw _err(
          409,
          'only_primary',
          '${c.fullName} is the only primary counselor for $names. Choose a new primary first.',
          extra: {'organizations': blocking.map((a) => a.organizationId).toList()},
        );
      }
    }
    c.isActive = active;
    return _counselorOut(c);
  });

  @override
  Future<TestRun> sendCounselorTest(String id) => _delay(() {
    final c = _c(id);
    return _runTest([
      (
        kind: 'counselor',
        id: c.id,
        name: c.fullName,
        role: 'Counselor',
        phone: c.mobile,
        whatsapp: c.whatsapp,
      ),
    ]);
  });

  // ── Delivery log ──────────────────────────────────────────────────────

  bool _matches(LogRow r, LogFilter f, DateTime now) {
    if (f.organizationId != null && r.organizationId != f.organizationId) return false;
    if (f.level != null && r.level != f.level) return false;
    if (f.range.span != null && r.time.isBefore(now.subtract(f.range.span!))) return false;
    if (f.needsAttentionOnly && !r.needsAttention) return false;
    switch (f.status) {
      case 'delivered':
        return r.channels.any((c) => c.status == DeliveryStatus.delivered);
      case 'failed':
        return r.anyFailed;
      case 'retrying':
        return r.channels.any((c) => c.status == DeliveryStatus.retrying);
      case 'skipped':
        return r.outcome.isSkipped;
    }
    return true;
  }

  @override
  Future<ApiPage<LogRow>> listLog(LogFilter filter, {int page = 1}) => _delay(() {
    final now = _now;
    final rows = _log.map((r) => r.row).where((r) => _matches(r, filter, now)).toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return _paginate(rows, page);
  });

  @override
  Future<int> countNeedsAttention() => _delay(() => _log.where((r) => r.row.needsAttention).length);

  @override
  Future<void> resendDelivery(String deliveryId) => _delay(() {
    final entry = _log.where((r) => r.row.channels.any((c) => c.deliveryId == deliveryId)).firstOrNull;
    if (entry == null) throw _notFound();
    final old = entry.row.channels.firstWhere((c) => c.deliveryId == deliveryId);
    if (old.status != DeliveryStatus.failed) {
      throw _err(400, 'not_failed', 'Only failed messages can be resent.');
    }
    // Current number on file (AC 4.2): old rows keep the old number.
    String? phone;
    if (entry.recipientKind == 'counselor') {
      final c = _counselors[entry.recipientId];
      phone = old.channel == Channel.sms ? c?.mobile : c?.whatsapp;
    } else if (entry.recipientKind == 'contact') {
      for (final o in _orgs.values) {
        final c = o.contacts.where((c) => c.id == entry.recipientId).firstOrNull;
        if (c != null) phone = old.channel == Channel.sms ? c.mobile : c.whatsapp;
      }
    }
    if (phone == null) {
      throw _err(400, 'no_number', 'This recipient has no ${old.channel.label} number on file any more.');
    }
    final result = _simulate(old.channel, phone);
    final newRow = LogRow(
      id: _id('row'),
      time: _now,
      level: entry.row.level,
      outcome: entry.row.outcome,
      organizationId: entry.row.organizationId,
      organizationName: entry.row.organizationName,
      studentRef: entry.row.studentRef,
      recipientName: entry.row.recipientName,
      recipientLabel: entry.row.recipientLabel,
      channels: [_logChannel(old.channel, result, phone)],
    );
    _log.insert(0, _Row(newRow, recipientKind: entry.recipientKind, recipientId: entry.recipientId));
    if (result.status == DeliveryStatus.delivered) {
      final r = entry.row;
      entry.row = LogRow(
        id: r.id,
        time: r.time,
        level: r.level,
        outcome: r.outcome,
        organizationId: r.organizationId,
        organizationName: r.organizationName,
        studentRef: r.studentRef,
        recipientName: r.recipientName,
        recipientLabel: r.recipientLabel,
        channels: r.channels,
        resolved: true,
      );
    }
  });

  // ── Sample data ───────────────────────────────────────────────────────

  void _seed() {
    final now = _now;
    _Counselor counselor(
      String name,
      String mobile, {
      String? whatsapp,
      List<String> langs = const [],
      bool consent = true,
      String email = '',
    }) {
      final c = _Counselor(
        id: _id('counselor'),
        fullName: name,
        mobile: mobile,
        whatsapp: whatsapp ?? mobile,
        email: email,
        languages: langs,
        consentAt: consent ? now.subtract(const Duration(days: 30)) : null,
      );
      _counselors[c.id] = c;
      return c;
    }

    final anjali = counselor('Anjali Menon', '+919847012345', langs: ['Malayalam', 'English']);
    final joseph = counselor('Joseph Varghese', '+919847154321', langs: ['Malayalam', 'English']);
    final rahul = counselor('Rahul Iyer', '+919886013579', langs: ['Tamil', 'English']);
    final sneha = counselor('Sneha Kulkarni', '+919822045671', langs: ['Marathi', 'Hindi', 'English']);
    counselor('Priya Raghavan', '+919986024681', langs: ['Kannada', 'English', 'Hindi']);
    counselor('Prithvi Gowda', '+919845011122', langs: ['Kannada', 'English'], consent: false);

    _Org org(String name, String code, OrgType type, String city, String state, OrgStatus status) {
      final o = _Org(
        id: _id('org'),
        name: name,
        code: code,
        type: type,
        city: city,
        state: state,
        status: status,
        setupStep: 5,
        createdAt: now.subtract(const Duration(days: 60)),
        activatedAt: status == OrgStatus.draft ? null : now.subtract(const Duration(days: 45)),
      );
      _orgs[o.id] = o;
      return o;
    }

    final ncc = org('North Campus College', 'NCC-01', OrgType.college, 'Kochi', 'Kerala', OrgStatus.active)
      ..assignments = [
        (counselorId: anjali.id, role: CounselorRole.primary),
        (counselorId: joseph.id, role: CounselorRole.backup),
      ]
      ..contacts = [
        OrgContact(
          id: _id('contact'),
          fullName: 'Dr. Thomas Kurian',
          title: 'Principal',
          mobile: '+919847066778',
          whatsapp: '+919847066778',
          receivesHighAlerts: true,
        ),
        OrgContact(
          id: _id('contact'),
          fullName: 'Leela George',
          title: 'Dean of Students',
          mobile: '+919847033445',
          whatsapp: '+919847033445',
          receivesHighAlerts: true,
        ),
      ];

    final dean = OrgContact(
      id: _id('contact'),
      fullName: 'Dean of Students',
      title: 'Dean',
      mobile: '+919443022110',
      whatsapp: '+919443022110',
      receivesHighAlerts: true,
    );
    final rac =
        org('Riverside Arts College', 'RAC', OrgType.college, 'Coimbatore', 'Tamil Nadu', OrgStatus.active)
          ..assignments = [(counselorId: rahul.id, role: CounselorRole.primary)]
          ..contacts = [dean];

    org('Hillview Youth Centre', 'HYC', OrgType.ngo, 'Pune', 'Maharashtra', OrgStatus.inactive)
      ..assignments = [(counselorId: sneha.id, role: CounselorRole.primary)]
      ..contacts = [
        OrgContact(
          id: _id('contact'),
          fullName: 'Kiran Joshi',
          title: 'Director',
          mobile: '+919822077881',
          whatsapp: null,
          receivesHighAlerts: true,
        ),
      ];

    for (final o in _orgs.values) {
      o.lastTestFingerprint = _fingerprint(o);
      o.lastTest = TestRun(
        runAt: now.subtract(const Duration(days: 45)),
        recipients: _recipients(o)
            .map(
              (r) => TestRecipient(
                name: r.name,
                roleLabel: r.role,
                phone: r.phone,
                sms: const ChannelResult(status: DeliveryStatus.delivered),
                whatsapp: r.whatsapp == null ? null : const ChannelResult(status: DeliveryStatus.delivered),
              ),
            )
            .toList(),
      );
    }

    LogChannel ch(Channel c, DeliveryStatus s, int attempts, String phone, {String? error, DateTime? next}) =>
        LogChannel(
          deliveryId: _id('dlv'),
          channel: c,
          status: s,
          attempts: attempts,
          error: error,
          nextRetryAt: next,
          phone: phone,
        );

    void add(LogRow row, {String? kind, String? id}) =>
        _log.add(_Row(row, recipientKind: kind, recipientId: id));

    final t1 = now.subtract(const Duration(hours: 8));
    add(
      LogRow(
        id: _id('row'),
        time: t1,
        level: AlertLevel.high,
        outcome: Outcome.sent,
        organizationId: rac.id,
        organizationName: rac.name,
        studentRef: 'ASH-7H3D',
        recipientName: dean.fullName,
        recipientLabel: 'contact',
        channels: [
          ch(Channel.sms, DeliveryStatus.failed, 4, '+919443022110', error: 'number unreachable'),
          ch(Channel.whatsapp, DeliveryStatus.failed, 4, '+919443022110', error: 'number not on WhatsApp'),
        ],
      ),
      kind: 'contact',
      id: dean.id,
    );
    add(
      LogRow(
        id: _id('row'),
        time: t1,
        level: AlertLevel.high,
        outcome: Outcome.sent,
        organizationId: rac.id,
        organizationName: rac.name,
        studentRef: 'ASH-7H3D',
        recipientName: rahul.fullName,
        recipientLabel: 'primary',
        channels: [
          ch(Channel.sms, DeliveryStatus.delivered, 1, rahul.mobile),
          ch(Channel.whatsapp, DeliveryStatus.delivered, 1, rahul.mobile),
        ],
      ),
      kind: 'counselor',
      id: rahul.id,
    );
    add(
      LogRow(
        id: _id('row'),
        time: now.subtract(const Duration(minutes: 3)),
        level: AlertLevel.medium,
        outcome: Outcome.sent,
        organizationId: ncc.id,
        organizationName: ncc.name,
        studentRef: 'ASH-9Q2M',
        recipientName: anjali.fullName,
        recipientLabel: 'primary',
        channels: [
          ch(Channel.sms, DeliveryStatus.delivered, 1, anjali.mobile),
          ch(
            Channel.whatsapp,
            DeliveryStatus.retrying,
            2,
            anjali.mobile,
            error: 'provider timeout',
            next: now.add(const Duration(minutes: 5)),
          ),
        ],
      ),
      kind: 'counselor',
      id: anjali.id,
    );
    add(
      LogRow(
        id: _id('row'),
        time: now.subtract(const Duration(days: 1, hours: 2)),
        level: AlertLevel.medium,
        outcome: Outcome.skippedNoOrg,
        studentRef: 'ASH-5T1Z',
      ),
    );
    add(
      LogRow(
        id: _id('row'),
        time: now.subtract(const Duration(days: 2)),
        level: AlertLevel.medium,
        outcome: Outcome.skippedRepeat,
        organizationId: ncc.id,
        organizationName: ncc.name,
        studentRef: 'ASH-2K8P',
      ),
    );
    add(
      LogRow(
        id: _id('row'),
        time: now.subtract(const Duration(days: 3)),
        level: AlertLevel.low,
        outcome: Outcome.lowRecorded,
        organizationId: ncc.id,
        organizationName: ncc.name,
        studentRef: 'ASH-1B4C',
      ),
    );
  }
}
