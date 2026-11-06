import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/console_api.dart';
import '../../app/scope.dart';
import '../../theme/console_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';
import 'setup_widgets.dart';

/// A5 · Step 3 Counselors. Medium and High alerts go to the primary; a
/// backup gets them only if the primary is inactive (AC 2.1).
class CounselorsStep extends StatelessWidget {
  const CounselorsStep({
    super.key,
    required this.org,
    required this.setup,
    required this.onSaved,
    this.onBack,
    this.justCreatedId,
  });

  final Organization org;
  final bool setup;
  final OnSaved onSaved;
  final VoidCallback? onBack;

  /// Counselor created via "Create new counselor"; added to the list unsaved.
  final String? justCreatedId;

  @override
  Widget build(BuildContext context) {
    final api = context.api;
    return Loader<(List<OrgCounselor>, Counselor?)>(
      load: () async {
        final assigned = await api.listOrgCounselors(org.id);
        Counselor? created;
        if (justCreatedId != null && !assigned.any((a) => a.counselor.id == justCreatedId)) {
          try {
            created = await api.getCounselor(justCreatedId!);
          } catch (_) {}
        }
        return (assigned, created);
      },
      builder: (context, data, _) => _CounselorsEditor(
        org: org,
        initial: data.$1,
        justCreated: data.$2,
        setup: setup,
        onSaved: onSaved,
        onBack: onBack,
      ),
    );
  }
}

class _CounselorsEditor extends StatefulWidget {
  const _CounselorsEditor({
    required this.org,
    required this.initial,
    required this.setup,
    required this.onSaved,
    this.onBack,
    this.justCreated,
  });

  final Organization org;
  final List<OrgCounselor> initial;
  final Counselor? justCreated;
  final bool setup;
  final OnSaved onSaved;
  final VoidCallback? onBack;

  @override
  State<_CounselorsEditor> createState() => _CounselorsEditorState();
}

