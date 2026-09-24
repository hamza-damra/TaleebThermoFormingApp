import '../../domain/entities/grinding_order_summary.dart';

class GrindingOrderSummaryModel extends GrindingOrderSummary {
  const GrindingOrderSummaryModel({
    required super.id,
    required super.orderNumber,
    required super.status,
    super.statusLabel,
    super.sourceType,
    super.sourceOrigin,
    super.creationBasis,
    super.managerApprovalRequired,
    super.legacy,
  });

  /// Tolerant parser — the block is absent for a normal pallet and every
  /// field is optional on the wire (`@JsonInclude(NON_NULL)`). A block
  /// missing its id or status is treated as "no order" rather than failing
  /// the create success path.
  static GrindingOrderSummaryModel? tryFromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    final status = raw['status'];
    if (id is! int || status is! String) return null;
    return GrindingOrderSummaryModel(
      id: id,
      orderNumber: raw['orderNumber'] as String? ?? '',
      status: status,
      statusLabel: raw['statusLabel'] as String?,
      sourceType: raw['sourceType'] as String?,
      sourceOrigin: raw['sourceOrigin'] as String?,
      creationBasis: raw['creationBasis'] as String?,
      managerApprovalRequired: raw['managerApprovalRequired'] as bool? ?? false,
      legacy: raw['legacy'] as bool? ?? false,
    );
  }
}
