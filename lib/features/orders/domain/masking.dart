class MaskingUtil {
  /// Mask PAN: show first 3 and last 3 characters if valid length 10, else return fully masked placeholder
  static String maskPan(String pan) {
    final clean = pan.trim();
    if (clean.length != 10) {
      return '••••••••••';
    }
    final first = clean.substring(0, 3);
    final last = clean.substring(clean.length - 3);
    return '$first••••$last';
  }

  /// Mask Phone: show last 4 digits, first 6 masked if valid length >= 10, else return fully masked placeholder
  static String maskPhone(String phone) {
    final clean = phone.trim();
    if (clean.length < 10) {
      return '••••••••••';
    }
    final last = clean.substring(clean.length - 4);
    return '••••••$last';
  }

  /// Mask Email: show first 2 characters of local part + ••• + @domain if valid format, else return placeholder
  static String maskEmail(String email) {
    final clean = email.trim();
    if (!clean.contains('@')) {
      return '•••••@•••••.com';
    }
    final parts = clean.split('@');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      return '•••••@•••••.com';
    }
    final local = parts[0];
    final domain = parts[1];
    if (local.length <= 2) {
      return '$local•••@$domain';
    }
    final prefix = local.substring(0, 2);
    return '$prefix•••@$domain';
  }

  /// Mask Folio: show last 4 characters, first 4 masked if length >= 6, else return fully masked placeholder
  static String maskFolio(String folio) {
    final clean = folio.trim();
    if (clean.length < 6) {
      return '••••••••';
    }
    final last = clean.substring(clean.length - 4);
    return '••••$last';
  }
}