class _CounselorsEditorState extends State<_CounselorsEditor> {
  late final List<OrgCounselor> _list;
  final _search = TextEditingController();
  Timer? _debounce;
  List<Counselor> _results = [];
  bool _searching = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _list = List.of(widget.initial);
    final c = widget.justCreated;
    if (c != null) {
      _list.add(OrgCounselor(counselor: c, role: _hasPrimary ? CounselorRole.backup : CounselorRole.primary));
      _dirty = true;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool get _hasPrimary => _list.any((a) => a.role == CounselorRole.primary);

  void _onSearch(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      setState(() => _searching = true);
      try {
        final page = await context.api.listCounselors(search: q);
        if (!mounted || _search.text != q) return;
        setState(() => _results = page.results);
      } catch (e) {
        if (mounted) showApiError(context, e);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _add(Counselor c) {
    setState(() {
      _list.add(OrgCounselor(counselor: c, role: _hasPrimary ? CounselorRole.backup : CounselorRole.primary));
      _search.clear();
      _results = [];
      _dirty = true;
    });
  }

  void _setRole(int i, CounselorRole role) {
    setState(() {
      if (role == CounselorRole.primary) {
        for (var j = 0; j < _list.length; j++) {
          if (_list[j].role == CounselorRole.primary) _list[j] = _list[j].withRole(CounselorRole.backup);
        }
      }
      _list[i] = _list[i].withRole(role);
      _dirty = true;
    });
  }

  void _remove(int i) {
    setState(() {
      final removed = _list.removeAt(i);
      if (removed.role == CounselorRole.primary && _list.isNotEmpty) {
        _list[0] = _list[0].withRole(CounselorRole.primary);
      }
      _dirty = true;
    });
  }

  Future<void> _save(AfterSave after) async {
    if (after == AfterSave.next && !_hasPrimary) {
      showToast(context, 'Choose a primary counselor before continuing.', error: true);
      return;
    }
    try {
      await context.api.saveOrgCounselors(widget.org.id, [
        for (final a in _list) (counselorId: a.counselor.id, role: a.role),
      ]);
      _dirty = false;
      await widget.onSaved(after);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Widget _searchResults() {
    final assigned = _list.map((a) => a.counselor.id).toSet();
    final shown = _results.where((c) => !assigned.contains(c.id)).take(6).toList();
    if (_search.text.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.border),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_searching && shown.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          if (!_searching && shown.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No matching counselors. Use “Create new counselor”.', style: Tx.body2),
            ),
          for (final c in shown)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.fullName, style: Tx.body1.copyWith(fontWeight: FontWeight.w500)),
                        if (!c.hasConsent)
                          const Text(
                            'Consent not recorded — can’t be assigned',
                            style: TextStyle(color: C.danger, fontSize: 13),
                          )
                        else if (!c.isActive)
                          const Text(
                            'Inactive — can’t be assigned',
                            style: TextStyle(color: C.danger, fontSize: 13),
                          )
                        else
                          Text(
                            c.languages.isEmpty
                                ? formatPhone(c.mobile)
                                : '${formatPhone(c.mobile)} · ${c.languages.join(', ')}',
                            style: Tx.small,
                          ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: c.canBeAssigned ? () => _add(c) : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    child: const Text('Add'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final others = _list.where((a) => a.counselor.assignments.any((x) => x.organizationId != widget.org.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(
                'Assign counselors',
                subtitle:
                    'Medium and High alerts go to the primary counselor. '
                    'A backup gets them only if the primary is inactive.',
              ),
              const SizedBox(height: 20),
              const Text('Add an existing counselor', style: Tx.label),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _search,
                          onChanged: _onSearch,
                          decoration: const InputDecoration(
                            hintText: 'Search by name or mobile',
                            prefixIcon: Icon(Icons.search, size: 20),
                          ),
                        ),
                        _searchResults(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      if (_dirty) {
                        final ok = await confirm(
                          context,
                          title: 'Leave without saving?',
                          message:
                              'Your changes to this list are not saved yet. Save them first, or continue '
                              'and add them again afterwards.',
                          confirmLabel: 'Continue',
                        );
                        if (!ok || !context.mounted) return;
                      }
                      if (!context.mounted) return;
                      context.go(
                        Uri(path: '/counselors/new', queryParameters: {'assignTo': widget.org.id}).toString(),
                      );
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Create new counselor'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ConsoleTable(
                minWidth: 900,
                columns: const [
                  Col('Counselor', flex: 3),
                  Col('Mobile', flex: 3),
                  Col('WhatsApp', flex: 3),
                  Col('Languages', flex: 4),
                  Col('Role', flex: 5),
                  Col('', flex: 2),
                ],
                empty: 'No counselors assigned yet.',
                rows: [
                  for (var i = 0; i < _list.length; i++)
                    [
                      Text(
                        _list[i].counselor.fullName,
                        style: Tx.body1.copyWith(fontWeight: FontWeight.w500),
                      ),
                      Text(formatPhone(_list[i].counselor.mobile), style: Tx.body1),
                      Text(
                        _list[i].counselor.whatsapp == null
                            ? 'None'
                            : (_list[i].counselor.whatsappSameAsMobile
                                  ? 'Same as mobile'
                                  : formatPhone(_list[i].counselor.whatsapp)),
                        style: Tx.body1,
                      ),
                      Text(_list[i].counselor.languages.join(', '), style: Tx.body1),
                      RadioGroup<CounselorRole>(
                        groupValue: _list[i].role,
                        onChanged: (r) => _setRole(i, r ?? CounselorRole.backup),
                        child: Wrap(
                          spacing: 4,
                          children: [
                            for (final r in CounselorRole.values)
                              InkWell(
                                onTap: () => _setRole(i, r),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Radio<CounselorRole>(value: r),
                                    Text(r.label, style: Tx.body1),
                                    const SizedBox(width: 8),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          style: TextButton.styleFrom(foregroundColor: C.danger),
                          onPressed: () => _remove(i),
                          child: const Text('Remove'),
                        ),
                      ),
                    ],
                ],
              ),
              const SizedBox(height: 12),
              for (final a in others)
                Text(
                  '${a.counselor.fullName} also serves '
                  '${a.counselor.assignments.where((x) => x.organizationId != widget.org.id).map((x) => x.organizationName).join(', ')}. '
                  'One counselor can serve several organizations.',
                  style: Tx.small,
                ),
              if (!_hasPrimary && _list.isNotEmpty) ...[
                const SizedBox(height: 12),
                const InfoBanner('Choose one primary counselor.', kind: BannerKind.warning),
              ],
            ],
          ),
        ),
        const SizedBox(height: 28),
        SectionFooter(setup: widget.setup, onSave: _save, onBack: widget.onBack),
      ],
    );
  }
}
