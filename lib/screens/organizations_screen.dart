import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/console_api.dart';
import '../app/scope.dart';
import '../theme/console_theme.dart';
import '../widgets/common.dart';

/// A2 · Organizations list.
class OrganizationsScreen extends StatefulWidget {
  const OrganizationsScreen({super.key});

  @override
  State<OrganizationsScreen> createState() => _OrganizationsScreenState();
}

class _OrganizationsScreenState extends State<OrganizationsScreen> {
  final _search = TextEditingController();
  OrgStatus? _status;
  Timer? _debounce;
  int _page = 1;
  final List<Organization> _items = [];
  int _count = 0;
  bool _hasMore = false;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) _page = 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await context.api.listOrganizations(search: _search.text, status: _status, page: _page);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.results);
        _count = page.count;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      context.session.handleAuthError(e);
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Organizations',
          subtitle: 'Only Active organizations send alerts to their counselors and contacts.',
          actions: [
            FilledButton.icon(
              onPressed: () => context.go('/organizations/new'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New organization'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, box) {
            final search = LabeledField(
              label: 'Search',
              child: TextField(
                controller: _search,
                onChanged: _onSearch,
                decoration: const InputDecoration(
                  hintText: 'Name or code',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
            );
            final status = LabeledField(
              label: 'Status',
              child: DropdownButtonFormField<OrgStatus?>(
                initialValue: _status,
                items: [
                  const DropdownMenuItem(value: null, child: Text('All statuses')),
                  for (final s in OrgStatus.values) DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) {
                  _status = v;
                  _load(reset: true);
                },
              ),
            );
            if (box.maxWidth < 640) {
              return Column(children: [search, const SizedBox(height: 16), status]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: search),
                const SizedBox(width: 16),
                SizedBox(width: 220, child: status),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        if (_error != null)
          InfoBanner(
            errorText(_error!),
            kind: BannerKind.danger,
            action: OutlinedButton(onPressed: () => _load(reset: true), child: const Text('Try again')),
          )
        else ...[
          ConsoleTable(
            columns: const [
              Col('Organization', flex: 3),
              Col('Code', flex: 2),
              Col('Type', flex: 2),
              Col('City', flex: 3),
              Col('Primary counselor', flex: 3),
              Col('High-risk contacts', flex: 2),
              Col('Status', flex: 3),
            ],
            empty: _loading ? 'Loading…' : 'No organizations match.',
            rows: [
              for (final o in _items)
                [
                  LinkText(o.name, onTap: () => context.go('/organizations/${o.id}')),
                  Text(o.code, style: Tx.mono),
                  Text(o.type.label, style: Tx.body1),
                  Text(o.location, style: Tx.body1),
                  o.primaryCounselor == null
                      ? const Text('Not assigned', style: TextStyle(color: C.warning, fontSize: 15))
                      : Text(o.primaryCounselor!.fullName, style: Tx.body1),
                  Text(
                    '${o.highRiskContacts.length}',
                    style: Tx.body1.copyWith(color: o.highRiskContacts.isEmpty ? C.warning : null),
                  ),
                  Align(alignment: Alignment.centerLeft, child: OrgStatusChip(o.status)),
                ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Showing ${_items.length} of $_count organizations.', style: Tx.small),
              const Spacer(),
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
      ],
    );
  }
}
