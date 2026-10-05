import '../models/tax_input.dart';
import 'exact_amount.dart';

final class TaxExemptions {
  static Exact hra(HraPeriod period, TaxYear year) {
    final salary = period.basic + period.eligibleDa + period.turnoverCommission;
    final cities = year == TaxYear.fy2025
        ? const {'Mumbai', 'Kolkata', 'Delhi', 'Chennai'}
        : const {
            'Mumbai',
            'Kolkata',
            'Delhi',
            'Chennai',
            'Hyderabad',
            'Pune',
            'Ahmedabad',
            'Bengaluru'
          };
    return period.actualHra
        .min((period.rent - salary.ratio(1, 10)).positive)
        .min(salary.ratio(cities.contains(period.city) ? 50 : 40, 100));
  }
}
