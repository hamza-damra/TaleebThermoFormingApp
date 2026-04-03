import '../../domain/entities/session_table_row.dart';

class SessionTableRowModel extends SessionTableRow {
  const SessionTableRowModel({
    required super.productTypeId,
    required super.productTypeName,
    required super.completedPalletCount,
    required super.completedPackageCount,
    required super.loosePackageCount,
  });

  factory SessionTableRowModel.fromJson(Map<String, dynamic> json) {
    return SessionTableRowModel(
      productTypeId: json['productTypeId'] as int,
      productTypeName: json['productTypeName'] as String,
      completedPalletCount: json['completedPalletCount'] as int? ?? 0,
      completedPackageCount: json['completedPackageCount'] as int? ?? 0,
      loosePackageCount: json['loosePackageCount'] as int? ?? 0,
    );
  }
}
