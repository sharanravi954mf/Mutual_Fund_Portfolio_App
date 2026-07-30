import '../domain/order_models.dart';

class OrderFolio {
  final String normalizedFolioNumber;
  final String sourceFolioMasked;
  final String registrar;

  const OrderFolio({
    required this.normalizedFolioNumber,
    required this.sourceFolioMasked,
    required this.registrar,
  });
}

class OrderInvestor {
  final String id;
  final String fullName;
  final String? email;
  final String? phoneNumber;

  const OrderInvestor({
    required this.id,
    required this.fullName,
    this.email,
    this.phoneNumber,
  });
}

abstract class OrderRepository {
  /// Submit the order draft to the database. Returns the generated order ID.
  Future<String> submitOrder(
    OrderDraft draft, {
    required String initiatedByProfileId,
    required String initiatedByRole,
    required String initiationChannel,
  });

  /// Fetch active folios for the investor.
  Future<List<OrderFolio>> fetchFolios(String investorProfileId);

  /// Fetch actively assigned investors for the advisor.
  Future<List<OrderInvestor>> fetchAssignedInvestors(String advisorProfileId);

  /// Fetch all available mutual funds.
  Future<List<Map<String, dynamic>>> fetchMutualFunds();
}
