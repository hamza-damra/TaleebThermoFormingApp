/// Arabic copy for the grinding recommendation at pallet creation (Unified
/// Grinding Lifecycle), verbatim from
/// docs/PALLETIZING_GRINDING_RECOMMENDATION_HANDOFF.md §10. The label marker
/// itself is never spelled here — it is printed from the backend's
/// `grindingLabelText`.
abstract final class GrindingRecommendationStrings {
  /// Backend limit on the recommendation reason (`@Size(max = 500)`).
  static const int reasonMaxLength = 500;

  // ── Create pallet dialog ──
  static const String switchLabel = 'توصية بالجرش';
  static const String reasonLabel = 'سبب التوصية بالجرش';
  static const String reasonRequired = 'سبب التوصية بالجرش مطلوب.';
  static const String reasonTooLong = 'يجب ألا يتجاوز السبب 500 حرف.';

  // ── After a successful create ──
  static const String sentNotice = 'تم إرسال توصية الجرش للمدير';

  // ── Reprint refused (labelReprintAllowed=false / 409) ──
  static const String reprintBlocked =
      'الطبلية قيد الجرش أو تم جرشها — لا يمكن إعادة طباعة الملصق.';

  /// Inline error for [reason], or `null` when it can be sent. Mirrors the
  /// backend rule: trimmed, non-blank, at most [reasonMaxLength] characters.
  static String? validateReason(String reason) {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) return reasonRequired;
    if (trimmed.length > reasonMaxLength) return reasonTooLong;
    return null;
  }
}
