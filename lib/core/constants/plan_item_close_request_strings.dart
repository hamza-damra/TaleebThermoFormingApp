/// Arabic copy for the plan-item close handshake (V190), verbatim from the
/// Palletizing handoff Appendix C. Shared by the provider (inline decision
/// errors) and the dialogs / banner.
abstract final class PlanItemCloseRequestStrings {
  // ── Blocking decision dialog (WAITING_FOR_PALLETIZER_DECISION) ──
  static const String dialogTitle = 'طلب إنهاء البند الحالي';
  static const String dialogBody =
      'المشغل يريد إنهاء البند الحالي.\n'
      'هل تم تسجيل جميع الطبليات المنتجة لهذا البند؟';
  static const String confirmAllAction = 'نعم، تم تسجيل جميع الطبليات';
  static const String morePalletsAction = 'لا، بقيت طبليات للتسجيل';

  // ── Persistent banner (PALLETIZER_COMPLETING_PALLETS) ──
  static const String bannerTitle = 'البند بانتظار الإنهاء';
  static const String bannerBody =
      'أكمل تسجيل الطبليات المتبقية ثم أكد اكتمال التسجيل.';
  static const String bannerAction = 'تم تسجيل جميع الطبليات';

  // ── Final confirmation (from the banner) ──
  static const String finalConfirmTitle = 'تأكيد اكتمال التسجيل';
  static const String finalConfirmBody =
      'هل تم تسجيل جميع الطبليات المنتجة للبند الحالي؟\n'
      'بعد التأكيد سيتم إنهاء البند والانتقال للبند التالي.';
  static const String finalConfirmCancel = 'إلغاء';
  static const String finalConfirmAction = 'تأكيد وإنهاء البند';

  // ── Context lines (values come from the backend response only) ──
  static const String productLabel = 'المنتج';
  static const String producedLabel = 'الكمية المنتجة';
  static const String requestedByLabel = 'طلب المشغل';

  // ── One-shot notices ──
  static const String confirmedNotice = 'تم إنهاء البند والانتقال للبند التالي';
  static const String cancelledNotice = 'ألغى المشغل طلب إنهاء البند';
  static const String noLongerValidNotice = 'لم يعد طلب إنهاء البند قائماً';

  // ── Inline decision errors (the request stays pending) ──
  static const String linePaused = 'الخط متوقف من الإدارة';
  static const String conflictRetry = 'تعذّر تنفيذ الطلب مؤقتاً، حاول مرة أخرى';
  static const String genericFailure = 'تعذّر تنفيذ الطلب، حاول مرة أخرى';
}
