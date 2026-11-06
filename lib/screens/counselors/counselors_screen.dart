import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/console_api.dart';
import '../../app/scope.dart';
import '../../theme/console_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';

/// Counselors list. One counselor can serve several organizations.
class CounselorsScreen extends StatefulWidget {
  const CounselorsScreen({super.key});

  @override
  State<CounselorsScreen> createState() => _CounselorsScreenState();
}

class _CounselorsScreenState extends State<CounselorsScreen> {
  final _search = TextEditingController();
  bool? _active = true;
  Timer? _debounce;
  int _page = 1;
  final List<Counselor> _items = [];
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
      final p = await context.api.listCounselors(search: _search.text, active: _active, page: _page);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(p.results);
        _count = p.count;
        _hasMore = p.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      context.session.handleAuthError(e);
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Counselors',
          subtitle:
              'One counselor can serve several organizations. Only counselors with recorded consent can '
              'be assigned.',
          actions: [
            FilledButton.icon(
              onPressed: () => context.go('/counselors/new'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add counselor'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: 'Search',
                child: TextField(
                  controller: _search,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () => _load(reset: true));
                  },
                  decoration: const InputDecoration(
                    hintText: 'Name or mobile',
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 200,
              child: LabeledField(
                label: 'Status',
                child: DropdownButtonFormField<bool?>(
                  initialValue: _active,
                  items: const [
                    DropdownMenuItem(value: true, child: Text('Active')),
                    DropdownMenuItem(value: false, child: Text('Inactive')),
                    DropdownMenuItem(value: null, child: Text('All')),
                  ],
                  onChanged: (v) {
                    _active = v;
                    _load(reset: true);
                  },
                ),
              ),
            ),
          ],
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
              Col('Counselor', flex: 3),
              Col('Mobile', flex: 3),
              Col('Languages', flex: 3),
              Col('Organizations', flex: 5),
              Col('Consent', flex: 2),
              Col('Status', flex: 2),
            ],
            empty: _loading ? 'Loading…' : 'No counselors match.',
            rows: [
              for (final c in _items)
                [
                  LinkText(c.fullName, onTap: () => context.go('/counselors/${c.id}')),
                  Text(formatPhone(c.mobile), style: Tx.body1),
                  Text(c.languages.join(', '), style: Tx.body1),
                  Text(
                    c.assignments.isEmpty
                        ? 'Not assigned'
                        : c.assignments.map((a) => '${a.organizationName} (${a.role.name})').join(', '),
                    style: Tx.body1.copyWith(color: c.assignments.isEmpty ? C.muted : null),
                  ),
                  Text(
                    c.hasConsent ? 'Recorded' : 'Missing',
                    style: Tx.body1.copyWith(
                      color: c.hasConsent ? C.success : C.danger,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: c.isActive
                        ? const Pill('Active', bg: C.successBg, fg: C.success)
                        : const Pill('Inactive', bg: C.neutralBg, fg: C.neutralInk),
                  ),
                ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Showing ${_items.length} of $_count counselors.', style: Tx.small),
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
