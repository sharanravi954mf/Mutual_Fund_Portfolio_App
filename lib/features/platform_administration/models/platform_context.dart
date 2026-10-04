/// Safe server projection for routing/display. Each mutation rechecks the DB.
class PlatformContext {
  const PlatformContext({
    this.isPlatformAdmin = false,
    this.capabilities = const {},
    this.stepUpVerified = false,
    this.mfaEnrolled = false,
  });

  final bool isPlatformAdmin;
  final Set<String> capabilities;
  final bool stepUpVerified;
  final bool mfaEnrolled;

  factory PlatformContext.fromJson(Map<String, dynamic> json) =>
      PlatformContext(
        isPlatformAdmin: json['is_platform_admin'] == true,
        capabilities:
            Set.unmodifiable((json['capabilities'] as List).cast<String>()),
        stepUpVerified: json['step_up_verified'] == true,
        mfaEnrolled: json['mfa_enrolled'] == true,
      );
}
