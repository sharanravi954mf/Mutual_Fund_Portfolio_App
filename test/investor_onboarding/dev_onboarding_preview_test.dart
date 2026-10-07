import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_onboarding/data/onboarding_kyc_repository.dart';
import 'package:mutual_fund_portfolio_app/features/investor_onboarding/presentation/dev_onboarding_preview_gate.dart';
import 'package:mutual_fund_portfolio_app/features/investor_onboarding/presentation/dev_onboarding_preview_page.dart';
import 'package:mutual_fund_portfolio_app/features/investor_onboarding/presentation/onboarding_kyc_controller.dart';
import 'package:mutual_fund_portfolio_app/features/investor_onboarding/presentation/onboarding_kyc_page.dart';
import 'onboarding_kyc_test.dart' show KycRepository;
import 'onboarding_test.dart' show FakeRepository;

class MarkerKycRepository extends KycRepository {
  @override
  Future<KycCase> get(String id) async => KycCase({
        'id': 'PRIVATE_CASE_MARKER',
        'workspace_id': 'workspace',
        'version': 1,
        'status': state,
        'relationship_status': 'PENDING',
        'account_link_status': 'PENDING_VERIFIED_IDENTITY',
        'nse_state': 'NOT_REGISTERED',
        'missing': <String>[],
        'fields': <String, String>{
          'pan': 'PRIVATE_PAN_MARKER',
          'email': 'PRIVATE_CONTACT_MARKER',
        },
        'masked_pan': 'PRIVATE_MASKED_PAN_MARKER',
        'amcs': <Map<String, String>>[],
        'can_open_ekyc': false,
      });
}

Future<void> openFlow(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DevOnboardingPreviewFlow(),
              ),
            ),
            child: const Text('Open synthetic preview'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open synthetic preview'));
  await tester.pumpAndSettle();
}

Future<void> next(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Next');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> personal(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('date-of-birth')),
    '2000-01-01',
  );
  await tester.enterText(
    find.byKey(const ValueKey('occupation')),
    'Demo artist',
  );
  await next(tester);
}

Future<void> address(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('address-line')),
    '1 Example Lane',
  );
  await tester.enterText(find.byKey(const ValueKey('city')), 'Demo City');
  await tester.enterText(find.byKey(const ValueKey('postal-code')), '000000');
  await tester.enterText(find.byKey(const ValueKey('country')), 'Exampleland');
  await next(tester);
}

