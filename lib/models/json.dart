// Tolerant JSON readers: the console must not crash on a null or a
// number-as-string from the API.

Map<String, dynamic> asMap(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : <String, dynamic>{};

List<Object?> asList(Object? v) => v is List ? v : const [];

String asString(Object? v, {String fallback = ''}) => v == null ? fallback : v.toString();

String? asNullableString(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

int asInt(Object? v, {int fallback = 0}) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

bool asBool(Object? v, {bool fallback = false}) {
  if (v is bool) return v;
  if (v is String) return v == 'true' || v == '1';
  if (v is num) return v != 0;
  return fallback;
}

DateTime? asDate(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// DRF paginated list: {"count", "next", "previous", "results"}.
class ApiPage<T> {
  const ApiPage({required this.results, required this.count, this.hasMore = false});
  final List<T> results;
  final int count;
  final bool hasMore;

  factory ApiPage.fromJson(Object? json, T Function(Object?) parse) {
    final m = asMap(json);
    final results = asList(m['results']).map(parse).toList();
    return ApiPage(
      results: results,
      count: asInt(m['count'], fallback: results.length),
      hasMore: m['next'] != null,
    );
  }
}
