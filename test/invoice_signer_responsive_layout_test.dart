import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/widgets/invoice_signer_responsive_layout.dart';

void main() {
  Widget testFrame({
    required double width,
    required Widget child,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );
  }

  List<Widget> uploadItems() {
    return List.generate(
      4,
      (index) => const SizedBox(
        height: 80,
        child: ColoredBox(color: Colors.deepPurple),
      ),
    );
  }

  testWidgets('upload cards form a two by two grid on desktop', (tester) async {
    await tester.pumpWidget(
      testFrame(
        width: 920,
        child: InvoiceSignerUploadGrid(children: uploadItems()),
      ),
    );

    final first = tester.getTopLeft(
      find.byKey(const ValueKey('invoice-signer-upload-item-0')),
    );
    final second = tester.getTopLeft(
      find.byKey(const ValueKey('invoice-signer-upload-item-1')),
    );
    final third = tester.getTopLeft(
      find.byKey(const ValueKey('invoice-signer-upload-item-2')),
    );
    final fourth = tester.getTopLeft(
      find.byKey(const ValueKey('invoice-signer-upload-item-3')),
    );

    expect(second.dy, first.dy);
    expect(second.dx, greaterThan(first.dx));
    expect(third.dy, greaterThan(first.dy));
    expect(fourth.dy, third.dy);
    expect(fourth.dx, greaterThan(third.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('upload cards stack without overflow on mobile', (tester) async {
    await tester.pumpWidget(
      testFrame(
        width: 320,
        child: InvoiceSignerUploadGrid(children: uploadItems()),
      ),
    );

    for (var index = 1; index < 4; index++) {
      final previous = tester.getTopLeft(
        find.byKey(ValueKey('invoice-signer-upload-item-${index - 1}')),
      );
      final current = tester.getTopLeft(
        find.byKey(ValueKey('invoice-signer-upload-item-$index')),
      );
      expect(current.dx, previous.dx);
      expect(current.dy, greaterThan(previous.dy));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop workspace uses 58/42 sibling panes', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      testFrame(
        width: 920,
        child: const InvoiceSignerWorkspace(
          preview: ColoredBox(color: Colors.white),
          controls: ColoredBox(color: Colors.deepPurple),
        ),
      ),
    );

    final previewFinder =
        find.byKey(const ValueKey('invoice-signer-preview-pane'));
    final controlsFinder =
        find.byKey(const ValueKey('invoice-signer-controls-pane'));
    final previewTopLeft = tester.getTopLeft(previewFinder);
    final controlsTopLeft = tester.getTopLeft(controlsFinder);
    final previewWidth = tester.getSize(previewFinder).width;
    final controlsWidth = tester.getSize(controlsFinder).width;

    expect(previewTopLeft.dy, controlsTopLeft.dy);
    expect(controlsTopLeft.dx, greaterThan(previewTopLeft.dx));
    expect(previewWidth / (previewWidth + controlsWidth), closeTo(0.58, 0.01));
    expect(
      tester.getSize(previewFinder).height,
      InvoiceSignerWorkspace.desktopHeight,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet workspace stacks preview above controls', (tester) async {
    await tester.pumpWidget(
      testFrame(
        width: 800,
        child: const InvoiceSignerWorkspace(
          preview: SizedBox(height: 400),
          controls: SizedBox(height: 600),
        ),
      ),
    );

    final previewTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey('invoice-signer-preview-pane')),
    );
    final controlsTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey('invoice-signer-controls-pane')),
    );

    expect(controlsTopLeft.dx, previewTopLeft.dx);
    expect(controlsTopLeft.dy, greaterThan(previewTopLeft.dy));
    expect(tester.takeException(), isNull);
  });
}
