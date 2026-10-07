/// Build-time gate for the synthetic, read-free onboarding preview.
///
/// This gate is a UI availability check, never an authority for business RPCs.
class DevOnboardingPreviewGate {
  const DevOnboardingPreviewGate._();

  static const _flag = bool.fromEnvironment('MONEYBOWL_DEV_ONBOARDING_PREVIEW');
  static const _environment = String.fromEnvironment('MONEYBOWL_ENV');
  static const _projectUrl = String.fromEnvironment('SUPABASE_URL');
  static const devProjectUrl = 'https://rskryngwzyuzmiwtriyy.supabase.co';

  static bool get enabled =>
      allows(flag: _flag, environment: _environment, projectUrl: _projectUrl);

  static bool allows({
    required bool flag,
    required String environment,
    required String projectUrl,
  }) =>
      flag && environment == 'dev' && projectUrl == devProjectUrl;
}
