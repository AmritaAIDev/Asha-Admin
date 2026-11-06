// Counselors are shared across organizations: one counselor record can be the
// primary at one college and a backup at another.

import 'json.dart';
import 'organization.dart';

const List<String> kCounselorLanguages = [
  'English',
  'Hindi',
  'Kannada',
  'Malayalam',
  'Tamil',
  'Telugu',
  'Marathi',
  'Bengali',
  'Gujarati',
  'Punjabi',
  'Odia',
  'Assamese',
  'Urdu',
];

enum CounselorRole {
  primary('Primary'),
  backup('Backup');

  const CounselorRole(this.label);
  final String label;

  static CounselorRole parse(Object? v) => v == 'primary' ? CounselorRole.primary : CounselorRole.backup;
}

/// One counselor's role at one organization.
class Assignment {
  const Assignment({
    required this.organizationId,
    required this.organizationName,
    required this.organizationStatus,
    required this.role,
    this.isOnlyPrimary = false,
  });

  final String organizationId;
  final String organizationName;
  final OrgStatus organizationStatus;
  final CounselorRole role;

  /// True when this counselor is the primary and the organization has no
  /// other active primary candidate set. Deactivating is blocked while this is
  /// true for an Active organization.
  final bool isOnlyPrimary;

  bool get blocksDeactivation =>
      isOnlyPrimary && role == CounselorRole.primary && organizationStatus == OrgStatus.active;

  factory Assignment.fromJson(Object? json) {
    final m = asMap(json);
    final org = asMap(m['organization']);
    return Assignment(
      organizationId: asString(org['id']),
      organizationName: asString(org['name']),
      organizationStatus: OrgStatus.parse(org['status']),
      role: CounselorRole.parse(m['role']),
      isOnlyPrimary: asBool(m['is_only_primary']),
    );
  }

  Map<String, dynamic> toJson() => {
    'organization': {'id': organizationId, 'name': organizationName, 'status': organizationStatus.name},
    'role': role.name,
    'is_only_primary': isOnlyPrimary,
  };
}

class LastTest {
  const LastTest({required this.at, required this.sms, this.whatsapp});
  final DateTime? at;
  final String sms;
  final String? whatsapp;

  factory LastTest.fromJson(Object? json) {
    final m = asMap(json);
    return LastTest(at: asDate(m['at']), sms: asString(m['sms']), whatsapp: asNullableString(m['whatsapp']));
  }

  Map<String, dynamic> toJson() => {'at': at?.toIso8601String(), 'sms': sms, 'whatsapp': whatsapp};
}

class Counselor {
  const Counselor({
    required this.id,
    required this.fullName,
    required this.mobile,
    this.whatsapp,
    this.email = '',
    this.languages = const [],
    this.notes = '',
    this.consentAt,
    this.isActive = true,
    this.assignments = const [],
    this.lastTest,
  });

  final String id;
  final String fullName;
  final String mobile;
  final String? whatsapp;
  final String email;
  final List<String> languages;
  final String notes;

  /// When the admin recorded the counselor's consent to receive alerts.
  /// A counselor without consent cannot be assigned to any organization.
  final DateTime? consentAt;
  final bool isActive;
  final List<Assignment> assignments;
  final LastTest? lastTest;

  bool get hasConsent => consentAt != null;
  bool get whatsappSameAsMobile => whatsapp != null && whatsapp == mobile;
  bool get canBeAssigned => hasConsent && isActive;

  List<Assignment> get blockingAssignments => assignments.where((a) => a.blocksDeactivation).toList();

  factory Counselor.fromJson(Object? json) {
    final m = asMap(json);
    return Counselor(
      id: asString(m['id']),
      fullName: asString(m['full_name']),
      mobile: asString(m['mobile']),
      whatsapp: asNullableString(m['whatsapp']),
      email: asString(m['email']),
      languages: asList(m['languages']).map(asString).toList(),
      notes: asString(m['notes']),
      consentAt: asDate(m['consent_at']),
      isActive: asBool(m['is_active'], fallback: true),
      assignments: asList(m['assignments']).map(Assignment.fromJson).toList(),
      lastTest: m['last_test'] == null ? null : LastTest.fromJson(m['last_test']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': fullName,
    'mobile': mobile,
    'whatsapp': whatsapp,
    'email': email,
    'languages': languages,
    'notes': notes,
    'consent_at': consentAt?.toUtc().toIso8601String(),
    'is_active': isActive,
    'assignments': assignments.map((a) => a.toJson()).toList(),
    'last_test': lastTest?.toJson(),
  };
}

class CounselorInput {
  const CounselorInput({
    required this.fullName,
    required this.mobile,
    this.whatsapp,
    this.email = '',
    this.languages = const [],
    this.notes = '',
    required this.consent,
  });

  final String fullName;
  final String mobile;
  final String? whatsapp;
  final String email;
  final List<String> languages;
  final String notes;

  /// Must be true on create; the server stamps consent_at.
  final bool consent;

  Map<String, dynamic> toJson() => {
    'full_name': fullName.trim(),
    'mobile': mobile,
    'whatsapp': whatsapp,
    'email': email.trim(),
    'languages': languages,
    'notes': notes.trim(),
    'consent': consent,
  };
}

/// A counselor as assigned to one organization (setup step 3).
class OrgCounselor {
  const OrgCounselor({required this.counselor, required this.role});
  final Counselor counselor;
  final CounselorRole role;

  OrgCounselor withRole(CounselorRole r) => OrgCounselor(counselor: counselor, role: r);

  factory OrgCounselor.fromJson(Object? json) {
    final m = asMap(json);
    return OrgCounselor(counselor: Counselor.fromJson(m['counselor']), role: CounselorRole.parse(m['role']));
  }

  Map<String, dynamic> toJson() => {'counselor': counselor.toJson(), 'role': role.name};
}
