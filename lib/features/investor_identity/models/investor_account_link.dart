enum InvestorLinkStatus {
  active,
  revoked;

  static InvestorLinkStatus fromDatabase(String value) {
    switch (value) {
      case 'active':
        return InvestorLinkStatus.active;
      case 'revoked':
        return InvestorLinkStatus.revoked;
      default:
        throw ArgumentError.value(
            value, 'value', 'Unknown investor link status');
    }
  }

  String get databaseValue {
    switch (this) {
      case InvestorLinkStatus.active:
        return 'active';
      case InvestorLinkStatus.revoked:
        return 'revoked';
    }
  }
}

class InvestorAccountLink {
  const InvestorAccountLink({
    required this.id,
    required this.userId,
    required this.profileId,
    required this.verificationMethod,
    required this.linkedAt,
    required this.linkStatus,
    required this.createdAt,
    required this.updatedAt,
    this.verifiedAt,
  });

  final String id;
  final String userId;
  final String profileId;
  final String verificationMethod;
  final DateTime? verifiedAt;
  final DateTime linkedAt;
  final InvestorLinkStatus linkStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory InvestorAccountLink.fromJson(Map<String, dynamic> json) {
    return InvestorAccountLink(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      profileId: json['profile_id'] as String,
      verificationMethod: json['verification_method'] as String,
      verifiedAt: json['verified_at'] == null
          ? null
          : DateTime.parse(json['verified_at'] as String),
      linkedAt: DateTime.parse(json['linked_at'] as String),
      linkStatus: InvestorLinkStatus.fromDatabase(
        json['link_status'] as String,
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
