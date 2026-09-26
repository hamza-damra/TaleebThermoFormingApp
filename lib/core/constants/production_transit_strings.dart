/// Arabic copy for the PRODUCTION → TRANSIT («الرصيف») move (V210), verbatim
/// from docs/FRONTEND_HANDOFF_PALLETIZING_APP_PRODUCTION_TO_TRANSIT_MOVE.md
/// §3.3 and §7. The location is `TRANSIT` in the API; the label stays
/// «الرصيف».
abstract final class ProductionTransitStrings {
  // ── §7 keys ──
  static const String action = 'نقل إلى الرصيف';
  static const String manualEntry = 'إدخال يدوي';
  static const String inheritedChip = 'موروثة من وردية سابقة';
  static const String success = 'تم نقل الطبلية إلى الرصيف';
  static const String replayUndone = 'أُعيدت الطبلية إلى خط الإنتاج';
  static const String createBlocked =
      'لا يمكن تسجيل طبلية جديدة من نفس المنتج قبل نقل الطبلية السابقة إلى الرصيف';
  static const String logoutBlocked =
      'لا يمكن تسجيل الخروج قبل نقل جميع الطبليات إلى الرصيف';

  // ── §3.3 refusals ──
  static const String identifierInvalid = 'رقم الطبلية غير صالح';
  static const String notFound = 'لا توجد طبلية بهذا الرقم';
  static const String cancelled = 'هذه الطبلية ملغاة';
  static const String blockedByGrinding = 'الطبلية محجوزة للجرش';
  static const String outsideLineScope = 'هذه الطبلية ليست من خطوطك الحالية';
  static const String outsideOperatorShift = 'هذه الطبلية من وردية مشغّل أخرى';
  static const String notAtProduction = 'الطبلية ليست في خط الإنتاج';
  static const String requestVoided = 'تم حذف الحركة من الإدارة';
  static const String requestVoidedScanAgain =
      'الطبلية ما زالت في خط الإنتاج — امسحها مرة أخرى لنقلها.';
  static const String sessionRequired =
      'انتهت جلسة موظف الطبليات، يرجى تسجيل الدخول مجددًا';
  static const String connectionFailed =
      'تعذّر الاتصال بالخادم. أعد المحاولة — لن تُسجَّل الحركة مرتين.';
  static const String genericFailure = 'تعذّر نقل الطبلية، حاول مرة أخرى';

  // ── Screens / dialogs ──
  static const String scanHint = 'وجّه الكاميرا نحو رمز QR على الطبلية';
  static const String cameraUnavailable =
      'تعذّر تشغيل الكاميرا. استخدم الإدخال اليدوي.';
  static const String cameraPermissionDenied =
      'لا توجد صلاحية لاستخدام الكاميرا. استخدم الإدخال اليدوي أو فعّل الصلاحية من إعدادات الجهاز.';
  static const String backToCamera = 'العودة إلى الكاميرا';
  static const String palletNumberLabel = 'رقم الطبلية';
  static const String palletNumberHint = '12 رقماً';
  static const String palletNumberRequired = 'يرجى إدخال رقم الطبلية';
  static const String palletNumberLength = 'رقم الطبلية يجب أن يكون 12 رقماً';
  static const String submit = 'نقل';
  static const String moving = 'جارٍ النقل…';
  static const String retry = 'إعادة المحاولة';
  static const String scanAgain = 'مسح مرة أخرى';
  static const String scanNext = 'مسح طبلية أخرى';
  static const String close = 'إغلاق';
  static const String cancel = 'إلغاء';
  static const String moved = 'تم النقل';
  static const String currentLocationLabel = 'الموقع الحالي';
  static const String productLabel = 'المنتج';
  static const String lineLabel = 'الخط';
  static const String producedAtLabel = 'وقت الإنتاج';
  static const String palletizerLabel = 'موظف الطبليات';
  static const String movedAtLabel = 'وقت النقل';
  static const String movedByLabel = 'نقلها';
  static const String createRetry = 'تسجيل الطبلية الآن';
  static const String logoutRetry = 'مغادرة الآن';

  // ── Scan of one selected blocking pallet ──
  static const String scanSelectedTitle = 'نقل الطبلية المطلوبة';
  static const String scanSelectedHint =
      'امسح رمز QR على الطبلية المطلوبة، أو أدخل رقمها يدوياً.';
  static const String selectedPalletLabel = 'الطبلية المطلوبة';
  static const String scannedPalletLabel = 'الطبلية الممسوحة';
  static const String identifierMismatch =
      'الرقم الممسوح لا يطابق الطبلية المطلوبة. لم يتم نقل أي طبلية.';

  // ── Blocking dialog states ──
  static const String remainingLabel = 'المتبقي';
  static const String checkingStatus = 'جارٍ التحقق من حالة الطبليات…';
  static const String checkFailed =
      'تعذّر التحقق من حالة الطبليات من الخادم. أعد المحاولة.';
  static const String allResolved =
      'لم تعد هناك طبليات تمنع المتابعة — يمكنك المتابعة الآن.';
  static const String verifying = 'جارٍ التحقق…';
  static const String leftProduction = 'لم تعد في خط الإنتاج';
  static const String checkAgain = 'تحقق مجدداً';

  // ── Shift production detail ──
  static const String movedToTransitBadge = 'تم النقل إلى الرصيف';

  /// «الرصيف» for `TRANSIT`, the backend's Arabic label for every other
  /// destination, or the raw value when unknown.
  static String locationLabel(String? location) => switch (location) {
    'TRANSIT' => 'الرصيف',
    'PRODUCTION' => 'خط الإنتاج',
    'WAREHOUSE_1' => 'مستودع 1',
    'WAREHOUSE_2' => 'مستودع 2',
    'DIRECT_OUT' => 'خروج مباشر',
    'OUT' => 'خارج',
    'RECYCLE' => 'إعادة تدوير',
    'REPRODUCTION' => 'إعادة إنتاج',
    null || '' => '—',
    _ => location,
  };
}
