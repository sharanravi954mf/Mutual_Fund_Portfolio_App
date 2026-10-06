import 'package:flutter/material.dart';
import '../domain/tax_rules.dart';
import '../models/tax_input.dart';
import '../models/tax_result.dart';
import '../models/guided_deductions.dart';
import 'income_tax_controller.dart';

class IncomeTaxScreen extends StatefulWidget {
  const IncomeTaxScreen({super.key});
  @override
  State<IncomeTaxScreen> createState() => _IncomeTaxScreenState();
}

class _IncomeTaxScreenState extends State<IncomeTaxScreen> {
  final c = IncomeTaxController();
  bool rules = false;
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: c,
      builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('Income Tax Calculator')),
          body: SingleChildScrollView(
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('Compare Old and New Regime',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall),
                                const SizedBox(height: 8),
                                const Text(
                                    'A bounded individual tax estimator for the supported income years and cases. It is not an ITR preparation or filing service. Unsupported or unverified combinations return no comparison.'),
                                const SizedBox(height: 8),
                                const Text(
                                    'What V1 supports: resident and ordinarily resident individuals with guided salary or employment pension, ordinary family pension, named interest and deductions. Advanced adds supported HRA, employer NPS, one self-occupied and one let-out property, bounded equity gains, domestic company dividends and tax credits. Some combinations are unavailable; declare them in the category sections and unsupported-case checklist. A blocked case returns no Old/New estimate.'),
                                const SizedBox(height: 16),
                                DropdownButtonFormField<TaxYear>(
                                    key: ValueKey('year-${c.generation}'),
                                    initialValue: c.year,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                        labelText: 'Income year'),
                                    items: TaxYear.values
                                        .map((y) => DropdownMenuItem(
                                            value: y,
                                            child: Text(
                                                TaxRulePack.forYear(y).label)))
                                        .toList(),
                                    onChanged: (v) {
                                      if (v != null) c.setYear(v);
                                    }),
                                const SizedBox(height: 8),
                                Text('${c.pack.period}\n${c.pack.act}'),
                                const SizedBox(height: 16),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  ChoiceChip(
                                      label: const Text('Normal'),
                                      selected: c.mode == TaxMode.normal,
                                      onSelected: (_) =>
                                          c.setMode(TaxMode.normal)),
                                  ChoiceChip(
                                      label: const Text('Advanced'),
                                      selected: c.mode == TaxMode.advanced,
                                      onSelected: (_) =>
                                          c.setMode(TaxMode.advanced)),
                                  ChoiceChip(
                                      label: const Text('Input'),
                                      selected: !rules,
                                      onSelected: (_) =>
                                          setState(() => rules = false)),
                                  ChoiceChip(
                                      label: const Text('Rules & Assumptions'),
                                      selected: rules,
                                      onSelected: (_) =>
                                          setState(() => rules = true)),
                                ]),
                                if (rules) _rules() else ..._inputs(),
                                const SizedBox(height: 16),
                                Wrap(spacing: 12, runSpacing: 8, children: [
                                  FilledButton.icon(
                                      key: const ValueKey('tax-calculate'),
                                      onPressed: () {
                                        FocusScope.of(context).unfocus();
                                        c.calculate();
                                      },
                                      icon:
                                          const Icon(Icons.calculate_outlined),
                                      label: const Text('Calculate')),
                                  OutlinedButton(
                                      onPressed: c.reset,
                                      child: const Text('Reset')),
                                ]),
                                const SizedBox(height: 16),
                                if (c.outcome != null)
                                  Semantics(
                                      liveRegion: true,
                                      child: _result(c.outcome!)),
                                const SizedBox(height: 24),
                                const Text(
                                    'Entries and computation stay in this screen’s memory. No identifiers, uploads or login are needed. Leaving the screen discards entries. No credit validation, filing, interest, late fees or penalties.'),
                              ])))))));

  Widget _section(String title, List<Widget> children,
          {bool open = false}) =>
      Card(
          child: ExpansionTile(
              key: ValueKey('$title-${c.generation}'),
              initiallyExpanded: open,
              title: Text(title),
              childrenPadding: const EdgeInsets.all(16),
              children: [
            Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children)
          ]));
  Widget _amount(TaxAmountField field, String label, String help) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
          key: ValueKey('${field.name}-${c.generation}'),
          initialValue: c.value(field),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
              label: Text(label),
              prefixText: '₹ ',
              helperText: help,
              helperMaxLines: 8),
          onChanged: (v) => c.setAmount(field, v)));
  Widget _check(TaxConfirmation flag, String label) => CheckboxListTile(
      key: ValueKey(flag.name),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label),
      value: c.confirmed(flag),
      onChanged: (v) => c.setConfirmation(flag, v ?? false));
  Widget _note(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8), child: Text(text));
  List<Widget> _inputs() => [
        _section('Eligibility', [
          _check(TaxConfirmation.residentOrdinarilyResidentIndividual,
              'I am an individual resident and ordinarily resident in India for this income period.'),
          DropdownButtonFormField<TaxAge>(
              key: ValueKey('age-${c.generation}'),
              initialValue: c.age,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Age reached during the selected income year'),
              items: const [
                DropdownMenuItem(
                    value: TaxAge.below60, child: Text('Below 60')),
                DropdownMenuItem(
                    value: TaxAge.from60to79, child: Text('60–79')),
                DropdownMenuItem(
                    value: TaxAge.atLeast80, child: Text('80 or above'))
              ],
              onChanged: (v) {
                if (v != null) c.setAge(v);
              }),
          _check(TaxConfirmation.ageForSelectedYear,
              'This age band is correct for the income period shown, not my age today.'),
          ExpansionTile(
              title: const Text('Unsupported cases and limitations'),
              subtitle: const Text(
                  'Open this checklist and declare any case that applies.'),
              children: [
                _note('Any selected case withholds the entire comparison.'),
                ...UnsupportedTaxCase.values.map((u) => CheckboxListTile(
                    key: ValueKey('unsupported-${u.name}'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(_excluded[u]!),
                    value: c.unsupported(u),
                    onChanged: (v) => c.setUnsupported(u, v ?? false))),
              ]),
          _check(TaxConfirmation.scopeChecklistReviewed,
              'I opened and reviewed the unsupported-case checklist and included all relevant income, deductions and circumstances.'),
        ]),
        _section(
            'Salary and interest',
            [
              _amount(
                  TaxAmountField.salary,
                  'Annual gross salary / employment pension',
                  'Before HRA exemption and standard deduction; include taxable perquisites. Not CTC, take-home pay or already-deducted taxable salary. Combine all employers and employment pension.'),
              if (c.hasValue(TaxAmountField.salary))
                _check(TaxConfirmation.salaryDefinition,
                    'My gross salary follows this definition. HRA is already included; I have not deducted the standard deduction.'),
              _amount(
                  TaxAmountField.savingsInterest,
                  'Savings-account interest',
                  'Gross before TDS from bank or co-operative bank savings accounts. Enter Post Office Savings Bank interest separately below.'),
              _amount(
                  TaxAmountField.postOfficeSavingsInterest,
                  'Post Office Savings Bank interest',
                  'One individually held savings account. The ₹3,500 exemption and eligible interest deduction are applied automatically, once.'),
              if (c.hasValue(TaxAmountField.postOfficeSavingsInterest))
                _check(TaxConfirmation.individualPostOfficeAccount,
                    'This is one account held individually in my own capacity, with no joint ownership or clubbing. I have not included this interest elsewhere.'),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                      'I need joint/multiple post-office savings attribution, or PPF, Sukanya, tax-free bond, excess PF or another special-interest treatment (not supported in V1).'),
                  value:
                      c.pending(PendingTaxFeature.postOfficeSavingsExemption),
                  onChanged: (v) => c.setPending(
                      PendingTaxFeature.postOfficeSavingsExemption,
                      v ?? false)),
              _amount(
                  TaxAmountField.depositInterest,
                  'Eligible deposit interest',
                  'Gross bank, co-operative-bank or post-office time-deposit interest, separate from savings. Other interest belongs in Advanced.'),
              if (c.hasValue(TaxAmountField.savingsInterest) ||
                  c.hasValue(TaxAmountField.depositInterest))
                _check(TaxConfirmation.depositEligibility,
                    'These are eligible deposits held in my own capacity, not on behalf of a firm, AOP or BOI. Interest deductions are calculated automatically.'),
              _note(
                  'Use Advanced for HRA, employer NPS, house property, family pension, dividends, capital gains or other taxable interest.'),
            ],
            open: true),
        _section('Investments and own NPS', [
          _amount(TaxAmountField.epf, 'Employee EPF contribution',
              'Your contribution to a recognised provident fund; exclude employer contributions.'),
          _amount(TaxAmountField.ppf, 'PPF contribution',
              'Eligible contribution paid during the income period to your, spouse’s or child’s notified PPF account.'),
          _amount(TaxAmountField.elss, 'ELSS subscription',
              'Only a qualifying notified equity-linked savings scheme subscription; not every mutual fund investment.'),
          _amount(
              TaxAmountField.annuity80ccc,
              'Eligible pension annuity contribution',
              '80CCC / Schedule XV1(x): amount paid from taxable income to an eligible insurer pension fund. Exclude interest/bonus credited and any duplicate claim.'),
          _check(TaxConfirmation.investmentEligibility,
              'Each investment meets the named instrument’s conditions and was paid this income year; no withdrawal/reversal or duplicate claim is involved.'),
          ...c.policies.map((row) => _guided(row, true)),
          OutlinedButton.icon(
              key: const ValueKey('add-life-policy'),
              onPressed: c.addPolicy,
              icon: const Icon(Icons.add),
              label: const Text('Add life insurance policy')),
          _note(
              'Tuition: choose at most two of your children. Include tuition for full-time education at an institution in India; exclude development fees, donations, transport, hostel and similar charges.'),
          _amount(TaxAmountField.tuitionChildOne, 'Tuition paid for child 1',
              'Tuition only; do not repeat another field or another person’s claim.'),
          _check(TaxConfirmation.tuitionChildOneEligible,
              'Child 1: my child, full-time education in India.'),
          _amount(TaxAmountField.tuitionChildTwo, 'Tuition paid for child 2',
              'A different child, with the same eligibility conditions.'),
          _check(TaxConfirmation.tuitionChildTwoEligible,
              'Child 2: my child, full-time education in India.'),
          _amount(
              TaxAmountField.housingPrincipal,
              'Housing principal / qualifying instalment',
              'Exclude interest, repair/renovation, membership/share costs and initial membership deposits.'),
          DropdownButtonFormField<HousingPaymentKind>(
              key: ValueKey('housing-kind-${c.generation}'),
              initialValue: c.housingKind,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Housing payment / lender category'),
              items: const {
                HousingPaymentKind.governmentOrBank: 'Government / bank',
                HousingPaymentKind.licOrNationalHousingBank:
                    'LIC or National Housing Bank',
                HousingPaymentKind.qualifyingHousingFinance: 'Housing finance',
                HousingPaymentKind.qualifyingEmployer:
                    'Qualifying employer loan',
                HousingPaymentKind.authorityOrSocietyInstallment:
                    'Housing instalment',
                HousingPaymentKind.otherLender: 'Other lender',
              }
                  .entries
                  .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value,
                          maxLines: 1, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) {
                if (v != null) c.setHousingKind(v);
              }),
          _note(
              'Government / bank includes Central or State Government and co-operative banks. Housing finance: an eligible Indian public housing-finance company, or a publicly held company/co-operative society financing construction. Qualifying employer: statutory authority/board/corporation, public or public-sector company, statutory university/affiliated college, local authority or co-operative society. Instalments must be towards ownership under the statutory authority scheme or an allotted company/society property. Other lender principal is ineligible.'),
          _amount(
              TaxAmountField.housingTransferCharges,
              'Housing stamp duty / registration',
              'Eligible expenses to transfer the residential house to you; separate from loan interest.'),
          _check(TaxConfirmation.housingPurchaseEligible,
              'These payments concern my completed residential house purchase/construction, with qualifying lender/instalment facts; no ineligible repairs, interest, membership expenses, early transfer or refund.'),
          _amount(TaxAmountField.nscSubscription, 'NSC VIII Issue subscription',
              'Paid in the selected year; not Kisan Vikas Patra. Interest is entered separately below.'),
          _amount(
              TaxAmountField.nscReinvestedInterest,
              'NSC interest reinvested in years 1–4',
              'Already-computed eligible accrual for this income year. Automatically added to taxable interest once; do not include it in another interest field.'),
          _amount(TaxAmountField.nscFinalInterest, 'NSC final-year interest',
              'Taxable interest, not reinvested or deductible as subscription. Do not duplicate it elsewhere.'),
          _check(TaxConfirmation.nscEligibility,
              'These are eligible VIII Issue holdings in my own taxable capacity; the accrued interest amounts and reinvestment years are correct, with no duplicate entry.'),
          _note(
              'Four additional V1 investments: enter current-year contributions only. Interest is separate. These share one Old-Regime ₹1.5 lakh group cap and are not deducted in New Regime.'),
          _amount(
              TaxAmountField.bankFiveYearDeposit,
              'Five-year bank tax-saving deposit paid',
              'Only Bank Term Deposit Scheme 2006 at a scheduled bank, held singly by you, locked at least five years. One current-year amount in ₹100 multiples; not an ordinary FD, renewal, interest or a pledged deposit.'),
          if (c.hasValue(TaxAmountField.bankFiveYearDeposit))
            _check(TaxConfirmation.bankFiveYearEligible,
                'I am the sole holder and paid this into the notified Bank Term Deposit Scheme at a scheduled bank during the selected year; it is a qualifying five-year tax-saving deposit, not pledged or entered elsewhere.'),
          _amount(
              TaxAmountField.postFiveYearDeposit,
              'Five-year Post Office Time Deposit paid',
              'Only a single-held National Savings Time Deposit five-year account opened this year. Exclude one-, two-, three-year, recurring and monthly-income accounts; enter taxable interest under eligible deposit interest.'),
          if (c.hasValue(TaxAmountField.postFiveYearDeposit))
            _check(TaxConfirmation.postFiveYearEligible,
                'I am the sole account holder; this is an eligible five-year National Savings Time Deposit opened and paid this income year, without a repeated amount.'),
          _amount(
              TaxAmountField.scssDeposit,
              'SCSS current-year opening deposit',
              'Single-held 2019 Senior Citizens Savings Scheme account opened with this deposit. You must have been at least 60 on opening date. Combined scheme deposits stay within ₹30 lakh; enter taxable interest separately.'),
          if (c.hasValue(TaxAmountField.scssDeposit)) ...[
            _check(TaxConfirmation.scssEligibleAtOpening,
                'I was at least 60 on the SCSS account opening date, am its sole holder, and this current-year opening deposit plus my other SCSS deposits stays within the scheme ceiling.'),
            _note(
                'SCSS accounts opened under a below-60 retirement or defence exception are not supported in V1. Declaring the amount with a below-60 age band returns no comparison.'),
          ],
          _amount(
              TaxAmountField.sukanyaChildOne,
              'Sukanya contribution for girl child 1',
              'Paid by you to an eligible Sukanya Samriddhi account opened for your own girl child or legal ward before she turned 10; the guardian and child must satisfy scheme residence/citizenship conditions. Deposit within the first 15 years. Max ₹1.5 lakh per account per financial year; do not enter interest.'),
          if (c.hasValue(TaxAmountField.sukanyaChildOne))
            _check(TaxConfirmation.sukanyaChildOneEligible,
                'Girl child 1: I am the eligible parent or legal guardian; the girl child and guardian meet the scheme residence and citizenship conditions, the account was opened before age 10, is in its deposit period, and this current-year payment is my own claim.'),
          _amount(
              TaxAmountField.sukanyaChildTwo,
              'Sukanya contribution for girl child 2',
              'Only a different eligible girl child and account. Enter one contribution amount per child; do not repeat child 1.'),
          if (c.hasValue(TaxAmountField.sukanyaChildTwo)) ...[
            _check(TaxConfirmation.sukanyaChildTwoEligible,
                'Girl child 2 meets the same opening, guardian, contribution-year and ownership conditions.'),
            _check(TaxConfirmation.sukanyaDistinctChildren,
                'Child 2 is a different girl child and account; neither contribution or beneficiary is repeated.'),
          ],
          if ([
            TaxAmountField.bankFiveYearDeposit,
            TaxAmountField.postFiveYearDeposit,
            TaxAmountField.scssDeposit,
            TaxAmountField.sukanyaChildOne,
            TaxAmountField.sukanyaChildTwo,
          ].any(c.hasValue))
            _check(TaxConfirmation.investmentAmountsExclusive,
                'All named investment contributions were paid in the selected year and each amount is entered exactly once, not repeated under EPF, PPF, ELSS, annuity, NSC or another category.'),
          _note(
              'Other investment instruments are outside V1. Declare them below instead of entering them under another field.'),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                  'I have another 80C / Schedule XV investment beyond the named guided inputs (not supported in V1).'),
              value: c.pending(PendingTaxFeature.additional80cInstruments),
              onChanged: (v) => c.setPending(
                  PendingTaxFeature.additional80cInstruments, v ?? false)),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                  'An earlier deduction may need to be added back because of early policy termination, home transfer/refund or deposit closure (not supported in V1).'),
              value: c.pending(PendingTaxFeature.deductionRecapture),
              onChanged: (v) => c.setPending(
                  PendingTaxFeature.deductionRecapture, v ?? false)),
          _amount(
              TaxAmountField.ownNpsTotal,
              'Total own Tier-I NPS contribution',
              'Enter once. The engine allocates up to ₹50,000 to the additional deduction, then the eligible remainder to the shared ₹1.5 lakh group. Exclude employer NPS and minor accounts.'),
          if (c.hasValue(TaxAmountField.ownNpsTotal) ||
              c.hasValue(TaxAmountField.employerNps) ||
              c.employers.isNotEmpty) ...[
            _check(TaxConfirmation.npsEmployee,
                'I had employee salary this year (employment pension alone does not make me an employee).'),
            _amount(TaxAmountField.npsSalaryBase, 'Statutory NPS salary base',
                'Total employee basic salary, contractual turnover-percentage commission and qualifying DA across employers for your own NPS limit. Employer-specific salary bases are entered separately in Advanced. Exclude allowances and perquisites. Required when an employee contribution remains eligible for the shared investment cap after the additional deduction. Blank is missing; enter 0 only when those qualifying components actually total zero.'),
            _check(TaxConfirmation.npsEligibility,
                'I confirm Tier-I eligibility, employee status and salary definitions; each employer has a distinct contribution/base. No minor-account contribution, UPS treatment or withdrawal is included.'),
          ],
        ]),
        _section('Health insurance and medical expenses', [
          _note(
              '80D / section 126. Pay from taxable income. Insurance and medical payments must be noncash; preventive checkups may be cash. Enter only this year’s apportioned share of a multi-year premium. No same-person insurance plus uninsured-medical claim.'),
          ..._health(true),
          ..._health(false),
          _check(TaxConfirmation.healthEligiblePayments,
              'Payments meet these conditions; the family bucket is self, spouse and dependent children, and the parent bucket is parents. Insurance is an approved plan; senior means resident in India and at least 60 during this year.'),
        ]),
        if (c.mode == TaxMode.normal && c.hasAdvancedData)
          _note(
              'Advanced entries are retained and included. Their sections remain visible below. Reset explicitly clears all data.'),
        if (c.showAdvanced) ..._advanced(),
      ];
  List<Widget> _health(bool family) => [
        Text(family ? 'Self / family' : 'Parents',
            style: Theme.of(context).textTheme.titleMedium),
        _amount(
            family
                ? TaxAmountField.familyInsurance
                : TaxAmountField.parentInsurance,
            '${family ? 'Family' : 'Parent'} insurance premium',
            'Eligible annual share, not a multi-year total.'),
        _check(
            family
                ? TaxConfirmation.familySeniorInsured
                : TaxConfirmation.parentSeniorInsured,
            'This insurance includes a resident senior citizen aged 60+ during the selected year.'),
        _amount(
            family
                ? TaxAmountField.familyCheckup
                : TaxAmountField.parentCheckup,
            '${family ? 'Family' : 'Parent'} preventive checkup',
            'Both buckets share one ₹5,000 sublimit; included within the bucket cap.'),
        _amount(
            family
                ? TaxAmountField.familyMedical
                : TaxAmountField.parentMedical,
            '${family ? 'Family' : 'Parent'} uninsured senior medical expense',
            'Only the uninsured resident senior’s noncash medical expenditure.'),
        _check(
            family
                ? TaxConfirmation.familyUninsuredResidentSenior
                : TaxConfirmation.parentUninsuredResidentSenior,
            'Medical expense is for a resident senior citizen aged 60+ with no health insurance paid for that person.'),
      ];
  List<Widget> _advanced() => [
        _section('Advanced salary and HRA', [
          _amount(
              TaxAmountField.professionalTax,
              'Professional tax actually paid',
              'Employment tax, allowed only in Old Regime.'),
          _amount(TaxAmountField.employerNps, 'Employer NPS contribution',
              'Included in salary exactly once before the separate percentage-limited deduction.'),
          _amount(
              TaxAmountField.employerSalaryBase,
              'Employer 1 statutory salary base',
              'Only this employer’s basic salary, contractual turnover-percentage commission and qualifying DA. Exclude NPS contribution itself, other allowances and perquisites.'),
          _check(TaxConfirmation.employerNpsAlreadyInSalary,
              'Employer NPS is already included in the gross salary above.'),
          _check(TaxConfirmation.governmentEmployer,
              'Employer is the Central or a State Government. Public-sector companies are other employers.'),
          ...c.employers.map((row) => _guided(row, false)),
          OutlinedButton.icon(
              key: const ValueKey('add-employer'),
              onPressed: c.addEmployer,
              icon: const Icon(Icons.add),
              label: const Text('Add another employer')),
          _check(TaxConfirmation.taxablePerquisitesIncluded,
              'All taxable excess-contribution perquisites and accretions are already computed and included in gross salary. The calculator does not compute them.'),
          _note(
              'HRA: add a separate, non-overlapping period whenever salary, HRA, rent or residence changes. All period salary/HRA amounts are already in annual gross salary. Enter rent for accommodation actually occupied; no rent paid means no exemption.'),
          ...c.hra.map(_hra),
          OutlinedButton.icon(
              onPressed: c.addHra,
              icon: const Icon(Icons.add),
              label: const Text('Add HRA period')),
        ]),
        _section('Other sources', [
          _amount(
              TaxAmountField.otherInterest,
              'Other ordinary taxable interest',
              'Gross before TDS; not eligible for savings/deposit interest deductions. Exclude special-rate or foreign income.'),
          _amount(TaxAmountField.dividends, 'Domestic company dividends',
              'Gross before TDS. Exclude REIT/InvIT/business-trust and other pass-through distributions.'),
          _check(TaxConfirmation.ordinaryCompanyDividends,
              'These are ordinary domestic company dividends, with no expense deduction claimed and no pass-through distributions.'),
          _amount(TaxAmountField.familyPension, 'Ordinary family pension',
              'Survivor family pension, distinct from your employment pension. The engine applies the one-third deduction and regime cap.'),
        ]),
        _section('House property', [
          _check(TaxConfirmation.completedFullyOwnedProperties,
              'At most one completed, fully owned self-occupied home and one completed, fully owned let-out property; no joint/deemed letting, pre-construction interest, vacancy/unrealised-rent dispute or foreign loan.'),
          _amount(
              TaxAmountField.selfOccupiedInterest,
              'Self-occupied loan interest',
              'Eligible current-period interest only; no principal or pre-construction instalment.'),
          _check(TaxConfirmation.selfLoanAcquisitionConstruction,
              'The self-occupied loan funded acquisition or construction (otherwise repair, renewal or reconstruction).'),
          if (c.year == TaxYear.fy2025)
            _check(TaxConfirmation.selfLoanAfterApril1999,
                'Capital was borrowed on or after 1 April 1999.'),
          _check(TaxConfirmation.selfLoanCompletedWithinFiveYears,
              'Acquisition/construction completed within five years from the end of the income year in which capital was borrowed.'),
          _check(TaxConfirmation.interestCertificate,
              'I hold the required lender interest certificate, including qualifying refinancing where relevant.'),
          _amount(TaxAmountField.grossAnnualValue, 'Let-out gross annual value',
              'Use the legally determined annual value: normally higher of reasonable expected rent and actual rent receivable. Actual rent alone may be wrong. Resolve rent-control valuation externally; disputed vacancy/unrealised rent is outside V1.'),
          _amount(TaxAmountField.municipalTax, 'Municipal taxes actually paid',
              'Eligible local-authority taxes paid by you as owner in this income year, irrespective of when due.'),
          _amount(TaxAmountField.letOutInterest, 'Let-out loan interest',
              'Eligible current-period borrowed-capital interest. No pre-construction interest calculation.'),
          _check(TaxConfirmation.annualValueVerified,
              'I have determined the correct gross annual value and eligible owner-paid municipal taxes.'),
        ]),
        _section('Education-loan interest', [
          _amount(
              TaxAmountField.educationInterest,
              'Eligible higher-education loan interest',
              '80E / section129. Interest paid from taxable income; never principal.'),
          DropdownButtonFormField<int>(
              key: ValueKey('education-${c.generation}'),
              initialValue: c.educationYear,
              decoration: const InputDecoration(
                  labelText: 'Year since first interest repayment'),
              items: List.generate(
                  10,
                  (i) => DropdownMenuItem(
                      value: i + 1, child: Text('Year ${i + 1}'))),
              onChanged: (v) {
                if (v != null) c.setEducationYear(v);
              }),
          _check(TaxConfirmation.educationEligible,
              'I am the borrower; the higher education is for me, spouse, child or student for whom I am legal guardian. The lender is an eligible bank/notified financial institution or approved charitable institution.'),
        ]),
        _section('Equity capital gains', [
          _note(
              'Enter already-computed non-negative gains, not sale proceeds. This does not classify holding periods, calculate cost/grandfathering, match trades, or set off capital losses.'),
          _amount(TaxAmountField.equityStcg, 'Eligible equity STCG',
              'Listed equity shares / equity-oriented mutual funds qualifying under 111A /196;20% rate.'),
          _check(TaxConfirmation.equityStcgEligible,
              'The STCG is correctly classified and the sale is chargeable to STT; only eligible domestic listed equity / equity-oriented funds are included.'),
          _amount(
              TaxAmountField.equityLtcg,
              'Eligible equity LTCG before threshold',
              '111A is not the LTCG rule: use112A /198 eligibility. Do not deduct the annual ₹1.25 lakh threshold yourself.'),
          _check(TaxConfirmation.equityLtcgEligible,
              'The LTCG qualifies under112A /198: STT on acquisition and transfer of shares (or a notified acquisition exception), or STT on transfer of equity-oriented fund units; eligible precomputed cost is used.'),
          _note(
              'Combined gains using unused basic exemption and mixed-income surcharge above ₹50 lakh are unavailable in V1. The calculator will withhold both estimates.'),
        ]),
        _section('Optional tax credits', [
          _note(
              'Eligible credits for this same income period only. These reduce the balance, not income. No Form26AS/AIS check is performed. Exclude payments for interest, fees or penalties.'),
          _amount(TaxAmountField.tds, 'TDS', 'Tax deducted at source.'),
          _amount(TaxAmountField.tcs, 'TCS', 'Tax collected at source.'),
          _amount(TaxAmountField.advanceTax, 'Advance tax',
              'Tax paid for this income period.'),
          _amount(TaxAmountField.selfAssessmentTax, 'Self-assessment tax',
              'Tax component already paid for this income period.'),
        ]),
      ];
  Widget _guided(GuidedDraft row, bool policy) {
    final kind = policy ? 'policy' : 'employer';
    Widget amount(String field, String label, {bool date = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: TextFormField(
            key: ValueKey('$kind-${row.id}-$field-${c.generation}'),
            initialValue: row.values[field],
            keyboardType: date
                ? TextInputType.datetime
                : const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                label: Text(label), prefixText: date ? null : '₹ '),
            onChanged: (v) => c.changeGuided(policy, row.id, field, v)));
    Widget check(String field, String label) => CheckboxListTile(
        key: ValueKey('$kind-${row.id}-$field'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(label),
        value: row.values[field] == 'yes',
        onChanged: (v) =>
            c.changeGuided(policy, row.id, field, v == true ? 'yes' : 'no'));
    return Card(
        key: ValueKey('$kind-${row.id}'),
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(policy
                      ? 'Life policy ${c.policies.indexOf(row) + 1}'
                      : 'Additional employer ${c.employers.indexOf(row) + 1}'),
                  if (policy) ...[
                    amount('paid', 'Premium paid in selected income year'),
                    amount('assured', 'Actual capital sum assured'),
                    _note(
                        'Minimum assured on the insured event over the policy term. Exclude returned premiums, bonuses and additional benefits. The calculator applies the issue-date percentage separately for each policy.'),
                    amount('issued', 'Policy issue date (YYYY-MM-DD)',
                        date: true),
                    check('family',
                        'The insured person is myself, my spouse or my child.'),
                    check('special',
                        'The insured person meets the statutory disability/severe-disability or specified-disease conditions (80U/80DDB; 154/128). The 15% limit applies only to policies issued from 1 April 2013.'),
                  ] else ...[
                    amount('contribution', 'This employer’s NPS contribution'),
                    amount('base', 'This employer’s statutory salary base'),
                    _note(
                        'Basic salary, contractual turnover-percentage commission and qualifying DA from this employer only; exclude contributions, other allowances and perquisites. Do not repeat another employer’s salary.'),
                    check('government',
                        'This employer is the Central or a State Government.'),
                    check('included',
                        'This contribution is already included in annual gross salary.'),
                  ],
                  TextButton(
                      key: ValueKey('remove-$kind-${row.id}'),
                      onPressed: () => c.removeGuided(policy, row.id),
                      child: Text(policy
                          ? 'Remove this life policy'
                          : 'Remove this employer')),
                ])));
  }

  Widget _hra(HraDraft p) => Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('HRA period ${p.id + 1}'),
            for (final field in const {
              'start': 'Start date (YYYY-MM-DD)',
              'end': 'End date (YYYY-MM-DD)',
              'basic': 'Period basic salary',
              'da': 'Period eligible DA',
              'commission': 'Period turnover commission',
              'hra': 'Period actual HRA received',
              'rent': 'Period rent paid'
            }.entries)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TextFormField(
                      key: ValueKey('hra-${p.id}-${field.key}-${c.generation}'),
                      initialValue: p.values[field.key],
                      keyboardType: field.key == 'start' || field.key == 'end'
                          ? TextInputType.datetime
                          : const TextInputType.numberWithOptions(
                              decimal: true),
                      decoration: InputDecoration(label: Text(field.value)),
                      onChanged: (v) => c.changeHra(p.id, field.key, v))),
            _note(c.year == TaxYear.fy2025
                ? 'DA qualifies where it forms part of retirement benefits; commission only at a fixed percentage of turnover. Exclude other allowances and perquisites.'
                : 'DA qualifies where employment terms provide; commission only at a contractual fixed percentage of turnover. Exclude other allowances and perquisites.'),
            DropdownButtonFormField<String>(
                key: ValueKey('hra-${p.id}-city-${c.generation}'),
                initialValue: p.values['city'] ?? 'Mumbai',
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'City of residential accommodation'),
                items: const [
                  'Mumbai',
                  'Kolkata',
                  'Delhi',
                  'Chennai',
                  'Hyderabad',
                  'Pune',
                  'Ahmedabad',
                  'Bengaluru',
                  'Other'
                ]
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) c.changeHra(p.id, 'city', v);
                }),
            TextButton(
                key: ValueKey('remove-hra-${p.id}'),
                onPressed: () => c.removeHra(p.id),
                child: const Text('Remove this HRA period')),
          ])));

  Widget _rules() => _section(
      'Rules and verification',
      [
        Text(
            '${c.pack.version}\n${c.pack.period}\n${c.pack.act}\nComponent sources verified as of ${TaxRulePack.verifiedAsOf}.'),
        _note(
            'Old and New are tax regimes, separate from the Act and income-year labels. Normal and Advanced use the same engine. Comparison is not a legal regime election or automatic filing choice.'),
        _note(
            'Old basic exemption: ₹2.5 lakh, ₹3 lakh or ₹5 lakh by age; New ₹4 lakh at every age. New ordinary slabs:0%,5%,10%,15%,20%,25%,30% at ₹4/8/12/16/20/24 lakh. ₹12 lakh is a rebate ceiling, not a nil slab.'),
        _note(
            'Income heads → exemptions → permitted set-offs → capped deductions → total-income rounding → ordinary/special tax → rebate and its relief → surcharge and its relief →4% cess → liability → entered credits → payable/refund. Exact arithmetic retains fractions; statutory rounding ignores paise then rounds to tens, digit5 upward.'),
        _note(
            'Unavailable in V1: combined gains with unused basic exemption, mixed-income surcharge cutoff, enhanced-band mixed dividends, gain-related loss allocation, negative property NAV, special-component rounding, senior NSC interest, joint/multiple post-office savings attribution, further special-interest exemptions and earlier-deduction recapture. Declaring any of these withholds both regime estimates. Source verification was refreshed through 5 October 2026; independent professional review remains outstanding.'),
        _note(
            'Known FY2025 utility discrepancy is reproduced statically, without running macros. Sole equity LTCG₹50,00,800 gives statutory New₹5,82,580 / Old₹6,02,080. No department confirmation of a defect is claimed.'),
        const SelectableText(
            'Official references (copy a static URL to open it yourself):\nhttps://incometaxindia.gov.in/documents/d/guest/finance-act-2026-pdf-1\nhttps://incometaxindia.gov.in/documents/d/guest/income_tax_act_2025_as_amended_by_fa_act_2026-pdf\nhttps://www.incometaxindia.gov.in/w/deductions\nhttps://www.incometax.gov.in/iec/foportal/help/individual/return-applicable-1'),
      ],
      open: true);
  Widget _result(TaxOutcome result) => switch (result) {
        TaxInvalidInput(:final issues) => _message('Check your inputs', issues),
        TaxUnsupported(:final cases) => _message(
            'This combination is not supported in V1. No tax comparison has been calculated.',
            cases.map((v) => _excluded[v]!)),
        TaxNotYetVerified(:final dependencies) => _message(
            'This combination is not supported in V1. No tax comparison has been calculated.',
            dependencies.entries.map((e) => '${e.key}: ${e.value}')),
        TaxCalculationFailure() => _message(
            'Calculation failed. No tax comparison has been calculated.',
            const ['Please review the entered values and try again.']),
        TaxComparison() =>
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                result.lowerRegime == null
                    ? 'Both regimes give the same estimated tax for the information entered.'
                    : '${result.lowerRegime == TaxRegime.old ? 'Old' : 'New'} Regime gives ${result.saving.inr} lower estimated tax for the information entered.',
                style: Theme.of(context).textTheme.titleLarge),
            _note(
                'This comparison is not a legal election or an automatic filing choice.'),
            LayoutBuilder(builder: (context, size) {
              final cards = [
                _estimate(result.oldRegime),
                _estimate(result.newRegime)
              ];
              return size.maxWidth >= 720
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: cards.map((w) => Expanded(child: w)).toList())
                  : Column(children: cards);
            }),
          ]),
      };
  Widget _message(String title, Iterable<String> details) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            ...details.map(_note)
          ])));
  Widget _estimate(RegimeEstimate r) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(r.regime == TaxRegime.old ? 'Old Regime' : 'New Regime',
                style: Theme.of(context).textTheme.titleLarge),
            _note('Estimated liability before credits\n${r.liability.inr}'),
            _note(
                'Statutory total income ${r.totalIncome.inr}\nEntered credits ${r.credits.inr}'),
            _note(r.balance.isNegative
                ? 'Estimated refund ${r.refund.inr}'
                : 'Estimated balance payable ${r.payable.inr}'),
            ExpansionTile(
                title: const Text('Computation and deductions'),
                children: [
                  for (final t in r.trace)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${t.label}: ${t.amount.inr}'),
                        subtitle: Text(
                            '${t.ruleId} — ${t.reason}\nExact rupees: ${t.amount}')),
                  for (final d
                      in r.deductions.where((d) => d.entered.isPositive))
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(d.label),
                        subtitle: Text(
                            'Entered/reference ${d.entered.inr}\nAllowed ${d.allowed.inr}\nDisallowed/unused ${d.disallowed.inr}\n${d.reason}')),
                  Text(
                      '${r.ruleVersion}\n${c.pack.period}\nVerified as of ${TaxRulePack.verifiedAsOf}'),
                ]),
          ])));
}

