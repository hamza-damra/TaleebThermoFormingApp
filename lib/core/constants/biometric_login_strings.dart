/// Arabic copy for the fingerprint dialog of the biometric login gate,
/// verbatim from docs/FRONTEND_HANDOFF_PALLETIZING_APP_BIOMETRIC_LOGIN_GATE.md
/// §10. The server `message` of a 403 is always shown as-is; these strings are
/// only the dialog chrome and the states the server does not word.
abstract final class BiometricLoginStrings {
  static const String dialogTitle = 'التحقق بالبصمة';
  static const String waiting = 'مرّر إصبعك على جهاز البصمة';
  static const String waitingSecondary =
      'سيكتمل تسجيل الدخول تلقائيًا بعد التحقق';
  static const String verifying = 'جارٍ تسجيل الدخول…';
  static const String deviceOffline =
      'جهاز البصمة غير متصل حاليًا. انتظر قليلًا أو أبلغ المسؤول.';
  static const String retry =
      'انتهت مهلة المحاولة. مرّر البصمة ثم أعد المحاولة.';
  static const String network = 'تعذّر الاتصال بالخادم، جارٍ إعادة المحاولة…';

  static const String cancelAction = 'إلغاء';
  static const String retryAction = 'إعادة المحاولة';
  static const String okAction = 'حسنًا';

  // ── Server messages (§10), used only when a status answer reports a
  // mapping problem — the status payload carries no message of its own. ──
  static const String serverMappingMissing =
      'لم يتم ربط بصمتك بحسابك بعد. يرجى مراجعة مسؤول النظام.';
  static const String serverMappingDisabled =
      'ربط البصمة الخاص بحسابك غير مفعّل. يرجى مراجعة مسؤول النظام.';
  static const String serverLoginAttemptExpired =
      'انتهت مهلة محاولة الدخول. يرجى تسجيل الدخول مرة أخرى.';
}
