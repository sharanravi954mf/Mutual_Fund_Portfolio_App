import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/application/folio_verification_service.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/data/folio_verification_repository.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/folio_verification_models.dart';

void main(){
  test('forwards correlation ID and records successful workflow',() async { final repo=_FakeRepository(); final log=_Log(); final service=FolioVerificationService(repo,repo,logSink:log); await service.submit(const SubmitFolioVerificationCommand(token:FolioSubmissionToken('opaque'),relationship:FolioHolderRelationship.soleHolder,correlationId:'cmd-1')); expect(repo.correlation,'cmd-1'); expect(log.success,['submit:cmd-1']); });
  test('maps repository failures and logs safe application failure',() async { final repo=_FakeRepository(failure:const FolioVerificationFailure(FolioVerificationFailureCode.staleVersion)); final log=_Log(); final service=FolioVerificationService(repo,repo,logSink:log); expect(()=>service.beginReview(const FolioVerificationDecisionCommand(requestId:'request',expectedVersion:1,correlationId:'cmd-2')),throwsA(isA<FolioVerificationApplicationFailure>().having((f)=>f.code,'code',FolioVerificationApplicationFailureCode.staleVersion))); await Future<void>.delayed(Duration.zero); expect(log.failure,['beginReview:cmd-2']); });
  test('requires structured reasons before repository invocation',() async { final repo=_FakeRepository(); final service=FolioVerificationService(repo,repo); expect(()=>service.approve(const FolioVerificationDecisionCommand(requestId:'request',expectedVersion:1,correlationId:'cmd-3')),throwsA(isA<FolioVerificationApplicationFailure>())); expect(repo.calls,0); });
  test('logging failure does not change a successful workflow result', () async {
    final service=FolioVerificationService(_FakeRepository(),_FakeRepository(),logSink:_ThrowingLog());
    final result=await service.submit(const SubmitFolioVerificationCommand(token:FolioSubmissionToken('opaque'),relationship:FolioHolderRelationship.soleHolder,correlationId:'cmd-success'));
    expect(result.id,'request');
  });
  test('logging failure does not replace a typed application failure', () async {
    final repo=_FakeRepository(failure:const FolioVerificationFailure(FolioVerificationFailureCode.staleVersion));
    final service=FolioVerificationService(repo,repo,logSink:_ThrowingLog());
    expect(() => service.beginReview(const FolioVerificationDecisionCommand(requestId:'request',expectedVersion:1,correlationId:'cmd-failure')),throwsA(isA<FolioVerificationApplicationFailure>().having((f)=>f.code,'code',FolioVerificationApplicationFailureCode.staleVersion)));
  });
  test('invalid decision commands never invoke repositories', () async {
    final repo=_FakeRepository(); final service=FolioVerificationService(repo,repo);
    expect(() => service.requestMoreInformation(const FolioVerificationDecisionCommand(requestId:'request',expectedVersion:1,correlationId:'cmd-invalid',reasonCode:'  ')),throwsA(isA<FolioVerificationApplicationFailure>()));
    expect(repo.calls,0);
  });
  test('forwards each write correlation ID exactly once', () async {
    final repo=_FakeRepository(); final service=FolioVerificationService(repo,repo);
    await service.submit(const SubmitFolioVerificationCommand(token:FolioSubmissionToken('opaque'),relationship:FolioHolderRelationship.soleHolder,correlationId:'submit'));
    await service.resubmit(const FolioVerificationDecisionCommand(requestId:'request',expectedVersion:1,correlationId:'resubmit'));
    await service.cancel(const FolioVerificationDecisionCommand(requestId:'request',expectedVersion:1,correlationId:'cancel'));
    await service.beginReview(const FolioVerificationDecisionCommand(requestId:'request',expectedVersion:1,correlationId:'review'));
    await service.requestMoreInformation(const FolioVerificationDecisionCommand(requestId:'request',expectedVersion:1,correlationId:'more',reasonCode:'INFO'));
    await service.approve(const FolioVerificationDecisionCommand(requestId:'request',expectedVersion:1,correlationId:'approve',reasonCode:'SOLE_HOLDER_CONFIRMED'));
    await service.reject(const FolioVerificationDecisionCommand(requestId:'request',expectedVersion:1,correlationId:'reject',reasonCode:'INSUFFICIENT_EVIDENCE'));
    await service.revokeGrant(const RevokeFolioGrantCommand(grantId:'grant',expectedVersion:1,reasonCode:'APPROVED_IN_ERROR',correlationId:'revoke'));
    expect(repo.correlations,['submit','resubmit','cancel','review','more','approve','reject','revoke']);
  });
}
class _Log implements FolioVerificationLogSink { final success=<String>[]; final failure=<String>[]; @override void operationSucceeded(String op,String id)=>success.add('$op:$id'); @override void operationFailed(String op,String id,FolioVerificationApplicationFailure error)=>failure.add('$op:$id'); }
class _ThrowingLog implements FolioVerificationLogSink { @override void operationSucceeded(String op,String id)=>throw StateError('logging'); @override void operationFailed(String op,String id,FolioVerificationApplicationFailure error)=>throw StateError('logging'); }
class _FakeRepository implements InvestorFolioVerificationRepository,AdvisorFolioVerificationRepository { _FakeRepository({this.failure}); final Object? failure; String? correlation; final correlations=<String>[]; int calls=0; Future<T> _run<T>(T value,[String? id]) async { calls++; correlation=id??correlation; if(id!=null) correlations.add(id); if(failure!=null) throw failure!; return value; } final request=const FolioVerificationRequest(id:'request',status:FolioVerificationStatus.pendingAdvisorReview,version:1);
  @override Future<FolioVerificationRequest> submit(FolioSubmissionToken t,FolioHolderRelationship r,String id)=>_run(request,id); @override Future<FolioVerificationRequest> resubmit(String id,int v,String c)=>_run(request,c); @override Future<FolioVerificationRequest> cancel(String id,int v,String c)=>_run(request,c); @override Future<FolioVerificationPage<FolioVerificationRequest>> getMyRequests({int page=0,int pageSize=25})=>_run(FolioVerificationPage(items:[request],page:page,pageSize:pageSize)); @override Future<FolioVerificationRequest> getRequestDetail(String id)=>_run(request); @override Future<FolioVerificationPage<FolioVerificationEvent>> getHistory(String id,{int page=0,int pageSize=25})=>_run(FolioVerificationPage(items:const [],page:page,pageSize:pageSize));
  @override Future<FolioVerificationRequest> beginReview(String id,int v,String c)=>_run(request,c); @override Future<FolioVerificationRequest> requestMoreInformation(String id,int v,String r,String c)=>_run(request,c); @override Future<FolioVerificationRequest> approve(String id,int v,String r,String c)=>_run(request,c); @override Future<FolioVerificationRequest> reject(String id,int v,String r,String c)=>_run(request,c); @override Future<void> revokeGrant(String id,int v,String r,String c)=>_run(null,c); @override Future<FolioVerificationPage<FolioVerificationRequest>> getAdvisorQueue(FolioQueueFilter f)=>_run(FolioVerificationPage(items:const [],page:f.page,pageSize:f.pageSize)); @override Future<FolioGrantSummary?> getGrantSummary(String id)=>_run(null);
}
