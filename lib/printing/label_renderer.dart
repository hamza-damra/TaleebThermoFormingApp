import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

import '../domain/entities/label_preset.dart';
import 'unit_converter.dart';

class LabelLayout {
  final int widthDots;
  final int heightDots;
  final int marginDots;
  final int printableWidthDots;
  final int printableHeightDots;
  final int qrSize;
  final int qrX;
  final int qrY;

  LabelLayout({
    required this.widthDots,
    required this.heightDots,
    required this.marginDots,
    required this.printableWidthDots,
    required this.printableHeightDots,
    required this.qrSize,
    required this.qrX,
    required this.qrY,
  });

  factory LabelLayout.fromPreset(LabelPreset preset) {
    final widthDots = UnitConverter.mmToDots(preset.widthMm);
    final heightDots = UnitConverter.mmToDots(preset.heightMm);
    final marginDots = UnitConverter.mmToDots(preset.marginMm);

    final printableWidthDots = widthDots - (marginDots * 2);
    final printableHeightDots = heightDots - (marginDots * 2);

    final qrSize = printableWidthDots < printableHeightDots
        ? printableWidthDots
        : printableHeightDots;

    final qrX = marginDots + ((printableWidthDots - qrSize) ~/ 2);
    final qrY = marginDots + ((printableHeightDots - qrSize) ~/ 2);

    return LabelLayout(
      widthDots: widthDots,
      heightDots: heightDots,
      marginDots: marginDots,
      printableWidthDots: printableWidthDots,
      printableHeightDots: printableHeightDots,
      qrSize: qrSize,
      qrX: qrX,
      qrY: qrY,
    );
  }

  int get widthBytes => UnitConverter.dotsToBytes(UnitConverter.alignToBytes(widthDots));
  int get alignedWidthDots => UnitConverter.alignToBytes(widthDots);
}

class LabelRenderResult {
  final Uint8List monochromeBytes;
  final int widthBytes;
  final int height;

  LabelRenderResult({
    required this.monochromeBytes,
    required this.widthBytes,
    required this.height,
  });
}

class LabelRenderer {
  Future<LabelRenderResult> render({
    required String value,
    required LabelPreset preset,
  }) async {
    final layout = LabelLayout.fromPreset(preset);

    final qrCode = QrCode.fromData(
      data: value,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final qrImage = QrImage(qrCode);

    final image = img.Image(
      width: layout.alignedWidthDots,
      height: layout.heightDots,
    );

    img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));

    _drawQrCode(image, qrImage, layout);

    final monochromeBytes = _convertToMonochrome(image);

    return LabelRenderResult(
      monochromeBytes: monochromeBytes,
      widthBytes: layout.widthBytes,
      height: layout.heightDots,
    );
  }

  void _drawQrCode(img.Image image, QrImage qrImage, LabelLayout layout) {
    final moduleCount = qrImage.moduleCount;
    final moduleSize = layout.qrSize ~/ moduleCount;

    for (int y = 0; y < moduleCount; y++) {
      for (int x = 0; x < moduleCount; x++) {
        if (qrImage.isDark(y, x)) {
          final px = layout.qrX + (x * moduleSize);
          final py = layout.qrY + (y * moduleSize);

          for (int dy = 0; dy < moduleSize; dy++) {
            for (int dx = 0; dx < moduleSize; dx++) {
              final targetX = px + dx;
              final targetY = py + dy;
              if (targetX < image.width && targetY < image.height) {
                image.setPixel(targetX, targetY, img.ColorRgba8(0, 0, 0, 255));
              }
            }
          }
        }
      }
    }
  }

  Uint8List _convertToMonochrome(img.Image image) {
    final widthBytes = (image.width + 7) ~/ 8;
    final bytes = Uint8List(widthBytes * image.height);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        final gray = (0.299 * r + 0.587 * g + 0.114 * b).round();
        final isWhite = gray > 127;

        final byteIndex = y * widthBytes + (x ~/ 8);
        final bitIndex = 7 - (x % 8);

        if (isWhite) {
          bytes[byteIndex] |= (1 << bitIndex);
        }
      }
    }

    return bytes;
  }

  Widget renderPreview({
    required String value,
    required LabelPreset preset,
    double maxWidth = 300,
    double maxHeight = 300,
  }) {
    final aspectRatio = preset.widthMm / preset.heightMm;

    double width, height;
    if (maxWidth / maxHeight > aspectRatio) {
      height = maxHeight;
      width = height * aspectRatio;
    } else {
      width = maxWidth;
      height = width / aspectRatio;
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(preset.marginMm * 2),
          child: AspectRatio(
            aspectRatio: 1,
            child: CustomPaint(
              painter: _QrPreviewPainter(value: value),
            ),
          ),
        ),
      ),
    );
  }
}

class _QrPreviewPainter extends CustomPainter {
  final String value;

  _QrPreviewPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    try {
      final qrCode = QrCode.fromData(
        data: value,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );
      final qrImage = QrImage(qrCode);
      final moduleCount = qrImage.moduleCount;
      final moduleSize = size.width / moduleCount;

      final paint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill;

      for (int y = 0; y < moduleCount; y++) {
        for (int x = 0; x < moduleCount; x++) {
          if (qrImage.isDark(y, x)) {
            canvas.drawRect(
              Rect.fromLTWH(
                x * moduleSize,
                y * moduleSize,
                moduleSize,
                moduleSize,
              ),
              paint,
            );
          }
        }
      }
    } catch (_) {
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'QR',
          style: TextStyle(color: Colors.grey, fontSize: 24),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _QrPreviewPainter oldDelegate) {
    return oldDelegate.value != value;
  }
}
