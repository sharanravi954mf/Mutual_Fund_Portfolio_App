/// A monthly loan payment, with no calendar dependency.
class AmortizationRow {
  const AmortizationRow({
    required this.monthNumber,
    required this.openingOutstanding,
    required this.payment,
    required this.interestComponent,
    required this.principalComponent,
    required this.closingOutstanding,
  });
  final int monthNumber;
  final double openingOutstanding;
  final double payment;
  final double interestComponent;
  final double principalComponent;
  final double closingOutstanding;
}
