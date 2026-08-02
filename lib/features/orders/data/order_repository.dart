import '../domain/order_models.dart';

abstract class OrderFailure implements Exception {
  final String message;
  const OrderFailure(this.message);
  @override
  String toString() => message;
}

class EmptyFailure extends OrderFailure {
  const EmptyFailure(super.message);
}

class AccessDeniedFailure extends OrderFailure {
  const AccessDeniedFailure(super.message);
}

class NetworkFailure extends OrderFailure {
  const NetworkFailure(super.message);
}

class ConfigurationFailure extends OrderFailure {
  const ConfigurationFailure(super.message);
}

class OrderFolio {
  final String folioReferenceId;
  final String portfolioId;
  final String maskedFolioDisplay;
  final String registrar;

  const OrderFolio({
    required this.folioReferenceId,
    required this.portfolioId,
    required this.maskedFolioDisplay,
    required this.registrar,
  });
}

class OrderInvestor {
  final String investorProfileId;
  final String workspaceId;
  final String investorFullName;
  final String? email;
  final String? phoneNumber;

  const OrderInvestor({
    required this.investorProfileId,
    required this.workspaceId,
    required this.investorFullName,
    this.email,
    this.phoneNumber,
  });
}

abstract class OrderRepository {
  /// Submit the order draft to the database. Returns the generated order ID.
  Future<String> submitOrder(OrderDraft draft);

  /// Fetch active folios for the investor in a specific workspace.
  Future<List<OrderFolio>> fetchFolios(
      String investorProfileId, String workspaceId);

  /// Fetch actively assigned investors for the advisor.
  Future<List<OrderInvestor>> fetchAssignedInvestors(String advisorProfileId);

  /// Fetch all available mutual funds.
  Future<List<Map<String, dynamic>>> fetchMutualFunds();

  /// Fetch initial mutual funds with a limit.
  Future<List<Map<String, dynamic>>> fetchInitialMutualFunds({int limit = 20});

  /// Search mutual funds by name or code.
  Future<List<Map<String, dynamic>>> searchMutualFunds(String query);

  /// Fetch currently held schemes for the investor's portfolio, scoped to selected folio
  Future<List<Map<String, dynamic>>> fetchHoldings(
      String investorProfileId, String workspaceId, String folioReferenceId);

  /// Resolves the active workspace membership/portfolio details for the investor
  Future<OrderContext> resolveInvestorContext({
    required String investorProfileId,
    required String initiatorProfileId,
    required String initiationRole,
    required String initiationChannel,
    String? selectedWorkspaceId,
  });
}
