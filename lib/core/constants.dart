import 'package:flutter/material.dart';

import '../domain/entities/palletizing_line.dart';

/// Accent colours for a palletizing line. Picked by `lineNumber` (never by
/// `lineId`), wrapping around the palette so any number of lines renders.
class LineAccent {
  final Color color;
  final Color lightColor;

  const LineAccent({required this.color, required this.lightColor});

  static const List<LineAccent> palette = [
    LineAccent(color: Color(0xFF1565C0), lightColor: Color(0xFFE3F2FD)), // Blue
    LineAccent(
      color: Color(0xFF388E3C),
      lightColor: Color(0xFFE8F5E9),
    ), // Green
    LineAccent(
      color: Color(0xFF6A1B9A),
      lightColor: Color(0xFFF3E5F5),
    ), // Purple
    LineAccent(
      color: Color(0xFFE65100),
      lightColor: Color(0xFFFFF3E0),
    ), // Orange
  ];

  static LineAccent forLineNumber(int lineNumber) {
    final index = (lineNumber - 1) % palette.length;
    return palette[index < 0 ? index + palette.length : index];
  }
}

/// Neutral app-bar / background colour for a waiting or blocked line.
const Color kInactiveLineColor = Color(0xFF78909C);
const Color kInactiveLineBackground = Color(0xFFF5F5F5);

extension PalletizingLineAccent on PalletizingLine {
  LineAccent get accent => LineAccent.forLineNumber(lineNumber);
  Color get color => accent.color;
  Color get lightColor => accent.lightColor;
}
