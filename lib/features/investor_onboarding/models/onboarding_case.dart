class OnboardingCase {
  OnboardingCase.fromJson(Map<String, dynamic> row)
      : id = row['id'] as String,
        workspaceId = row['workspace_id'] as String,
        version = row['version'] as int,
        name = row['legal_name'] as String? ?? 'Incomplete investor',
        status = row['status'] as String,
        relationship = row['relationship_status'] as String,
        accountLink = row['account_link_status'] as String,
        nseState = row['nse_state'] as String,
        kycState = row['kyc_state'] as String? ?? 'VERIFICATION_REQUIRED',
        uccState = row['ucc_state'] as String? ?? 'PREREQUISITES_INCOMPLETE',
        investorId = row['investor_profile_id'] as String?,
        operationId = row['integration_operation_id'] as String?,
        maskedPan = row['masked_pan'] as String? ?? '••••',
        maskedAccount = row['masked_account'] as String? ?? '••••',
        missing = List<String>.from(row['missing'] as List),
        fields = Map<String, String>.from(row['fields'] as Map);

  final String id,
      workspaceId,
      name,
      status,
      relationship,
      accountLink,
      nseState;
  final String? investorId, operationId;
  final String maskedPan, maskedAccount, kycState, uccState;
  final int version;
  final List<String> missing;
  final Map<String, String> fields;
  bool get reconciliation => status.endsWith('RECONCILIATION_REQUIRED');
  static String label(String value) => value.toLowerCase().replaceAll('_', ' ');
}

class OnboardingField {
  const OnboardingField(this.key, this.label,
      {this.choices, this.secret = false});
  final String key, label;
  final List<String>? choices;
  final bool secret;
}

// Capture actual facts only. Empty choices are intentional; no DOB, KYC,
// declaration, nomination or contact ownership defaults are manufactured.
const onboardingSections = <String, List<OnboardingField>>{
  'Personal details': [
    OnboardingField('legal_name', 'Legal name'),
    OnboardingField('legal_first_name', 'Legal first name'),
    OnboardingField('legal_middle_name', 'Legal middle name'),
    OnboardingField('legal_last_name', 'Legal last name'),
    OnboardingField('pan', 'PAN', secret: true),
    OnboardingField('email', 'Email'),
    OnboardingField('mobile', 'Mobile with country code'),
    OnboardingField('date_of_birth', 'Date of birth (YYYY-MM-DD)'),
    OnboardingField('gender', 'Gender',
        choices: ['male', 'female', 'other', 'transgender']),
  ],
  'Address': [
    OnboardingField('address_line_1', 'Address line 1'),
    OnboardingField('address_line_2', 'Address line 2'),
    OnboardingField('address_line_3', 'Address line 3'),
    OnboardingField('city', 'City'),
    OnboardingField('region', 'State / region'),
    OnboardingField('postal_code', 'Postal code'),
    OnboardingField('country', 'Country'),
  ],
  'KYC and holding': [
    OnboardingField('residency_status', 'Residency status',
        choices: ['resident_individual', 'non_resident_individual']),
    OnboardingField('tax_status', 'NSE tax status code'),
    OnboardingField('occupation', 'Occupation'),
    OnboardingField('occupation_code', 'NSE occupation code'),
    OnboardingField('holding_mode', 'Holding mode',
        choices: ['single', 'joint', 'anyone_or_survivor']),
    OnboardingField(
        'holder_details', 'Additional holder details, where applicable'),
    OnboardingField('kyc_method', 'KYC type',
        choices: ['kra', 'ckyc', 'biometric', 'aadhaar_ekyc_pan']),
    OnboardingField('kyc_status', 'Reported KYC status',
        choices: ['unknown', 'pending', 'completed']),
    OnboardingField('ckyc_number', 'CKYC number, where applicable'),
  ],
  'Bank': [
    OnboardingField('bank_name', 'Bank name'),
    OnboardingField('account_type', 'Account type',
        choices: ['savings', 'current', 'nre', 'nro']),
    OnboardingField('account_number', 'Bank account number', secret: true),
    OnboardingField('ifsc_code', 'IFSC'),
    OnboardingField('micr_code', 'MICR'),
  ],
  'Choices and declarations': [
    OnboardingField('communication_preference', 'Communication preference',
        choices: ['physical', 'electronic', 'mobile']),
    OnboardingField('onboarding_mode', 'Onboarding mode',
        choices: ['paper', 'paperless']),
    OnboardingField('mobile_owner_relationship', 'Mobile owner relationship',
        choices: ['self', 'spouse', 'dependent', 'guardian']),
    OnboardingField('email_owner_relationship', 'Email owner relationship',
        choices: ['self', 'spouse', 'dependent', 'guardian']),
    OnboardingField('nomination_choice', 'Nomination choice',
        choices: ['opt_in', 'opt_out']),
    OnboardingField(
        'nominee_details', 'Nominee / guardian details, where applicable'),
    OnboardingField('declarations', 'Declaration evidence / consent reference'),
    OnboardingField('mobile_declaration_flag', 'NSE mobile declaration code'),
    OnboardingField('email_declaration_flag', 'NSE email declaration code'),
    OnboardingField('div_pay_mode', 'NSE dividend payment mode code'),
    OnboardingField('nse_state', 'NSE state code'),
    OnboardingField('nse_country', 'NSE country code'),
  ],
};
