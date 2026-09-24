// LINE_3 handoff §6.10 — unit tests for the line model, label rule, print
// letter, accent palette, layout rule and bootstrap parsing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/constants.dart';
import 'package:taleeb_thermoforming/core/responsive.dart';
import 'package:taleeb_thermoforming/data/models/bootstrap_response_model.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_label_content.dart';
import 'package:taleeb_thermoforming/domain/entities/palletizing_line.dart';

void main() {
  group('Label resolver (lineDisplayName → lineName → abjad ordinal)', () {
    test('lineDisplayName wins', () {
      const line = PalletizingLine(
        lineId: 11,
        lineNumber: 3,
        lineName: 'اسم قديم',
        lineDisplayName: 'خط ج',
      );
      expect(line.label, 'خط ج');
    });

    test('blank display name falls back to lineName', () {
      const line = PalletizingLine(
        lineId: 11,
        lineNumber: 3,
        lineName: 'خط ج',
        lineDisplayName: '   ',
      );
      expect(line.label, 'خط ج');
    });

    test('both blank → abjad ordinal from lineNumber', () {
      String ordinal(int n) => PalletizingLine(
        lineId: 11, // never consulted
        lineNumber: n,
        lineName: '',
        lineDisplayName: null,
      ).label;

      expect(ordinal(1), 'خط أ');
      expect(ordinal(2), 'خط ب');
      expect(ordinal(3), 'خط ج');
      expect(ordinal(4), 'خط د');
      expect(ordinal(5), 'خط هـ');
      expect(ordinal(8), 'خط ح');
      expect(ordinal(9), 'خط 9');
      expect(ordinal(0), 'خط 0');
    });

    test('lineId is never used for the label', () {
      const a = PalletizingLine(lineId: 11, lineNumber: 3);
      const b = PalletizingLine(lineId: 3, lineNumber: 3);
      expect(a.label, b.label);
      expect(a.label, 'خط ج');
    });
  });

  group('Print letter', () {
    test('derived from lineNumber: 1→A, 2→B, 3→C, 4→D', () {
      expect(PalletLabelContentMapper.lineDisplayForNumber(1), 'A');
      expect(PalletLabelContentMapper.lineDisplayForNumber(2), 'B');
      expect(PalletLabelContentMapper.lineDisplayForNumber(3), 'C');
      expect(PalletLabelContentMapper.lineDisplayForNumber(4), 'D');
    });

    test('never falls back to another line\'s letter out of range', () {
      expect(PalletizingLine.printLetterForNumber(0), '0');
      expect(PalletizingLine.printLetterForNumber(27), '27');
    });

    test('uses lineNumber, not lineId', () {
      const line = PalletizingLine(lineId: 11, lineNumber: 3);
      expect(line.printLetter, 'C');
    });
  });

  group('Accent palette', () {
    test('lines 1 and 2 keep blue and green; line 3 gets a third accent', () {
      expect(LineAccent.forLineNumber(1).color, const Color(0xFF1565C0));
      expect(LineAccent.forLineNumber(2).color, const Color(0xFF388E3C));
      final third = LineAccent.forLineNumber(3).color;
      expect(third, isNot(LineAccent.forLineNumber(1).color));
      expect(third, isNot(LineAccent.forLineNumber(2).color));
    });

    test('wraps around by lineNumber and tolerates odd numbers', () {
      final n = LineAccent.palette.length;
      expect(LineAccent.forLineNumber(n + 1), LineAccent.forLineNumber(1));
      expect(() => LineAccent.forLineNumber(0), returnsNormally);
      expect(() => LineAccent.forLineNumber(-5), returnsNormally);
    });
  });

  group('Panes vs tabs layout rule', () {
    test('3 panes only when each gets at least minPaneWidth', () {
      expect(usePalletizingPanes(1200, 2), isTrue);
      expect(usePalletizingPanes(1200, 3), isFalse); // 400 dp < 420 dp
      expect(usePalletizingPanes(1280, 3), isTrue);
      expect(usePalletizingPanes(1000, 2), isFalse); // below the breakpoint
      expect(usePalletizingPanes(1600, 0), isFalse);
    });
  });

  group('BootstrapResponseModel', () {
    Map<String, dynamic> entry(int id, int number, String name) => {
      'lineId': id,
      'lineName': name,
      'lineDisplayName': name,
      'lineNumber': number,
      'authorized': false,
      'sessionTable': <dynamic>[],
      'blocked': false,
    };

    test('parses 3 lines in server order with lineDisplayName', () {
      final model = BootstrapResponseModel.fromJson({
        'productTypes': <dynamic>[],
        'lines': [
          entry(1, 1, 'خط أ'),
          entry(2, 2, 'خط ب'),
          entry(3, 3, 'خط ج'),
        ],
      });

      expect(model.lines.map((l) => l.lineId), [1, 2, 3]);
      expect(model.lines.map((l) => l.lineDisplayName), [
        'خط أ',
        'خط ب',
        'خط ج',
      ]);
      expect(PalletizingLine.fromState(model.lines[2]).label, 'خط ج');
    });

    test('keeps server order even when it is not lineId order', () {
      final model = BootstrapResponseModel.fromJson({
        'lines': [entry(12, 1, 'خط أ'), entry(3, 2, 'خط ب')],
      });
      expect(model.lines.map((l) => l.lineId), [12, 3]);
    });

    test('a missing lineDisplayName parses as null', () {
      final model = BootstrapResponseModel.fromJson({
        'lines': [
          {'lineId': 7, 'lineNumber': 3, 'lineName': ''},
        ],
      });
      expect(model.lines.single.lineDisplayName, isNull);
      expect(PalletizingLine.fromState(model.lines.single).label, 'خط ج');
    });

    test('lines: [] parses to an empty list', () {
      final model = BootstrapResponseModel.fromJson({
        'productTypes': <dynamic>[],
        'lines': <dynamic>[],
      });
      expect(model.lines, isEmpty);
    });
  });
}
