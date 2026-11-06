import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/console_api.dart';
import '../../app/scope.dart';
import '../../theme/console_theme.dart';
import '../../utils/india.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';
import 'setup_widgets.dart';

/// A3 · Step 1 Details (also the Details tab). With [org] null it creates a
/// new Draft.
class DetailsStep extends StatefulWidget {
  const DetailsStep({
    super.key,
    required this.org,
    required this.setup,
    required this.onSaved,
    required this.onCreated,
    this.onCancel,
  });

  final Organization? org;
  final bool setup;
  final OnSaved onSaved;

  /// Only for a new organization.
  final Future<void> Function(Organization org, AfterSave after) onCreated;
  final VoidCallback? onCancel;

  @override
  State<DetailsStep> createState() => _DetailsStepState();
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

class _DetailsStepState extends State<DetailsStep> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _city;
  late final TextEditingController _notes;
  late OrgType _type;
  String? _state;
  Map<String, String> _serverErrors = {};

  @override
  void initState() {
    super.initState();
    final o = widget.org;
    _name = TextEditingController(text: o?.name ?? '');
    _code = TextEditingController(text: o?.code ?? '');
    _city = TextEditingController(text: o?.city ?? '');
    _notes = TextEditingController(text: o?.notes ?? '');
    _type = o?.type ?? OrgType.college;
    _state = (o?.state.isNotEmpty ?? false) ? o!.state : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _city.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save(AfterSave after) async {
    setState(() => _serverErrors = {});
    if (!(_form.currentState?.validate() ?? false)) return;
    final input = OrgDetailsInput(
      name: _name.text,
      code: _code.text,
      type: _type,
      city: _city.text,
      state: _state ?? '',
      notes: _notes.text,
    );
    try {
      if (widget.org == null) {
        final created = await context.api.createOrganization(input);
        await widget.onCreated(created, after);
      } else {
        await context.api.updateOrganization(widget.org!.id, input);
        await widget.onSaved(after);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.fieldErrors.isNotEmpty) {
        setState(() => _serverErrors = {for (final f in e.fieldErrors.keys) f: e.fieldError(f)!});
        _form.currentState?.validate();
      } else {
        showApiError(context, e);
      }
    }
  }

  String? _server(String field) => _serverErrors[field];

  @override
  Widget build(BuildContext context) {
    final states = {...kIndianStates, ?_state}.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  'Organization details',
                  subtitle: widget.org == null || widget.org!.status == OrgStatus.draft
                      ? 'Saving creates a Draft. Drafts never send alerts.'
                      : 'Changing the code means new students must use the new code.',
                ),
                const SizedBox(height: 24),
                FieldGrid(
                  children: [
                    LabeledField(
                      label: 'Organization name',
                      required: true,
                      child: TextFormField(
                        controller: _name,
                        maxLength: 120,
                        buildCounter: _noCounter,
                        validator: (v) =>
                            _server('name') ?? validateRequired(v, 'Organization name', min: 2, max: 120),
                      ),
                    ),
                    LabeledField(
                      label: 'Short code',
                      required: true,
                      child: TextFormField(
                        controller: _code,
                        style: Tx.mono.copyWith(fontSize: 15),
                        inputFormatters: [
                          _UpperCase(),
                          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                          LengthLimitingTextInputFormatter(12),
                        ],
                        onChanged: (_) {
                          if (_serverErrors.containsKey('code')) {
                            setState(() => _serverErrors.remove('code'));
                          }
                        },
                        validator: (v) => _server('code') ?? validateOrgCode(v),
                        decoration: const InputDecoration(helperText: orgCodeHelp),
                      ),
                    ),
                    LabeledField(
                      label: 'Type',
                      required: true,
                      child: DropdownButtonFormField<OrgType>(
                        initialValue: _type,
                        items: [
                          for (final t in OrgType.values) DropdownMenuItem(value: t, child: Text(t.label)),
                        ],
                        onChanged: (v) => setState(() => _type = v ?? _type),
                      ),
                    ),
                    LabeledField(
                      label: 'City',
                      required: true,
                      child: TextFormField(
                        controller: _city,
                        validator: (v) => _server('city') ?? validateRequired(v, 'City', max: 80),
                      ),
                    ),
                    LabeledField(
                      label: 'State',
                      required: true,
                      child: DropdownButtonFormField<String>(
                        initialValue: _state,
                        isExpanded: true,
                        hint: const Text('Choose a state'),
                        items: [for (final s in states) DropdownMenuItem(value: s, child: Text(s))],
                        onChanged: (v) => setState(() => _state = v),
                        validator: (v) => _server('state') ?? (v == null ? 'State is required.' : null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                LabeledField(
                  label: 'Notes (optional)',
                  child: TextFormField(
                    controller: _notes,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText: 'Anything other admins should know about this organization',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        SectionFooter(setup: widget.setup, onSave: _save, onBack: widget.onCancel, backLabel: 'Cancel'),
      ],
    );
  }
}

Widget? _noCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) => null;
