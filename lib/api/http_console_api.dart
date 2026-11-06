// ConsoleApi over HTTP against Django.
//
// Auth reuses the existing endpoints (POST /api/auth/login/, /token/refresh/,
// /logout/, GET /api/auth/me/). Everything else lives under /api/console/,
// which the backend still has to add — see docs/BACKEND_CHANGES.md.
//
// Token refresh follows Asha_Frontend's ApiService: refresh proactively when
// the access token is about to expire, single-flight so parallel requests
// share one refresh, and retry once on 401.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'console_api.dart';
import 'token_store.dart';

class HttpConsoleApi implements ConsoleApi {
  HttpConsoleApi({required this.baseUrl, required this.tokens, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final TokenStore tokens;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 30);

  // ── plumbing ──────────────────────────────────────────────────────────

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('$baseUrl$path');
    return (query == null || query.isEmpty) ? u : u.replace(queryParameters: query);
  }

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool auth = true,
    bool retried = false,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json', 'Accept': 'application/json'};
    if (auth) {
      final t = await _freshAccess();
      if (t != null) headers['Authorization'] = 'Bearer $t';
    }
    final req = http.Request(method, _uri(path, query))..headers.addAll(headers);
    if (body != null) req.body = jsonEncode(body);

    final http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(_timeout));
    } on TimeoutException {
      throw ApiException.network();
    } catch (_) {
      throw ApiException.network();
    }

    if (res.statusCode == 401 && auth && !retried) {
      if (await _refresh()) {
        return _send(method, path, body: body, query: query, auth: auth, retried: true);
      }
    }

    Object? decoded;
    if (res.body.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        decoded = null;
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
    if (res.statusCode == 401 && auth) {
      await tokens.clear();
    }
    throw ApiException.fromBody(res.statusCode, decoded);
  }

  Future<Object?> _get(String path, [Map<String, String>? q]) => _send('GET', path, query: q);
  Future<Object?> _post(String path, [Object? body]) => _send('POST', path, body: body ?? const {});
  Future<Object?> _patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<Object?> _put(String path, Object body) => _send('PUT', path, body: body);

  // ── tokens ────────────────────────────────────────────────────────────

  Future<String?> _freshAccess() async {
    final access = await tokens.access;
    if (access == null || access.isEmpty) return null;
    final exp = _jwtExpiry(access);
    if (exp != null && exp.isBefore(DateTime.now().toUtc().add(const Duration(seconds: 30)))) {
      if (await _refresh()) return tokens.access;
    }
    return access;
  }

  Future<bool>? _refreshing;

  Future<bool> _refresh() {
    final existing = _refreshing;
    if (existing != null) return existing;
    final f = _doRefresh();
    _refreshing = f;
    f.whenComplete(() {
      if (identical(_refreshing, f)) _refreshing = null;
    });
    return f;
  }

  Future<bool> _doRefresh() async {
    final refresh = await tokens.refresh;
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final res = await _client
          .post(
            _uri('/api/auth/token/refresh/'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh': refresh}),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) return false;
      final m = asMap(jsonDecode(res.body));
      final access = asNullableString(m['access']);
      if (access == null) return false;
      // The backend omits "refresh" inside its multi-tab grace window.
      await tokens.save(access: access, refresh: asNullableString(m['refresh']) ?? refresh);
      return true;
    } catch (_) {
      return false;
    }
  }

  static DateTime? _jwtExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload = asMap(jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))));
      final exp = payload['exp'];
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
    } catch (_) {
      return null;
    }
  }

  // ── Auth ──────────────────────────────────────────────────────────────

  @override
  Future<AdminUser> signIn(String login, String password) async {
    final m = asMap(
      await _send(
        'POST',
        '/api/auth/login/',
        body: {'login': login.trim(), 'password': password},
        auth: false,
      ),
    );
    await tokens.save(access: asString(m['access']), refresh: asString(m['refresh']));
    final user = AdminUser.fromJson(await _get('/api/auth/me/'));
    if (!user.isStaff) {
      // Sign this device back out so the account's device limit isn't used up.
      await signOut();
      throw ApiException(statusCode: 403, code: 'not_staff', detail: kNoConsoleAccess);
    }
    return user;
  }

  @override
  Future<AdminUser?> restoreSession() async {
    if ((await tokens.access) == null) return null;
    try {
      final user = AdminUser.fromJson(await _get('/api/auth/me/'));
      if (!user.isStaff) {
        await tokens.clear();
        return null;
      }
      return user;
    } on ApiException catch (e) {
      if (e.isAuth || e.statusCode == 403) {
        await tokens.clear();
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    final refresh = await tokens.refresh;
    try {
      if ((await tokens.access) != null) {
        await _post('/api/auth/logout/', {'refresh': ?refresh});
      }
    } catch (_) {
      // Signing out locally must work even when the server can't be reached.
    } finally {
      await tokens.clear();
    }
  }

  // ── Organizations ─────────────────────────────────────────────────────

  static const _c = '/api/console';

  @override
  Future<ApiPage<Organization>> listOrganizations({String? search, OrgStatus? status, int page = 1}) async =>
      ApiPage.fromJson(
        await _get('$_c/organizations/', {
          if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
          if (status != null) 'status': status.name,
          'page': '$page',
        }),
        Organization.fromJson,
      );

  @override
  Future<Organization> getOrganization(String id) async =>
      Organization.fromJson(await _get('$_c/organizations/$id/'));

  @override
  Future<Organization> createOrganization(OrgDetailsInput input) async =>
      Organization.fromJson(await _post('$_c/organizations/', input.toJson()));

  @override
  Future<Organization> updateOrganization(String id, OrgDetailsInput input) async =>
      Organization.fromJson(await _patch('$_c/organizations/$id/', input.toJson()));

  @override
  Future<Organization> updateChannels(String id, AlertChannels channels) async =>
      Organization.fromJson(await _patch('$_c/organizations/$id/', {'channels': channels.toJson()}));

  @override
  Future<void> saveSetupStep(String id, int step) async {
    await _patch('$_c/organizations/$id/', {'setup_step': step});
  }

  @override
  Future<List<OrgContact>> listContacts(String orgId) async =>
      asList(await _get('$_c/organizations/$orgId/contacts/')).map(OrgContact.fromJson).toList();

  @override
  Future<List<OrgContact>> saveContacts(String orgId, List<OrgContact> contacts) async => asList(
    await _put('$_c/organizations/$orgId/contacts/', contacts.map((c) => c.toJson()).toList()),
  ).map(OrgContact.fromJson).toList();

  @override
  Future<List<OrgCounselor>> listOrgCounselors(String orgId) async =>
      asList(await _get('$_c/organizations/$orgId/counselors/')).map(OrgCounselor.fromJson).toList();

  @override
  Future<List<OrgCounselor>> saveOrgCounselors(
    String orgId,
    List<({String counselorId, CounselorRole role})> assignments,
  ) async => asList(
    await _put(
      '$_c/organizations/$orgId/counselors/',
      assignments.map((a) => {'counselor_id': a.counselorId, 'role': a.role.name}).toList(),
    ),
  ).map(OrgCounselor.fromJson).toList();

  @override
  Future<Readiness> getReadiness(String orgId) async =>
      Readiness.fromJson(await _get('$_c/organizations/$orgId/readiness/'));

  @override
  Future<TestRun> sendOrgTestAlerts(String orgId) async =>
      TestRun.fromJson(await _post('$_c/organizations/$orgId/test-alerts/'));

  @override
  Future<TestRun?> latestOrgTest(String orgId) async {
    try {
      return TestRun.fromJson(await _get('$_c/organizations/$orgId/test-alerts/latest/'));
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<Organization> activate(String orgId) async =>
      Organization.fromJson(await _post('$_c/organizations/$orgId/activate/'));

  @override
  Future<Organization> deactivate(String orgId) async =>
      Organization.fromJson(await _post('$_c/organizations/$orgId/deactivate/'));

  // ── Counselors ────────────────────────────────────────────────────────

  @override
  Future<ApiPage<Counselor>> listCounselors({String? search, bool? active, int page = 1}) async =>
      ApiPage.fromJson(
        await _get('$_c/counselors/', {
          if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
          if (active != null) 'is_active': '$active',
          'page': '$page',
        }),
        Counselor.fromJson,
      );

  @override
  Future<Counselor> getCounselor(String id) async => Counselor.fromJson(await _get('$_c/counselors/$id/'));

  @override
  Future<Counselor> createCounselor(CounselorInput input) async =>
      Counselor.fromJson(await _post('$_c/counselors/', input.toJson()));

  @override
  Future<Counselor> updateCounselor(String id, CounselorInput input) async =>
      Counselor.fromJson(await _patch('$_c/counselors/$id/', input.toJson()));

  @override
  Future<Counselor> setCounselorActive(String id, bool active) async =>
      Counselor.fromJson(await _patch('$_c/counselors/$id/', {'is_active': active}));

  @override
  Future<TestRun> sendCounselorTest(String id) async =>
      TestRun.fromJson(await _post('$_c/counselors/$id/test-alert/'));

  // ── Delivery log ──────────────────────────────────────────────────────

  @override
  Future<ApiPage<LogRow>> listLog(LogFilter filter, {int page = 1}) async => ApiPage.fromJson(
    await _get('$_c/alerts/', {...filter.toQuery(DateTime.now()), 'page': '$page'}),
    LogRow.fromJson,
  );

  @override
  Future<int> countNeedsAttention() async =>
      asInt(asMap(await _get('$_c/alerts/summary/'))['needs_attention']);

  @override
  Future<void> resendDelivery(String deliveryId) async {
    await _post('$_c/alerts/$deliveryId/resend/');
  }
}
