// Message simulator: what each phone would have received while SMS and
// WhatsApp are simulated (GET /api/console/simulator/ and .../messages/).
//
// Pure Dart: no Flutter imports.

import 'alerts.dart';
import 'json.dart';

class SimulatorStatus {
  const SimulatorStatus({
    required this.enabled,
    required this.smsProvider,
    required this.whatsappProvider,
    required this.failures,
    required this.keepDays,
    required this.phones,
  });

  /// True when SMS or WhatsApp goes to the simulator instead of a real gateway.
  final bool enabled;
  final String smsProvider;
  final String whatsappProvider;

  /// Failure rules on: a number ending in 0 is "not on WhatsApp", 00 also fails on SMS.
  final bool failures;
  final int keepDays;

  /// Every number that got a simulated message, most recent first.
  final List<SimPhone> phones;

  factory SimulatorStatus.fromJson(Object? json) {
    final m = asMap(json);
    return SimulatorStatus(
      enabled: asBool(m['enabled']),
      smsProvider: asString(m['sms_provider']),
      whatsappProvider: asString(m['whatsapp_provider']),
      failures: asBool(m['failures']),
      keepDays: asInt(m['keep_days'], fallback: 7),
      phones: asList(m['phones']).map(SimPhone.fromJson).toList(),
    );
  }
}

class SimPhone {
  const SimPhone({
    required this.phone,
    required this.name,
    required this.label,
    required this.organizationName,
    required this.count,
    required this.lastAt,
  });

  final String phone;
  final String name;

  /// primary | backup | contact
  final String label;
  final String organizationName;
  final int count;
  final DateTime? lastAt;

  factory SimPhone.fromJson(Object? json) {
    final m = asMap(json);
    return SimPhone(
      phone: asString(m['phone']),
      name: asString(m['name']),
      label: asString(m['label']),
      organizationName: asString(m['organization_name']),
      count: asInt(m['count']),
      lastAt: asDate(m['last_at']),
    );
  }
}

class SimMessage {
  const SimMessage({
    required this.id,
    required this.createdAt,
    required this.channel,
    required this.phone,
    required this.recipientName,
    required this.recipientLabel,
    required this.organizationName,
    required this.level,
    required this.text,
    required this.delivered,
    this.error,
  });

  final String id;
  final DateTime? createdAt;
  final Channel channel;
  final String phone;
  final String recipientName;
  final String recipientLabel;
  final String organizationName;
  final AlertLevel level;
  final String text;

  /// False when a failure rule refused it (the phone never showed it).
  final bool delivered;
  final String? error;

  factory SimMessage.fromJson(Object? json) {
    final m = asMap(json);
    return SimMessage(
      id: asString(m['id']),
      createdAt: asDate(m['created_at']),
      channel: Channel.parse(m['channel']),
      phone: asString(m['phone']),
      recipientName: asString(m['recipient_name']),
      recipientLabel: asString(m['recipient_label']),
      organizationName: asString(m['organization_name']),
      level: AlertLevel.parse(m['level']),
      text: asString(m['text']),
      delivered: asString(m['status'], fallback: 'delivered') != 'failed',
      error: asNullableString(m['error']),
    );
  }
}
