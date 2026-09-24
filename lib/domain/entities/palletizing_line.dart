import 'bootstrap_response.dart';

/// One palletizing line the app renders — built from a bootstrap `lines[]`
/// entry (and kept current by later `/state` refreshes).
///
/// Identity rules (LINE_3 handoff §3, §6.3):
///   * [lineId] is the backend `ProductionLine.id` and the **only** key for
///     maps, selection, tokens, request paths and announcement acks. It is
///     never computed and never assumed to equal [lineNumber].
///   * [lineNumber] is `production_lines.line_number` — used only for the
///     ordinal label fallback, the printed side-band letter and the accent
///     colour. It is not unique in the database, so it is never a key.
///   * A `thermoformingLineId` (SSE / close-request frames) is a different id
///     space and must never be used to find a line.
class PalletizingLine {
  final int lineId;
  final int lineNumber;
  final String? lineName;
  final String? lineDisplayName;

  const PalletizingLine({
    required this.lineId,
    required this.lineNumber,
    this.lineName,
    this.lineDisplayName,
  });

  factory PalletizingLine.fromState(BootstrapLineState state) =>
      PalletizingLine(
        lineId: state.lineId,
        lineNumber: state.lineNumber,
        lineName: state.lineName,
        lineDisplayName: state.lineDisplayName,
      );

  /// Resolved Arabic label for tabs, panes, cards and dialogs.
  String get label => resolveLabel(
    lineDisplayName: lineDisplayName,
    lineName: lineName,
    lineNumber: lineNumber,
  );

  /// Latin side-band letter printed on the pallet label (1 → A, 3 → C).
  String get printLetter => printLetterForNumber(lineNumber);

  /// Abjad ordinals mirrored from the backend `LocalizedLineName`.
  static const List<String> _abjadLetters = [
    'أ',
    'ب',
    'ج',
    'د',
    'هـ',
    'و',
    'ز',
    'ح',
  ];

  /// Backend label fallback rule (`LineStateResponse` javadoc):
  /// `lineDisplayName` → `lineName` → abjad ordinal from `lineNumber`
  /// (1..8) → `خط <n>`. Never derived from `lineId`.
  static String resolveLabel({
    String? lineDisplayName,
    String? lineName,
    required int lineNumber,
  }) {
    final display = lineDisplayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    final name = lineName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return ordinalLabel(lineNumber);
  }

  static String ordinalLabel(int lineNumber) {
    if (lineNumber >= 1 && lineNumber <= _abjadLetters.length) {
      return 'خط ${_abjadLetters[lineNumber - 1]}';
    }
    return 'خط $lineNumber';
  }

  /// `'A' + lineNumber - 1`, the same derivation as the backend
  /// `ThermoformingMachineNameResolver`. Outside A..Z the number itself is
  /// printed so a misconfigured line never borrows another line's letter.
  static String printLetterForNumber(int lineNumber) {
    if (lineNumber >= 1 && lineNumber <= 26) {
      return String.fromCharCode('A'.codeUnitAt(0) + lineNumber - 1);
    }
    return '$lineNumber';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PalletizingLine &&
          lineId == other.lineId &&
          lineNumber == other.lineNumber &&
          lineName == other.lineName &&
          lineDisplayName == other.lineDisplayName;

  @override
  int get hashCode =>
      Object.hash(lineId, lineNumber, lineName, lineDisplayName);

  @override
  String toString() =>
      'PalletizingLine(lineId: $lineId, lineNumber: $lineNumber, '
      'label: $label)';
}
