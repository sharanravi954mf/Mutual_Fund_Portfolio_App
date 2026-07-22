import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/folio_verification_service.dart';
import '../data/supabase_folio_verification_datasource.dart';
import '../data/supabase_folio_verification_repository.dart';
import 'folio_verification_controller.dart';
import 'pages/folio_verification_page.dart';

typedef FolioVerificationRouteFactory = Route<void> Function(
  BuildContext context,
);

Route<void> buildFolioVerificationRoute(BuildContext context) {
  final datasource = SupabaseFolioVerificationDatasource(
    Supabase.instance.client,
  );
  final repository = SupabaseFolioVerificationRepository(datasource);
  return MaterialPageRoute(
    builder: (_) => ChangeNotifierProvider(
      create: (_) => FolioVerificationController(
        FolioVerificationService(repository, repository),
      ),
      child: const FolioVerificationPage(),
    ),
  );
}
