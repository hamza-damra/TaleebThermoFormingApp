import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

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

  // 4-side text layout fields
  final bool hasText;
  final bool useLargeFont;
  final int mainFontHeight;
  final int topTextY;
  final int bottomTextY;
  final int sideBandWidth;
  final int sideBandTop;
  final int sideBandBottom;

  LabelLayout({
    required this.widthDots,
    required this.heightDots,
    required this.marginDots,
    required this.printableWidthDots,
    required this.printableHeightDots,
    required this.qrSize,
    required this.qrX,
    required this.qrY,
    this.hasText = false,
    this.useLargeFont = false,
    this.mainFontHeight = 0,
    this.topTextY = 0,
    this.bottomTextY = 0,
    this.sideBandWidth = 0,
    this.sideBandTop = 0,
    this.sideBandBottom = 0,
  });

  static const int _gap = 6;
  static const int _minQrDots = 80;

  factory LabelLayout.fromPreset(LabelPreset preset, {bool hasText = false}) {
    final widthDots = UnitConverter.mmToDots(preset.widthMm);
    final heightDots = UnitConverter.mmToDots(preset.heightMm);
    final marginDots = UnitConverter.mmToDots(preset.marginMm);

    final printableWidthDots = widthDots - (marginDots * 2);
    final printableHeightDots = heightDots - (marginDots * 2);

    if (!hasText) {
      final qrSize = math.min(printableWidthDots, printableHeightDots);
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

    // Choose main font: prefer arial48, fall back to arial24
    final arial48H = img.arial48.lineHeight;
    final arial24H = img.arial24.lineHeight;
    final bool useLarge =
        printableHeightDots - 2 * (arial48H + _gap) >= _minQrDots;
    final mainFontH = useLarge ? arial48H : arial24H;

    // Top / bottom text bands
    final topTextY = marginDots;
    final bottomTextY = heightDots - marginDots - mainFontH;

    // Vertical zone between top/bottom bands (for QR + side bands)
    final qrZoneTop = marginDots + mainFontH + _gap;
    final qrZoneBottom = heightDots - marginDots - mainFontH - _gap;
    final qrZoneHeight = qrZoneBottom - qrZoneTop;

    // Left / right side bands (same font as top/bottom, rotated)
    final sideBandW = mainFontH + _gap;
    final qrZoneLeft = marginDots + sideBandW;
    final qrZoneRight = widthDots - marginDots - sideBandW;
    final qrZoneWidth = qrZoneRight - qrZoneLeft;

    final qrSize = math.min(qrZoneWidth, qrZoneHeight);
    final qrX = qrZoneLeft + ((qrZoneWidth - qrSize) ~/ 2);
    final qrY = qrZoneTop + ((qrZoneHeight - qrSize) ~/ 2);

    return LabelLayout(
      widthDots: widthDots,
      heightDots: heightDots,
      marginDots: marginDots,
      printableWidthDots: printableWidthDots,
      printableHeightDots: printableHeightDots,
      qrSize: qrSize,
      qrX: qrX,
      qrY: qrY,
      hasText: true,
      useLargeFont: useLarge,
      mainFontHeight: mainFontH,
      topTextY: topTextY,
      bottomTextY: bottomTextY,
      sideBandWidth: sideBandW,
      sideBandTop: qrZoneTop,
      sideBandBottom: qrZoneBottom,
    );
  }

  int get widthBytes => UnitConverter.dotsToBytes(UnitConverter.alignToBytes(widthDots));
  int get alignedWidthDots => UnitConverter.alignToBytes(widthDots);

  // Alias kept for backward-compat in tests
  int get textHeight => mainFontHeight;
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
    String? topText,
    String? bottomText,
    String? sideText,
  }) async {
    final hasText = topText != null || bottomText != null || sideText != null;
    final layout = LabelLayout.fromPreset(preset, hasText: hasText);

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

    if (hasText) {
      await _drawLabelText(image, layout, topText: topText, bottomText: bottomText, sideText: sideText);
    }

    _drawQrCode(image, qrImage, layout);

    final monochromeBytes = _convertToMonochrome(image);

    return LabelRenderResult(
      monochromeBytes: monochromeBytes,
      widthBytes: layout.widthBytes,
      height: layout.heightDots,
    );
  }

  Future<void> _drawLabelText(img.Image image, LabelLayout layout, {String? topText, String? bottomText, String? sideText}) async {
    final fontSize = layout.mainFontHeight * 0.72;
    final maxHorizWidth = image.width - (layout.marginDots * 2);

    // Top text (horizontal, centered)
    if (topText != null) {
      final textBitmap = await _renderTextBitmap(topText, fontSize, maxHorizWidth);
      final centerX = (image.width - textBitmap.width) ~/ 2;
      _compositeBlackPixels(image, textBitmap, centerX, layout.topTextY);
    }

    // Bottom text (horizontal, centered)
    if (bottomText != null) {
      final textBitmap = await _renderTextBitmap(bottomText, fontSize, maxHorizWidth);
      final centerX = (image.width - textBitmap.width) ~/ 2;
      _compositeBlackPixels(image, textBitmap, centerX, layout.bottomTextY);
    }

    // Left / right rotated text — dedicated sideText (e.g. scannedValue + lineLetter)
    final resolvedSideText = sideText ?? topText ?? bottomText;
    final sideAvailable = layout.sideBandBottom - layout.sideBandTop;

    if (sideAvailable > 0 && resolvedSideText != null) {
      var sideBitmap = await _renderTextBitmap(resolvedSideText, fontSize, sideAvailable);

      // Scale down if wider than available space
      if (sideBitmap.width > sideAvailable) {
        final scale = sideAvailable / sideBitmap.width;
        sideBitmap = img.copyResize(sideBitmap,
          width: sideAvailable,
          height: (sideBitmap.height * scale).round().clamp(1, sideBitmap.height),
          interpolation: img.Interpolation.average,
        );
      }

      // Left side — text reads bottom-to-top (CCW 90°)
      final leftRotated = img.copyRotate(sideBitmap, angle: -90);
      final leftOffsetY = (sideAvailable - leftRotated.height) ~/ 2;
      final leftOffsetX = (layout.mainFontHeight - leftRotated.width) ~/ 2;
      _compositeBlackPixels(image, leftRotated,
        layout.marginDots + leftOffsetX, layout.sideBandTop + leftOffsetY);

      // Right side — text reads top-to-bottom (CW 90°)
      final rightRotated = img.copyRotate(sideBitmap, angle: 90);
      final rightOffsetY = (sideAvailable - rightRotated.height) ~/ 2;
      final rightOffsetX = (layout.mainFontHeight - rightRotated.width) ~/ 2;
      _compositeBlackPixels(image, rightRotated,
        layout.widthDots - layout.marginDots - layout.mainFontHeight + rightOffsetX,
        layout.sideBandTop + rightOffsetY);
    }
  }

  /// Renders [text] using Flutter’s text engine (supports Arabic / Unicode)
  /// and returns an [img.Image] with black text on a white background.
  Future<img.Image> _renderTextBitmap(String text, double fontSize, int maxWidth) async {
    // Detect base text direction for proper BiDi rendering
    final isRtl = RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]').hasMatch(text);

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF000000),
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      maxLines: 1,
    );
    textPainter.layout();

    // Scale font down if text overflows the available width
    double usedFontSize = fontSize;
    if (textPainter.width > maxWidth && maxWidth > 0) {
      usedFontSize = fontSize * (maxWidth / textPainter.width);
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF000000),
          fontSize: usedFontSize,
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout();
    }

    final w = textPainter.width.ceil().clamp(1, maxWidth.clamp(1, 4096));
    final h = textPainter.height.ceil().clamp(1, 512);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    textPainter.paint(canvas, Offset.zero);

    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(w, h);
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return img.Image(width: 1, height: 1);

    final result = img.Image(width: w, height: h);
    final pixels = byteData.buffer.asUint8List();
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        result.setPixel(x, y, img.ColorRgba8(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]));
      }
    }
    return result;
  }

  /// Composites only dark pixels from [src] onto [dest] at the given offset.
  void _compositeBlackPixels(img.Image dest, img.Image src, int destX, int destY) {
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        if (pixel.r.toInt() < 128) {
          final dx = destX + x;
          final dy = destY + y;
          if (dx >= 0 && dx < dest.width && dy >= 0 && dy < dest.height) {
            dest.setPixel(dx, dy, img.ColorRgba8(0, 0, 0, 255));
          }
        }
      }
    }
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
