// Organization, its contacts and its alert channel settings.
// JSON shapes follow docs/BACKEND_CHANGES.md (section "Console API contract").

import 'json.dart';

enum OrgStatus {
  draft('Draft'),
  active('Active'),
  inactive('Inactive');

  const OrgStatus(this.label);
  final String label;

  static OrgStatus parse(Object? v) =>
      OrgStatus.values.firstWhere((s) => s.name == v, orElse: () => OrgStatus.draft);

  /// Only Active organizations send alerts.
  bool get sendsAlerts => this == OrgStatus.active;
}

enum OrgType {
  college('College'),
  school('School'),
  ngo('NGO'),
  other('Other');

  const OrgType(this.label);
  final String label;

  static OrgType parse(Object? v) =>
      OrgType.values.firstWhere((s) => s.name == v, orElse: () => OrgType.college);
}

class LevelChannels {
  const LevelChannels({this.sms = true, this.whatsapp = true});
  final bool sms;
  final bool whatsapp;

  bool get any => sms || whatsapp;

  String get label {
    if (sms && whatsapp) return 'SMS + WhatsApp';
    if (sms) return 'SMS only';
    if (whatsapp) return 'WhatsApp only';
    return 'Not set';
  }

  LevelChannels copyWith({bool? sms, bool? whatsapp}) =>
      LevelChannels(sms: sms ?? this.sms, whatsapp: whatsapp ?? this.whatsapp);

  factory LevelChannels.fromJson(Object? json) {
    final m = asMap(json);
    return LevelChannels(
      sms: asBool(m['sms'], fallback: true),
      whatsapp: asBool(m['whatsapp'], fallback: true),
    );
  }

  Map<String, dynamic> toJson() => {'sms': sms, 'whatsapp': whatsapp};
}

/// Which channels each risk level uses. Low is recorded only (Phase 1).
class AlertChannels {
  const AlertChannels({this.medium = const LevelChannels(), this.high = const LevelChannels()});
  final LevelChannels medium;
  final LevelChannels high;

  bool get valid => medium.any && high.any;

  factory AlertChannels.fromJson(Object? json) {
    final m = asMap(json);
    return AlertChannels(
      medium: LevelChannels.fromJson(m['medium']),
      high: LevelChannels.fromJson(m['high']),
    );
  }

  Map<String, dynamic> toJson() => {'medium': medium.toJson(), 'high': high.toJson()};
}

class PersonRef {
  const PersonRef({required this.id, required this.fullName, this.mobile});
  final String id;
  final String fullName;
  final String? mobile;

