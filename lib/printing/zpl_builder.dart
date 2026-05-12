import 'dart:typed_data';

import 'unit_converter.dart';

/// Builds ZPL II command sequences for Zebra printers (e.g. ZD230t).
///
/// The bitmap input is expected to follow the same convention as
/// [LabelRenderer] / [TsplBuilder] output: bit `1` = white, bit `0` = black.
/// ZPL `^GFA` uses the opposite polarity (`1` = black), so this builder
/// inverts the bitmap internally — leaving the TSPL path untouched.
class ZplBuilder {
  static const String _lineEnding = '\r\n';

  Uint8List createLabelPrint({
    required double widthMm,
    required double heightMm,
    required int bitmapWidthBytes,
    required int bitmapHeight,
    required Uint8List bitmapData,
    int copies = 1,
  }) {
    final widthDots = UnitConverter.mmToDots(widthMm);
    final heightDots = UnitConverter.mmToDots(heightMm);

    final inverted = _invertBitmap(bitmapData);
    final totalBytes = bitmapWidthBytes * bitmapHeight;
    final hexData = _bytesToHex(inverted);
    final qty = copies < 1 ? 1 : copies;

    final buffer = StringBuffer()
      ..write('^XA')
      ..write(_lineEnding)
      ..write('^PW$widthDots')
      ..write(_lineEnding)
      ..write('^LL$heightDots')
      ..write(_lineEnding)
      ..write('^FO0,0')
      ..write(_lineEnding)
      ..write('^GFA,$totalBytes,$totalBytes,$bitmapWidthBytes,$hexData')
      ..write(_lineEnding)
      ..write('^FS')
      ..write(_lineEnding)
      ..write('^PQ$qty')
      ..write(_lineEnding)
      ..write('^XZ')
      ..write(_lineEnding);

    return Uint8List.fromList(buffer.toString().codeUnits);
  }

  /// Small built-in self-test label used by the printer settings test action.
  /// Uses native ZPL text/QR commands so it works without rendering a bitmap.
  Uint8List createSelfTestLabel({
    required double widthMm,
    required double heightMm,
  }) {
    final widthDots = UnitConverter.mmToDots(widthMm);
    final heightDots = UnitConverter.mmToDots(heightMm);

    final buffer = StringBuffer()
      ..write('^XA')
      ..write(_lineEnding)
      ..write('^PW$widthDots')
      ..write(_lineEnding)
      ..write('^LL$heightDots')
      ..write(_lineEnding)
      ..write('^CI28')
      ..write(_lineEnding)
      ..write('^FO20,20^A0N,30,30^FDZEBRA TEST^FS')
      ..write(_lineEnding)
      ..write('^FO20,60^BQN,2,4^FDLA,TEST123^FS')
      ..write(_lineEnding)
      ..write('^PQ1')
      ..write(_lineEnding)
      ..write('^XZ')
      ..write(_lineEnding);

    return Uint8List.fromList(buffer.toString().codeUnits);
  }

  Uint8List _invertBitmap(Uint8List source) {
    final out = Uint8List(source.length);
    for (var i = 0; i < source.length; i++) {
      out[i] = source[i] ^ 0xFF;
    }
    return out;
  }

  String _bytesToHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      final hex = b.toRadixString(16).toUpperCase();
      if (hex.length == 1) sb.write('0');
      sb.write(hex);
    }
    return sb.toString();
  }
}
