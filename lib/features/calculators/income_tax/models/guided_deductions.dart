import '../domain/exact_amount.dart';

/// No policy number, person name or employer identity is needed.
final class LifePremium {
  const LifePremium(
      {required this.paid,
      required this.assured,
      required this.issued,
      required this.selfSpouseOrChild,
      this.qualifyingDisabilityOrAilment = false});
  final Exact paid, assured;
  final DateTime issued;
  final bool selfSpouseOrChild, qualifyingDisabilityOrAilment;
  int get percentage => issued.isBefore(DateTime.utc(2012, 4, 1))
      ? 20
      : !issued.isBefore(DateTime.utc(2013, 4, 1)) &&
              qualifyingDisabilityOrAilment
          ? 15
          : 10;
  Exact get eligible =>
      selfSpouseOrChild ? paid.min(assured.ratio(percentage, 100)) : Exact.zero;
}

enum HousingPaymentKind {
  governmentOrBank,
  licOrNationalHousingBank,
  qualifyingHousingFinance,
  qualifyingEmployer,
  authorityOrSocietyInstallment,
  otherLender,
}

final class EmployerNps {
  const EmployerNps(
      {required this.contribution,
      required this.salaryBase,
      required this.government,
      required this.alreadyInGrossSalary});
  final Exact contribution, salaryBase;
  final bool government, alreadyInGrossSalary;
}
