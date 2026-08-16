import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Bounds the raster work sent to the Edge Function without changing the
/// overlay's PDF dimensions, aspect ratio, transparency, or coordinates.
class OverlayImageOptimizer {
  // 512 px still yields over 250 DPI at the default 120 pt draw width,
  // while keeping pdf-lib's pure-JS PNG work safely below Edge CPU limits.
  static const int maxRasterDimension = 512;

  const OverlayImageOptimizer();

  Future<String> optimizePngBase64(String encodedPng) async {
    final normalized = encodedPng.contains(',')
        ? encodedPng.substring(encodedPng.indexOf(',') + 1)
        : encodedPng;
    final bytes = base64Decode(normalized);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);

    try {
      final largestDimension = descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height;
      if (largestDimension <= maxRasterDimension) return normalized;

      final scale = maxRasterDimension / largestDimension;
      final targetWidth = (descriptor.width * scale).round().clamp(1, 1 << 30);
      final targetHeight =
          (descriptor.height * scale).round().clamp(1, 1 << 30);
      final codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final pngData = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (pngData == null) {
            throw StateError('Unable to encode optimized PNG overlay.');
          }
          final optimized = pngData.buffer.asUint8List(
            pngData.offsetInBytes,
            pngData.lengthInBytes,
          );
          debugPrint(
            'Invoice Signer: optimized PNG overlay '
            '${descriptor.width}x${descriptor.height} -> '
            '${targetWidth}x$targetHeight.',
          );
          return base64Encode(optimized);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }
}
