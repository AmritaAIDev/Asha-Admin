// Delivery log rows and test-alert results.

import 'json.dart';

enum AlertLevel {
  low('Low'),
  medium('Medium'),
  high('High'),
  test('Test');

  const AlertLevel(this.label);
  final String label;

  static AlertLevel parse(Object? v) =>
      AlertLevel.values.firstWhere((l) => l.name == v, orElse: () => AlertLevel.low);
}

enum Channel {
  sms('SMS'),
  whatsapp('WhatsApp');

  const Channel(this.label);
  final String label;

  static Channel parse(Object? v) => v == 'whatsapp' ? Channel.whatsapp : Channel.sms;
}

enum DeliveryStatus {
  queued('Queued'),
  sent('Sent'),
  delivered('Delivered'),
  retrying('Retrying'),
  failed('Failed');

  const DeliveryStatus(this.label);
  final String label;

  static DeliveryStatus parse(Object? v) =>
      DeliveryStatus.values.firstWhere((s) => s.name == v, orElse: () => DeliveryStatus.queued);

  bool get isFinal => this == delivered || this == failed;
  bool get reached => this == delivered;
}

/// RiskEvent.outcome, plus "test" for test messages.
enum Outcome {
  sent('Sent'),
  test('Test'),
  lowRecorded('Recorded only'),
  skippedDraft('Skipped · organization is Draft'),
  skippedInactive('Skipped · organization is Inactive'),
  skippedNoOrg('Skipped · student has no organization'),
  skippedRepeat('Skipped · repeat within 6 hours');

  const Outcome(this.label);
  final String label;

  static const Map<String, Outcome> _wire = {
    'sent': Outcome.sent,
    'test': Outcome.test,
    'low_recorded': Outcome.lowRecorded,
    'skipped_draft': Outcome.skippedDraft,
    'skipped_inactive': Outcome.skippedInactive,
    'skipped_no_org': Outcome.skippedNoOrg,
    'skipped_repeat': Outcome.skippedRepeat,
  };

  static Outcome parse(Object? v) => _wire[v] ?? Outcome.sent;
  String get wire => _wire.entries.firstWhere((e) => e.value == this).key;

  bool get isSkipped =>
      this == skippedDraft || this == skippedInactive || this == skippedNoOrg || this == skippedRepeat;
}

class LogChannel {
  const LogChannel({
    required this.deliveryId,
    required this.channel,
    required this.status,
    this.attempts = 0,
    this.error,
    this.nextRetryAt,
    this.phone,
  });

  final String deliveryId;
  final Channel channel;
  final DeliveryStatus status;
  final int attempts;

  /// Human-readable reason from the provider, e.g. "number not on WhatsApp".
  final String? error;
  final DateTime? nextRetryAt;

  /// Number used for this attempt (snapshot).
  final String? phone;

  factory LogChannel.fromJson(Object? json) {
    final m = asMap(json);
    return LogChannel(
      deliveryId: asString(m['delivery_id']),
      channel: Channel.parse(m['channel']),
      status: DeliveryStatus.parse(m['status']),
      attempts: asInt(m['attempts']),
      error: asNullableString(m['error']),
      nextRetryAt: asDate(m['next_retry_at']),
      phone: asNullableString(m['phone']),
    );
  }

  Map<String, dynamic> toJson() => {
    'delivery_id': deliveryId,
    'channel': channel.name,
    'status': status.name,
    'attempts': attempts,
    'error': error,
    'next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
    'phone': phone,
  };
}

/// One row per risk event per recipient (all channels to that recipient), or
/// one row per skipped event with no recipient.
class LogRow {
  const LogRow({
    required this.id,
    required this.time,
    required this.level,
    required this.outcome,
    this.organizationId,
    this.organizationName,
    this.studentRef,
    this.recipientName,
    this.recipientLabel,
    this.channels = const [],
    this.resolved = false,
  });

  final String id;
  final DateTime time;
  final AlertLevel level;
  final Outcome outcome;
  final String? organizationId;
  final String? organizationName;

  /// ASH-XXXX. Null for test messages.
  final String? studentRef;
  final String? recipientName;

  /// "primary", "backup", "contact" or the contact's title.
  final String? recipientLabel;
  final List<LogChannel> channels;

  /// True once a resend of this row was delivered, so the red banner clears.
  final bool resolved;

  bool get failedOnEvery => channels.isNotEmpty && channels.every((c) => c.status == DeliveryStatus.failed);

  bool get anyFailed => channels.any((c) => c.status == DeliveryStatus.failed);

  /// High alert that reached this recipient on no channel and was not resent.
  bool get needsAttention => level == AlertLevel.high && failedOnEvery && !resolved;

  int get attempts => channels.fold(0, (m, c) => c.attempts > m ? c.attempts : m);

  String get channelsLabel {
    if (channels.isEmpty) return '—';
    return channels.map((c) => c.channel.label).join(' + ');
  }

