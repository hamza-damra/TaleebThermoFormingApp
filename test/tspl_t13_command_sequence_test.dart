import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/constants/printing_constants.dart';
import 'package:taleeb_thermoforming/printing/tspl_builder.dart';

void main() {
  group('T13 Tear Mode — TSPL Command Sequence', () {
    late Uint8List printData;
    late String commandString;

    setUp(() {
      final builder = TsplBuilder();
      final fakeBitmap = Uint8List(100 * 48); // fake 100 widthBytes × 48 height

      printData = builder.createLabelPrint(
        widthMm: 50.0,
        heightMm: 30.0,
        bitmapWidthBytes: 100,
        bitmapHeight: 48,
        bitmapData: fakeBitmap,
        copies: 1,
        gapMm: PrintingConstants.defaultGapMm,
      );

      // Extract the text commands (before and after binary bitmap data).
      // The pre-bitmap commands end just before the bitmap payload.
      // The post-bitmap commands start after the bitmap payload.
      final fullString = String.fromCharCodes(printData);
      commandString = fullString;
    });

    test('command sequence order matches T13 spec', () {
      final commands = commandString.split('\r\n').where((l) => l.isNotEmpty).toList();

      // Extract command names (skip binary BITMAP payload)
      final textCommands = <String>[];
      for (final cmd in commands) {
        if (cmd.startsWith('SIZE') ||
            cmd.startsWith('GAP') ||
            cmd.startsWith('DIRECTION') ||
            cmd.startsWith('OFFSET') ||
            cmd.startsWith('SHIFT') ||
            cmd.startsWith('REFERENCE') ||
            cmd.startsWith('SET ') ||
            cmd.startsWith('CLS') ||
            cmd.startsWith('BITMAP') ||
            cmd.startsWith('PRINT') ||
            cmd.startsWith('FEED')) {
          textCommands.add(cmd.split(',').first.contains('BITMAP')
              ? 'BITMAP'
              : cmd);
        }
      }

      expect(textCommands[0], startsWith('SIZE'));
      expect(textCommands[1], startsWith('GAP'));
      expect(textCommands[2], equals('DIRECTION 0'));
      expect(textCommands[3], equals('OFFSET 0 mm'));
      expect(textCommands[4], equals('SHIFT 0'));
      expect(textCommands[5], equals('REFERENCE 0,0'));
      expect(textCommands[6], equals('SET PEEL OFF'));
      expect(textCommands[7], equals('SET TEAR ON'));
      expect(textCommands[8], equals('SET CUTTER OFF'));
      expect(textCommands[9], equals('CLS'));
      expect(textCommands[10], equals('BITMAP'));
    });

    test('SET TEAR ON is present before CLS, BITMAP, PRINT', () {
      final tearOnIndex = commandString.indexOf('SET TEAR ON');
      final clsIndex = commandString.indexOf('CLS\r\n');
      final bitmapIndex = commandString.indexOf('BITMAP');
      final printIndex = commandString.indexOf('PRINT 1,1');

      expect(tearOnIndex, greaterThan(-1), reason: 'SET TEAR ON must be present');
      expect(tearOnIndex, lessThan(clsIndex), reason: 'SET TEAR ON must be before CLS');
      expect(tearOnIndex, lessThan(bitmapIndex), reason: 'SET TEAR ON must be before BITMAP');
      expect(tearOnIndex, lessThan(printIndex), reason: 'SET TEAR ON must be before PRINT');
    });

    test('SET PEEL OFF is present', () {
      expect(commandString, contains('SET PEEL OFF\r\n'));
    });

    test('SET CUTTER OFF is present', () {
      expect(commandString, contains('SET CUTTER OFF\r\n'));
    });

    test('OFFSET/SHIFT/REFERENCE reset is applied', () {
      expect(commandString, contains('OFFSET 0 mm\r\n'));
      expect(commandString, contains('SHIFT 0\r\n'));
      expect(commandString, contains('REFERENCE 0,0\r\n'));
    });

    test('no FEED after PRINT', () {
      final printIndex = commandString.indexOf('PRINT 1,1');
      expect(printIndex, greaterThan(-1));

      final afterPrint = commandString.substring(printIndex);
      expect(afterPrint, isNot(contains('FEED')));
    });

    test('prints exactly one label (PRINT 1,1)', () {
      expect(commandString, contains('PRINT 1,1\r\n'));
    });

    test('GAP uses 0.0 mm second parameter', () {
      expect(commandString, contains('GAP ${PrintingConstants.defaultGapMm} mm,0.0 mm\r\n'));
    });

    test('SIZE uses real width and height from preset', () {
      expect(commandString, contains('SIZE 50.0 mm,30.0 mm\r\n'));
    });

    test('no SET TEAR OFF present', () {
      expect(commandString, isNot(contains('SET TEAR OFF')));
    });
  });
}
