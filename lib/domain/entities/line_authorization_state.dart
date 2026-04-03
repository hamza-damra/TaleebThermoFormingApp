import 'operator.dart';

class LineAuthorizationState {
  final int lineId;
  final int lineNumber;
  final bool isAuthorized;
  final Operator? operator;
  final DateTime? authorizedAt;
  final bool isAuthorizing;
  final String? authError;
  final String? authErrorCode;

  const LineAuthorizationState({
    required this.lineId,
    required this.lineNumber,
    this.isAuthorized = false,
    this.operator,
    this.authorizedAt,
    this.isAuthorizing = false,
    this.authError,
    this.authErrorCode,
  });

  LineAuthorizationState copyWith({
    int? lineId,
    int? lineNumber,
    bool? isAuthorized,
    Operator? operator,
    DateTime? authorizedAt,
    bool? isAuthorizing,
    String? authError,
    String? authErrorCode,
    bool clearOperator = false,
    bool clearAuthorizedAt = false,
    bool clearAuthError = false,
  }) {
    return LineAuthorizationState(
      lineId: lineId ?? this.lineId,
      lineNumber: lineNumber ?? this.lineNumber,
      isAuthorized: isAuthorized ?? this.isAuthorized,
      operator: clearOperator ? null : (operator ?? this.operator),
      authorizedAt:
          clearAuthorizedAt ? null : (authorizedAt ?? this.authorizedAt),
      isAuthorizing: isAuthorizing ?? this.isAuthorizing,
      authError: clearAuthError ? null : (authError ?? this.authError),
      authErrorCode: clearAuthError ? null : (authErrorCode ?? this.authErrorCode),
    );
  }

  factory LineAuthorizationState.unauthorized({
    required int lineId,
    required int lineNumber,
  }) {
    return LineAuthorizationState(
      lineId: lineId,
      lineNumber: lineNumber,
      isAuthorized: false,
    );
  }
}
