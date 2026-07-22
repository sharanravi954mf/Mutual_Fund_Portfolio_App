import '../application/folio_verification_service.dart';
import '../models/folio_verification_models.dart';

sealed class FolioVerificationState { const FolioVerificationState(); }
class FolioVerificationIdle extends FolioVerificationState { const FolioVerificationIdle(); }
class FolioVerificationLoading extends FolioVerificationState { const FolioVerificationLoading({this.previous}); final FolioVerificationState? previous; }
class FolioVerificationReady extends FolioVerificationState { const FolioVerificationReady({this.requests=const [],this.selectedRequest,this.message}); final List<FolioVerificationRequest> requests; final FolioVerificationRequest? selectedRequest; final String? message; }
class FolioVerificationFailureState extends FolioVerificationState { const FolioVerificationFailureState(this.failure,{this.previous}); final FolioVerificationApplicationFailure failure; final FolioVerificationState? previous; }
