import '../domain/qualification_queue_models.dart';

abstract class QualificationQueueSubscription {
  Future<void> cancel();
}

class NoopQualificationQueueSubscription
    implements QualificationQueueSubscription {
  const NoopQualificationQueueSubscription();

  @override
  Future<void> cancel() async {}
}

abstract class QualificationQueueRepository {
  Duration get fallbackRefreshInterval;

  Future<QualificationQueueSnapshot> fetchQueue({
    required String reviewerProfileId,
  });

  Future<void> qualifyOrder({
    required String orderId,
    required QualificationDecision decision,
    String? rejectionReason,
  });

  QualificationQueueSubscription subscribeToOrderChanges(
    void Function() onChanged,
  );
}
