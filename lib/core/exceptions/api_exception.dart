class ApiException implements Exception {
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  final int? statusCode;

  ApiException({
    required this.code,
    required this.message,
    this.details,
    this.statusCode,
  });

  factory ApiException.fromJson(Map<String, dynamic> json, {int? statusCode}) {
    final error = json['error'] as Map<String, dynamic>?;
    if (error != null) {
      return ApiException(
        code: error['code'] as String? ?? 'UNKNOWN_ERROR',
        message: error['message'] as String? ?? 'حدث خطأ غير متوقع',
        details: error['details'] as Map<String, dynamic>?,
        statusCode: statusCode,
      );
    }
    return ApiException(
      code: 'UNKNOWN_ERROR',
      message: 'حدث خطأ غير متوقع',
      statusCode: statusCode,
    );
  }

  factory ApiException.network() {
    return ApiException(
      code: 'NETWORK_ERROR',
      message: 'فشل الاتصال بالخادم. تحقق من اتصالك بالإنترنت',
    );
  }

  factory ApiException.timeout() {
    return ApiException(
      code: 'TIMEOUT_ERROR',
      message: 'انتهت مهلة الاتصال. حاول مرة أخرى',
    );
  }

  factory ApiException.unauthorized() {
    return ApiException(
      code: 'UNAUTHORIZED',
      message: 'انتهت صلاحية المناوبة. يرجى تسجيل الدخول مرة أخرى',
      statusCode: 401,
    );
  }

  String get displayMessage {
    switch (code) {
      case 'OPERATOR_NOT_FOUND':
        return 'المشغل غير موجود';
      case 'OPERATOR_INACTIVE':
        return 'المشغل غير نشط';
      case 'PRODUCT_TYPE_NOT_FOUND':
        return 'نوع المنتج غير موجود';
      case 'PRODUCT_TYPE_INACTIVE':
        return 'نوع المنتج غير نشط';
      case 'PRODUCTION_LINE_NOT_FOUND':
        return 'خط الإنتاج غير موجود';
      case 'PRODUCTION_LINE_INACTIVE':
        return 'خط الإنتاج غير نشط';
      case 'PALLET_NOT_FOUND':
        return 'الطبلية غير موجودة';
      case 'SERIAL_GENERATION_FAILED':
        return 'فشل في توليد الرقم التسلسلي';
      case 'VALIDATION_ERROR':
        return _formatValidationErrors();
      case 'AUTH_INVALID_CREDENTIALS':
        return 'بيانات الدخول غير صحيحة';
      case 'EMPLOYEE_CODE_NOT_FOUND':
        return 'رمز الموظف غير صحيح';
      case 'USER_DISABLED':
        return 'الحساب معطل، تواصل مع الإدارة';
      case 'ROLE_NOT_ELIGIBLE_FOR_PIN_LOGIN':
        return 'هذا الحساب غير مصرح له';
      case 'ROLE_NOT_ALLOWED':
        return 'ليس لديك صلاحية استخدام هذا التطبيق';
      case 'SHIFT_PROFILE_NOT_FOUND':
        return 'لم يتم العثور على جدول المناوبات';
      case 'OPERATOR_PIN_INVALID':
        return 'رمز المشغل غير صحيح';
      case 'OPERATOR_PIN_LOCKED':
        return 'تم قفل الحساب بسبب محاولات متعددة. حاول لاحقاً';
      case 'INVALID_PIN_FORMAT':
        return 'صيغة الرمز غير صحيحة. يجب أن يكون 4 أرقام';
      case 'LINE_NOT_AUTHORIZED':
        return 'لا يوجد مشغل مصرح على هذا الخط';
      case 'LINE_BLOCKED_BY_PENDING_HANDOVER':
        return 'الخط محظور بسبب تسليم معلق';
      case 'PALLET_LINE_MISMATCH':
        return 'الطبلية لا تنتمي لهذا الخط';
      case 'PENDING_LINE_HANDOVER_EXISTS':
        return 'يوجد تسليم معلق بالفعل لهذا الخط';
      case 'LINE_HANDOVER_NOT_FOUND':
        return 'لم يتم العثور على التسليم';
      case 'LINE_HANDOVER_ALREADY_RESOLVED':
        return 'تم معالجة هذا التسليم مسبقاً';
      case 'INVALID_LOOSE_BALANCE':
        return 'عدد العبوات الفالتة غير صحيح';
      case 'INSUFFICIENT_LOOSE_BALANCE':
        return 'الكمية الفالتة غير كافية';
      case 'LOOSE_BALANCE_NOT_FOUND':
        return 'لا يوجد رصيد فالت لهذا المنتج';
      case 'INCOMPLETE_PALLET_NOT_FOUND':
        return 'لا يوجد طبلية ناقصة معلقة';
      case 'INCOMPLETE_PALLET_ALREADY_RESOLVED':
        return 'تم معالجة الطبلية الناقصة مسبقاً';
      case 'PRODUCT_ALREADY_SELECTED':
        return 'تم اختيار منتج بالفعل — استخدم تبديل المنتج';
      case 'NO_CURRENT_PRODUCT':
        return 'لا يوجد منتج محدد — يجب اختيار منتج أولاً';
      case 'CURRENT_PRODUCT_MISMATCH':
        return 'تم تغيير المنتج من جهاز آخر';
      case 'SAME_PRODUCT_SWITCH':
        return 'لا يمكن التبديل إلى نفس المنتج';
      // ── Handover FALET reconciliation errors ──
      case 'HANDOVER_FALET_DECISION_REQUIRED':
        return 'يجب حل جميع عناصر الفالت المفتوحة قبل التسليم';
      case 'HANDOVER_FALET_DECISION_MISSING':
        return 'قرار مفقود لبعض عناصر الفالت';
      case 'HANDOVER_FALET_DECISION_DUPLICATE':
        return 'عنصر فالت مكرر';
      case 'HANDOVER_FALET_INVALID_ACTION':
        return 'إجراء غير صالح';
      case 'HANDOVER_FALET_PALLETE_REQUIRED':
        return 'اختر طبلية للضم';
      case 'HANDOVER_FALET_PALLETE_NOT_FOUND':
        return 'الطبلية المحددة غير موجودة';
      case 'HANDOVER_FALET_PALLETE_WRONG_SESSION':
        return 'الطبلية من مناوبة مختلفة';
      case 'HANDOVER_FALET_PALLETE_WRONG_LINE':
        return 'الطبلية من خط مختلف';
      case 'HANDOVER_FALET_PALLETE_CANCELLED':
        return 'تم إلغاء الطبلية';
      case 'HANDOVER_FALET_PALLETE_PRODUCT_MISMATCH':
        return 'نوع المنتج غير متطابق';
      case 'HANDOVER_FALET_QUANTITY_EXCEEDS_PALLETE':
        return 'الكمية تتجاوز سعة الطبلية';
      case 'HANDOVER_FALET_NO_SESSION_PRODUCTION':
        return 'لا يوجد إنتاج نشط في هذه المناوبة لنوع المنتج. لا يمكن اعتبار الفالت محسوباً.';
      case 'NO_ACTIVE_PRODUCT_FOR_UNDECLARED_FALET':
        return 'لا يوجد منتج نشط على الخط';
      case 'FALET_NOT_FOUND':
        return 'الفالت غير موجود';
      case 'FALET_ALREADY_RESOLVED':
        return 'الفالت محلول مسبقاً';
      case 'FALET_LINE_MISMATCH':
        return 'الفالت لا ينتمي لهذا الخط';
      case 'FALET_MUST_BE_CONSUMED_FIRST':
        return 'يوجد فالت مفتوح لهذا المنتج يجب استهلاكه أولاً';
      case 'FALET_DISPUTE_NOT_FOUND':
        return 'النزاع غير موجود';
      case 'FALET_DISPUTE_ALREADY_RESOLVED':
        return 'تم حل هذا النزاع مسبقاً';
      case 'FALET_DISPUTE_ITEM_NOT_FOUND':
        return 'عنصر النزاع غير موجود';
      case 'FALET_DISPUTE_ITEM_FULLY_RESOLVED':
        return 'عنصر النزاع محلول بالكامل';
      case 'FALET_DISPUTE_QUANTITY_EXCEEDS_REMAINING':
        return 'الكمية تتجاوز المتبقي';
      case 'FALET_DISPUTE_NO_ACTIVE_AUTH_FOR_PALLETIZE':
        return 'يتطلب تفويض نشط للتنصيب';
      // ── Handover rejection strict-validation errors ──
      case 'HANDOVER_OBSERVATION_SNAPSHOT_MISMATCH':
        return 'بيانات التسليم قديمة، يرجى تحديث الصفحة والمحاولة مرة أخرى.';
      case 'HANDOVER_OBSERVATION_DUPLICATE':
        return 'تم إرسال نفس بند الفالت أكثر من مرة.';
      case 'HANDOVER_OBSERVATION_MISSING':
        return 'يجب تحديد الكمية المرصودة لكل بند فالت.';
      case 'HANDOVER_OBSERVED_QUANTITY_INVALID':
        return 'الكمية المرصودة غير صحيحة.';
      case 'HANDOVER_INCORRECT_QUANTITY_NO_MISMATCH':
        return 'الكمية المرصودة تطابق الكمية المصرح عنها. لا يمكن الرفض.';
      case 'HANDOVER_REJECTION_REASON_INVALID':
        return 'سبب الرفض غير كافٍ. يجب اختيار مشكلة كمية أو فالت غير مصرح عنه.';
      case 'FALET_STATE_NOT_AVAILABLE_FOR_REJECTION':
        return 'حالة الفالت تغيرت، يرجى تحديث بيانات الخط.';
      case 'INTERNAL_ERROR':
        return 'حدث خطأ في الخادم. حاول مرة أخرى';
      default:
        return message;
    }
  }

  String _formatValidationErrors() {
    if (details == null || details!.isEmpty) {
      return message;
    }
    return details!.values.join('\n');
  }

  @override
  String toString() => 'ApiException: [$code] $message';
}