  factory LogRow.fromJson(Object? json) {
    final m = asMap(json);
    final org = m['organization'] == null ? null : asMap(m['organization']);
    final rec = m['recipient'] == null ? null : asMap(m['recipient']);
    return LogRow(
      id: asString(m['id']),
      time: asDate(m['time']) ?? DateTime.now(),
      level: AlertLevel.parse(m['level']),
      outcome: Outcome.parse(m['outcome']),
      organizationId: org == null ? null : asNullableString(org['id']),
      organizationName: org == null ? null : asNullableString(org['name']),
      studentRef: asNullableString(m['student_ref']),
      recipientName: rec == null ? null : asNullableString(rec['name']),
      recipientLabel: rec == null ? null : asNullableString(rec['label']),
      channels: asList(m['channels']).map(LogChannel.fromJson).toList(),
      resolved: asBool(m['resolved']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'time': time.toUtc().toIso8601String(),
    'level': level.name,
    'outcome': outcome.wire,
    'organization': organizationId == null ? null : {'id': organizationId, 'name': organizationName},
    'student_ref': studentRef,
    'recipient': recipientName == null ? null : {'name': recipientName, 'label': recipientLabel},
    'channels': channels.map((c) => c.toJson()).toList(),
    'resolved': resolved,
  };
}

enum LogRange {
  day('Last 24 hours', Duration(days: 1)),
  week('Last 7 days', Duration(days: 7)),
  month('Last 30 days', Duration(days: 30)),
  all('All time', null);

  const LogRange(this.label, this.span);
  final String label;
  final Duration? span;
}

/// Filter values for the delivery log. Status "failed" means at least one
/// channel failed; "skipped" means the event was not sent.
class LogFilter {
  const LogFilter({
    this.organizationId,
    this.level,
    this.status,
    this.range = LogRange.week,
    this.needsAttentionOnly = false,
  });

  final String? organizationId;
  final AlertLevel? level;
  final String? status; // delivered | failed | retrying | skipped
  final LogRange range;
  final bool needsAttentionOnly;

  Map<String, String> toQuery(DateTime now) => {
    'organization': ?organizationId,
    if (level != null) 'level': level!.name,
    'status': ?status,
    if (range.span != null) 'from': now.subtract(range.span!).toUtc().toIso8601String(),
    if (needsAttentionOnly) 'needs_attention': 'true',
  };
}

class ChannelResult {
  const ChannelResult({required this.status, this.error, this.deliveryId});
  final DeliveryStatus status;
  final String? error;
  final String? deliveryId;

  factory ChannelResult.fromJson(Object? json) {
    final m = asMap(json);
    return ChannelResult(
      status: DeliveryStatus.parse(m['status']),
      error: asNullableString(m['error']),
      deliveryId: asNullableString(m['delivery_id']),
    );
  }

  Map<String, dynamic> toJson() => {'status': status.name, 'error': error, 'delivery_id': deliveryId};
}

class TestRecipient {
  const TestRecipient({
    required this.name,
    required this.roleLabel,
    required this.phone,
    required this.sms,
    this.whatsapp,
  });

  final String name;
  final String roleLabel;
  final String phone;
  final ChannelResult sms;

  /// Null when the recipient has no WhatsApp number.
  final ChannelResult? whatsapp;

  bool get reached => sms.status.reached || (whatsapp?.status.reached ?? false);
  bool get pending => !sms.status.isFinal || (whatsapp != null && !whatsapp!.status.isFinal);

  factory TestRecipient.fromJson(Object? json) {
    final m = asMap(json);
    return TestRecipient(
      name: asString(m['name']),
      roleLabel: asString(m['role_label']),
      phone: asString(m['phone']),
      sms: ChannelResult.fromJson(m['sms']),
      whatsapp: m['whatsapp'] == null ? null : ChannelResult.fromJson(m['whatsapp']),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'role_label': roleLabel,
    'phone': phone,
    'sms': sms.toJson(),
    'whatsapp': whatsapp?.toJson(),
  };
}

class TestRun {
  const TestRun({required this.runAt, required this.recipients});
  final DateTime runAt;
  final List<TestRecipient> recipients;

  bool get allReached => recipients.isNotEmpty && recipients.every((r) => r.reached);
  bool get pending => recipients.any((r) => r.pending);

  factory TestRun.fromJson(Object? json) {
    final m = asMap(json);
    return TestRun(
      runAt: asDate(m['run_at']) ?? DateTime.now(),
      recipients: asList(m['recipients']).map(TestRecipient.fromJson).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'run_at': runAt.toUtc().toIso8601String(),
    'recipients': recipients.map((r) => r.toJson()).toList(),
  };
}

class AdminUser {
  const AdminUser({required this.id, required this.username, this.email, this.isStaff = false});
  final String id;
  final String username;
  final String? email;
  final bool isStaff;

  factory AdminUser.fromJson(Object? json) {
    final m = asMap(json);
    return AdminUser(
      id: asString(m['id']),
      username: asString(m['username']),
      email: asNullableString(m['email']),
      isStaff: asBool(m['is_staff']),
    );
  }
}
