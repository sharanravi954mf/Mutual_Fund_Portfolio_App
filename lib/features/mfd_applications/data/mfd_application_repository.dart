import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/mfd_application.dart';

abstract class MfdApplicationRepository {
  Future<bool> canApply();
  Future<List<MfdApplication>> list({bool review = false, int offset = 0});
  Future<MfdApplication> load(String id);
  Future<List<MfdApplicationEvent>> events(String id);
  Future<MfdApplication> mutate(MfdRequest request);
}

class SupabaseMfdApplicationRepository implements MfdApplicationRepository {
  SupabaseMfdApplicationRepository(this.client);
  final SupabaseClient client;
  @override
  Future<bool> canApply() async =>
      (await client.rpc('get_my_mfd_application_context'))['can_apply'] == true;
  @override
  Future<List<MfdApplication>> list(
      {bool review = false, int offset = 0}) async {
    var query = client.from('mfd_applications').select();
    if (!review) {
      query = query.eq('applicant_user_id', client.auth.currentUser!.id);
    }
    final rows = await query
        .order('submitted_at', ascending: false)
        .order('id')
        .range(offset, offset + 49);
    return rows.map(MfdApplication.fromJson).toList();
  }

  @override
  Future<MfdApplication> load(String id) async => MfdApplication.fromJson(
      await client.from('mfd_applications').select().eq('id', id).single());
  @override
  Future<List<MfdApplicationEvent>> events(String id) async => (await client
          .from('mfd_application_events')
          .select('event_type,occurred_at')
          .eq('application_id', id)
          .order('new_version'))
      .map(MfdApplicationEvent.fromJson)
      .toList();
  @override
  Future<MfdApplication> mutate(MfdRequest request) async {
    final Map<String, dynamic> params = {'p_request_id': request.requestId};
    final String rpc;
    if (request.operation == MfdOperation.submit) {
      rpc = 'submit_mfd_application';
      params.addAll({
        'p_business_name': request.businessName,
        'p_claimed_arn': request.claimedArn,
        'p_applicant_note': request.note
      });
    } else {
      params.addAll({
        'p_application_id': request.applicationId,
        'p_expected_version': request.expectedVersion
      });
      switch (request.operation) {
        case MfdOperation.startReview:
          rpc = 'start_mfd_application_review';
        case MfdOperation.approve:
          rpc = 'approve_mfd_application';
          params['p_evidence'] = request.note;
        case MfdOperation.reject:
          rpc = 'reject_mfd_application';
          params['p_reason'] = request.note;
        case MfdOperation.submit:
          throw StateError('Unreachable operation');
      }
    }
    final row = await client.rpc(rpc, params: params);
    return MfdApplication.fromJson(Map<String, dynamic>.from(row as Map));
  }
}

/// Never display raw transport/database details, even for an unknown failure.
String mfdErrorMessage(Object error) {
  if (error is MfdFailure) return error.message;
  final code = error is PostgrestException ? error.message : '';
  return switch (code) {
    'platform_admin_step_up_required' =>
      'MFA verification is required before approving or rejecting an MFD application.',
    'platform_capability_required' ||
    'mfd_authentication_required' =>
      'Your permission is unavailable. Refresh your account access.',
    'mfd_applicant_ineligible' =>
      'This account is no longer eligible. V1 supports Explorers without an existing business identity.',
    'mfd_application_open' =>
      'An application is already open. Refresh to see its status.',
    'mfd_application_changed' =>
      'This application has changed. Refresh before taking another action.',
    'mfd_application_decided' =>
      'This application has already been decided. Refresh to see the result.',
    'mfd_request_conflict' =>
      'This request conflicts with an earlier action. Refresh to check the recorded result.',
    'mfd_decision_note_required' =>
      'Enter a review evidence reference or rejection reason.',
    'mfd_invalid_input' => 'Check the required fields and text lengths.',
    'mfd_application_unavailable' => 'This application is unavailable.',
    _ =>
      'The result could not be confirmed. Retry safely with the same request, or refresh to check the status.',
  };
}
