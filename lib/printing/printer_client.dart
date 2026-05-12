import 'dart:io';
import 'dart:typed_data';

import '../core/exceptions/printing_exception.dart';
import '../domain/entities/label_preset.dart';
import '../domain/entities/printer_config.dart';
import '../domain/entities/printer_language.dart';
import 'label_renderer.dart';
import 'tspl_builder.dart';
import 'zpl_builder.dart';

class PrinterClient {
  final PrinterConfig printer;

  PrinterClient(this.printer);

  Future<void> print({
    required String value,
    required LabelPreset preset,
    int copies = 1,
    String? topText,
    String? bottomText,
    String? sideText,
  }) async {
    final renderer = LabelRenderer();
    final renderResult = await renderer.render(
      value: value,
      preset: preset,
      topText: topText,
      bottomText: bottomText,
      sideText: sideText,
    );

    final Uint8List printData;
    switch (printer.language) {
      case PrinterLanguage.zpl:
        final zpl = ZplBuilder();
        printData = zpl.createLabelPrint(
          widthMm: preset.widthMm,
          heightMm: preset.heightMm,
          bitmapWidthBytes: renderResult.widthBytes,
          bitmapHeight: renderResult.height,
          bitmapData: renderResult.monochromeBytes,
          copies: copies,
        );
        break;
      case PrinterLanguage.tspl:
        final tsplBuilder = TsplBuilder();
        printData = tsplBuilder.createLabelPrint(
          widthMm: preset.widthMm,
          heightMm: preset.heightMm,
          bitmapWidthBytes: renderResult.widthBytes,
          bitmapHeight: renderResult.height,
          bitmapData: renderResult.monochromeBytes,
          copies: copies,
        );
        break;
    }

    await _sendData(printData);
  }

  /// Sends a small built-in label so the user can validate that the printer
  /// actually prints — not just that a TCP socket opens. The label content
  /// is generated per protocol, so a mismatched language will be visible.
  Future<void> testPrint({LabelPreset? preset}) async {
    final LabelPreset effectivePreset = preset ?? DefaultPresets.defaultPreset;

    final Uint8List data;
    switch (printer.language) {
      case PrinterLanguage.zpl:
        final zpl = ZplBuilder();
        data = zpl.createSelfTestLabel(
          widthMm: effectivePreset.widthMm,
          heightMm: effectivePreset.heightMm,
        );
        break;
      case PrinterLanguage.tspl:
        data = await _buildTsplTestLabel(effectivePreset);
        break;
    }

    await _sendData(data);
  }

  Future<Uint8List> _buildTsplTestLabel(LabelPreset preset) async {
    final renderer = LabelRenderer();
    final rendered = await renderer.render(
      value: 'TEST123',
      preset: preset,
      topText: 'TEST',
    );

    final builder = TsplBuilder();
    return builder.createLabelPrint(
      widthMm: preset.widthMm,
      heightMm: preset.heightMm,
      bitmapWidthBytes: rendered.widthBytes,
      bitmapHeight: rendered.height,
      bitmapData: rendered.monochromeBytes,
      copies: 1,
    );
  }

  Future<void> _sendData(Uint8List data) async {
    Socket? socket;

    try {
      socket = await Socket.connect(
        printer.ip,
        printer.port,
        timeout: Duration(milliseconds: printer.timeoutMs),
      );

      socket.add(data);
      await socket.flush();
    } on SocketException catch (e) {
      if (e.osError?.errorCode == 110 || e.osError?.errorCode == 10060) {
        throw PrintingException.connectionTimeout();
      }
      throw PrintingException.connectionFailed(error: e);
    } catch (e) {
      throw PrintingException.sendFailed(error: e);
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  Future<bool> testConnection() async {
    Socket? socket;

    try {
      socket = await Socket.connect(
        printer.ip,
        printer.port,
        timeout: Duration(milliseconds: printer.timeoutMs),
      );
      return true;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }
}
