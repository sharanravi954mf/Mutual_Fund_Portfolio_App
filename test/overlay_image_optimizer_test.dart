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
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      base64Decode(optimized),
    );
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();

    try {
      expect(descriptor.width, 512);
      expect(descriptor.height, 85);
      final rgba = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(rgba, isNotNull);
      expect(rgba!.getUint8(3), 0);
    } finally {
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  });
}