const _excluded = <UnsupportedTaxCase, String>{
  UnsupportedTaxCase.nonResidentOrRnor:
      'Non-resident or resident not ordinarily resident (RNOR)',
  UnsupportedTaxCase.otherTaxpayerType:
      'HUF, firm, company or another taxpayer type',
  UnsupportedTaxCase.businessOrFreelancing:
      'Business, freelancing, presumptive income or AMT',
  UnsupportedTaxCase.foreignIncomeOrAssets:
      'Foreign income/assets, treaty relief or foreign tax credits',
  UnsupportedTaxCase.agriculturalIncome:
      'Agricultural income requiring integration',
  UnsupportedTaxCase.broughtForwardLoss: 'Brought-forward loss utilisation',
  UnsupportedTaxCase.capitalLoss: 'Capital losses or capital-loss adjustments',
  UnsupportedTaxCase.cryptoLotteryGaming:
      'Crypto, lottery, gaming or similar special-rate income',
  UnsupportedTaxCase.complexSalaryOrArrears:
      'Complex retirement/perquisite exemptions or salary-arrears relief',
  UnsupportedTaxCase.otherDeduction:
      'Donations, disability or deductions outside the named supported categories',
  UnsupportedTaxCase.complexProperty:
      'Joint ownership, deemed letting, vacancy disputes, pre-construction interest or property-sale gains',
  UnsupportedTaxCase.businessTrustDistribution:
      'REIT/InvIT/business-trust or other pass-through distributions',
  UnsupportedTaxCase.otherSpecialIncome:
      'Other income or special-rate gains outside the displayed categories',
};
