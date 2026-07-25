enum UserRole {
  investor,
  advisor,
  admin,
  operations,
  client, // legacy compatibility role
  platformAdmin; // platform administrator

  static UserRole fromDatabase(String value) {
    switch (value.toLowerCase()) {
      case 'investor':
        return UserRole.investor;
      case 'advisor':
        return UserRole.advisor;
      case 'admin':
        return UserRole.admin;
      case 'operations':
        return UserRole.operations;
      case 'client':
        return UserRole.client;
      case 'platform_admin':
        return UserRole.platformAdmin;
      default:
        return UserRole.investor; // fallback default
    }
  }

  String get databaseValue {
    if (this == UserRole.platformAdmin) {
      return 'platform_admin';
    }
    return name;
  }
}

enum AccountStatus {
  active,
  inactive,
  suspended;

  static AccountStatus fromDatabase(String value) {
    switch (value.toLowerCase()) {
      case 'active':
        return AccountStatus.active;
      case 'inactive':
        return AccountStatus.inactive;
      case 'suspended':
        return AccountStatus.suspended;
      default:
        return AccountStatus.active; // fallback default
    }
  }

  String get databaseValue => name;
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.role,
    required this.accountStatus,
    required this.createdAt,
    required this.updatedAt,
    this.fullName,
    this.phoneNumber,
    this.email,
  });

  final String id;
  final UserRole role;
  final AccountStatus accountStatus;
  final String? fullName;
  final String? phoneNumber;
  final String? email;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether the user profile is active and has full access
  bool get isActive => accountStatus == AccountStatus.active;

  /// Whether the user profile is suspended from system access
  bool get isSuspended => accountStatus == AccountStatus.suspended;

  /// Whether the user profile is marked inactive
  bool get isInactive => accountStatus == AccountStatus.inactive;

  /// Enforce strongly-typed dashboard route verification
  bool get isAuthorizedForAdvisorDashboard =>
      role == UserRole.advisor ||
      role == UserRole.admin ||
      role == UserRole.operations ||
      role == UserRole.platformAdmin;

  bool get isAuthorizedForInvestorDashboard =>
      role == UserRole.investor || role == UserRole.client;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      role: UserRole.fromDatabase(json['role'] as String),
      accountStatus: AccountStatus.fromDatabase(
        json['account_status'] as String? ?? 'active',
      ),
      fullName: json['full_name'] as String?,
      phoneNumber: json['phone_number'] as String?,
      email: json['email'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(
        json['updated_at'] as String? ?? json['created_at'] as String,
      ),
    );
  }
}
