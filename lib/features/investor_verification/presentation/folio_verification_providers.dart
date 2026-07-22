import 'package:provider/provider.dart';
import '../application/folio_verification_service.dart';
import 'folio_verification_controller.dart';

class FolioVerificationProviders {
  const FolioVerificationProviders._();
  static ChangeNotifierProvider<FolioVerificationController> controller({required FolioVerificationService service}) => ChangeNotifierProvider(create: (_) => FolioVerificationController(service));
}
