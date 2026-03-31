class PrintingException implements Exception {
  final String code;
  final String message;
  final dynamic originalError;

  PrintingException({
    required this.code,
    required this.message,
    this.originalError,
  });

  factory PrintingException.noPrinterSelected() {
    return PrintingException(
      code: 'NO_PRINTER_SELECTED',
      message: 'لم يتم اختيار طابعة',
    );
  }

  factory PrintingException.noPresetSelected() {
    return PrintingException(
      code: 'NO_PRESET_SELECTED',
      message: 'لم يتم اختيار حجم الملصق',
    );
  }

  factory PrintingException.connectionFailed({dynamic error}) {
    return PrintingException(
      code: 'CONNECTION_FAILED',
      message: 'فشل الاتصال بالطابعة',
      originalError: error,
    );
  }

  factory PrintingException.connectionTimeout() {
    return PrintingException(
      code: 'CONNECTION_TIMEOUT',
      message: 'انتهت مهلة الاتصال بالطابعة',
    );
  }

  factory PrintingException.sendFailed({dynamic error}) {
    return PrintingException(
      code: 'SEND_FAILED',
      message: 'فشل إرسال البيانات للطابعة',
      originalError: error,
    );
  }

  factory PrintingException.renderFailed({dynamic error}) {
    return PrintingException(
      code: 'RENDER_FAILED',
      message: 'فشل في إنشاء صورة الباركود',
      originalError: error,
    );
  }

  factory PrintingException.printerNotFound(String printerId) {
    return PrintingException(
      code: 'PRINTER_NOT_FOUND',
      message: 'الطابعة غير موجودة',
    );
  }

  factory PrintingException.presetNotFound(String presetId) {
    return PrintingException(
      code: 'PRESET_NOT_FOUND',
      message: 'حجم الملصق غير موجود',
    );
  }

  String get displayMessage => message;

  @override
  String toString() => 'PrintingException: [$code] $message';
}
