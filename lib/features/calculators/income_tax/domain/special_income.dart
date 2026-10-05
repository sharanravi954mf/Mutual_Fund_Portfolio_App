import '../models/tax_input.dart';
import 'exact_amount.dart';
import 'tax_rules.dart';

final class SpecialIncomeTax {
  const SpecialIncomeTax(this.ordinaryTax, this.stcgTax, this.ltcgTax,
      this.basicUsed, this.annualThresholdUsed);
  final Exact ordinaryTax, stcgTax, ltcgTax, basicUsed, annualThresholdUsed;
  Exact get total => ordinaryTax + stcgTax + ltcgTax;
}

/// Caller first verifies allocation dependencies. This function deliberately
/// rejects the unresolved combined-gain shortfall, even when called directly.
SpecialIncomeTax specialIncomeTax(TaxRulePack pack, TaxRegime regime,
    TaxAge age, Exact ordinary, Exact stcg, Exact ltcg) {
  final shortfall = (pack.basic(regime, age) - ordinary).positive;
  if (shortfall.isPositive && stcg.isPositive && ltcg.isPositive) {
    throw StateError('IT-GAINS-ALLOCATION has not been verified');
  }
  final used = shortfall.min(stcg + ltcg);
  final adjustedStcg = stcg.isPositive ? stcg - used : stcg;
  final adjustedLtcg = stcg.isPositive ? ltcg : ltcg - used;
  final annual = adjustedLtcg.min(Exact.rupees(125000));
  return SpecialIncomeTax(
      pack.ordinaryTax(ordinary, regime, age),
      adjustedStcg.ratio(20, 100),
      (adjustedLtcg - annual).ratio(1, 8),
      used,
      annual);
}

final class SurchargeResult {
  const SurchargeResult(this.amount, this.relief);
  final Exact amount, relief;
}

/// Only homogeneous income has an unambiguous counterfactual composition here.
/// Mixed special/dividend computations are gated in the engine before calling.
SurchargeResult homogeneousSurcharge(Exact income, Exact tax, TaxRegime regime,
    {required bool cappedCategory, required Exact Function(Exact) taxAt}) {
  int rate(Exact at) => at <= Exact.rupees(5000000)
      ? 0
      : at <= Exact.rupees(10000000)
          ? 10
          : cappedCategory || at <= Exact.rupees(20000000)
              ? 15
              : regime == TaxRegime.newRegime || at <= Exact.rupees(50000000)
                  ? 25
                  : 37;
  final nominal = tax.ratio(rate(income), 100);
  var surcharge = nominal;
  final cutoffs = cappedCategory
      ? [5000000, 10000000]
      : [5000000, 10000000, 20000000, if (regime == TaxRegime.old) 50000000];
  for (final cutoff in cutoffs.reversed) {
    final c = Exact.rupees(cutoff);
    if (income > c) {
      final ceiling = taxAt(c).ratio(100 + rate(c), 100) + income - c;
      surcharge = nominal.min((ceiling - tax).positive);
      break;
    }
  }
  return SurchargeResult(surcharge, nominal - surcharge);
}
