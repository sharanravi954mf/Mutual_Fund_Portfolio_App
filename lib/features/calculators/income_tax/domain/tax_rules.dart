import '../models/tax_input.dart';
import 'exact_amount.dart';

final class TaxRulePack {
  const TaxRulePack._(
      {required this.year,
      required this.version,
      required this.label,
      required this.period,
      required this.act,
      required this.slabReference,
      required this.roundingReference,
      required this.surchargeReference});
  final TaxYear year;
  final String version,
      label,
      period,
      act,
      slabReference,
      roundingReference,
      surchargeReference;
  static const verifiedAsOf = '2026-10-05';
  static const fy2025 = TaxRulePack._(
      year: TaxYear.fy2025,
      version: 'in-1961-fy2025-26-v3',
      label: 'FY 2025–26 / AY 2026–27',
      period: '1 April 2025 – 31 March 2026',
      act: 'Income-tax Act, 1961',
      slabReference: '115BAC(1A)(iii); Finance Act 2026 Part I-A A',
      roundingReference: '288A / 288B',
      surchargeReference: 'Finance Act 2026 s2(4)–(6), Part I-A F');
  static const ty2026 = TaxRulePack._(
      year: TaxYear.ty2026,
      version: 'in-2025-ty2026-27-v3',
      label: 'Tax Year 2026–27',
      period: '1 April 2026 – 31 March 2027',
      act: 'Income-tax Act, 2025',
      slabReference: '202(1); Finance Act 2026 Part I-B A',
      roundingReference: '516',
      surchargeReference: 'Finance Act 2026 s3(4)–(5), (15), Part I-B F');
  static TaxRulePack forYear(TaxYear year) => switch (year) {
        TaxYear.fy2025 => fy2025,
        TaxYear.ty2026 => ty2026,
      };
  Exact basic(TaxRegime regime, TaxAge age) =>
      Exact.rupees(regime == TaxRegime.newRegime
          ? 400000
          : switch (age) {
              TaxAge.below60 => 250000,
              TaxAge.from60to79 => 300000,
              TaxAge.atLeast80 => 500000
            });
  Exact standard(TaxRegime regime) =>
      Exact.rupees(regime == TaxRegime.old ? 50000 : 75000);

  /// Each supported pack explicitly selects its enacted schedule. No year fallback.
  List<(int, int)> bands(TaxRegime regime, TaxAge age) => switch (year) {
        TaxYear.fy2025 => regime == TaxRegime.newRegime
            ? const [
                (400000, 0),
                (800000, 5),
                (1200000, 10),
                (1600000, 15),
                (2000000, 20),
                (2400000, 25)
              ]
            : [
                (
                  age == TaxAge.below60
                      ? 250000
                      : age == TaxAge.from60to79
                          ? 300000
                          : 500000,
                  0
                ),
                (500000, 5),
                (1000000, 20)
              ],
        TaxYear.ty2026 => regime == TaxRegime.newRegime
            ? const [
                (400000, 0),
                (800000, 5),
                (1200000, 10),
                (1600000, 15),
                (2000000, 20),
                (2400000, 25)
              ]
            : [
                (
                  age == TaxAge.below60
                      ? 250000
                      : age == TaxAge.from60to79
                          ? 300000
                          : 500000,
                  0
                ),
                (500000, 5),
                (1000000, 20)
              ],
      };
  Exact ordinaryTax(Exact income, TaxRegime regime, TaxAge age) {
    var previous = Exact.zero;
    var tax = Exact.zero;
    for (final (limit, percent) in bands(regime, age)) {
      final upper = Exact.rupees(limit);
      tax += (income.min(upper) - previous).positive.ratio(percent, 100);
      previous = upper;
    }
    return tax + (income - previous).positive.ratio(30, 100);
  }
}
