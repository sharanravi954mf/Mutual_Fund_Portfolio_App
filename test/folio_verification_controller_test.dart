import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/application/folio_verification_service.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/folio_verification_models.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/folio_verification_controller.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/folio_verification_state.dart';
import 'support/folio_verification_fakes.dart';
void main(){
 FolioVerificationController controller(FolioTestRepository r)=>FolioVerificationController(FolioVerificationService(r,r));
 test('starts idle and refresh reaches ready once',() async {final r=FolioTestRepository();final c=controller(r);expect(c.state,isA<FolioVerificationIdle>());await c.refresh();expect(c.state,isA<FolioVerificationReady>());expect(r.refreshCalls,1);});
 test('submit transitions ready and forwards correlation once',() async {final r=FolioTestRepository();final c=controller(r);await c.submit(const SubmitFolioVerificationCommand(token:FolioSubmissionToken('opaque'),relationship:FolioHolderRelationship.soleHolder,correlationId:'corr'));expect(c.state,isA<FolioVerificationReady>());expect(r.submitCalls,1);expect(r.correlation,'corr');});
 test('failure is typed and retry reruns operation',() async {final r=FolioTestRepository()..error=const FolioVerificationFailure(FolioVerificationFailureCode.staleVersion);final c=controller(r);await c.refresh();expect(c.state,isA<FolioVerificationFailureState>());r.error=null;await c.retry();expect(c.state,isA<FolioVerificationReady>());expect(r.refreshCalls,2);});
 test('cancel invokes service once',() async {final r=FolioTestRepository();final c=controller(r);await c.cancel(const FolioVerificationDecisionCommand(requestId:'request',expectedVersion:1,correlationId:'cancel'));expect(r.cancelCalls,1);});
}
