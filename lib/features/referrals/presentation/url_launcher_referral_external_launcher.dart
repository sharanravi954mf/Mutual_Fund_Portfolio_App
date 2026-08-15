import 'package:url_launcher/url_launcher.dart';

import '../application/referral_share_controller.dart';

class UrlLauncherReferralExternalLauncher implements ReferralExternalLauncher {
  const UrlLauncherReferralExternalLauncher();

  @override
  Future<bool> open(Uri uri) => launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
}
