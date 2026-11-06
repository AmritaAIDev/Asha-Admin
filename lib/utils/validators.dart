// Form rules shared by every screen. They mirror the backend rules in
// docs/BACKEND_CHANGES.md so the console rejects bad input before it is sent.
//
// Pure Dart (no Flutter imports) so `dart run tool/check_logic.dart` can check it.

final RegExp _orgCode = RegExp(r'^[A-Z0-9-]{3,12}$');
final RegExp _indianMobile = RegExp(r'^[6-9]\d{9}$');
final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

const String orgCodeHelp = '3–12 letters, numbers or hyphens. Students enter this code when they register.';
const String orgCodeError = 'Use 3–12 letters, numbers or hyphens.';
const String mobileError = 'Enter a 10-digit Indian mobile number starting with 6–9.';
const String mobileHelp = '10 digits starting 6–9. Saved as +91.';

/// Uppercases and trims an organization code as the admin types it.
String normalizeOrgCode(String input) => input.trim().toUpperCase();

String? validateOrgCode(String? input) {
  final code = normalizeOrgCode(input ?? '');
  if (code.isEmpty) return 'Short code is required.';
  if (!_orgCode.hasMatch(code)) return orgCodeError;
  return null;
}

String? validateRequired(String? input, String label, {int min = 1, int max = 120}) {
  final v = (input ?? '').trim();
  if (v.isEmpty) return '$label is required.';
  if (v.length < min) return '$label must be at least $min characters.';
  if (v.length > max) return '$label must be at most $max characters.';
  return null;
}

/// Returns the 10 national digits of an Indian mobile number, or null.
///
/// Accepts spaces, dashes, brackets and a leading +91, 91 or 0, so
/// "+91 98450 67890", "098450-67890" and "9845067890" all work.
String? mobileDigits(String? input) {
  var digits = (input ?? '').replaceAll(RegExp(r'[\s\-()]'), '');
  if (digits.startsWith('+')) {
    if (!digits.startsWith('+91')) return null;
    digits = digits.substring(3);
  } else if (digits.length == 12 && digits.startsWith('91')) {
    digits = digits.substring(2);
  } else if (digits.length == 11 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return _indianMobile.hasMatch(digits) ? digits : null;
}

/// "+91XXXXXXXXXX" (the stored form) or null when invalid.
String? normalizeMobile(String? input) {
  final d = mobileDigits(input);
  return d == null ? null : '+91$d';
}

String? validateMobile(String? input, {bool required = true}) {
  final v = (input ?? '').trim();
  if (v.isEmpty) return required ? 'Mobile number is required.' : null;
  return mobileDigits(v) == null ? mobileError : null;
}

String? validateEmail(String? input) {
  final v = (input ?? '').trim();
  if (v.isEmpty) return null; // optional everywhere in the console
  return _email.hasMatch(v) ? null : 'Enter a valid email address.';
}

/// "+91 98450 67890" for display; returns the input unchanged if it is not a
/// valid Indian mobile.
String formatPhone(String? stored) {
  final d = mobileDigits(stored);
  if (d == null) return stored ?? '';
  return '+91 ${d.substring(0, 5)} ${d.substring(5)}';
}
