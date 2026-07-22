import 'package:flutter/foundation.dart';
import '../application/folio_verification_service.dart';
import '../models/folio_verification_models.dart';
import 'folio_verification_state.dart';

class FolioVerificationController extends ChangeNotifier {
  FolioVerificationController(this._service);
  final FolioVerificationService _service;
  FolioVerificationState _state=const FolioVerificationIdle();
  Future<void> Function()? _retry;
  bool _submitting=false;
  FolioVerificationState get state=>_state;
  bool get isSubmitting=>_submitting;
  Future<void> refresh() => _execute(() async { final page=await _service.getMyRequests(); _state=FolioVerificationReady(requests:List.unmodifiable(page.items)); },retry:refresh);
  Future<void> submit(SubmitFolioVerificationCommand command) async { if(_submitting) return; _submitting=true; await _execute(() async { final request=await _service.submit(command); _state=FolioVerificationReady(selectedRequest:request,message:'submitted'); },retry:()=>submit(command)); _submitting=false; }
  Future<void> cancel(FolioVerificationDecisionCommand command)=>_execute(() async { final request=await _service.cancel(command); _state=FolioVerificationReady(selectedRequest:request,message:'cancelled'); },retry:()=>cancel(command));
  Future<void> retry() async { final action=_retry; if(action!=null) await action(); }
  Future<void> _execute(Future<void> Function() action,{required Future<void> Function() retry}) async { final previous=_state; _state=FolioVerificationLoading(previous:previous); notifyListeners(); try { await action(); _retry=null; } on FolioVerificationApplicationFailure catch(failure) { _retry=retry; _state=FolioVerificationFailureState(failure,previous:previous); } finally { notifyListeners(); } }
}
