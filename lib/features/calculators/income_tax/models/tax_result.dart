import '../domain/exact_amount.dart';
import 'tax_input.dart';

enum TaxStage {
  incomeHeads,
  exemptions,
  setOffs,
  deductions,
  totalIncome,
  incomeTax,
  rebate,
  rebateRelief,
  surcharge,
  surchargeRelief,
  cess,
  liability,
  credits,
  balance
}

final class TaxAuditEntry {
  const TaxAuditEntry(
      this.stage, this.ruleId, this.label, this.amount, this.reason);
  final TaxStage stage;
  final String ruleId, label, reason;
  final Exact amount;
}

final class DeductionDecision {
  const DeductionDecision(
      this.ruleId, this.label, this.entered, this.allowed, this.reason);
  final String ruleId, label, reason;
  final Exact entered, allowed;
  Exact get disallowed => entered - allowed;
}

sealed class TaxOutcome {
  const TaxOutcome();
}

final class TaxInvalidInput extends TaxOutcome {
  TaxInvalidInput(Iterable<String> issues) : issues = List.unmodifiable(issues);
  final List<String> issues;
}

final class TaxUnsupported extends TaxOutcome {
  TaxUnsupported(Iterable<UnsupportedTaxCase> cases)
      : cases = Set.unmodifiable(cases);
  final Set<UnsupportedTaxCase> cases;
}

final class TaxNotYetVerified extends TaxOutcome {
  TaxNotYetVerified(Map<String, String> dependencies)
      : dependencies = Map.unmodifiable(dependencies);
  final Map<String, String> dependencies;
}

/// A calculation failed unexpectedly. Never expose a partial regime result.
final class TaxCalculationFailure extends TaxOutcome {
  const TaxCalculationFailure();
}

final class TaxComparison extends TaxOutcome {
  const TaxComparison({required this.oldRegime, required this.newRegime});
  final RegimeEstimate oldRegime, newRegime;
  Exact get saving =>
      (oldRegime.liability - newRegime.liability).positive +
      (newRegime.liability - oldRegime.liability).positive;
  TaxRegime? get lowerRegime => oldRegime.liability == newRegime.liability
      ? null
      : oldRegime.liability < newRegime.liability
          ? TaxRegime.old
          : TaxRegime.newRegime;
}

final class RegimeEstimate {
  RegimeEstimate({
    required this.regime,
    required this.ruleVersion,
    required this.totalIncome,
    required this.ordinaryIncome,
    required this.stcg,
    required this.ltcg,
    required this.incomeTax,
    required this.rebate,
    required this.rebateRelief,
    required this.surcharge,
    required this.surchargeRelief,
    required this.cess,
    required this.exactLiability,
    required this.liability,
    required this.credits,
    required this.balance,
    required Iterable<TaxAuditEntry> trace,
    required Iterable<DeductionDecision> deductions,
  })  : trace = List.unmodifiable(trace),
        deductions = List.unmodifiable(deductions);
  final TaxRegime regime;
  final String ruleVersion;
  final Exact totalIncome,
      ordinaryIncome,
      stcg,
      ltcg,
      incomeTax,
      rebate,
      rebateRelief,
      surcharge,
      surchargeRelief,
      cess,
      exactLiability,
      liability,
      credits,
      balance;
  final List<TaxAuditEntry> trace;
  final List<DeductionDecision> deductions;
  Exact get payable => balance.positive;
  Exact get refund => (-balance).positive;
}