  factory PersonRef.fromJson(Object? json) {
    final m = asMap(json);
    return PersonRef(
      id: asString(m['id']),
      fullName: asString(m['full_name']),
      mobile: asNullableString(m['mobile']),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'full_name': fullName, 'mobile': mobile};
}

class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.code,
    required this.type,
    required this.city,
    required this.state,
    this.notes = '',
    this.status = OrgStatus.draft,
    this.channels = const AlertChannels(),
    this.primaryCounselor,
    this.backupCounselors = const [],
    this.highRiskContacts = const [],
    this.counselorCount = 0,
    this.contactCount = 0,
    this.setupStep = 1,
    this.createdAt,
    this.activatedAt,
  });

  final String id;
  final String name;
  final String code;
  final OrgType type;
  final String city;
  final String state;
  final String notes;
  final OrgStatus status;
  final AlertChannels channels;
  final PersonRef? primaryCounselor;
  final List<PersonRef> backupCounselors;
  final List<PersonRef> highRiskContacts;
  final int counselorCount;
  final int contactCount;

  /// Highest setup step the admin has saved (1–5). Lets a Draft reopen on the
  /// next unfinished step.
  final int setupStep;
  final DateTime? createdAt;
  final DateTime? activatedAt;

  String get location => [city, state].where((s) => s.isNotEmpty).join(', ');

  factory Organization.fromJson(Object? json) {
    final m = asMap(json);
    return Organization(
      id: asString(m['id']),
      name: asString(m['name']),
      code: asString(m['code']),
      type: OrgType.parse(m['type']),
      city: asString(m['city']),
      state: asString(m['state']),
      notes: asString(m['notes']),
      status: OrgStatus.parse(m['status']),
      channels: AlertChannels.fromJson(m['channels']),
      primaryCounselor: m['primary_counselor'] == null ? null : PersonRef.fromJson(m['primary_counselor']),
      backupCounselors: asList(m['backup_counselors']).map(PersonRef.fromJson).toList(),
      highRiskContacts: asList(m['high_risk_contacts']).map(PersonRef.fromJson).toList(),
      counselorCount: asInt(m['counselor_count']),
      contactCount: asInt(m['contact_count']),
      setupStep: asInt(m['setup_step'], fallback: 1),
      createdAt: asDate(m['created_at']),
      activatedAt: asDate(m['activated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'code': code,
    'type': type.name,
    'city': city,
    'state': state,
    'notes': notes,
    'status': status.name,
    'channels': channels.toJson(),
    'primary_counselor': primaryCounselor?.toJson(),
    'backup_counselors': backupCounselors.map((p) => p.toJson()).toList(),
    'high_risk_contacts': highRiskContacts.map((p) => p.toJson()).toList(),
    'counselor_count': counselorCount,
    'contact_count': contactCount,
    'setup_step': setupStep,
    'created_at': createdAt?.toIso8601String(),
    'activated_at': activatedAt?.toIso8601String(),
  };
}

/// Fields the admin edits on step 1 / the Details tab.
class OrgDetailsInput {
  const OrgDetailsInput({
    required this.name,
    required this.code,
    required this.type,
    required this.city,
    required this.state,
    this.notes = '',
  });
  final String name;
  final String code;
  final OrgType type;
  final String city;
  final String state;
  final String notes;

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'code': code.trim().toUpperCase(),
    'type': type.name,
    'city': city.trim(),
    'state': state.trim(),
    'notes': notes.trim(),
  };
}

/// Someone at the organization (principal, dean, welfare officer) who may be
/// told about High-risk cases. Not a counselor.
class OrgContact {
  const OrgContact({
    this.id,
    required this.fullName,
    required this.title,
    required this.mobile,
    this.whatsapp,
    this.email = '',
    this.receivesHighAlerts = false,
  });

  /// Null for a contact not saved yet.
  final String? id;
  final String fullName;

  /// Their role at the organization, e.g. "Principal".
  final String title;
  final String mobile;

  /// Null = no WhatsApp.
  final String? whatsapp;
  final String email;
  final bool receivesHighAlerts;

  bool get whatsappSameAsMobile => whatsapp != null && whatsapp == mobile;

  factory OrgContact.fromJson(Object? json) {
    final m = asMap(json);
    return OrgContact(
      id: asNullableString(m['id']),
      fullName: asString(m['full_name']),
      title: asString(m['title']),
      mobile: asString(m['mobile']),
      whatsapp: asNullableString(m['whatsapp']),
      email: asString(m['email']),
      receivesHighAlerts: asBool(m['receives_high_alerts']),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'full_name': fullName,
    'title': title,
    'mobile': mobile,
    'whatsapp': whatsapp,
    'email': email,
    'receives_high_alerts': receivesHighAlerts,
  };

  OrgContact copyWith({String? id}) => OrgContact(
    id: id ?? this.id,
    fullName: fullName,
    title: title,
    mobile: mobile,
    whatsapp: whatsapp,
    email: email,
    receivesHighAlerts: receivesHighAlerts,
  );
}

/// GET /organizations/{id}/readiness/ — what still blocks activation.
class Readiness {
  const Readiness({
    required this.detailsComplete,
    required this.code,
    required this.highRiskContactCount,
    required this.primaryCounselorName,
    required this.channelsSet,
    required this.testRun,
    required this.testsAllReached,
    required this.missing,
  });

  final bool detailsComplete;
  final String code;
  final int highRiskContactCount;
  final String? primaryCounselorName;
  final bool channelsSet;
  final bool testRun;
  final bool testsAllReached;

  /// Machine codes: high_risk_contact, primary_counselor, channels, test_alerts.
  final List<String> missing;

  bool get canActivate => missing.isEmpty;

  factory Readiness.fromJson(Object? json) {
    final m = asMap(json);
    return Readiness(
      detailsComplete: asBool(m['details_complete']),
      code: asString(m['code']),
      highRiskContactCount: asInt(m['high_risk_contact_count']),
      primaryCounselorName: asNullableString(m['primary_counselor_name']),
      channelsSet: asBool(m['channels_set']),
      testRun: asBool(m['test_run']),
      testsAllReached: asBool(m['tests_all_reached']),
      missing: asList(m['missing']).map(asString).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'details_complete': detailsComplete,
    'code': code,
    'high_risk_contact_count': highRiskContactCount,
    'primary_counselor_name': primaryCounselorName,
    'channels_set': channelsSet,
    'test_run': testRun,
    'tests_all_reached': testsAllReached,
    'missing': missing,
  };
}
