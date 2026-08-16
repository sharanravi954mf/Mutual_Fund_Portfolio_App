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
    final dimensions = _readPngDimensions(bytes);
    final largestDimension = dimensions.width > dimensions.height
        ? dimensions.width
        : dimensions.height;
    if (largestDimension <= maxRasterDimension) return normalized;

    final scale = maxRasterDimension / largestDimension;
    final targetWidth = (dimensions.width * scale).round().clamp(1, 1 << 30);
    final targetHeight = (dimensions.height * scale).round().clamp(1, 1 << 30);
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      allowUpscaling: false,
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
          '${dimensions.width}x${dimensions.height} -> '
          '${targetWidth}x$targetHeight.',
        );
        return base64Encode(optimized);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  _PngDimensions _readPngDimensions(Uint8List bytes) {
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 24) {
      throw const FormatException('Invoice Signer overlay must be a PNG.');
    }
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) {
        throw const FormatException('Invoice Signer overlay must be a PNG.');
      }
    }
    if (bytes[12] != 73 ||
        bytes[13] != 72 ||
        bytes[14] != 68 ||
        bytes[15] != 82) {
      throw const FormatException('Invoice Signer overlay must be a PNG.');
    }

    final data = ByteData.sublistView(bytes);
    final width = data.getUint32(16, Endian.big);
    final height = data.getUint32(20, Endian.big);
    if (width == 0 || height == 0) {
      throw const FormatException('Invoice Signer overlay PNG is invalid.');
    }
    return _PngDimensions(width, height);
  }
}

class _PngDimensions {
  const _PngDimensions(this.width, this.height);

  final int width;
  final int height;
}
