import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/console_api.dart';
import '../app/scope.dart';
import '../theme/console_theme.dart';

// ── Chips ────────────────────────────────────────────────────────────────

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.bg, required this.fg, this.bold = false});
  final String text;
  final Color bg;
  final Color fg;
  final bool bold;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, color: fg, fontWeight: bold ? FontWeight.w600 : FontWeight.w500),
    ),
  );
}

class OrgStatusChip extends StatelessWidget {
  const OrgStatusChip(this.status, {super.key, this.long = false});
  final OrgStatus status;

  /// "Active · alerts on" instead of "Active".
  final bool long;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case OrgStatus.active:
        return Pill(long ? 'Active · alerts on' : 'Active', bg: C.successBg, fg: C.success);
      case OrgStatus.draft:
        return const Pill('Draft · alerts off', bg: C.warningBg, fg: C.warning);
      case OrgStatus.inactive:
        return const Pill('Inactive · alerts off', bg: C.neutralBg, fg: C.neutralInk);
    }
  }
}

class LevelChip extends StatelessWidget {
  const LevelChip(this.level, {super.key});
  final AlertLevel level;

  @override
  Widget build(BuildContext context) {
    switch (level) {
      case AlertLevel.high:
        return const Pill('High', bg: C.dangerBg, fg: C.danger);
      case AlertLevel.medium:
        return const Pill('Medium', bg: C.mediumBg, fg: C.mediumInk);
      case AlertLevel.low:
        return const Pill('Low', bg: C.neutralBg, fg: C.neutralInk);
      case AlertLevel.test:
        return const Pill('Test', bg: C.testBg, fg: C.testInk);
    }
  }
}

// ── Layout pieces ────────────────────────────────────────────────────────

class Crumb {
  const Crumb(this.label, [this.path]);
  final String label;
  final String? path;
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.crumbs = const [],
    this.chip,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Crumb> crumbs;
  final Widget? chip;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (crumbs.isNotEmpty) ...[
          Wrap(
            children: [
              for (var i = 0; i < crumbs.length; i++) ...[
                if (i > 0) const Text(' / ', style: Tx.body2),
                crumbs[i].path == null
                    ? Text(crumbs[i].label, style: Tx.body2)
                    : InkWell(
                        onTap: () => context.go(crumbs[i].path!),
                        child: Text(
                          crumbs[i].label,
                          style: Tx.body2.copyWith(color: C.primary, decoration: TextDecoration.underline),
                        ),
                      ),
              ],
            ],
          ),
          const SizedBox(height: 18),
        ],
        // Full width so the actions sit at the right edge (a bare Wrap shrinks to its content).
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 12,
            spacing: 16,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(title, style: Tx.pageTitle),
                  ?chip,
                ],
              ),
              if (actions.isNotEmpty) Wrap(spacing: 10, runSpacing: 10, children: actions),
            ],
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: Tx.body2.copyWith(fontSize: 15)),
        ],
      ],
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color = C.surface,
    this.borderColor = C.border,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderColor),
    ),
    child: child,
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Tx.sectionTitle),
            if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: Tx.body2)],
          ],
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 16), trailing!],
    ],
  );
}

enum BannerKind { info, success, warning, danger }

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.text, {super.key, this.kind = BannerKind.info, this.action});
  final String text;
  final BannerKind kind;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (kind) {
      BannerKind.info => (C.surfaceAlt, C.ink, Icons.info_outline),
      BannerKind.success => (C.successBg, C.primaryDark, Icons.check),
      BannerKind.warning => (C.warningBg, C.mediumInk, Icons.warning_amber_rounded),
      BannerKind.danger => (C.dangerBg, C.danger, Icons.warning_amber_rounded),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Tx.body2.copyWith(
                color: fg,
                fontWeight: kind == BannerKind.danger ? FontWeight.w500 : null,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ],
      ),
    );
  }
}

/// Label above a field, optional caption below (like the designs).
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child, this.required = false});
  final String label;
  final Widget child;
  final bool required;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(required ? '$label *' : label, style: Tx.label),
      const SizedBox(height: 8),
      child,
    ],
  );
}

/// Lays fields out in a responsive grid of [columns] (1 on narrow screens).
class FieldGrid extends StatelessWidget {
  const FieldGrid({super.key, required this.children, this.columns = 3, this.spacing = 20});
  final List<Widget> children;
  final int columns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth < 640 ? 1 : (box.maxWidth < 900 ? (columns > 2 ? 2 : columns) : columns);
        final w = (box.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final c in children) SizedBox(width: w, child: c)],
        );
      },
    );
  }
}

