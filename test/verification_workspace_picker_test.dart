import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/verification_workspace.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/widgets/verification_workspace_picker.dart';

void main() {
  Future<void> show(WidgetTester tester, List<VerificationWorkspace> workspaces,
      void Function(String?) onSelected) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async =>
            onSelected(await selectVerificationWorkspace(context, workspaces)),
        child: const Text('Verify'),
      ),
    ))));
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
  }

  testWidgets('two eligible MFDs require an explicit selection',
      (tester) async {
    String? selected;
    await show(
        tester,
        const [
          VerificationWorkspace('A', 'MFD A'),
          VerificationWorkspace('B', 'MFD B')
        ],
        (value) => selected = value);
    expect(selected, isNull);
    await tester.tap(find.text('MFD B'));
    await tester.pumpAndSettle();
    expect(selected, 'B');
  });

  testWidgets('a unique proven workspace preserves the single workspace flow',
      (tester) async {
    String? selected;
    await show(tester, const [VerificationWorkspace('A', 'MFD A')],
        (value) => selected = value);
    expect(selected, 'A');
    expect(find.byType(SimpleDialog), findsNothing);
  });

  testWidgets('no proven relationship does not invent a workspace',
      (tester) async {
    String? selected;
    await show(tester, const [], (value) => selected = value);
    expect(selected, isNull);
    expect(find.textContaining('workspace invitation'), findsOneWidget);
  });
}
