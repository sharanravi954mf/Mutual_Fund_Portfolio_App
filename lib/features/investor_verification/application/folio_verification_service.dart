import '../data/folio_verification_repository.dart';
import '../models/folio_verification_models.dart';

abstract class FolioVerificationLogSink {
  void operationSucceeded(String operation, String correlationId);
  void operationFailed(String operation, String correlationId, FolioVerificationApplicationFailure failure);
}

class NoopFolioVerificationLogSink implements FolioVerificationLogSink {
  const NoopFolioVerificationLogSink();
  @override void operationFailed(String operation, String correlationId, FolioVerificationApplicationFailure failure) {}
  @override void operationSucceeded(String operation, String correlationId) {}
}

enum FolioVerificationApplicationFailureCode { unauthenticated, permissionDenied, unavailable, invalidTransition, staleVersion, duplicate, tokenInvalidOrExpired, evidenceChanged, unsupportedRelationship, validation, timeout, temporary, unexpected }
class FolioVerificationApplicationFailure implements Exception { const FolioVerificationApplicationFailure(this.code); final FolioVerificationApplicationFailureCode code; }

class SubmitFolioVerificationCommand { const SubmitFolioVerificationCommand({required this.token,required this.relationship,required this.correlationId}); final FolioSubmissionToken token; final FolioHolderRelationship relationship; final String correlationId; }
class FolioVerificationDecisionCommand { const FolioVerificationDecisionCommand({required this.requestId,required this.expectedVersion,required this.correlationId,this.reasonCode}); final String requestId,correlationId; final int expectedVersion; final String? reasonCode; }
class RevokeFolioGrantCommand { const RevokeFolioGrantCommand({required this.grantId,required this.expectedVersion,required this.reasonCode,required this.correlationId}); final String grantId,reasonCode,correlationId; final int expectedVersion; }

