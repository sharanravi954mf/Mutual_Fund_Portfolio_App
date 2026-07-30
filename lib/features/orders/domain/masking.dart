class MaskingUtil {
  /// Mask PAN: show first 3 and last 3 characters, e.g. ABC123456F -> ABC••••56F
  static String maskPan(String pan) {
    final clean = pan.trim();
    if (clean.length < 6) return clean;
    final first = clean.substring(0, 3);
    final last = clean.substring(clean.length - 3);
    return '$first••••$last';
  }

  /// Mask Phone: show last 4 digits, first 6 masked, e.g. 9876543210 -> ••••••3210
  static String maskPhone(String phone) {
    final clean = phone.trim();
    if (clean.length < 4) return clean;
    final last = clean.substring(clean.length - 4);
    return '••••••$last';
  }

  /// Mask Email: show first 2 characters of local part + ••• + @domain, e.g. ravi@example.com -> ra•••@example.com
  static String maskEmail(String email) {
    final clean = email.trim();
    if (!clean.contains('@')) return clean;
    final parts = clean.split('@');
    final local = parts[0];
    final domain = parts[1];
    if (local.length <= 2) {
      return '$local•••@$domain';
    }
    final prefix = local.substring(0, 2);
    return '$prefix•••@$domain';
  }

  /// Mask Folio: show last 4 characters, first 4 masked, e.g. 12345678 -> ••••5678
  static String maskFolio(String folio) {
    final clean = folio.trim();
    if (clean.length < 4) return clean;
    final last = clean.substring(clean.length - 4);
    return '••••$last';
  }
}
