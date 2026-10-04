import 'dart:math';

class MfdApplication {
  const MfdApplication(
      {required this.id,
      required this.businessName,
      required this.claimedArn,
      required this.email,
      required this.status,
      required this.version,
      required this.submittedAt,
      this.applicantNote,
      this.decisionNote,
      this.approvedArn});
  final String id, businessName, claimedArn, email, status;
  final int version;
  final DateTime submittedAt;
  final String? applicantNote, decisionNote, approvedArn;
  bool get isTerminal => status == 'approved' || status == 'rejected';
  String get statusLabel => switch (status) {
        'submitted' => 'Submitted',
        'under_review' => 'Under review',
        'approved' => 'Approved',
        'rejected' => 'Rejected',
        _ => 'Unavailable',
      };
  factory MfdApplication.fromJson(Map<String, dynamic> row) => MfdApplication(
        id: row['id'] as String,
        businessName: row['business_name'] as String,
        claimedArn: row['claimed_arn'] as String,
        email: row['applicant_email'] as String,
        status: row['status'] as String,
        version: row['version'] as int,
        submittedAt: DateTime.parse(row['submitted_at'] as String),
        applicantNote: row['applicant_note'] as String?,
        decisionNote: row['decision_note'] as String?,
        approvedArn: row['approved_arn'] as String?,
      );
}

class MfdApplicationEvent {
  const MfdApplicationEvent(this.type, this.occurredAt);
  final String type;
  final DateTime occurredAt;
  String get label => switch (type) {
        'submitted' => 'Submitted',
        'review_started' => 'Review started',
        'approved' => 'Approved',
        'rejected' => 'Rejected',
        _ => 'Application updated',
      };
  factory MfdApplicationEvent.fromJson(Map<String, dynamic> row) =>
      MfdApplicationEvent(row['event_type'] as String,
          DateTime.parse(row['occurred_at'] as String));
}

enum MfdOperation { submit, startReview, approve, reject }

/// Frozen on first attempt. A retry sends this same request, including version.
class MfdRequest {
  const MfdRequest(
      {required this.operation,
      required this.requestId,
      this.applicationId,
      this.expectedVersion,
      this.businessName,
      this.claimedArn,
      this.note});
  final MfdOperation operation;
  final String requestId;
  final String? applicationId, businessName, claimedArn, note;
  final int? expectedVersion;
}

String newMfdRequestId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class MfdFailure implements Exception {
  const MfdFailure(this.message);
  final String message;
}
