import 'package:flutter/material.dart';

/// Responsive layout primitives for the Invoice Signer presentation.
class InvoiceSignerUploadGrid extends StatelessWidget {
  const InvoiceSignerUploadGrid({
    super.key,
    required this.children,
  });

  static const double twoColumnBreakpoint = 680;
  static const double gap = 16;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= twoColumnBreakpoint;
        final itemWidth = useTwoColumns
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;

        return Wrap(
          key: const ValueKey('invoice-signer-upload-grid'),
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var index = 0; index < children.length; index++)
              SizedBox(
                key: ValueKey('invoice-signer-upload-item-$index'),
                width: itemWidth,
                child: children[index],
              ),
          ],
        );
      },
    );
  }
}

class InvoiceSignerWorkspace extends StatelessWidget {
  const InvoiceSignerWorkspace({
    super.key,
    required this.preview,
    required this.controls,
  });

  static const double sideBySideBreakpoint = 900;
  static const double paneGap = 24;
  static const double desktopHeight = 720;

  final Widget preview;
  final Widget controls;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < sideBySideBreakpoint) {
          return Column(
            key: const ValueKey('invoice-signer-stacked-workspace'),
            children: [
              KeyedSubtree(
                key: const ValueKey('invoice-signer-preview-pane'),
                child: preview,
              ),
              const SizedBox(height: paneGap),
              KeyedSubtree(
                key: const ValueKey('invoice-signer-controls-pane'),
                child: controls,
              ),
            ],
          );
        }

        return SizedBox(
          height: desktopHeight,
          child: Row(
            key: const ValueKey('invoice-signer-side-by-side-workspace'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 58,
                child: KeyedSubtree(
                  key: const ValueKey('invoice-signer-preview-pane'),
                  child: preview,
                ),
              ),
              const SizedBox(width: paneGap),
              Expanded(
                flex: 42,
                child: KeyedSubtree(
                  key: const ValueKey('invoice-signer-controls-pane'),
                  child: controls,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
