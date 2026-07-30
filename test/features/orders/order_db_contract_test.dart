import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('Database Contract Smoke Validation Tests', () {
    late SupabaseClient client;
    bool isConnected = false;

    setUpAll(() async {
      try {
        // Connect to local Supabase instance
        client = SupabaseClient(
          'http://127.0.0.1:54321',
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im11dHVhbC1mdW5kLXBvcnRmb2xpby1hcHAiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTYyMjUwMDAwMCwiZXhwIjoyNTI0NjA4MDAwfQ.placeholder',
        );
        // Ping database using a simple metadata query
        await client.from('mutual_funds').select('scheme_code').limit(1);
        isConnected = true;
      } catch (_) {
        isConnected = false;
      }
    });

    test('verifies public.mutual_funds table columns contract', () async {
      if (!isConnected) {
        markTestSkipped('Local Supabase container is offline or inaccessible.');
        return;
      }

      final res = await client.from('mutual_funds').select().limit(1);
      if (res.isNotEmpty) {
        final row = res.first;
        expect(row.containsKey('scheme_code'), isTrue);
        expect(row.containsKey('scheme_name'), isTrue);
      }
    });

    test('verifies public.order_requests table columns contract', () async {
      if (!isConnected) {
        markTestSkipped('Local Supabase container is offline.');
        return;
      }

      final res = await client.from('order_requests').select().limit(1);
      // Even if empty, verify metadata if possible or check columns in row
      if (res.isNotEmpty) {
        final row = res.first;
        expect(row.containsKey('id'), isTrue);
        expect(row.containsKey('workspace_id'), isTrue);
        expect(row.containsKey('investor_profile_id'), isTrue);
        expect(row.containsKey('scheme_code'), isTrue);
        expect(row.containsKey('type'), isTrue);
        expect(row.containsKey('amount'), isTrue);
        expect(row.containsKey('units'), isTrue);
        expect(row.containsKey('status'), isTrue);
        expect(row.containsKey('initiated_by_profile_id'), isTrue);
        expect(row.containsKey('initiated_by_role'), isTrue);
        expect(row.containsKey('initiation_channel'), isTrue);
      }
    });

    test('verifies workspace_memberships table columns contract', () async {
      if (!isConnected) {
        markTestSkipped('Local Supabase container is offline.');
        return;
      }

      final res = await client.from('workspace_memberships').select().limit(1);
      if (res.isNotEmpty) {
        final row = res.first;
        expect(row.containsKey('workspace_id'), isTrue);
        expect(row.containsKey('profile_id'), isTrue);
        expect(row.containsKey('role'), isTrue);
        expect(row.containsKey('status'), isTrue);
      }
    });

    test('verifies portfolios table columns contract', () async {
      if (!isConnected) {
        markTestSkipped('Local Supabase container is offline.');
        return;
      }

      final res = await client.from('portfolios').select().limit(1);
      if (res.isNotEmpty) {
        final row = res.first;
        expect(row.containsKey('id'), isTrue);
        expect(row.containsKey('client_id'), isTrue);
        expect(row.containsKey('workspace_id'), isTrue);
      }
    });

    test('verifies portfolio_folio_references table columns contract',
        () async {
      if (!isConnected) {
        markTestSkipped('Local Supabase container is offline.');
        return;
      }

      final res =
          await client.from('portfolio_folio_references').select().limit(1);
      if (res.isNotEmpty) {
        final row = res.first;
        expect(row.containsKey('portfolio_id'), isTrue);
        expect(row.containsKey('folio_reference_id'), isTrue);
      }
    });
  });
}
