import 'package:supabase_flutter/supabase_flutter.dart';
import 'folio_verification_datasource.dart';
class SupabaseFolioVerificationDatasource implements FolioVerificationDatasource { SupabaseFolioVerificationDatasource(this._client); final SupabaseClient _client; @override Future<dynamic> rpc(String function,{Map<String,dynamic>? params})=>_client.rpc(function,params:params); }
