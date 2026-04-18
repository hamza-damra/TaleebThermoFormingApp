import 'dart:typed_data';

import '../core/constants/printing_constants.dart';
import '../core/constants/tspl_constants.dart';

class TsplBuilder {
  final StringBuffer _commands = StringBuffer();

  TsplBuilder size(double widthMm, double heightMm) {
    _commands.write('SIZE $widthMm mm,$heightMm mm${TsplConstants.lineEnding}');
    return this;
  }

  TsplBuilder gap(double gapMm) {
    _commands.write('GAP $gapMm mm,0.0 mm${TsplConstants.lineEnding}');
    return this;
  }

  TsplBuilder direction() {
    _commands.write('${TsplConstants.direction}${TsplConstants.lineEnding}');
    return this;
  }

  TsplBuilder offset() {
    _commands.write('${TsplConstants.offset}${TsplConstants.lineEnding}');
    return this;
  }

  TsplBuilder shift() {
    _commands.write('${TsplConstants.shift}${TsplConstants.lineEnding}');
    return this;
  }

  TsplBuilder reference() {
    _commands.write('${TsplConstants.reference}${TsplConstants.lineEnding}');
    return this;
  }

  TsplBuilder setPeelOff() {
    _commands.write('${TsplConstants.setPeelOff}${TsplConstants.lineEnding}');
    return this;
  }

  TsplBuilder setTearOff() {
    _commands.write('${TsplConstants.setTearOff}${TsplConstants.lineEnding}');
    return this;
  }

  TsplBuilder setTearOn() {
    _commands.write('${TsplConstants.setTearOn}${TsplConstants.lineEnding}');
    return this;
  }

  TsplBuilder setCutterOff() {
    _commands.write('${TsplConstants.setCutterOff}${TsplConstants.lineEnding}');
    return this;
  }

  TsplBuilder cls() {
    _commands.write('${TsplConstants.cls}${TsplConstants.lineEnding}');
    return this;
  }

  TsplBuilder bitmap(int x, int y, int widthBytes, int height, Uint8List data) {
    _commands.write('BITMAP $x,$y,$widthBytes,$height,0,');
    return this;
  }

  TsplBuilder print(int sets, int copies) {
    _commands.write('PRINT $sets,$copies${TsplConstants.lineEnding}');
    return this;
  }

  String build() {
    return _commands.toString();
  }

  Uint8List createLabelPrint({
    required double widthMm,
    required double heightMm,
    required int bitmapWidthBytes,
    required int bitmapHeight,
    required Uint8List bitmapData,
    int copies = 1,
    double gapMm = PrintingConstants.defaultGapMm,
  }) {
    final builder = TsplBuilder()
      ..size(widthMm, heightMm)
      ..gap(gapMm)
      ..direction()
      ..offset()
      ..shift()
      ..reference()
      ..setPeelOff()
      ..setTearOn()
      ..setCutterOff()
      ..cls()
      ..bitmap(0, 0, bitmapWidthBytes, bitmapHeight, bitmapData);

    final preCommands = builder.build();
    final preBytes = Uint8List.fromList(preCommands.codeUnits);

    final postCommands = TsplBuilder()..print(1, copies);
    final postBytes = Uint8List.fromList(postCommands.build().codeUnits);

    final result = Uint8List(preBytes.length + bitmapData.length + postBytes.length);
    result.setAll(0, preBytes);
    result.setAll(preBytes.length, bitmapData);
    result.setAll(preBytes.length + bitmapData.length, postBytes);

    return result;
  }
}
