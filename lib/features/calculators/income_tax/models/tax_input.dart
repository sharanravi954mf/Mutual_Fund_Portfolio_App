import '../domain/exact_amount.dart';
import 'guided_deductions.dart';

enum TaxYear { fy2025, ty2026 }

enum TaxRegime { old, newRegime }

enum TaxAge { below60, from60to79, atLeast80 }

enum TaxMode { normal, advanced }

enum PendingTaxFeature {
  additional80cInstruments,
  postOfficeSavingsExemption,
  multipleEmployerNps,
  deductionRecapture
}

/// Closed set of supported categories, not an unrestricted deduction override.
enum TaxAmountField {
  salary,
  savingsInterest,
  postOfficeSavingsInterest,
  depositInterest,
  otherInterest,
  dividends,
  familyPension,
  professionalTax,
  employerNps,
  employerSalaryBase,
  npsSalaryBase,
  epf,
  ppf,
  elss,
  annuity80ccc,
  tuitionChildOne,
  tuitionChildTwo,
  housingPrincipal,
  housingTransferCharges,
  bankFiveYearDeposit,
  postFiveYearDeposit,
  scssDeposit,
  sukanyaChildOne,
  sukanyaChildTwo,
  nscSubscription,
  nscReinvestedInterest,
  nscFinalInterest,
  ownNpsTotal,
  familyInsurance,
  familyCheckup,
  familyMedical,
  parentInsurance,
  parentCheckup,
  parentMedical,
  educationInterest,
  selfOccupiedInterest,
  grossAnnualValue,
  municipalTax,
  letOutInterest,
  equityStcg,
  equityLtcg,
  tds,
  tcs,
  advanceTax,
  selfAssessmentTax,
}

enum TaxConfirmation {
  residentOrdinarilyResidentIndividual,
  ageForSelectedYear,
  scopeChecklistReviewed,
  salaryDefinition,
  depositEligibility,
  individualPostOfficeAccount,
  investmentEligibility,
  npsEligibility,
  npsEmployee,
  governmentEmployer,
  employerNpsAlreadyInSalary,
  taxablePerquisitesIncluded,
  familySeniorInsured,
  parentSeniorInsured,
  familyUninsuredResidentSenior,
  parentUninsuredResidentSenior,
  healthEligiblePayments,
  educationEligible,
  equityStcgEligible,
  equityLtcgEligible,
  ordinaryCompanyDividends,
  completedFullyOwnedProperties,
  annualValueVerified,
  selfLoanAcquisitionConstruction,
  selfLoanAfterApril1999,
  selfLoanCompletedWithinFiveYears,
  interestCertificate,
  tuitionChildOneEligible,
  tuitionChildTwoEligible,
  housingPurchaseEligible,
  bankFiveYearEligible,
  postFiveYearEligible,
  scssEligibleAtOpening,
  sukanyaChildOneEligible,
  sukanyaChildTwoEligible,
  sukanyaDistinctChildren,
  investmentAmountsExclusive,
  nscEligibility,
}

enum UnsupportedTaxCase {
  nonResidentOrRnor,
  otherTaxpayerType,
  businessOrFreelancing,
  foreignIncomeOrAssets,
  agriculturalIncome,
  broughtForwardLoss,
  capitalLoss,
  cryptoLotteryGaming,
  complexSalaryOrArrears,
  otherDeduction,
  complexProperty,
  businessTrustDistribution,
  otherSpecialIncome,
}

/// Relevant-period amounts, never annual salary percentages supplied as overrides.
final class HraPeriod {
  HraPeriod(
      {required this.firstDay,
      required this.lastDay,
      required this.city,
      required this.basic,
      required this.eligibleDa,
      required this.turnoverCommission,
      required this.actualHra,
      required this.rent});
  final int firstDay,
      lastDay; // inclusive, 1..365 in the selected income period
  final String city;
  final Exact basic, eligibleDa, turnoverCommission, actualHra, rent;
}

final class TaxInput {
  TaxInput({
    required this.year,
    required this.age,
    Map<TaxAmountField, Exact> amounts = const {},
    Set<TaxConfirmation> confirmations = const {},
    Set<UnsupportedTaxCase> unsupported = const {},
    Set<PendingTaxFeature> pending = const {},
    List<HraPeriod> hraPeriods = const [],
    List<LifePremium> lifePremiums = const [],
    List<EmployerNps> additionalEmployers = const [],
    this.housingPaymentKind = HousingPaymentKind.governmentOrBank,
    this.educationRepaymentYear = 1,
  })  : amounts = Map.unmodifiable(amounts),
        confirmations = Set.unmodifiable(confirmations),
        unsupported = Set.unmodifiable(unsupported),
        pending = Set.unmodifiable(pending),
        hraPeriods = List.unmodifiable(hraPeriods),
        lifePremiums = List.unmodifiable(lifePremiums),
        additionalEmployers = List.unmodifiable(additionalEmployers);
  final TaxYear year;
  final TaxAge age;
  final Map<TaxAmountField, Exact> amounts;
  final Set<TaxConfirmation> confirmations;
  final Set<UnsupportedTaxCase> unsupported;
  final Set<PendingTaxFeature> pending;
  final List<HraPeriod> hraPeriods;
  final List<LifePremium> lifePremiums;
  final List<EmployerNps> additionalEmployers;
  final HousingPaymentKind housingPaymentKind;
  List<EmployerNps> get employers => List.unmodifiable([
        if (amount(TaxAmountField.employerNps).isPositive)
          EmployerNps(
              contribution: amount(TaxAmountField.employerNps),
              salaryBase: amount(TaxAmountField.employerSalaryBase),
              government: confirmed(TaxConfirmation.governmentEmployer),
              alreadyInGrossSalary:
                  confirmed(TaxConfirmation.employerNpsAlreadyInSalary)),
        ...additionalEmployers,
      ]);
  final int educationRepaymentYear;
  Exact amount(TaxAmountField field) => amounts[field] ?? Exact.zero;
  bool confirmed(TaxConfirmation flag) => confirmations.contains(flag);
}
