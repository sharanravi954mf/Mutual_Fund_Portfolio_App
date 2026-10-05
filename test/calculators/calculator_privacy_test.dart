import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'feature dependency boundary excludes services, storage, network and logging',
      () {
    final root = Directory('lib/features/calculators').absolute;
    final sources = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    const allowed = {
      'dart:math',
      'dart:ui',
      'package:flutter/material.dart',
      'package:flutter/foundation.dart',
      'package:intl/intl.dart'
    };
    for (final file in sources) {
      final source = file.readAsStringSync();
      for (final match
          in RegExp(r'''(?:import|export|part)\s+['"]([^'"]+)['"]''')
              .allMatches(source)) {
        final uri = match.group(1)!;
        if (uri.startsWith('dart:') || uri.startsWith('package:')) {
          expect(allowed, contains(uri), reason: file.path);
        } else {
          expect(
              file.uri.resolve(uri).toFilePath(), startsWith('${root.path}/'),
              reason: file.path);
        }
        if (file.path.contains('/domain/') || file.path.contains('/models/')) {
          expect(uri.startsWith('package:'), isFalse,
              reason: 'Domain must remain pure Dart');
        }
      }
      expect(
          RegExp(r'\b(print|debugPrint|log|reportError)\s*\(').hasMatch(source),
          isFalse,
          reason: file.path);
    }
  });
}
