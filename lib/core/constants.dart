import 'package:flutter/material.dart';

enum ProductionLine {
  line1,
  line2;

  Color get color {
    switch (this) {
      case ProductionLine.line1:
        return const Color(0xFF1565C0); // Blue
      case ProductionLine.line2:
        return const Color(0xFF388E3C); // Green
    }
  }

  Color get lightColor {
    switch (this) {
      case ProductionLine.line1:
        return const Color(0xFFE3F2FD); // Light Blue
      case ProductionLine.line2:
        return const Color(0xFFE8F5E9); // Light Green
    }
  }

  String get arabicLabel {
    switch (this) {
      case ProductionLine.line1:
        return 'خط الإنتاج 1';
      case ProductionLine.line2:
        return 'خط الإنتاج 2';
    }
  }

  int get number {
    switch (this) {
      case ProductionLine.line1:
        return 1;
      case ProductionLine.line2:
        return 2;
    }
  }
}
