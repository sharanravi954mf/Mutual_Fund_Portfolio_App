import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/models/tax_input.dart';
import 'income_tax_engine_test.dart' as f;

void main() {
  final rows = (jsonDecode(
      File('test/calculators/income_tax/fixtures/age_interaction_goldens.json')
          .readAsStringSync()) as Map<String, dynamic>)['vectors'] as List;
  for (final year in TaxYear.values) {
    for (final (index, row) in rows.indexed) {
      test(
          '${year.name} age and interaction golden $index ${row['age']} ${row['regime']} ${row['kind']} ${row['input']}',
          () {
        final kind = row['kind'];
        final input = f.e(row['input']);
        final comparison = f.compute(
            year,
            {
              if (kind == 'ordinary')
                TaxAmountField.otherInterest: row['input'],
              if (kind == 'stcg') TaxAmountField.equityStcg: row['input'],
              if (kind == 'ltcg') TaxAmountField.equityLtcg: row['input'],
              if (kind == 'dividend') TaxAmountField.dividends: row['input'],
              if (kind == 'mixed') ...{
                TaxAmountField.otherInterest:
                    (input - f.e(row['st']) - f.e(row['lt'])).toString(),
                TaxAmountField.equityStcg: row['st'],
                TaxAmountField.equityLtcg: row['lt'],
              }
            },
            age: TaxAge.values.byName(row['age']));
        final r = row['regime'] == 'old'
            ? comparison.oldRegime
            : comparison.newRegime;
        final actual = {
          'total': r.totalIncome,
          'tax': r.incomeTax,
          'rebate': r.rebate,
          'rebateRelief': r.rebateRelief,
          'surcharge': r.surcharge,
          'surchargeRelief': r.surchargeRelief,
          'cess': r.cess,
          'liability': r.liability
        };
        for (final entry in actual.entries) {
          expect(entry.value, f.e(row[entry.key]), reason: entry.key);
        }
        expect(r.ordinaryIncome + r.stcg + r.ltcg, r.totalIncome);
        expect(r.ordinaryIncome.isNegative, isFalse);
      });
    }
  }
}
