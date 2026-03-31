import 'dart:io';
import 'dart:typed_data';

import '../core/exceptions/printing_exception.dart';
import '../domain/entities/printer_config.dart';
import '../domain/entities/label_preset.dart';
import 'label_renderer.dart';
import 'tspl_builder.dart';

class PrinterClient {
  final PrinterConfig printer;

  PrinterClient(this.printer);

  Future<void> print({
    required String value,
    required LabelPreset preset,
    int copies = 1,
  }) async {
    final renderer = LabelRenderer();
    final renderResult = await renderer.render(value: value, preset: preset);

    final tsplBuilder = TsplBuilder();
    final printData = tsplBuilder.createLabelPrint(
      widthMm: preset.widthMm,
      heightMm: preset.heightMm,
      bitmapWidthBytes: renderResult.widthBytes,
      bitmapHeight: renderResult.height,
      bitmapData: renderResult.monochromeBytes,
      copies: copies,
    );

    await _sendData(printData);
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
