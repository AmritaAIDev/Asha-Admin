import 'package:flutter/material.dart';

import '../api/console_api.dart';
import '../app/scope.dart';
import '../theme/console_theme.dart';
import '../widgets/common.dart';
import '../widgets/log_view.dart';

/// A10/A11 · Delivery log: every alert and test message, one row per
/// recipient. Never shows message text.
class DeliveryLogScreen extends StatelessWidget {
  const DeliveryLogScreen({super.key, this.organizationId});
  final String? organizationId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          title: 'Delivery log',
          subtitle:
              'Every alert and test message, one row per recipient and channel. Message text isn’t shown '
              'here; every alert carried the student’s name and their last 5 messages.',
        ),
        const SizedBox(height: 24),
        DeliveryLogView(initialOrganizationId: organizationId),
      ],
    );
  }
}

class DeliveryLogView extends StatefulWidget {
  const DeliveryLogView({super.key, this.initialOrganizationId, this.fixedOrganizationId});

  final String? initialOrganizationId;

  /// When set (organization Log tab) the organization filter is hidden.
  final String? fixedOrganizationId;

  @override
  State<DeliveryLogView> createState() => _DeliveryLogViewState();
}

class _DeliveryLogViewState extends State<DeliveryLogView> {
  late LogFilter _filter = LogFilter(
    organizationId: widget.fixedOrganizationId ?? widget.initialOrganizationId,
  );
  final List<LogRow> _rows = [];
  List<Organization> _orgs = [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  int _attention = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadOrgs();
    _load(reset: true);
  }

  Future<void> _loadOrgs() async {
    if (widget.fixedOrganizationId != null) return;
    try {
      final all = <Organization>[];
      var page = 1;
      while (true) {
        final p = await context.api.listOrganizations(page: page);
        all.addAll(p.results);
        if (!p.hasMore || page >= 10) break;
        page++;
      }
      if (mounted) setState(() => _orgs = all);
    } catch (_) {
      // The filter just stays empty; the log itself still loads.
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) _page = 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.api;
      final page = await api.listLog(_filter, page: _page);
      final attention = await api.countNeedsAttention();
      if (!mounted) return;
      setState(() {
        if (reset) _rows.clear();
        _rows.addAll(page.results);
        _hasMore = page.hasMore;
        _attention = attention;
      });
    } catch (e) {
      if (!mounted) return;
      context.session.handleAuthError(e);
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _set(LogFilter f) {
    _filter = f;
    _load(reset: true);
  }

  LogFilter _copy({
    Object? organizationId = _keep,
    Object? level = _keep,
    Object? status = _keep,
    LogRange? range,
    bool? needsAttentionOnly,
  }) => LogFilter(
    organizationId: identical(organizationId, _keep) ? _filter.organizationId : organizationId as String?,
    level: identical(level, _keep) ? _filter.level : level as AlertLevel?,
    status: identical(status, _keep) ? _filter.status : status as String?,
    range: range ?? _filter.range,
    needsAttentionOnly: needsAttentionOnly ?? _filter.needsAttentionOnly,
  );

  @override
  Widget build(BuildContext context) {
    final filters = <Widget>[
      if (widget.fixedOrganizationId == null)
        LabeledField(
          label: 'Organization',
          child: DropdownButtonFormField<String?>(
            key: ValueKey('org-${_orgs.length}-${_filter.organizationId}'),
            initialValue: _orgs.any((o) => o.id == _filter.organizationId) ? _filter.organizationId : null,
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: null, child: Text('All organizations')),
              for (final o in _orgs)
                DropdownMenuItem(
                  value: o.id,
                  child: Text(o.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => _set(_copy(organizationId: v)),
          ),
        ),
      LabeledField(
        label: 'Level',
        child: DropdownButtonFormField<AlertLevel?>(
          key: ValueKey('level-${_filter.level}'),
          initialValue: _filter.level,
          items: [
            const DropdownMenuItem(value: null, child: Text('All levels')),
            for (final l in AlertLevel.values) DropdownMenuItem(value: l, child: Text(l.label)),
          ],
          onChanged: (v) => _set(_copy(level: v)),
        ),
      ),
      LabeledField(
        label: 'Status',
        child: DropdownButtonFormField<String?>(
          key: ValueKey('status-${_filter.status}'),
          initialValue: _filter.status,
          items: const [
            DropdownMenuItem(value: null, child: Text('All statuses')),
            DropdownMenuItem(value: 'delivered', child: Text('Delivered')),
            DropdownMenuItem(value: 'failed', child: Text('Failed')),
            DropdownMenuItem(value: 'retrying', child: Text('Retrying')),
            DropdownMenuItem(value: 'skipped', child: Text('Skipped')),
          ],
          onChanged: (v) => _set(_copy(status: v)),
        ),
      ),
      LabeledField(
        label: 'Date',
        child: DropdownButtonFormField<LogRange>(
          key: ValueKey('range-${_filter.range}'),
          initialValue: _filter.range,
          items: [for (final r in LogRange.values) DropdownMenuItem(value: r, child: Text(r.label))],
          onChanged: (v) => _set(_copy(range: v)),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_attention > 0 && widget.fixedOrganizationId == null) ...[
          InfoBanner(
            '$_attention High-risk alert${_attention == 1 ? '' : 's'} failed on every channel for a recipient. '
            'Check the number and resend.',
            kind: BannerKind.danger,
            action: _filter.needsAttentionOnly
                ? OutlinedButton(
                    onPressed: () => _set(_copy(needsAttentionOnly: false)),
                    child: const Text('Show all'),
                  )
                : FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: C.danger),
                    onPressed: () => _set(const LogFilter(range: LogRange.all, needsAttentionOnly: true)),
                    child: const Text('Show failed'),
                  ),
          ),
          const SizedBox(height: 20),
        ],
        FieldGrid(columns: filters.length, spacing: 12, children: filters),
        const SizedBox(height: 20),
        if (_error != null)
          InfoBanner(
            errorText(_error!),
            kind: BannerKind.danger,
            action: OutlinedButton(onPressed: () => _load(reset: true), child: const Text('Try again')),
          )
        else if (_loading && _rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          LogTable(
            rows: _rows,
            showOrganization: widget.fixedOrganizationId == null,
            onResend: (r) async {
              if (await resendRow(context, r)) _load(reset: true);
            },
          ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Text(
                'Retries run at 1, 5 and 15 minutes. A repeat at the same level within 6 hours in the same session '
                'is skipped; a rise from Medium to High always sends.',
                style: Tx.small,
              ),
            ),
            if (_hasMore)
              OutlinedButton(
                onPressed: _loading
                    ? null
                    : () {
                        _page++;
                        _load();
                      },
                child: const Text('Load more'),
              ),
          ],
        ),
      ],
    );
  }
}

const Object _keep = Object();
