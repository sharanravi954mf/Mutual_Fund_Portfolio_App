import '../domain/nse_models.dart';

abstract class NseReadRepository {
  Future<NsePage<NseTarget>> targets({String? after});
  Future<NseReadContext> context(String target);
  Future<NseAcceptance> submit(
      String target, String requestId, NseReadCommand command);
  Future<NseOperation> operation({String? operationId, String? requestId});
  Future<NsePage<NseOperation>> history(String target, {Object? cursor});
  Future<NsePage<NseCandidate>> candidates(
      String target, NseReadKind kind, String source,
      {int after = -1});
}
