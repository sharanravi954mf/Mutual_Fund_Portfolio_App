import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const fixtureDirectory = 'test/fixtures/cams';
  const beforeCamsXls = '$fixtureDirectory/BeforeCams.xls';
  const afterCamsXls = '$fixtureDirectory/AfterCams.xls';
  const camsInvoice = '$fixtureDirectory/UK_ARN-153316_UKM26-27E3.pdf';
  const beforeCamsXlsx = '$fixtureDirectory/BeforeCams.xlsx';
  const afterCamsXlsx = '$fixtureDirectory/AfterCams.xlsx';

  test(
    'real CAMS .xls fixtures are available for Invoice Signer characterization',
    () {
      expect(
        File(beforeCamsXls).existsSync(),
        isTrue,
        reason: 'Missing $beforeCamsXls',
      );
      expect(
        File(afterCamsXls).existsSync(),
        isTrue,
        reason: 'Missing $afterCamsXls',
      );
      expect(File(camsInvoice).existsSync(), isTrue,
          reason: 'Missing $camsInvoice');

      // The source tracker must remain a genuine Excel 97-2003 compound file.
      final beforeBytes = File(beforeCamsXls).readAsBytesSync();
      expect(
          beforeBytes.take(8),
          orderedEquals(
              const [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]));

      // The approved expected output and representative PDF are deliberately
      // read as part of this fixture contract. Browser characterization tests
      // compare the cell-level CAMS result once matching expectations are
      // supplied with the fixture set.
      expect(File(afterCamsXls).lengthSync(), greaterThan(0));
      expect(File(camsInvoice).lengthSync(), greaterThan(0));
    },
    skip: !File(beforeCamsXls).existsSync() ||
            !File(afterCamsXls).existsSync() ||
            !File(camsInvoice).existsSync()
        ? 'Real CAMS .xls fixtures are not available in this repository. Add the approved before/after trackers and representative PDF before enabling this characterization suite.'
        : false,
  );

  test('CAMS .xlsx fixtures are paired when they are added', () {
    final hasBefore = File(beforeCamsXlsx).existsSync();
    final hasAfter = File(afterCamsXlsx).existsSync();

    expect(
      hasBefore,
      hasAfter,
      reason: 'Add both $beforeCamsXlsx and $afterCamsXlsx together.',
    );
  });
}
