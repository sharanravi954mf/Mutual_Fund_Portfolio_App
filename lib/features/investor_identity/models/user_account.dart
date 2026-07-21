enum AccountState {
  explorer,
  linkPending,
  linkedInvestor,
  advisor;

  static AccountState fromDatabase(String value) {
    switch (value) {
      case 'explorer':
        return AccountState.explorer;
      case 'link_pending':
        return AccountState.linkPending;
      case 'linked_investor':
        return AccountState.linkedInvestor;
      case 'advisor':
        return AccountState.advisor;
      default:
        throw ArgumentError.value(value, 'value', 'Unknown account state');
    }
  }

  String get databaseValue {
    switch (this) {
      case AccountState.explorer:
        return 'explorer';
      case AccountState.linkPending:
        return 'link_pending';
      case AccountState.linkedInvestor:
        return 'linked_investor';
      case AccountState.advisor:
        return 'advisor';
    }
  }
}

class UserAccount {
  const UserAccount({
    required this.userId,
    required this.accountState,
    required this.onboardingCompleted,
    required this.createdAt,
    required this.updatedAt,
    this.lastLoginAt,
  });

  final String userId;
  final AccountState accountState;
  final bool onboardingCompleted;
  final DateTime? lastLoginAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      userId: json['user_id'] as String,
      accountState: AccountState.fromDatabase(json['account_state'] as String),
      onboardingCompleted: json['onboarding_completed'] as bool,
      lastLoginAt: json['last_login_at'] == null
          ? null
          : DateTime.parse(json['last_login_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
