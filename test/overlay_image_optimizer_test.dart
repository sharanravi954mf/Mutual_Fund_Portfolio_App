import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/processors/overlay_image_optimizer.dart';

const _wideTransparentPng =
    'iVBORw0KGgoAAAANSUhEUgAAAlgAAABkCAYAAABaQU4jAAABjUlEQVR42u3WIQEAIRREQY4gJDpBHCIQB0EikqBRdwL3Z/SqVS8lAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABOz99hLW26CwCIbqz+fm2ymwAA7hJYAAACCwBAYAEACCwAAAQWAIDAAgAQWAAACCwAAIEFACCwAAAQWAAAAgsAQGABAAgsAAAEFgCAwAIAEFgAAAgsAACBBQAgsAAAEFgAAAILAEBgAQAgsAAABBYAgMACABBYAAAILAAAgQUAILAAABBYAAACCwBAYAEAILAAAAQWAIDAAgBAYAEACCwAAIEFACCwAAAQWAAAAgsAQGABACCwAAAEFgCAwAIAQGABAAgsAACBBQCAwAIAEFgAAAILAEBgAQAgsAAABBYAgMACAEBgAQAILAAAgQUAgMACABBYAAACCwBAYAEAILAAAAQWAIDAAgBAYAEACCwAAIEFAIDAAgAQWAAAAgsAAIEFACCwAAAEFgCAwAIAQGABAAgsAACBBQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQ0Qbs4wSi/oRQcgAAAABJRU5ErkJggg==';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bounds oversized PNG while retaining aspect ratio and alpha', () async {
    const optimizer = OverlayImageOptimizer();
    final optimized = await optimizer.optimizePngBase64(_wideTransparentPng);
    final codec = await ui.instantiateImageCodec(base64Decode(optimized));
    final frame = await codec.getNextFrame();

    try {
      expect(frame.image.width, 512);
      expect(frame.image.height, 85);
      final rgba = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(rgba, isNotNull);
      expect(rgba!.getUint8(3), 0);
    } finally {
      frame.image.dispose();
      codec.dispose();
    }
  });

  test('keeps a bounded PNG unchanged when supplied as a data URL', () async {
    const optimizer = OverlayImageOptimizer();
    final bounded = await optimizer.optimizePngBase64(_wideTransparentPng);

    final unchanged = await optimizer.optimizePngBase64(
      'data:image/png;base64,$bounded',
    );

    expect(unchanged, bounded);
  });

  test('rejects invalid PNG bytes before codec work', () async {
    const optimizer = OverlayImageOptimizer();

    await expectLater(
      optimizer.optimizePngBase64(base64Encode(List<int>.filled(24, 0))),
      throwsA(isA<FormatException>()),
    );
  });
}