class KeyValue extends StatelessWidget {
  const KeyValue(this.k, this.v, {super.key, this.mono = false, this.valueColor});
  final String k;
  final String v;
  final bool mono;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: Tx.small),
        const SizedBox(height: 2),
        Text(v, style: (mono ? Tx.mono.copyWith(fontSize: 15) : Tx.body1).copyWith(color: valueColor)),
      ],
    ),
  );
}

// ── Tables ───────────────────────────────────────────────────────────────

class Col {
  const Col(this.label, {this.flex = 1});
  final String label;
  final int flex;
}

/// Simple bordered table matching the designs (cream header, ruled rows).
class ConsoleTable extends StatelessWidget {
  const ConsoleTable({
    super.key,
    required this.columns,
    required this.rows,
    this.empty = 'Nothing here yet.',
    this.rowColors,
    this.minWidth = 820,
  });

  final List<Col> columns;
  final List<List<Widget>> rows;
  final String empty;
  final List<Color?>? rowColors;
  final double minWidth;

  Widget _row(List<Widget> cells, {Color? color, bool header = false}) => Container(
    color: color,
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: header ? 14 : 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < columns.length; i++)
          Expanded(
            flex: columns[i].flex,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: i < cells.length ? cells[i] : const SizedBox.shrink(),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final table = Container(
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(
            [for (final c in columns) Text(c.label, style: Tx.tableHead)],
            color: C.tableHeader,
            header: true,
          ),
          if (rows.isEmpty)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: C.border)),
              ),
              padding: const EdgeInsets.all(18),
              child: Text(empty, style: Tx.body2),
            ),
          for (var r = 0; r < rows.length; r++)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: C.border)),
              ),
              child: _row(rows[r], color: rowColors != null && r < rowColors!.length ? rowColors![r] : null),
            ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= minWidth) return table;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: minWidth, child: table),
        );
      },
    );
  }
}

class LinkText extends StatelessWidget {
  const LinkText(this.text, {super.key, required this.onTap, this.color = C.primary, this.bold = false});
  final String text;
  final VoidCallback onTap;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        style: Tx.body1.copyWith(
          color: color,
          decoration: TextDecoration.underline,
          decorationColor: color,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    ),
  );
}

// ── Buttons ──────────────────────────────────────────────────────────────

/// Filled button that shows a spinner while [onPressed] runs.
class BusyButton extends StatefulWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.outlined = false,
    this.danger = false,
  });

  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  final Color? color;
  final bool outlined;
  final bool danger;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.outlined ? (widget.danger ? C.danger : C.primary) : Colors.white;
    final child = _busy
        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[Icon(widget.icon, size: 18), const SizedBox(width: 8)],
              Text(widget.label),
            ],
          );
    final onPressed = widget.onPressed == null ? null : _run;
    if (widget.outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: widget.danger
            ? OutlinedButton.styleFrom(
                foregroundColor: C.danger,
                side: const BorderSide(color: C.danger),
              )
            : null,
        child: child,
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: widget.color == null ? null : FilledButton.styleFrom(backgroundColor: widget.color),
      child: child,
    );
  }
}

// ── Async loading ────────────────────────────────────────────────────────

/// Loads data once (and again on [reload]); shows spinner and error states.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback reload) builder;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = _guarded();
  }

  Future<T> _guarded() async {
    try {
      return await widget.load();
    } catch (e) {
      if (mounted) context.session.handleAuthError(e);
      rethrow;
    }
  }

  void _reload() => setState(() => _future = _guarded());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          final e = snap.error;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: InfoBanner(
              e is ApiException ? e.detail : 'Something went wrong: $e',
              kind: BannerKind.danger,
              action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
            ),
          );
        }
        return widget.builder(context, snap.data as T, _reload);
      },
    );
  }
}

// ── Feedback helpers ─────────────────────────────────────────────────────

String errorText(Object e) => e is ApiException ? e.detail : 'Something went wrong. Try again.';

void showToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? C.danger : C.primaryDark,
        width: (MediaQuery.sizeOf(context).width - 32).clamp(280, 520).toDouble(),
      ),
    );
}

/// Shows an API error as a toast (and signs out on 401).
void showApiError(BuildContext context, Object e) {
  context.session.handleAuthError(e);
  showToast(context, errorText(e), error: true);
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: Tx.sectionTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Text(message, style: Tx.body1),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: C.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

String fmtDateTime(DateTime? t) {
  if (t == null) return '—';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '${t.day} ${months[t.month - 1]} ${t.year}, $hh:$mm';
}

String fmtDate(DateTime? t) {
  if (t == null) return '—';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${months[t.month - 1]} ${t.year}';
}
