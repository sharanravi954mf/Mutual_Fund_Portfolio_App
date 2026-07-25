import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/user_profile.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/workspace.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/workspace_membership.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/workspace_invitation.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/advisor_investor_assignment.dart';

void main() {
  group('Workspace Model Tests', () {
    test('Workspace status database value mapping', () {
      for (final status in WorkspaceStatus.values) {
        expect(WorkspaceStatus.fromDatabase(status.databaseValue), status);
      }
    });

    test('Workspace fromJson and toJson parsing', () {
      final json = {
        'id': 'workspace-uuid',
        'name': 'Test Workspace',
        'slug': 'test-workspace',
        'owner_profile_id': 'owner-profile-uuid',
        'workspace_status': 'active',
        'created_at': '2026-07-25T12:00:00.000Z',
        'updated_at': '2026-07-25T12:00:00.000Z',
      };

      final workspace = Workspace.fromJson(json);

      expect(workspace.id, 'workspace-uuid');
      expect(workspace.name, 'Test Workspace');
      expect(workspace.slug, 'test-workspace');
      expect(workspace.ownerProfileId, 'owner-profile-uuid');
      expect(workspace.workspaceStatus, WorkspaceStatus.active);
      expect(workspace.isActive, isTrue);
      expect(workspace.isSuspended, isFalse);

      final backToJson = workspace.toJson();
      expect(backToJson['id'], 'workspace-uuid');
      expect(backToJson['workspace_status'], 'active');
    });
  });

  group('WorkspaceMembership Model Tests', () {
    test('WorkspaceRole and MembershipStatus mapping', () {
      for (final role in WorkspaceRole.values) {
        expect(WorkspaceRole.fromDatabase(role.databaseValue), role);
      }
      for (final status in MembershipStatus.values) {
        expect(MembershipStatus.fromDatabase(status.databaseValue), status);
      }
    });

    test('WorkspaceMembership parsing', () {
      final json = {
        'id': 'membership-uuid',
        'workspace_id': 'workspace-uuid',
        'profile_id': 'profile-uuid',
        'role': 'admin',
        'status': 'active',
        'joined_at': '2026-07-25T12:00:00.000Z',
        'ended_at': null,
        'invited_by': 'inviter-uuid',
        'created_at': '2026-07-25T12:00:00.000Z',
        'updated_at': '2026-07-25T12:00:00.000Z',
      };

      final membership = WorkspaceMembership.fromJson(json);

      expect(membership.id, 'membership-uuid');
      expect(membership.workspaceId, 'workspace-uuid');
      expect(membership.role, WorkspaceRole.admin);
      expect(membership.status, MembershipStatus.active);
      expect(membership.isActive, isTrue);
      expect(membership.endedAt, isNull);
    });
  });

  group('WorkspaceInvitation Model Tests', () {
    test('InvitationStatus mapping', () {
      for (final status in InvitationStatus.values) {
        expect(InvitationStatus.fromDatabase(status.databaseValue), status);
      }
    });

    test('WorkspaceInvitation parsing', () {
      final json = {
        'id': 'invite-uuid',
        'workspace_id': 'workspace-uuid',
        'email': 'invitee@sharanfincorp.test',
        'role': 'investor',
        'invited_by': 'inviter-uuid',
        'token_hash': 'sha256-hash-value',
        'status': 'pending',
        'expires_at': '2026-07-26T12:00:00.000Z',
        'created_at': '2026-07-25T12:00:00.000Z',
        'updated_at': '2026-07-25T12:00:00.000Z',
      };

      final invite = WorkspaceInvitation.fromJson(json);

      expect(invite.id, 'invite-uuid');
      expect(invite.email, 'invitee@sharanfincorp.test');
      expect(invite.role, WorkspaceRole.investor);
      expect(invite.status, InvitationStatus.pending);
      expect(invite.isPending, isTrue);
      expect(invite.isExpired, isFalse);
    });
  });

  group('AdvisorInvestorAssignment Model Tests', () {
    test('AssignmentStatus mapping', () {
      for (final status in AssignmentStatus.values) {
        expect(AssignmentStatus.fromDatabase(status.databaseValue), status);
      }
    });

    test('AdvisorInvestorAssignment parsing', () {
      final json = {
        'id': 'assignment-uuid',
        'advisor_id': 'advisor-uuid',
        'investor_id': 'investor-uuid',
        'assigned_by': 'assigner-uuid',
        'assigned_at': '2026-07-25T12:00:00.000Z',
        'ended_by': null,
        'ended_at': null,
        'status': 'active',
        'created_at': '2026-07-25T12:00:00.000Z',
        'updated_at': '2026-07-25T12:00:00.000Z',
      };

      final assignment = AdvisorInvestorAssignment.fromJson(json);

      expect(assignment.id, 'assignment-uuid');
      expect(assignment.advisorId, 'advisor-uuid');
      expect(assignment.investorId, 'investor-uuid');
      expect(assignment.status, AssignmentStatus.active);
      expect(assignment.isActive, isTrue);
      expect(assignment.endedAt, isNull);
    });
  });

  group('UserProfile Compatibility and platformAdmin Authorization Tests', () {
    test('Supports new platform_admin role mapping', () {
      expect(UserRole.fromDatabase('platform_admin'), UserRole.platformAdmin);
      expect(UserRole.platformAdmin.databaseValue, 'platform_admin');
    });

    test('UserProfile routing and authorization checks', () {
      final json = {
        'id': 'platform-admin-uuid',
        'role': 'platform_admin',
        'account_status': 'active',
        'full_name': 'Platform Admin Owner',
        'phone_number': null,
        'email': 'admin@platform.moneyball',
        'created_at': '2026-07-25T12:00:00.000Z',
        'updated_at': '2026-07-25T12:00:00.000Z',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.role, UserRole.platformAdmin);
      expect(profile.isActive, isTrue);
      expect(profile.isAuthorizedForAdvisorDashboard, isTrue);
      expect(profile.isAuthorizedForInvestorDashboard, isFalse);
    });
  });
}
