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
    final rawError = json['error'];
    if (rawError is Map<String, dynamic>) {
      return ApiException(
        code: rawError['code'] as String? ?? 'UNKNOWN_ERROR',
        message: rawError['message'] as String? ?? 'حدث خطأ غير متوقع',
        details: rawError['details'] is Map<String, dynamic>
            ? rawError['details'] as Map<String, dynamic>
            : null,
        statusCode: statusCode,
      );
    }
    if (rawError is String && rawError.isNotEmpty) {
      return ApiException(
        code: json['code'] as String? ?? 'UNKNOWN_ERROR',
        message: rawError,
        statusCode: statusCode,
      );
    }
    final topMessage = json['message'];
    if (topMessage is String && topMessage.isNotEmpty) {
      return ApiException(
        code: json['code'] as String? ?? 'UNKNOWN_ERROR',
        message: topMessage,
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
      // Safety-net: any old build that still calls POST /handover hits this.
      // Should never fire after the worker UI cleanup is complete.
      case 'LINE_HANDOVER_NOT_ALLOWED_IN_NEW_WORKFLOW':
        return 'تم إيقاف تسليم المناوبة من تطبيق الطبليات';
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
      case 'PALLETIZER_SESSION_REQUIRED':
        return 'انتهت جلسة موظف الطبليات، يرجى تسجيل الدخول مجددًا';
      case 'PALLETIZER_NOT_ALLOWED':
        return 'هذا الموظف غير مصرح له بتسجيل الطبليات';
      case 'NO_ACTIVE_THERMOFORMING_SHIFT_FOR_LINE':
        return 'بانتظار بدء المناوبة من المشغّل';
      case 'FALET_NOT_FOUND':
        return 'الفالت غير موجود';
      case 'FALET_ALREADY_RESOLVED':
        return 'الفالت محلول مسبقاً';
      case 'FALET_LINE_MISMATCH':
        return 'الفالت لا ينتمي لهذا الخط';
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
