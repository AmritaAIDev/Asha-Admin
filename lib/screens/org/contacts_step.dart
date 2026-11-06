import 'package:flutter/material.dart';

import '../../api/console_api.dart';
import '../../app/scope.dart';
import '../../theme/console_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';
import 'setup_widgets.dart';

/// A4 · Step 2 Contacts: people at the organization who may be told about
/// High-risk cases (principal, dean …). Counselors are added in step 3.
class ContactsStep extends StatelessWidget {
  const ContactsStep({super.key, required this.org, required this.setup, required this.onSaved, this.onBack});

  final Organization org;
  final bool setup;
  final OnSaved onSaved;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Loader<List<OrgContact>>(
      load: () => context.api.listContacts(org.id),
      builder: (context, contacts, _) =>
          _ContactsEditor(org: org, initial: contacts, setup: setup, onSaved: onSaved, onBack: onBack),
    );
  }
}

class _Draft {
  _Draft.from(OrgContact? c)
    : id = c?.id,
      name = TextEditingController(text: c?.fullName ?? ''),
      title = TextEditingController(text: c?.title ?? ''),
      mobile = TextEditingController(text: c == null ? '' : formatPhone(c.mobile)),
      whatsapp = TextEditingController(
        text: c == null || c.whatsapp == null || c.whatsappSameAsMobile ? '' : formatPhone(c.whatsapp),
      ),
      email = TextEditingController(text: c?.email ?? ''),
      sameAsMobile = c == null || c.whatsappSameAsMobile,
      high = c?.receivesHighAlerts ?? false;

  final String? id;
  final TextEditingController name;
  final TextEditingController title;
  final TextEditingController mobile;
  final TextEditingController whatsapp;
  final TextEditingController email;
  bool sameAsMobile;
  bool high;
  final Key key = UniqueKey();

  OrgContact toContact() {
    final mob = normalizeMobile(mobile.text) ?? mobile.text.trim();
    final String? wa;
    if (sameAsMobile) {
      wa = mob;
    } else if (whatsapp.text.trim().isEmpty) {
      wa = null;
    } else {
      wa = normalizeMobile(whatsapp.text) ?? whatsapp.text.trim();
    }
    return OrgContact(
      id: id,
      fullName: name.text.trim(),
      title: title.text.trim(),
      mobile: mob,
      whatsapp: wa,
      email: email.text.trim(),
      receivesHighAlerts: high,
    );
  }

  void dispose() {
    for (final c in [name, title, mobile, whatsapp, email]) {
      c.dispose();
    }
  }
}

class _ContactsEditor extends StatefulWidget {
  const _ContactsEditor({
    required this.org,
    required this.initial,
    required this.setup,
    required this.onSaved,
    this.onBack,
  });

  final Organization org;
  final List<OrgContact> initial;
  final bool setup;
  final OnSaved onSaved;
  final VoidCallback? onBack;

  @override
  State<_ContactsEditor> createState() => _ContactsEditorState();
}

class _ContactsEditorState extends State<_ContactsEditor> {
  final _form = GlobalKey<FormState>();
  late final List<_Draft> _drafts;
  Map<String, String> _serverErrors = {};

  @override
  void initState() {
    super.initState();
    _drafts = widget.initial.isEmpty
        ? [_Draft.from(null)..high = true]
        : widget.initial.map(_Draft.from).toList();
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  int get _highCount => _drafts.where((d) => d.high).length;

  Future<void> _save(AfterSave after) async {
    setState(() => _serverErrors = {});
    if (!(_form.currentState?.validate() ?? false)) return;
    if (after == AfterSave.next && _highCount == 0) {
      showToast(context, 'Tick “Receives High-risk alerts” for at least one contact.', error: true);
      return;
    }
    try {
      await context.api.saveContacts(widget.org.id, _drafts.map((d) => d.toContact()).toList());
      await widget.onSaved(after);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.fieldErrors.isNotEmpty) {
        setState(() => _serverErrors = {for (final k in e.fieldErrors.keys) k: e.fieldError(k)!});
        _form.currentState?.validate();
      } else {
        showApiError(context, e);
      }
    }
  }

  String? _server(int i, String field) => _serverErrors['contacts.$i.$field'];

  Widget _contactCard(int i) {
    final d = _drafts[i];
    return Container(
      key: d.key,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Contact ${i + 1}', style: Tx.cardTitle),
          const SizedBox(height: 16),
          FieldGrid(
            columns: 4,
            spacing: 16,
            children: [
              LabeledField(
                label: 'Full name',
                required: true,
                child: TextFormField(
                  controller: d.name,
                  validator: (v) => _server(i, 'full_name') ?? validateRequired(v, 'Full name'),
                ),
              ),
              LabeledField(
                label: 'Role',
                required: true,
                child: TextFormField(
                  controller: d.title,
                  decoration: const InputDecoration(hintText: 'Principal, Dean …'),
                  validator: (v) => _server(i, 'title') ?? validateRequired(v, 'Role', max: 80),
                ),
              ),
              LabeledField(
                label: 'Mobile',
                required: true,
                child: TextFormField(
                  controller: d.mobile,
                  keyboardType: TextInputType.phone,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(hintText: '+91 98450 67890'),
                  validator: (v) => _server(i, 'mobile') ?? validateMobile(v),
                ),
              ),
              LabeledField(
                label: 'Email',
                child: TextFormField(
                  controller: d.email,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => _server(i, 'email') ?? validateEmail(v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 24,
            runSpacing: 8,
            children: [
              _check('WhatsApp same as mobile', d.sameAsMobile, (v) => setState(() => d.sameAsMobile = v)),
              _check('Receives High-risk alerts', d.high, (v) => setState(() => d.high = v), bold: true),
            ],
          ),
          if (!d.sameAsMobile) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: 320,
              child: LabeledField(
                label: 'WhatsApp number',
                child: TextFormField(
                  controller: d.whatsapp,
                  keyboardType: TextInputType.phone,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(helperText: 'Leave empty if they don’t use WhatsApp.'),
                  validator: (v) => _server(i, 'whatsapp') ?? validateMobile(v, required: false),
                ),
              ),
            ),
          ],
          if (_drafts.length > 1)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: C.danger),
                onPressed: () => setState(() {
                  _drafts.removeAt(i).dispose();
                  _serverErrors = {};
                }),
                child: const Text('Remove contact'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _check(String label, bool value, ValueChanged<bool> onChanged, {bool bold = false}) => InkWell(
    onTap: () => onChanged(!value),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        Text(label, style: Tx.body1.copyWith(fontWeight: bold ? FontWeight.w500 : null)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final high = _highCount;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'Organization contacts',
            subtitle:
                'People at the organization who are told about High-risk cases. '
                'Counselors are added in the next step.',
            trailing: OutlinedButton.icon(
              onPressed: () => setState(() => _drafts.add(_Draft.from(null))),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add contact'),
            ),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < _drafts.length; i++) _contactCard(i),
          InfoBanner(
            high == 0
                ? 'No contact receives High-risk alerts yet. At least one is needed before you can activate.'
                : '$high contact${high == 1 ? '' : 's'} receive${high == 1 ? 's' : ''} High-risk alerts. '
                      'At least one is needed before you can activate.',
            kind: high == 0 ? BannerKind.warning : BannerKind.success,
          ),
          const SizedBox(height: 28),
          SectionFooter(setup: widget.setup, onSave: _save, onBack: widget.onBack),
        ],
      ),
    );
  }
}