void main() {
  test(
    'build gate is default-off and excludes Production and other projects',
    () {
      expect(
        DevOnboardingPreviewGate.allows(
          flag: false,
          environment: 'dev',
          projectUrl: DevOnboardingPreviewGate.devProjectUrl,
        ),
        isFalse,
      );
      expect(
        DevOnboardingPreviewGate.allows(
          flag: true,
          environment: 'production',
          projectUrl: DevOnboardingPreviewGate.devProjectUrl,
        ),
        isFalse,
      );
      expect(
        DevOnboardingPreviewGate.allows(
          flag: true,
          environment: 'dev',
          projectUrl: 'https://auxbbotbcvrgzvynyrgg.supabase.co',
        ),
        isFalse,
      );
      expect(
        DevOnboardingPreviewGate.allows(
          flag: true,
          environment: 'dev',
          projectUrl: DevOnboardingPreviewGate.devProjectUrl,
        ),
        isTrue,
      );
    },
  );

  testWidgets('direct route honors compiled gate', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DevOnboardingPreviewPage()),
    );
    if (DevOnboardingPreviewGate.enabled) {
      expect(find.text('DEV SIMULATION — NOT KYC VERIFIED'), findsOneWidget);
    } else {
      expect(find.text('Onboarding preview unavailable'), findsOneWidget);
      expect(find.text('DEV SIMULATION — NOT KYC VERIFIED'), findsNothing);
    }
  });

  testWidgets('synthetic start, required validation and full navigation', (
    tester,
  ) async {
    await openFlow(tester);
    expect(find.text('DEV SIMULATION — NOT KYC VERIFIED'), findsOneWidget);
    expect(find.text('Demo Investor'), findsOneWidget);
    expect(find.text('demo@example.test'), findsOneWidget);
    expect(find.text('PAN'), findsNothing);
    expect(find.textContaining('ekycVerifyByUser'), findsNothing);
    await next(tester);
    expect(find.text('Required for this preview.'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('date-of-birth')),
      'invalid',
    );
    await next(tester);
    expect(find.text('Use YYYY-MM-DD.'), findsOneWidget);
    await personal(tester);
    expect(find.text('Address information'), findsOneWidget);
    await next(tester);
    expect(find.text('Required for this preview.'), findsWidgets);
    await address(tester);
    expect(find.text('Nominee decision'), findsOneWidget);
    await next(tester);
    expect(find.text('Choose Yes or No to continue.'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'No'));
    await next(tester);
    expect(find.text('FATCA declarations'), findsOneWidget);
    await next(tester);
    expect(
      find.text('Choose a tax residency answer to continue.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Yes, India'));
    await next(tester);
    expect(find.text('Bank details'), findsOneWidget);
    expect(
      find.textContaining('Bank verification is unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('account number or IFSC'), findsOneWidget);
    await next(tester);
    expect(find.text('Required for this preview.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('account-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Savings').last);
    await tester.pumpAndSettle();
    await next(tester);
    expect(find.text('Review and consent preview'), findsOneWidget);
    expect(find.textContaining('unverified'), findsOneWidget);
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Finish preview'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Finish preview'));
    await tester.pumpAndSettle();
    expect(
      find.text('Acknowledge that this is only a preview.'),
      findsOneWidget,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Finish preview'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Preview complete. No real investor was verified, registered or made ready to transact.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('READY_TO_TRANSACT'), findsNothing);
    expect(find.textContaining('UCC registered'), findsNothing);
    expect(find.text('DEV SIMULATION — NOT KYC VERIFIED'), findsOneWidget);
  });

  testWidgets('back navigation and nominee/FATCA conditional fields', (
    tester,
  ) async {
    await openFlow(tester);
    await personal(tester);
    await address(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Yes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nominee-name')), findsOneWidget);
    await next(tester);
    expect(find.text('Required for this preview.'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('nominee-name')),
      'Demo Nominee',
    );
    await tester.enterText(
      find.byKey(const ValueKey('nominee-relationship')),
      'Fictional relative',
    );
    await next(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'No / other country'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('other-tax-country')), findsOneWidget);
    final back = find.widgetWithText(OutlinedButton, 'Back');
    await tester.ensureVisible(back);
    await tester.pumpAndSettle();
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('Nominee decision'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'No'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nominee-name')), findsNothing);
  });

  testWidgets('exit discards editable memory and returns to original route', (
    tester,
  ) async {
    await openFlow(tester);
    await tester.enterText(
      find.byKey(const ValueKey('occupation')),
      'Demo sculptor',
    );
    await tester.tap(find.byTooltip('Exit preview'));
    await tester.pumpAndSettle();
    expect(find.text('Open synthetic preview'), findsOneWidget);
    await tester.tap(find.text('Open synthetic preview'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('occupation')))
          .initialValue,
      isEmpty,
    );
    expect(find.text('Demo Investor'), findsOneWidget);
  });

  testWidgets('MFD KYC entry exposes preview only with compiled DEV gate', (
    tester,
  ) async {
    final repository = MarkerKycRepository()..state = 'EKYC_IN_PROGRESS';
    final controller = OnboardingKycController(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: OnboardingKycPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    await controller.resume('synthetic-case');
    await tester.pumpAndSettle();
    final action = find.text('Preview remaining onboarding (DEV)');
    if (DevOnboardingPreviewGate.enabled) {
      expect(action, findsOneWidget);
      final before = List<List<String>>.from(repository.calls);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('DEV SIMULATION — NOT KYC VERIFIED'), findsOneWidget);
      expect(find.text('Demo Investor'), findsOneWidget);
      for (final marker in [
        'PRIVATE_CASE_MARKER',
        'PRIVATE_PAN_MARKER',
        'PRIVATE_CONTACT_MARKER',
        'PRIVATE_MASKED_PAN_MARKER',
      ]) {
        expect(find.textContaining(marker), findsNothing);
      }
      expect(
        repository.calls,
        before,
        reason: 'Preview navigation cannot call KYC, eKYC or UCC operations',
      );
      await tester.tap(find.byTooltip('Exit preview'));
      await tester.pumpAndSettle();
      expect(find.text('eKYC in progress'), findsOneWidget);
      expect(controller.current?.state, 'EKYC_IN_PROGRESS');
      expect(repository.calls, before);
      expect((repository.legacy as FakeRepository).calls, isEmpty,
          reason: 'Preview navigation cannot save or resolve onboarding');
    } else {
      expect(action, findsNothing);
    }
    repository.state = 'PROVIDER_RECONCILIATION_REQUIRED';
    await controller.resume('synthetic-case');
    await tester.pumpAndSettle();
    expect(action, findsNothing);
  });

  testWidgets('no approved MFD workspace means no preview entry',
      (tester) async {
    final repository = KycRepository();
    (repository.legacy as FakeRepository).denied = true;
    final controller = OnboardingKycController(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
        MaterialApp(home: OnboardingKycPage(controller: controller)));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('active approved MFD workspace'), findsOneWidget);
    expect(find.text('Preview remaining onboarding (DEV)'), findsNothing);
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets('preview fits width $width at large text scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: DevOnboardingPreviewFlow(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('DEV SIMULATION — NOT KYC VERIFIED'), findsOneWidget);
      await personal(tester);
      expect(tester.takeException(), isNull);
      await address(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(ChoiceChip, 'No'));
      await next(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Yes, India'));
      await next(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('account-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Savings').last);
      await tester.pumpAndSettle();
      await next(tester);
      expect(find.text('Review and consent preview'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
