import '../data/identity_repository.dart';
import '../models/identity_bootstrap_result.dart';

class IdentityBootstrapService {
  const IdentityBootstrapService(this._repository);

  final IdentityRepository _repository;

  Future<IdentityBootstrapResult> load() => _repository.bootstrap();
}
