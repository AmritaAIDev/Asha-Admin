// Everything the console asks the backend for. Two implementations:
//   * HttpConsoleApi  — talks to Django (/api/auth/*, /api/console/*)
//   * MockConsoleApi  — in-memory sample data (USE_MOCK=true) so the UI can be
//                       built and demoed before the backend exists.
// Paths, bodies and error codes are listed in docs/BACKEND_CHANGES.md.
//
// Pure Dart: no Flutter imports.

import '../models/alerts.dart';
import '../models/counselor.dart';
import '../models/json.dart';
import '../models/organization.dart';

export '../models/alerts.dart';
export '../models/counselor.dart';
export '../models/json.dart';
export '../models/organization.dart';

/// Error from the API in the project-wide shape
/// `{"detail", "code", "errors"?: {field: [msg]}}` (Asha_Django/api_errors.py).
class ApiException implements Exception {
  ApiException({
    required this.statusCode,
    required this.code,
    required this.detail,
    this.fieldErrors = const {},
    this.extra = const {},
  });

  final int statusCode;
  final String code;
  final String detail;
  final Map<String, List<String>> fieldErrors;

  /// Any other keys in the body, e.g. `missing` on 422 activate,
  /// `retry_after` on 429 login_locked.
  final Map<String, dynamic> extra;

  String? fieldError(String field) {
    final list = fieldErrors[field];
    return (list == null || list.isEmpty) ? null : list.first;
  }

  bool get isAuth => statusCode == 401;

  factory ApiException.fromBody(int statusCode, Object? body) {
    final m = asMap(body);
    final errors = <String, List<String>>{};
    asMap(m['errors']).forEach((k, v) {
      errors[k] = v is List ? v.map((e) => e.toString()).toList() : [v.toString()];
    });
    final extra = Map<String, dynamic>.from(m)
      ..remove('detail')
      ..remove('code')
      ..remove('errors');
    return ApiException(
      statusCode: statusCode,
      code: asString(m['code'], fallback: 'error'),
      detail: asString(
        m['detail'],
        fallback: statusCode >= 500
            ? 'The server had a problem. Try again in a minute.'
            : 'Something went wrong.',
      ),
      fieldErrors: errors,
      extra: extra,
    );
  }

  factory ApiException.network() => ApiException(
    statusCode: 0,
    code: 'network_error',
    detail: "Can't reach the Asha server. Check your connection and try again.",
  );

  @override
  String toString() => 'ApiException($statusCode, $code, $detail)';
}

/// Shown on the login screen for any non-staff account.
const String kNoConsoleAccess = "This account doesn't have console access.";

abstract class ConsoleApi {
  // ── Auth ──────────────────────────────────────────────────────────────
  /// Signs in and returns the user. Throws ApiException with code
  /// `not_staff` when the account is not staff (tokens are discarded).
  Future<AdminUser> signIn(String login, String password);

  /// Current user from stored tokens, or null if there is no valid session.
  Future<AdminUser?> restoreSession();

  Future<void> signOut();

  // ── Organizations ─────────────────────────────────────────────────────
  Future<ApiPage<Organization>> listOrganizations({String? search, OrgStatus? status, int page = 1});
  Future<Organization> getOrganization(String id);

  /// Creates a Draft. 400 `validation_error` with errors.code when the code is taken.
  Future<Organization> createOrganization(OrgDetailsInput input);
  Future<Organization> updateOrganization(String id, OrgDetailsInput input);
  Future<Organization> updateChannels(String id, AlertChannels channels);

  /// Records how far setup got so a Draft reopens on the right step.
  Future<void> saveSetupStep(String id, int step);

  Future<List<OrgContact>> listContacts(String orgId);

  /// Replaces the organization's contact list. Contacts missing from [contacts]
  /// are removed (deactivated server-side so old log rows keep their name).
  Future<List<OrgContact>> saveContacts(String orgId, List<OrgContact> contacts);

  Future<List<OrgCounselor>> listOrgCounselors(String orgId);

  /// Replaces assignments. 400 when more than one primary or a counselor has no
  /// consent; 409 `primary_required` when an Active organization would be left
  /// without a primary.
  Future<List<OrgCounselor>> saveOrgCounselors(
    String orgId,
    List<({String counselorId, CounselorRole role})> assignments,
  );

  Future<Readiness> getReadiness(String orgId);

  /// Sends a TEST message on every channel to every recipient.
  Future<TestRun> sendOrgTestAlerts(String orgId);
  Future<TestRun?> latestOrgTest(String orgId);

  /// 422 `not_ready` with `missing: [...]` when something blocks activation.
  Future<Organization> activate(String orgId);
  Future<Organization> deactivate(String orgId);

  // ── Counselors ────────────────────────────────────────────────────────
  Future<ApiPage<Counselor>> listCounselors({String? search, bool? active, int page = 1});
  Future<Counselor> getCounselor(String id);
  Future<Counselor> createCounselor(CounselorInput input);
  Future<Counselor> updateCounselor(String id, CounselorInput input);

  /// 409 `only_primary` while the counselor is the only primary of an Active organization.
  Future<Counselor> setCounselorActive(String id, bool active);
  Future<TestRun> sendCounselorTest(String id);

  // ── Delivery log ──────────────────────────────────────────────────────
  Future<ApiPage<LogRow>> listLog(LogFilter filter, {int page = 1});

  /// High alerts that failed on every channel for a recipient and were not resent.
  Future<int> countNeedsAttention();

  /// Re-queues a failed delivery to the recipient's current number.
  Future<void> resendDelivery(String deliveryId);
}
