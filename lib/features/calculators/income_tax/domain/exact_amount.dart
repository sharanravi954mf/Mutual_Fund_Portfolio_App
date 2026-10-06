/// Exact rupees, including fractional rupees. No floating point intermediates.
/// BigInt keeps products exact on Dart VM and Flutter web alike.
final class Exact implements Comparable<Exact> {
  factory Exact(BigInt numerator, [BigInt? denominator]) {
    final d = denominator ?? BigInt.one;
    if (d <= BigInt.zero) throw ArgumentError('Positive denominator required');
    final gcd = numerator.abs().gcd(d);
    return Exact._(numerator ~/ gcd, d ~/ gcd);
  }
  const Exact._(this.numerator, this.denominator);
  factory Exact.rupees(int value) => Exact(BigInt.from(value));
  factory Exact.parse(String input) {
    final value = input.trim();
    if (!RegExp(r'^\d{1,12}(\.\d{1,2})?$').hasMatch(value)) {
      throw const FormatException(
          'Use up to 12 rupee digits and 2 paise digits');
    }
    final parts = value.split('.');
    return Exact(
        BigInt.parse(parts[0]) * BigInt.from(100) +
            BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0')),
        BigInt.from(100));
  }
  final BigInt numerator;
  final BigInt denominator;
  static final zero = Exact.rupees(0);
  bool get isZero => numerator == BigInt.zero;
  bool get isPositive => numerator > BigInt.zero;
  bool get isNegative => numerator < BigInt.zero;
  Exact operator +(Exact b) => Exact(
      numerator * b.denominator + b.numerator * denominator,
      denominator * b.denominator);
  Exact operator -(Exact b) => Exact(
      numerator * b.denominator - b.numerator * denominator,
      denominator * b.denominator);
  Exact operator -() => Exact(-numerator, denominator);
  Exact ratio(int n, [int d = 1]) =>
      Exact(numerator * BigInt.from(n), denominator * BigInt.from(d));
  Exact min(Exact b) => this < b ? this : b;
  Exact max(Exact b) => this > b ? this : b;
  Exact get positive => max(zero);
  bool operator <(Exact b) => compareTo(b) < 0;
  bool operator <=(Exact b) => compareTo(b) <= 0;
  bool operator >(Exact b) => compareTo(b) > 0;
  bool operator >=(Exact b) => compareTo(b) >= 0;
  @override
  int compareTo(Exact other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);

  /// 288A/288B and 516: ignore paise BEFORE rounding the rupee digit.
  /// A negative balance denotes a refund; round its magnitude under the same rule.
  Exact statutoryTen() {
    final rupees = numerator.abs() ~/ denominator;
    final rounded =
        ((rupees + BigInt.from(5)) ~/ BigInt.from(10)) * BigInt.from(10);
    return Exact(isNegative ? -rounded : rounded);
  }

  /// Display rounding only. Never feed formatted amounts back into calculations.
  String decimal([int digits = 2]) {
    final scale = BigInt.from(10).pow(digits);
    final scaled = (numerator.abs() * scale * BigInt.two + denominator) ~/
        (denominator * BigInt.two);
    final whole = (scaled ~/ scale).toString();
    final tail = digits == 0
        ? ''
        : '.${(scaled % scale).toString().padLeft(digits, '0')}';
    return '${isNegative && scaled != BigInt.zero ? '-' : ''}$whole$tail';
  }

  String get inr {
    final parts = decimal().split('.');
    final negative = parts[0].startsWith('-');
    final raw = negative ? parts[0].substring(1) : parts[0];
    var grouped = raw.length <= 3 ? raw : raw.substring(raw.length - 3);
    for (var end = raw.length - 3; end > 0; end -= 2) {
      grouped = '${raw.substring(end > 2 ? end - 2 : 0, end)},$grouped';
    }
    return '${negative ? '-' : ''}₹$grouped${parts[1] == '00' ? '' : '.${parts[1]}'}';
  }

  @override
  String toString() =>
      denominator == BigInt.one ? '$numerator' : '$numerator/$denominator';
  @override
  bool operator ==(Object other) =>
      other is Exact &&
      numerator == other.numerator &&
      denominator == other.denominator;
  @override
  int get hashCode => Object.hash(numerator, denominator);
}
