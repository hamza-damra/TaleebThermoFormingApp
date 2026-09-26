import '../../domain/entities/production_transit.dart';

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

String? _asString(Object? v) => v is String ? v : null;

bool _asBool(Object? v) => v == true;

/// ISO-8601 string (the backend's Jackson config), tolerating epoch seconds.
DateTime? _asInstant(Object? v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  if (v is num) {
    return DateTime.fromMillisecondsSinceEpoch((v * 1000).round(), isUtc: true);
  }
  return null;
}

List<Map<String, dynamic>> _asMaps(Object? v) =>
    v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

class PalletizerTransitMoveResultModel extends PalletizerTransitMoveResult {
  const PalletizerTransitMoveResultModel({
    super.movementId,
    required super.palletId,
    required super.scannedValue,
    super.productTypeId,
    super.productTypeName,
    super.palletizingLineId,
    super.palletizingLineName,
    super.thermoformingShiftLineId,
    super.fromLocation,
    super.toLocation,
    super.currentLocation,
    super.movedAt,
    super.movedAtDisplay,
    super.movedByName,
    super.producedByPalletizerName,
    super.inherited,
    super.replayed,
    super.movementUndone,
  });

  factory PalletizerTransitMoveResultModel.fromJson(Map<String, dynamic> json) {
    return PalletizerTransitMoveResultModel(
      movementId: _asInt(json['movementId']),
      palletId: _asInt(json['palletId']) ?? 0,
      scannedValue: _asString(json['scannedValue']) ?? '',
      productTypeId: _asInt(json['productTypeId']),
      productTypeName: _asString(json['productTypeName']),
      palletizingLineId: _asInt(json['palletizingLineId']),
      palletizingLineName: _asString(json['palletizingLineName']),
      thermoformingShiftLineId: _asInt(json['thermoformingShiftLineId']),
      fromLocation: _asString(json['fromLocation']),
      toLocation: _asString(json['toLocation']),
      currentLocation: _asString(json['currentLocation']),
      movedAt: _asInstant(json['movedAt']),
      movedAtDisplay: _asString(json['movedAtDisplay']),
      movedByName: _asString(json['movedByName']),
      producedByPalletizerName: _asString(json['producedByPalletizerName']),
      inherited: _asBool(json['inherited']),
      replayed: _asBool(json['replayed']),
      movementUndone: _asBool(json['movementUndone']),
    );
  }
}

class ProductionPendingPalletModel extends ProductionPendingPallet {
  const ProductionPendingPalletModel({
    required super.palletId,
    required super.scannedValue,
    super.productTypeId,
    super.productTypeName,
    super.thermoformingShiftLineId,
    super.currentLocation,
    super.producedAt,
    super.producedAtDisplay,
    super.palletizerName,
    super.inherited,
  });

  factory ProductionPendingPalletModel.fromJson(Map<String, dynamic> json) {
    return ProductionPendingPalletModel(
      palletId: _asInt(json['palletId']) ?? 0,
      scannedValue: _asString(json['scannedValue']) ?? '',
      productTypeId: _asInt(json['productTypeId']),
      productTypeName: _asString(json['productTypeName']),
      thermoformingShiftLineId: _asInt(json['thermoformingShiftLineId']),
      currentLocation: _asString(json['currentLocation']),
      producedAt: _asInstant(json['producedAt']),
      producedAtDisplay: _asString(json['producedAtDisplay']),
      palletizerName: _asString(json['palletizerName']),
      inherited: _asBool(json['inherited']),
    );
  }

  static List<ProductionPendingPallet> listFrom(Object? raw) => [
    for (final item in _asMaps(raw))
      ProductionPendingPalletModel.fromJson(item),
  ];
}

class ProductionPendingLineModel extends ProductionPendingLine {
  const ProductionPendingLineModel({
    super.palletizerSessionId,
    required super.palletizingLineId,
    super.palletizingLineName,
    super.thermoformingShiftLineId,
    required super.pendingCount,
    super.pallets,
  });

  /// A `lines[]` entry of the pending list, or a `blockedLines[]` entry of the
  /// logout refusal (which names its count `count`).
  factory ProductionPendingLineModel.fromJson(Map<String, dynamic> json) {
    final pallets = ProductionPendingPalletModel.listFrom(json['pallets']);
    return ProductionPendingLineModel(
      palletizerSessionId: _asInt(json['palletizerSessionId']),
      palletizingLineId: _asInt(json['palletizingLineId']) ?? 0,
      palletizingLineName: _asString(json['palletizingLineName']),
      thermoformingShiftLineId: _asInt(json['thermoformingShiftLineId']),
      pendingCount:
          _asInt(json['pendingCount']) ??
          _asInt(json['count']) ??
          pallets.length,
      pallets: pallets,
    );
  }
}

class ProductionPendingPalletsModel extends ProductionPendingPallets {
  const ProductionPendingPalletsModel({
    required super.totalPendingCount,
    required super.lines,
  });

  factory ProductionPendingPalletsModel.fromJson(Map<String, dynamic> json) {
    final lines = [
      for (final line in _asMaps(json['lines']))
        ProductionPendingLineModel.fromJson(line),
    ];
    return ProductionPendingPalletsModel(
      totalPendingCount:
          _asInt(json['totalPendingCount']) ??
          lines.fold<int>(0, (sum, l) => sum + l.pendingCount),
      lines: lines,
    );
  }
}

abstract final class ProductionPalletBlockersModel {
  static const String createBlockedCode = 'PREVIOUS_PALLET_STILL_AT_PRODUCTION';
  static const String logoutBlockedCode =
      'PALLETIZER_LOGOUT_BLOCKED_BY_PRODUCTION_PALLETS';

  /// Parses the `details` of either refusal; `null` for any other code.
  /// [lineId] / [lineName] fill in the line of a create refusal, whose
  /// details carry no line of their own.
  static ProductionPalletBlockers? fromError({
    required String code,
    required Map<String, dynamic>? details,
    int? lineId,
    String? lineName,
  }) {
    final d = details ?? const <String, dynamic>{};
    switch (code) {
      case createBlockedCode:
        final pallets = ProductionPendingPalletModel.listFrom(
          d['blockingPallets'],
        );
        final count = _asInt(d['blockingPalletCount']) ?? pallets.length;
        return ProductionPalletBlockers(
          totalCount: count,
          productTypeId: _asInt(d['productTypeId']),
          lines: [
            ProductionPendingLine(
              palletizingLineId: lineId ?? 0,
              palletizingLineName: lineName,
              thermoformingShiftLineId: _asInt(d['thermoformingShiftLineId']),
              pendingCount: count,
              pallets: pallets,
            ),
          ],
        );
      case logoutBlockedCode:
        final lines = [
          for (final line in _asMaps(d['blockedLines']))
            ProductionPendingLineModel.fromJson(line),
        ];
        return ProductionPalletBlockers(
          totalCount:
              _asInt(d['pendingProductionPalletCount']) ??
              lines.fold<int>(0, (sum, l) => sum + l.pendingCount),
          lines: lines,
        );
      default:
        return null;
    }
  }
}
