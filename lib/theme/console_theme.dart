import 'package:flutter/material.dart';

/// Colours from the Phase 1 console designs. Green and cream match
/// Asha_Frontend's WebsiteTheme so the console feels like the same product.
abstract final class C {
  static const Color sidebar = Color(0xFF1F4D3A);
  static const Color primary = Color(0xFF1F4D3A);
  static const Color primaryDark = Color(0xFF163A2C);
  static const Color background = Color(0xFFFAF7F0);
  static const Color surface = Colors.white;
  static const Color surfaceAlt = Color(0xFFF6F1E7);
  static const Color tableHeader = Color(0xFFF6F1E7);
  static const Color border = Color(0xFFE1DACB);
  static const Color borderStrong = Color(0xFFBFB6A5);
  static const Color ink = Color(0xFF18291F);
  static const Color ink2 = Color(0xFF4A5D52);
  static const Color muted = Color(0xFF6E7C74);

  /// Current setup step and the Activate button.
  static const Color accent = Color(0xFFA9532E);

  static const Color success = Color(0xFF1F6B4A);
  static const Color successBg = Color(0xFFE2EEE6);
  static const Color warning = Color(0xFF9A5B00);
  static const Color warningBg = Color(0xFFFBEBD3);
  static const Color danger = Color(0xFF962A1D);
  static const Color dangerBg = Color(0xFFF7DCD7);
  static const Color dangerRow = Color(0xFFFCF0EE);
  static const Color mediumBg = Color(0xFFFBEAD2);
  static const Color mediumInk = Color(0xFF7A400C);
  static const Color testBg = Color(0xFFE3ECF5);
  static const Color testInk = Color(0xFF2F5D86);
  static const Color neutralBg = Color(0xFFEDE8DE);
  static const Color neutralInk = Color(0xFF5B5446);
}

abstract final class Tx {
  static const String display = 'PlayfairDisplay';
  static const String body = 'Roboto';

  static const TextStyle pageTitle = TextStyle(
    fontFamily: display,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: C.primary,
    height: 1.15,
  );
  static const TextStyle brand = TextStyle(
    fontFamily: display,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: body,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: C.ink,
  );
  static const TextStyle cardTitle = TextStyle(
    fontFamily: body,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: C.ink,
  );
  static const TextStyle body1 = TextStyle(fontFamily: body, fontSize: 15, color: C.ink, height: 1.45);
  static const TextStyle body2 = TextStyle(fontFamily: body, fontSize: 14, color: C.ink2, height: 1.45);
  static const TextStyle small = TextStyle(fontFamily: body, fontSize: 13, color: C.ink2, height: 1.4);
  static const TextStyle label = TextStyle(
    fontFamily: body,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: C.ink,
  );
  static const TextStyle tableHead = TextStyle(
    fontFamily: body,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: C.ink2,
  );
  static const TextStyle mono = TextStyle(fontFamily: 'monospace', fontSize: 14, color: C.ink);
  static const TextStyle fieldCaption = TextStyle(fontFamily: body, fontSize: 12.5, color: C.muted);
}

ThemeData buildConsoleTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: C.primary,
    primary: C.primary,
    secondary: C.accent,
    error: C.danger,
    surface: C.surface,
  );
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: c, width: w),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: Tx.body,
    scaffoldBackgroundColor: C.background,
    dividerColor: C.border,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(color: C.muted, fontSize: 15),
      border: border(C.borderStrong),
      enabledBorder: border(C.borderStrong),
      focusedBorder: border(C.primary, 2),
      errorBorder: border(C.danger, 1.5),
      focusedErrorBorder: border(C.danger, 2),
      disabledBorder: border(C.border),
      errorStyle: const TextStyle(color: C.danger, fontSize: 12.5),
      errorMaxLines: 3,
      helperMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: C.neutralBg,
        disabledForegroundColor: C.muted,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        textStyle: const TextStyle(fontFamily: Tx.body, fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.primary,
        backgroundColor: C.surface,
        side: const BorderSide(color: C.primary),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        textStyle: const TextStyle(fontFamily: Tx.body, fontSize: 15, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: C.primary,
        textStyle: const TextStyle(
          fontFamily: Tx.body,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.underline,
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? C.primary : Colors.transparent,
      ),
      side: const BorderSide(color: C.borderStrong, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? C.primary : C.borderStrong,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dialogTheme: DialogThemeData(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
