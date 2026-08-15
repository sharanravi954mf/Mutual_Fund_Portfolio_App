class InvestorReferral {
  const InvestorReferral({
    required this.code,
    required this.createdAt,
  });

  final String code;
  final DateTime createdAt;
}

class ReferralShareLinkBuilder {
  const ReferralShareLinkBuilder(this.publicAppUri);

  factory ReferralShareLinkBuilder.fromEnvironment() {
    const configuredBase = String.fromEnvironment(
      'MONEYBOWL_PUBLIC_APP_URL',
      defaultValue: 'https://moneybowl.app',
    );
    return ReferralShareLinkBuilder(Uri.parse(configuredBase));
  }

  final Uri publicAppUri;

  Uri referralUri(String code) {
    final basePath = publicAppUri.path.endsWith('/')
        ? publicAppUri.path.substring(0, publicAppUri.path.length - 1)
        : publicAppUri.path;
    return publicAppUri.replace(
      path: '$basePath/join',
      queryParameters: <String, String>{
        ...publicAppUri.queryParameters,
        'ref': code,
      },
    );
  }

  String message(String code) =>
      'Join me on Money Bowl and start organising your mutual fund '
      'portfolio securely: ${referralUri(code)}';

  Uri whatsAppUri(String code) => Uri.https(
        'wa.me',
        '/',
        <String, String>{'text': message(code)},
      );
}
