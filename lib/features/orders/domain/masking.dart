/// Fail-closed masking utility for sensitive financial PII.
///
/// All methods validate the structure of the input before revealing any
/// characters. Malformed inputs always return a fully masked placeholder.
/// No raw characters from a malformed input are ever returned.
class MaskingUtil {
  // PAN format: 5 letters + 4 digits + 1 letter (total 10 chars)
  static final _panStructure = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');

  // Phone: 10 consecutive digits (after stripping non-digit characters)
  static final _phoneDigits = RegExp(r'^\d{10}$');

  // Email: must have exactly one @ with non-empty local and domain parts
  static final _emailStructure = RegExp(
    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
  );

  /// Mask PAN: shows first 3 and last 3 characters of a valid 10-char PAN.
  ///
  /// PAN must strictly match [A-Z]{5}[0-9]{4}[A-Z] (all uppercase).
  /// Any deviation returns a fully masked placeholder.
  static String maskPan(String pan) {
    final clean = pan.trim();
    if (clean.length != 10 || !_panStructure.hasMatch(clean)) {
      return '••••••••••';
    }
    final first = clean.substring(0, 3);
    final last = clean.substring(clean.length - 3);
    return '$first••••$last';
  }

  /// Mask Phone: shows last 4 digits of a normalised 10-digit phone number.
  ///
  /// Strips whitespace, dashes, and parentheses before validating.
  /// The normalised number must contain exactly 10 digits.
  /// Any deviation returns a fully masked placeholder.
  static String maskPhone(String phone) {
    // Strip common formatting characters
    final clean = phone.trim().replaceAll(RegExp(r'[\s\-().+]'), '');
    if (!_phoneDigits.hasMatch(clean)) {
      return '••••••••••';
    }
    final last = clean.substring(clean.length - 4);
    return '••••••$last';
  }

  /// Mask Email: shows first 2 chars of local part + ••• + @domain.
  ///
  /// The full email must match a basic structural pattern (local@domain.tld).
  /// Any deviation returns a fully masked placeholder.
  static String maskEmail(String email) {
    final clean = email.trim().toLowerCase();
    if (!_emailStructure.hasMatch(clean)) {
      return '•••••@•••••.com';
    }
    final atIndex = clean.indexOf('@');
    final local = clean.substring(0, atIndex);
    final domain = clean.substring(atIndex + 1);

    // Domain must contain at least one dot with non-empty segments
    final domainParts = domain.split('.');
    if (domainParts.length < 2 ||
        domainParts.any((p) => p.isEmpty)) {
      return '•••••@•••••.com';
    }

    if (local.length <= 1) {
      return '$local•••@$domain';
    }
    if (local.length == 2) {
      return '$local•••@$domain';
    }
    final prefix = local.substring(0, 2);
    return '$prefix•••@$domain';
  }

  /// Mask Folio: shows last 4 digits of a folio number that is at least 6
  /// characters long and contains only alphanumeric characters.
  ///
  /// Folio numbers must be alphanumeric only; any special character or
  /// insufficient length returns a fully masked placeholder.
  static String maskFolio(String folio) {
    final clean = folio.trim();
    // Folio must be at least 6 chars and strictly alphanumeric
    if (clean.length < 6 || !RegExp(r'^[a-zA-Z0-9]+$').hasMatch(clean)) {
      return '••••••••';
    }
    final last = clean.substring(clean.length - 4);
    return '••••$last';
  }
}
