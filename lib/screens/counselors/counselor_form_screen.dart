import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/console_api.dart';
import '../../app/scope.dart';
import '../../theme/console_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';

/// A6 · Add counselor (also Edit details). Consent must be ticked before a
/// counselor can be saved and assigned (AC 1.7).
class CounselorFormScreen extends StatelessWidget {
  const CounselorFormScreen({super.key, this.counselorId, this.assignToOrgId});

  final String? counselorId;

  /// Came from setup step 3: go back there with the new counselor.
  final String? assignToOrgId;

  @override
  Widget build(BuildContext context) {
    if (counselorId == null) return _CounselorForm(existing: null, assignToOrgId: assignToOrgId);
    return Loader<Counselor>(
      load: () => context.api.getCounselor(counselorId!),
      builder: (context, c, _) => _CounselorForm(existing: c),
    );
  }
}

class _CounselorForm extends StatefulWidget {
  const _CounselorForm({required this.existing, this.assignToOrgId});
  final Counselor? existing;
  final String? assignToOrgId;

  @override
  State<_CounselorForm> createState() => _CounselorFormState();
}

class _CounselorFormState extends State<_CounselorForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _mobile;
  late final TextEditingController _whatsapp;
  late final TextEditingController _notes;
  late bool _sameAsMobile;
  late Set<String> _languages;
  bool _consent = false;
  bool _consentError = false;
  Map<String, String> _serverErrors = {};

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.fullName ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _mobile = TextEditingController(text: c == null ? '' : formatPhone(c.mobile));
    _sameAsMobile = c == null || c.whatsappSameAsMobile;
    _whatsapp = TextEditingController(
      text: c == null || c.whatsapp == null || c.whatsappSameAsMobile ? '' : formatPhone(c.whatsapp),
    );
    _notes = TextEditingController(text: c?.notes ?? '');
    _languages = {...?c?.languages};
    _mobile.addListener(() {
      if (_sameAsMobile) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _mobile, _whatsapp, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isNew => widget.existing == null;
  bool get _hasConsent => widget.existing?.hasConsent ?? false;

  Future<void> _save() async {
    setState(() {
      _serverErrors = {};
      _consentError = !_hasConsent && !_consent && _isNew;
    });
    final valid = _form.currentState?.validate() ?? false;
    if (!valid || _consentError) return;

    final mobile = normalizeMobile(_mobile.text)!;
    final String? wa = _sameAsMobile
        ? mobile
        : (_whatsapp.text.trim().isEmpty ? null : normalizeMobile(_whatsapp.text));
    final input = CounselorInput(
      fullName: _name.text,
      mobile: mobile,
      whatsapp: wa,
      email: _email.text,
      languages: kCounselorLanguages.where(_languages.contains).toList(),
      notes: _notes.text,
      consent: _hasConsent || _consent,
    );
    try {
      final api = context.api;
      final saved = _isNew
          ? await api.createCounselor(input)
          : await api.updateCounselor(widget.existing!.id, input);
      if (!mounted) return;
      showToast(context, '${saved.fullName} saved.');
      if (widget.assignToOrgId != null) {
        context.go(
          Uri(
            path: '/organizations/${widget.assignToOrgId}/counselors',
            queryParameters: {'added': saved.id},
          ).toString(),
        );
      } else {
        context.go('/counselors/${saved.id}');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.fieldErrors.isNotEmpty) {
        setState(() {
          _serverErrors = {for (final k in e.fieldErrors.keys) k: e.fieldError(k)!};
          _consentError = _serverErrors.containsKey('consent');
        });
        _form.currentState?.validate();
      } else {
        showApiError(context, e);
      }
    }
  }

  void _cancel() {
    if (widget.assignToOrgId != null) {
      context.go('/organizations/${widget.assignToOrgId}/counselors');
    } else if (widget.existing != null) {
      context.go('/counselors/${widget.existing!.id}');
    } else {
      context.go('/counselors');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isNew ? 'Add counselor' : 'Edit ${widget.existing!.fullName}';
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: title,
            crumbs: [
              const Crumb('Counselors', '/counselors'),
              if (!_isNew) Crumb(widget.existing!.fullName, '/counselors/${widget.existing!.id}'),
              Crumb(_isNew ? 'Add counselor' : 'Edit'),
            ],
          ),
          if (widget.assignToOrgId != null) ...[
            const SizedBox(height: 16),
            const InfoBanner(
              'After saving you’ll go back to the organization’s Counselors step with this '
              'counselor ready to add.',
            ),
          ],
          const SizedBox(height: 28),
          SectionCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Contact details', style: Tx.sectionTitle),
                const SizedBox(height: 16),
                FieldGrid(
                  children: [
                    LabeledField(
                      label: 'Full name',
                      required: true,
                      child: TextFormField(
                        controller: _name,
                        validator: (v) => _serverErrors['full_name'] ?? validateRequired(v, 'Full name'),
                      ),
                    ),
                    LabeledField(
                      label: 'Email',
                      child: TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => _serverErrors['email'] ?? validateEmail(v),
                      ),
                    ),
                    LabeledField(
                      label: 'Mobile (for SMS)',
                      required: true,
                      child: TextFormField(
                        controller: _mobile,
                        keyboardType: TextInputType.phone,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: const InputDecoration(
                          helperText: mobileHelp,
                          hintText: '+91 99860 24680',
                        ),
                        validator: (v) => _serverErrors['mobile'] ?? validateMobile(v),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LabeledField(
                          label: 'WhatsApp number',
                          child: TextFormField(
                            key: ValueKey(_sameAsMobile ? 'wa-same-${_mobile.text}' : 'wa-own'),
                            controller: _sameAsMobile ? null : _whatsapp,
                            initialValue: _sameAsMobile ? _mobile.text : null,
                            enabled: !_sameAsMobile,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: _sameAsMobile ? C.surfaceAlt : C.surface,
                              helperText: _sameAsMobile ? null : 'Leave empty if they don’t use WhatsApp.',
                            ),
                            validator: (v) => _sameAsMobile
                                ? null
                                : (_serverErrors['whatsapp'] ?? validateMobile(v, required: false)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => setState(() => _sameAsMobile = !_sameAsMobile),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: _sameAsMobile,
                                onChanged: (v) => setState(() => _sameAsMobile = v ?? false),
                              ),
                              const Text('Same as mobile', style: Tx.body1),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('Languages spoken', style: Tx.sectionTitle),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final l in kCounselorLanguages)
                      FilterChip(
                        label: Text(l),
                        selected: _languages.contains(l),
                        showCheckmark: true,
                        checkmarkColor: C.primary,
                        selectedColor: C.successBg,
                        backgroundColor: C.surface,
                        side: BorderSide(color: _languages.contains(l) ? C.primary : C.borderStrong),
                        shape: const StadiumBorder(),
                        onSelected: (on) => setState(() => on ? _languages.add(l) : _languages.remove(l)),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                LabeledField(
                  label: 'Notes (optional)',
                  child: TextFormField(
                    controller: _notes,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText: 'Working hours, qualifications, anything admins should know',
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 12, 16, 14),
                  decoration: BoxDecoration(
                    color: _consentError ? C.dangerBg : C.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _hasConsent
                      ? Row(
                          children: [
                            const Icon(Icons.check_circle_outline, color: C.success),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Consent to receive Asha safety alerts recorded on '
                                '${fmtDate(widget.existing!.consentAt)}.',
                                style: Tx.body1,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: _consent,
                              onChanged: (v) => setState(() {
                                _consent = v ?? false;
                                if (_consent) _consentError = false;
                              }),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'The counselor has agreed to receive Asha safety alerts by SMS and WhatsApp on '
                                      'these numbers. *',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: C.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _consentError
                                          ? (_serverErrors['consent'] ?? 'Tick this before saving.')
                                          : 'Required before they can be assigned to any organization. The date you tick '
                                                'this is saved.',
                                      style: Tx.small.copyWith(color: _consentError ? C.danger : null),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              TextButton(onPressed: _cancel, child: const Text('Cancel')),
              const Spacer(),
              BusyButton(label: 'Save counselor', onPressed: _save),
            ],
          ),
        ],
      ),
    );
  }
}
