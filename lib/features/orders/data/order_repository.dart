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
  final String normalizedFolioNumber;
  final String sourceFolioMasked;
  final String registrar;
  final String portfolioId;

  const OrderFolio({
    required this.normalizedFolioNumber,
    required this.sourceFolioMasked,
    required this.registrar,
    required this.portfolioId,
  });
}

class OrderInvestor {
  final String id;
  final String fullName;
  final String? email;
  final String? phoneNumber;
  final String workspaceId;

  const OrderInvestor({
    required this.id,
    required this.fullName,
    this.email,
    this.phoneNumber,
    required this.workspaceId,
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

  /// Search mutual funds by name or code.
  Future<List<Map<String, dynamic>>> searchMutualFunds(String query);

  /// Fetch currently held schemes for the investor's portfolio in a specific workspace.
  Future<List<Map<String, dynamic>>> fetchHoldings(
      String investorProfileId, String workspaceId);

  /// Resolves the active workspace membership/portfolio details for the investor
  Future<OrderContext> resolveInvestorContext({
    required String investorProfileId,
    required String initiatorProfileId,
    required String initiationRole,
    required String initiationChannel,
  });
}
