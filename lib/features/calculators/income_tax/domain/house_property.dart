import '../models/tax_input.dart';
import '../models/tax_result.dart';
import 'exact_amount.dart';

final class PropertyComputation {
  PropertyComputation(
      this.netAnnualValue,
      this.statutoryDeduction,
      this.letOut,
      this.selfInterest,
      this.interHeadUsed,
      this.unabsorbed,
      this.incomeAdded,
      Iterable<DeductionDecision> decisions)
      : decisions = List.unmodifiable(decisions);
  final Exact netAnnualValue,
      statutoryDeduction,
      letOut,
      selfInterest,
      interHeadUsed,
      unabsorbed,
      incomeAdded;
  final List<DeductionDecision> decisions;
  Exact get head => letOut - selfInterest;
}

PropertyComputation houseProperty(
    TaxInput input, TaxRegime regime, Exact availableOtherIncome) {
  final old = regime == TaxRegime.old;
  Exact a(TaxAmountField f) => input.amount(f);
  final nav =
      a(TaxAmountField.grossAnnualValue) - a(TaxAmountField.municipalTax);
  if (nav.isNegative) {
    throw StateError('IT-PROPERTY-NEGATIVE-NAV has not been verified');
  }
  final standard = nav.ratio(30, 100);
  final letOut = nav - standard - a(TaxAmountField.letOutInterest);
  final qualified =
      input.confirmed(TaxConfirmation.selfLoanAcquisitionConstruction) &&
          input.confirmed(TaxConfirmation.selfLoanCompletedWithinFiveYears) &&
          input.confirmed(TaxConfirmation.interestCertificate) &&
          (input.year == TaxYear.ty2026 ||
              input.confirmed(TaxConfirmation.selfLoanAfterApril1999));
  final self = old
      ? a(TaxAmountField.selfOccupiedInterest)
          .min(Exact.rupees(qualified ? 200000 : 30000))
      : Exact.zero;
  final head = letOut - self;
  final loss = (-head).positive;
  final used = old
      ? loss.min(Exact.rupees(200000)).min(availableOtherIncome)
      : Exact.zero;
  return PropertyComputation(
      nav, standard, letOut, self, used, loss - used, head.positive - used, [
    DeductionDecision(
        'IT-PROPERTY',
        'Self-occupied interest',
        a(TaxAmountField.selfOccupiedInterest),
        self,
        old
            ? 'Purpose, borrowing date, five-year completion and certificate determine ₹30,000 / ₹2,00,000 cap'
            : 'Disallowed in New Regime'),
    DeductionDecision(
        'IT-PROPERTY',
        'Let-out municipal taxes',
        a(TaxAmountField.municipalTax),
        a(TaxAmountField.municipalTax),
        'Eligible owner-paid taxes, before 30% NAV deduction'),
    DeductionDecision(
        'IT-PROPERTY',
        'Let-out interest',
        a(TaxAmountField.letOutInterest),
        a(TaxAmountField.letOutInterest),
        'Eligible current-period borrowed-capital interest; loss use disclosed separately'),
  ]);
}
