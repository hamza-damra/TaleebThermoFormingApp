import 'palletizer_session.dart';

class PalletizerSessionState {
  final int lineNumber;
  final PalletizerSession? session;
  final bool isAuthenticating;
  final String? authError;
  final String? authErrorCode;

  const PalletizerSessionState({
    required this.lineNumber,
    this.session,
    this.isAuthenticating = false,
    this.authError,
    this.authErrorCode,
  });

  bool get hasActiveSession => session != null && session!.isActive;

  PalletizerSessionState copyWith({
    PalletizerSession? session,
    bool? isAuthenticating,
    String? authError,
    String? authErrorCode,
    bool clearSession = false,
    bool clearAuthError = false,
  }) {
    return PalletizerSessionState(
      lineNumber: lineNumber,
      session: clearSession ? null : (session ?? this.session),
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      authError: clearAuthError ? null : (authError ?? this.authError),
      authErrorCode: clearAuthError
          ? null
          : (authErrorCode ?? this.authErrorCode),
    );
  }

  factory PalletizerSessionState.empty(int lineNumber) =>
      PalletizerSessionState(lineNumber: lineNumber);
}
