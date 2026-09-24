import 'palletizer_session.dart';

class PalletizerSessionState {
  final int lineId;
  final PalletizerSession? session;
  final bool isAuthenticating;
  final String? authError;
  final String? authErrorCode;

  const PalletizerSessionState({
    required this.lineId,
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
      lineId: lineId,
      session: clearSession ? null : (session ?? this.session),
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      authError: clearAuthError ? null : (authError ?? this.authError),
      authErrorCode: clearAuthError
          ? null
          : (authErrorCode ?? this.authErrorCode),
    );
  }

  factory PalletizerSessionState.empty(int lineId) =>
      PalletizerSessionState(lineId: lineId);
}
