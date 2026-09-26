/// PRODUCTION → TRANSIT («الرصيف») move (V210). See
/// docs/FRONTEND_HANDOFF_PALLETIZING_APP_PRODUCTION_TO_TRANSIT_MOVE.md.
library;

/// How the identifier was captured. Audit only on the backend.
enum PalletTransitScanType {
  qr('QR'),
  number('NUMBER');

  const PalletTransitScanType(this.wire);
  final String wire;
}

/// Client mirror of the backend's identifier canonicalization: every
/// whitespace / format (bidi) character is removed and Arabic-Indic digits
/// (٠–٩, ۰–۹) become ASCII. Used for local validation and matching only —
/// the raw identifier is what gets sent.
abstract final class PalletIdentifier {
  static final RegExp _twelveDigits = RegExp(r'^\d{12}$');

  /// Zero-width and bidi-control characters (Unicode "format", Cf).
  static bool _isFormat(int rune) =>
      rune == 0x00AD ||
      rune == 0x061C ||
      rune == 0x180E ||
      (rune >= 0x200B && rune <= 0x200F) ||
      (rune >= 0x202A && rune <= 0x202E) ||
      (rune >= 0x2060 && rune <= 0x2064) ||
      (rune >= 0x2066 && rune <= 0x206F) ||
      rune == 0xFEFF;

  static bool _isWhitespace(int rune) =>
      String.fromCharCode(rune).trim().isEmpty;

  static String canonicalize(String raw) {
    final out = StringBuffer();
    for (final rune in raw.runes) {
      if (_isFormat(rune) || _isWhitespace(rune)) continue;
      if (rune >= 0x0660 && rune <= 0x0669) {
        out.writeCharCode(0x30 + rune - 0x0660);
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        out.writeCharCode(0x30 + rune - 0x06F0);
      } else {
        out.writeCharCode(rune);
      }
    }
    return out.toString();
  }

  static bool isValid(String raw) => _twelveDigits.hasMatch(canonicalize(raw));

  /// An ASCII, Arabic-Indic or Extended Arabic-Indic digit.
  static bool isDigitRune(int rune) =>
      (rune >= 0x30 && rune <= 0x39) ||
      (rune >= 0x0660 && rune <= 0x0669) ||
      (rune >= 0x06F0 && rune <= 0x06F9);
}

/// Result of `POST /palletizing-line/palletizer/pallets/move-to-transit`, or
/// of a replay of one (same `clientRequestId`).
class PalletizerTransitMoveResult {
  final int? movementId;
  final int palletId;
  final String scannedValue;
  final int? productTypeId;
  final String? productTypeName;
  final int? palletizingLineId;
  final String? palletizingLineName;
  final int? thermoformingShiftLineId;
  final String? fromLocation;
  final String? toLocation;

  /// Where the pallet is NOW — differs from [toLocation] on a replay after
  /// the movement was undone.
  final String? currentLocation;
  final DateTime? movedAt;
  final String? movedAtDisplay;
  final String? movedByName;
  final String? producedByPalletizerName;
  final bool inherited;

  /// This `clientRequestId` was already executed — no second movement.
  final bool replayed;

  /// Only on a replay: the warehouse undid the movement; the pallet is back
  /// at PRODUCTION.
  final bool movementUndone;

  const PalletizerTransitMoveResult({
    this.movementId,
    required this.palletId,
    required this.scannedValue,
    this.productTypeId,
    this.productTypeName,
    this.palletizingLineId,
    this.palletizingLineName,
    this.thermoformingShiftLineId,
    this.fromLocation,
    this.toLocation,
    this.currentLocation,
    this.movedAt,
    this.movedAtDisplay,
    this.movedByName,
    this.producedByPalletizerName,
    this.inherited = false,
    this.replayed = false,
    this.movementUndone = false,
  });

  /// The replayed movement was undone — the pallet is on the line again. Must
  /// never be shown as a green success.
  bool get returnedToProduction =>
      movementUndone || currentLocation == 'PRODUCTION';
}

/// One pallet still at PRODUCTION — a row of the pending list and of the
/// create / logout refusal details.
class ProductionPendingPallet {
  final int palletId;
  final String scannedValue;
  final int? productTypeId;
  final String? productTypeName;
  final int? thermoformingShiftLineId;
  final String? currentLocation;
  final DateTime? producedAt;

  /// Absent in refusal details — callers fall back to [producedAt].
  final String? producedAtDisplay;
  final String? palletizerName;

  /// Carried over from an earlier shift that ended without moving it.
  final bool inherited;

  const ProductionPendingPallet({
    required this.palletId,
    required this.scannedValue,
    this.productTypeId,
    this.productTypeName,
    this.thermoformingShiftLineId,
    this.currentLocation,
    this.producedAt,
    this.producedAtDisplay,
    this.palletizerName,
    this.inherited = false,
  });
}

/// The pending pallets of one palletizing line.
class ProductionPendingLine {
  /// `null` in the logout refusal details.
  final int? palletizerSessionId;
  final int palletizingLineId;
  final String? palletizingLineName;
  final int? thermoformingShiftLineId;

  /// The full count — [pallets] is capped at 50 in refusal details.
  final int pendingCount;
  final List<ProductionPendingPallet> pallets;

  const ProductionPendingLine({
    this.palletizerSessionId,
    required this.palletizingLineId,
    this.palletizingLineName,
    this.thermoformingShiftLineId,
    required this.pendingCount,
    this.pallets = const [],
  });
}

/// `GET /palletizing-line/palletizer/production-pending-pallets` — every line
/// the token's employee holds an ACTIVE session on.
class ProductionPendingPallets {
  final int totalPendingCount;
  final List<ProductionPendingLine> lines;

  const ProductionPendingPallets({
    required this.totalPendingCount,
    required this.lines,
  });

  static const empty = ProductionPendingPallets(
    totalPendingCount: 0,
    lines: [],
  );
}

/// The pallets named by a `PREVIOUS_PALLET_STILL_AT_PRODUCTION` or
/// `PALLETIZER_LOGOUT_BLOCKED_BY_PRODUCTION_PALLETS` refusal.
class ProductionPalletBlockers {
  /// Total blocking pallets, including any beyond the listed 50 per line.
  final int totalCount;
  final List<ProductionPendingLine> lines;

  /// Create refusal only: the product the new pallet was blocked for.
  final int? productTypeId;

  const ProductionPalletBlockers({
    required this.totalCount,
    required this.lines,
    this.productTypeId,
  });

  List<ProductionPendingPallet> get pallets => [
    for (final line in lines) ...line.pallets,
  ];

  /// `true` when the details list fewer pallets than [totalCount].
  bool get hasUnlistedPallets => pallets.length < totalCount;
}
