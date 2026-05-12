import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/printing/zpl_builder.dart';

void main() {
  group('ZplBuilder.createLabelPrint', () {
    late String output;

    setUp(() {
      final bitmap = Uint8List.fromList([
        0x00, 0xFF, // row 1
        0xFF, 0x00, // row 2
      ]);
      final bytes = ZplBuilder().createLabelPrint(
        widthMm: 50.0,
        heightMm: 30.0,
        bitmapWidthBytes: 2,
        bitmapHeight: 2,
        bitmapData: bitmap,
        copies: 3,
      );
      output = String.fromCharCodes(bytes);
    });

    test('starts with ^XA and ends with ^XZ', () {
      expect(output.trimRight().startsWith('^XA'), isTrue);
      expect(output.trimRight().endsWith('^XZ'), isTrue);
    });

    test('contains ^PW (print width) and ^LL (label length) in dots', () {
      // 50mm @ 203dpi ≈ 400 dots, 30mm @ 203dpi ≈ 240 dots
      expect(output, contains('^PW400'));
      expect(output, contains('^LL240'));
    });

    test('contains ^GFA bitmap block with correct dimensions', () {
      // 2 widthBytes * 2 rows = 4 total bytes
      expect(output, contains('^GFA,4,4,2,'));
    });

    test('contains ^PQ with copy count', () {
      expect(output, contains('^PQ3'));
    });

    test('contains ^FO0,0 and ^FS field markers', () {
      expect(output, contains('^FO0,0'));
      expect(output, contains('^FS'));
    });

    test('inverts bitmap polarity for ZPL (1 = black)', () {
      // Input bytes: 0x00, 0xFF, 0xFF, 0x00 → inverted: FF, 00, 00, FF
      expect(output, contains('FF0000FF'));
    });

    test('hex data is uppercase', () {
      final hexBlock = RegExp(r'\^GFA,\d+,\d+,\d+,([0-9A-F]+)').firstMatch(output);
      expect(hexBlock, isNotNull);
      expect(hexBlock!.group(1), matches(RegExp(r'^[0-9A-F]+$')));
    });

    test('copies < 1 is clamped to 1', () {
      final bytes = ZplBuilder().createLabelPrint(
        widthMm: 50.0,
        heightMm: 30.0,
        bitmapWidthBytes: 1,
        bitmapHeight: 1,
        bitmapData: Uint8List.fromList([0]),
        copies: 0,
      );
      expect(String.fromCharCodes(bytes), contains('^PQ1'));
    });
  });

  group('ZplBuilder.createSelfTestLabel', () {
    test('produces a minimal ZPL document with ZEBRA TEST text and QR', () {
      final bytes = ZplBuilder().createSelfTestLabel(
        widthMm: 50.0,
        heightMm: 30.0,
      );
      final output = String.fromCharCodes(bytes);

      expect(output, contains('^XA'));
      expect(output, contains('^XZ'));
      expect(output, contains('ZEBRA TEST'));
      expect(output, contains('TEST123'));
      expect(output, contains('^BQ')); // QR barcode command
    });
  });
}