class FolioVerificationService {
  FolioVerificationService(this._investorRepository,this._advisorRepository,{FolioVerificationLogSink logSink=const NoopFolioVerificationLogSink()}):_logSink=logSink;
  final InvestorFolioVerificationRepository _investorRepository; final AdvisorFolioVerificationRepository _advisorRepository; final FolioVerificationLogSink _logSink;
  Future<FolioVerificationRequest> submit(SubmitFolioVerificationCommand command)=>_run('submit',command.correlationId,()=>_investorRepository.submit(command.token,command.relationship,command.correlationId));
  Future<FolioVerificationRequest> resubmit(FolioVerificationDecisionCommand command)=>_run('resubmit',command.correlationId,()=>_investorRepository.resubmit(command.requestId,command.expectedVersion,command.correlationId));
  Future<FolioVerificationRequest> cancel(FolioVerificationDecisionCommand command)=>_run('cancel',command.correlationId,()=>_investorRepository.cancel(command.requestId,command.expectedVersion,command.correlationId));
  Future<FolioVerificationRequest> beginReview(FolioVerificationDecisionCommand command)=>_run('beginReview',command.correlationId,()=>_advisorRepository.beginReview(command.requestId,command.expectedVersion,command.correlationId));
  Future<FolioVerificationRequest> requestMoreInformation(FolioVerificationDecisionCommand command)=>_run('requestMoreInformation',command.correlationId,()=>_advisorRepository.requestMoreInformation(command.requestId,command.expectedVersion,_reason(command),command.correlationId));
  Future<FolioVerificationRequest> approve(FolioVerificationDecisionCommand command)=>_run('approve',command.correlationId,()=>_advisorRepository.approve(command.requestId,command.expectedVersion,_reason(command),command.correlationId));
  Future<FolioVerificationRequest> reject(FolioVerificationDecisionCommand command)=>_run('reject',command.correlationId,()=>_advisorRepository.reject(command.requestId,command.expectedVersion,_reason(command),command.correlationId));
  Future<void> revokeGrant(RevokeFolioGrantCommand command)=>_run('revokeGrant',command.correlationId,()=>_advisorRepository.revokeGrant(command.grantId,command.expectedVersion,command.reasonCode,command.correlationId));
  Future<FolioVerificationPage<FolioVerificationRequest>> getMyRequests({int page=0,int pageSize=25})=>_read(()=>_investorRepository.getMyRequests(page:page,pageSize:pageSize));
  Future<FolioVerificationRequest> getRequestDetail(String requestId)=>_read(()=>_investorRepository.getRequestDetail(requestId));
  Future<FolioVerificationPage<FolioVerificationEvent>> getHistory(String requestId,{int page=0,int pageSize=25})=>_read(()=>_investorRepository.getHistory(requestId,page:page,pageSize:pageSize));
  Future<FolioVerificationPage<FolioVerificationRequest>> getAdvisorQueue(FolioQueueFilter filter)=>_read(()=>_advisorRepository.getAdvisorQueue(filter));
  Future<FolioGrantSummary?> getGrantSummary(String requestId)=>_read(()=>_advisorRepository.getGrantSummary(requestId));
  String _reason(FolioVerificationDecisionCommand command) { final value=command.reasonCode?.trim(); if(value==null||value.isEmpty) throw const FolioVerificationApplicationFailure(FolioVerificationApplicationFailureCode.validation); return value; }
  Future<T> _run<T>(String operation,String correlationId,Future<T> Function() action) async { try { final result=await action(); _logSuccess(operation,correlationId); return result; } catch(error) { final failure=_map(error); _logFailure(operation,correlationId,failure); throw failure; } }
  void _logSuccess(String operation,String correlationId) { try { _logSink.operationSucceeded(operation,correlationId); } catch (_) {} }
  void _logFailure(String operation,String correlationId,FolioVerificationApplicationFailure failure) { try { _logSink.operationFailed(operation,correlationId,failure); } catch (_) {} }
  Future<T> _read<T>(Future<T> Function() action) async { try{return await action();} catch(error){throw _map(error);} }
  FolioVerificationApplicationFailure _map(Object error) { if(error is FolioVerificationApplicationFailure) return error; if(error is FolioVerificationFailure) return FolioVerificationApplicationFailure(switch(error.code){ FolioVerificationFailureCode.unauthenticated=>FolioVerificationApplicationFailureCode.unauthenticated,FolioVerificationFailureCode.permissionDenied=>FolioVerificationApplicationFailureCode.permissionDenied,FolioVerificationFailureCode.requestUnavailable=>FolioVerificationApplicationFailureCode.unavailable,FolioVerificationFailureCode.invalidTransition=>FolioVerificationApplicationFailureCode.invalidTransition,FolioVerificationFailureCode.staleVersion=>FolioVerificationApplicationFailureCode.staleVersion,FolioVerificationFailureCode.duplicateRequest||FolioVerificationFailureCode.duplicateGrant=>FolioVerificationApplicationFailureCode.duplicate,FolioVerificationFailureCode.tokenInvalidOrExpired=>FolioVerificationApplicationFailureCode.tokenInvalidOrExpired,FolioVerificationFailureCode.evidenceChanged=>FolioVerificationApplicationFailureCode.evidenceChanged,FolioVerificationFailureCode.unsupportedRelationship=>FolioVerificationApplicationFailureCode.unsupportedRelationship,FolioVerificationFailureCode.validationFailed=>FolioVerificationApplicationFailureCode.validation,FolioVerificationFailureCode.timeout=>FolioVerificationApplicationFailureCode.timeout,FolioVerificationFailureCode.temporaryFailure=>FolioVerificationApplicationFailureCode.temporary,FolioVerificationFailureCode.unexpected=>FolioVerificationApplicationFailureCode.unexpected}); return const FolioVerificationApplicationFailure(FolioVerificationApplicationFailureCode.unexpected); }
}
