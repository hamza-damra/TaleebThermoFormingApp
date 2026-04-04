import 'package:flutter/foundation.dart';

import '../../core/exceptions/api_exception.dart';
import '../../domain/entities/complete_incomplete_pallet_response.dart';
import '../../domain/entities/line_authorization_state.dart';
import '../../domain/entities/line_handover_info.dart';
import '../../domain/entities/open_items_response.dart';
import '../../domain/entities/operator.dart';
import '../../domain/entities/pallet_create_response.dart';
import '../../domain/entities/produce_pallet_from_loose_response.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/entities/production_line.dart';
import '../../domain/entities/session_table_row.dart';
import '../../domain/repositories/palletizing_repository.dart';

enum PalletizingState { idle, loading, loaded, error }

class PalletizingProvider extends ChangeNotifier {
  final PalletizingRepository _repository;

  PalletizingProvider(this._repository);

  // ── Global state ──
  PalletizingState _state = PalletizingState.idle;
  String? _errorMessage;

  // ── Reference data ──
  List<ProductType> _productTypes = [];
  List<ProductionLine> _productionLines = [];

  // ── Per-line state (keyed by lineNumber) ──
  final Map<int, LineAuthorizationState> _lineAuthorizations = {};
  final Map<int, List<SessionTableRow>> _sessionTables = {};
  final Map<int, ProductType?> _selectedProductTypes = {};
  final Map<int, PalletCreateResponse?> _lastPalletResponses = {};
  final Map<int, LineHandoverInfo?> _pendingHandovers = {};
  final Map<int, String?> _blockedReasons = {};
  final Map<int, bool> _lineCreating = {};
  final Map<int, String?> _lineErrors = {};
  final Map<int, bool> _lineSwitchingProduct = {};
  final Map<int, String?> _lineUiModes = {};
  final Map<int, bool> _canInitiateHandovers = {};
  final Map<int, bool> _canConfirmHandovers = {};
  final Map<int, bool> _canRejectHandovers = {};
  final Map<int, OpenItemsResponse?> _openItems = {};
  final Map<int, bool> _openItemsLoading = {};

  // ── Global getters ──
  PalletizingState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == PalletizingState.loading;
  List<ProductType> get productTypes => _productTypes;
  List<ProductionLine> get productionLines => _productionLines;

  // Backward compat: global isCreating (true if ANY line is creating)
  bool get isCreating => _lineCreating.values.any((v) => v);

  // ── Per-line getters ──

  LineAuthorizationState? getLineAuth(int lineNumber) =>
      _lineAuthorizations[lineNumber];

  bool isLineAuthorized(int lineNumber) =>
      _lineAuthorizations[lineNumber]?.isAuthorized ?? false;

  bool isLineAuthorizing(int lineNumber) =>
      _lineAuthorizations[lineNumber]?.isAuthorizing ?? false;

  Operator? getAuthorizedOperator(int lineNumber) =>
      _lineAuthorizations[lineNumber]?.operator;

  List<SessionTableRow> getSessionTable(int lineNumber) =>
      _sessionTables[lineNumber] ?? [];

  ProductType? getSelectedProductType(int lineNumber) =>
      _selectedProductTypes[lineNumber];

  PalletCreateResponse? getLastPalletResponse(int lineNumber) =>
      _lastPalletResponses[lineNumber];

  LineHandoverInfo? getPendingHandover(int lineNumber) =>
      _pendingHandovers[lineNumber];

  String? getBlockedReason(int lineNumber) => _blockedReasons[lineNumber];

  bool isLineCreating(int lineNumber) => _lineCreating[lineNumber] ?? false;

  String? getLineError(int lineNumber) => _lineErrors[lineNumber];

  bool isLineSwitchingProduct(int lineNumber) =>
      _lineSwitchingProduct[lineNumber] ?? false;

  String? getLineUiMode(int lineNumber) => _lineUiModes[lineNumber];

  bool canInitiateHandover(int lineNumber) =>
      _canInitiateHandovers[lineNumber] ?? false;

  bool canConfirmHandover(int lineNumber) =>
      _canConfirmHandovers[lineNumber] ?? false;

  bool canRejectHandover(int lineNumber) =>
      _canRejectHandovers[lineNumber] ?? false;

  OpenItemsResponse? getOpenItems(int lineNumber) => _openItems[lineNumber];

  bool isOpenItemsLoading(int lineNumber) =>
      _openItemsLoading[lineNumber] ?? false;

  bool isLineBlocked(int lineNumber) {
    final uiMode = _lineUiModes[lineNumber];
    if (uiMode == 'PENDING_HANDOVER_NEEDS_INCOMING') return true;
    if (!isLineAuthorized(lineNumber)) return true;
    if (_pendingHandovers[lineNumber]?.isPending ?? false) return true;
    if (_blockedReasons[lineNumber] != null) return true;
    return false;
  }

  int? getLineIdForNumber(int lineNumber) {
    final line = _productionLines
        .where((l) => l.lineNumber == lineNumber)
        .firstOrNull;
    return line?.id ?? _lineAuthorizations[lineNumber]?.lineId;
  }

  // ── Bootstrap ──

  Future<void> loadBootstrap() async {
    _state = PalletizingState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final bootstrap = await _repository.bootstrap();

      _productTypes = bootstrap.productTypes;
      _productionLines = bootstrap.productionLines;

      // Hydrate per-line state from bootstrap
      for (final lineState in bootstrap.lines) {
        final ln = lineState.lineNumber;

        _lineAuthorizations[ln] = LineAuthorizationState(
          lineId: lineState.lineId,
          lineNumber: ln,
          isAuthorized: lineState.isAuthorized,
          operator: lineState.authorizedOperator,
          authorizedAt: lineState.authorizedAt,
        );

        _sessionTables[ln] = lineState.sessionTable;
        _pendingHandovers[ln] = lineState.pendingHandover;
        _blockedReasons[ln] = lineState.blockedReason;
        _lineUiModes[ln] = lineState.lineUiMode;
        _canInitiateHandovers[ln] = lineState.canInitiateHandover;
        _canConfirmHandovers[ln] = lineState.canConfirmHandover;
        _canRejectHandovers[ln] = lineState.canRejectHandover;

        if (lineState.selectedProductType != null) {
          _selectedProductTypes[ln] = lineState.selectedProductType;
        }
      }

      // Fetch full handover details for lines in review mode.
      // Bootstrap only contains a condensed LineHandoverSummary that lacks
      // incompletePallet and looseBalances — the review screen needs the
      // full LineHandoverResponse from GET /handover/pending.
      for (final lineState in bootstrap.lines) {
        if (lineState.lineUiMode == 'PENDING_HANDOVER_REVIEW') {
          try {
            final fullHandover =
                await _repository.getLineHandover(lineState.lineId);
            if (fullHandover != null) {
              _pendingHandovers[lineState.lineNumber] = fullHandover;
            }
          } catch (e) {
            debugPrint(
              'Failed to fetch full handover details for line ${lineState.lineNumber}: $e',
            );
          }
        }
      }

      _state = PalletizingState.loaded;
    } on ApiException catch (e) {
      _errorMessage = e.displayMessage;
      _state = PalletizingState.error;
      debugPrint(
        'PalletizingProvider bootstrap error: ${e.code} - ${e.message}',
      );
    } catch (e, stackTrace) {
      _errorMessage = 'فشل في تحميل البيانات: $e';
      _state = PalletizingState.error;
      debugPrint('PalletizingProvider bootstrap unexpected error: $e');
      debugPrint('Stack trace: $stackTrace');
    }
    notifyListeners();
  }

  // ── Line Authorization ──

  Future<bool> authorizeLineWithPin(int lineNumber, String pin) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return false;

    // Set authorizing state
    _lineAuthorizations[lineNumber] =
        (_lineAuthorizations[lineNumber] ??
                LineAuthorizationState.unauthorized(
                  lineId: lineId,
                  lineNumber: lineNumber,
                ))
            .copyWith(isAuthorizing: true, clearAuthError: true);
    notifyListeners();

    try {
      final authState = await _repository.authorizeLine(
        lineId: lineId,
        pin: pin,
      );

      _lineAuthorizations[lineNumber] = LineAuthorizationState(
        lineId: authState.lineId,
        lineNumber: lineNumber,
        isAuthorized: authState.isAuthorized,
        operator: authState.operator,
        authorizedAt: authState.authorizedAt,
        isAuthorizing: false,
      );

      // Refresh line data without overwriting the auth state we just set.
      // Do NOT optimistically set lineUiMode — the backend computes the
      // correct mode (e.g. PENDING_HANDOVER_REVIEW when a pending handover
      // exists, not AUTHORIZED).
      await _refreshLineStateFromBackend(
        lineNumber,
        lineId,
        preserveAuth: true,
      );

      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _lineAuthorizations[lineNumber] =
          (_lineAuthorizations[lineNumber] ??
                  LineAuthorizationState.unauthorized(
                    lineId: lineId,
                    lineNumber: lineNumber,
                  ))
              .copyWith(
                isAuthorizing: false,
                authError: e.displayMessage,
                authErrorCode: e.code,
              );
      notifyListeners();
      return false;
    } catch (e) {
      _lineAuthorizations[lineNumber] =
          (_lineAuthorizations[lineNumber] ??
                  LineAuthorizationState.unauthorized(
                    lineId: lineId,
                    lineNumber: lineNumber,
                  ))
              .copyWith(
                isAuthorizing: false,
                authError: 'فشل في التحقق من الرمز',
              );
      notifyListeners();
      return false;
    }
  }

  void clearLineAuthError(int lineNumber) {
    final current = _lineAuthorizations[lineNumber];
    if (current != null) {
      _lineAuthorizations[lineNumber] = current.copyWith(clearAuthError: true);
      notifyListeners();
    }
  }

  /// Revoke line authorization to trigger the PIN overlay again
  void revokeLineAuthorization(int lineNumber) {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;
    _lineAuthorizations[lineNumber] = LineAuthorizationState.unauthorized(
      lineId: lineId,
      lineNumber: lineNumber,
    );
    _lineUiModes[lineNumber] = 'NEEDS_AUTHORIZATION';
    _canInitiateHandovers[lineNumber] = false;
    _canConfirmHandovers[lineNumber] = false;
    _canRejectHandovers[lineNumber] = false;
    notifyListeners();
  }

  // ── Refresh single line state ──

  Future<void> refreshLineState(int lineNumber) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;
    await _refreshLineStateFromBackend(lineNumber, lineId);
    notifyListeners();
  }

  Future<void> _refreshLineStateFromBackend(
    int lineNumber,
    int lineId, {
    bool preserveAuth = false,
  }) async {
    try {
      final lineState = await _repository.getLineState(lineId);

      if (preserveAuth) {
        // Keep the existing auth state (e.g. just-authorized) and only update line data
        final existing = _lineAuthorizations[lineNumber];
        if (existing != null && existing.isAuthorized) {
          _lineAuthorizations[lineNumber] = LineAuthorizationState(
            lineId: existing.lineId,
            lineNumber: lineNumber,
            isAuthorized: existing.isAuthorized,
            operator: existing.operator,
            authorizedAt: existing.authorizedAt,
          );
        }
      } else {
        _lineAuthorizations[lineNumber] = LineAuthorizationState(
          lineId: lineState.lineId,
          lineNumber: lineNumber,
          isAuthorized: lineState.isAuthorized,
          operator: lineState.authorizedOperator,
          authorizedAt: lineState.authorizedAt,
        );
      }

      _sessionTables[lineNumber] = lineState.sessionTable;
      _pendingHandovers[lineNumber] = lineState.pendingHandover;
      _blockedReasons[lineNumber] = lineState.blockedReason;
      _lineUiModes[lineNumber] = lineState.lineUiMode;
      _canInitiateHandovers[lineNumber] = lineState.canInitiateHandover;
      _canConfirmHandovers[lineNumber] = lineState.canConfirmHandover;
      _canRejectHandovers[lineNumber] = lineState.canRejectHandover;

      if (lineState.selectedProductType != null) {
        _selectedProductTypes[lineNumber] = lineState.selectedProductType;
      }

      // In PENDING_HANDOVER_REVIEW mode the line state only contains a
      // summary (LineHandoverSummary) which lacks the nested incompletePallet
      // object and looseBalances array.  Fetch the full handover details so
      // the review card can display complete information.
      if (lineState.lineUiMode == 'PENDING_HANDOVER_REVIEW') {
        try {
          final fullHandover = await _repository.getLineHandover(lineId);
          if (fullHandover != null) {
            _pendingHandovers[lineNumber] = fullHandover;
          }
        } catch (e) {
          debugPrint(
            'Failed to fetch full handover details for line $lineNumber: $e',
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to refresh line $lineNumber state: $e');
    }
  }

  // ── Product selection ──

  void selectProductType(int lineNumber, ProductType? productType) {
    _selectedProductTypes[lineNumber] = productType;
    notifyListeners();
  }

  // ── Product switch with loose balance ──

  Future<bool> switchProduct({
    required int lineNumber,
    required int previousProductTypeId,
    required int looseCount,
  }) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return false;

    _lineSwitchingProduct[lineNumber] = true;
    notifyListeners();

    try {
      final updatedTable = await _repository.switchProduct(
        lineId: lineId,
        previousProductTypeId: previousProductTypeId,
        looseCount: looseCount,
      );

      _sessionTables[lineNumber] = updatedTable;
      _lineSwitchingProduct[lineNumber] = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _lineErrors[lineNumber] = e.displayMessage;
      _lineSwitchingProduct[lineNumber] = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('ProductSwitch error (line $lineNumber): $e');
      _lineErrors[lineNumber] = 'فشل في تبديل المنتج';
      _lineSwitchingProduct[lineNumber] = false;
      notifyListeners();
      return false;
    }
  }

  // ── Create pallet (line-scoped) ──

  Future<PalletCreateResponse?> createPallet({
    required int lineNumber,
    required int productTypeId,
    required int quantity,
  }) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return null;

    _lineCreating[lineNumber] = true;
    _lineErrors[lineNumber] = null;
    notifyListeners();

    try {
      final response = await _repository.createLinePallet(
        lineId: lineId,
        productTypeId: productTypeId,
        quantity: quantity,
      );

      _lastPalletResponses[lineNumber] = response;

      // Update selected product to match the response
      final matchIndex = _productTypes.indexWhere(
        (p) => p.id == response.productType.id,
      );
      _selectedProductTypes[lineNumber] = matchIndex >= 0
          ? _productTypes[matchIndex]
          : response.productType;

      // Refresh line state from backend
      await _refreshLineStateFromBackend(lineNumber, lineId);

      _lineCreating[lineNumber] = false;
      notifyListeners();
      return response;
    } on ApiException catch (e) {
      _lineCreating[lineNumber] = false;
      _lineErrors[lineNumber] = e.displayMessage;
      notifyListeners();
      debugPrint(
        'PalletizingProvider createPallet API error: ${e.code} - ${e.message}',
      );
      rethrow;
    } catch (e) {
      _lineCreating[lineNumber] = false;
      _lineErrors[lineNumber] = 'فشل في إنشاء الطبلية';
      debugPrint('PalletizingProvider createPallet error: $e');
      notifyListeners();
      rethrow;
    }
  }

  // ── Print attempt logging (line-scoped) ──

  Future<bool> logPrintAttempt({
    required int lineNumber,
    required int palletId,
    required String printerIdentifier,
    required bool success,
    String? failureReason,
  }) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return false;

    try {
      await _repository.logLinePrintAttempt(
        lineId: lineId,
        palletId: palletId,
        printerIdentifier: printerIdentifier,
        status: success ? 'SUCCESS' : 'FAILED',
        failureReason: failureReason,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  // ── Line handover ──

  Future<LineHandoverInfo?> createLineHandover(
    int lineNumber, {
    int? incompletePalletProductTypeId,
    int? incompletePalletQuantity,
    List<Map<String, dynamic>>? looseBalances,
    String? notes,
  }) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return null;

    try {
      final handover = await _repository.createLineHandover(
        lineId,
        incompletePalletProductTypeId: incompletePalletProductTypeId,
        incompletePalletQuantity: incompletePalletQuantity,
        looseBalances: looseBalances,
        notes: notes,
      );
      _pendingHandovers[lineNumber] = handover;

      // Refresh full line state from backend — the backend releases the
      // outgoing operator's authorization when a handover is created, so
      // lineUiMode will transition to PENDING_HANDOVER_NEEDS_INCOMING.
      await _refreshLineStateFromBackend(lineNumber, lineId);

      notifyListeners();
      return handover;
    } on ApiException catch (e) {
      _lineErrors[lineNumber] = e.displayMessage;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> confirmLineHandover({
    required int lineNumber,
    required int handoverId,
  }) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;

    try {
      await _repository.confirmLineHandover(
        lineId: lineId,
        handoverId: handoverId,
      );

      _pendingHandovers[lineNumber] = null;

      // Refresh line state after handover confirmation
      await _refreshLineStateFromBackend(lineNumber, lineId);
      notifyListeners();
    } on ApiException catch (e) {
      _lineErrors[lineNumber] = e.displayMessage;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> rejectLineHandover({
    required int lineNumber,
    required int handoverId,
    String? notes,
  }) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;

    try {
      await _repository.rejectLineHandover(
        lineId: lineId,
        handoverId: handoverId,
        notes: notes,
      );

      _pendingHandovers[lineNumber] = null;

      // Refresh line state after handover rejection
      await _refreshLineStateFromBackend(lineNumber, lineId);
      notifyListeners();
    } on ApiException catch (e) {
      _lineErrors[lineNumber] = e.displayMessage;
      notifyListeners();
      rethrow;
    }
  }

  // ── Open Items ──

  Future<void> fetchOpenItems(int lineNumber) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;

    _openItemsLoading[lineNumber] = true;
    notifyListeners();

    try {
      final result = await _repository.getOpenItems(lineId);
      _openItems[lineNumber] = result;
    } on ApiException catch (e) {
      _lineErrors[lineNumber] = e.displayMessage;
      debugPrint('fetchOpenItems error: ${e.code} - ${e.message}');
    } catch (e) {
      _lineErrors[lineNumber] = 'فشل في تحميل العناصر غير المكتملة';
      debugPrint('fetchOpenItems unexpected error: $e');
    }

    _openItemsLoading[lineNumber] = false;
    notifyListeners();
  }

  Future<ProducePalletFromLooseResponse?> producePalletFromLoose({
    required int lineNumber,
    required int productTypeId,
    required int looseQuantityToUse,
    int freshQuantityToAdd = 0,
  }) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return null;

    try {
      final result = await _repository.producePalletFromLoose(
        lineId: lineId,
        productTypeId: productTypeId,
        looseQuantityToUse: looseQuantityToUse,
        freshQuantityToAdd: freshQuantityToAdd,
      );

      // Refresh open items and line state
      await Future.wait([
        fetchOpenItems(lineNumber),
        _refreshLineStateFromBackend(lineNumber, lineId),
      ]);
      notifyListeners();
      return result;
    } on ApiException catch (e) {
      _lineErrors[lineNumber] = e.displayMessage;
      notifyListeners();
      rethrow;
    }
  }

  Future<CompleteIncompletePalletResponse?> completeIncompletePallet({
    required int lineNumber,
    int additionalFreshQuantity = 0,
  }) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return null;

    try {
      final result = await _repository.completeIncompletePallet(
        lineId: lineId,
        additionalFreshQuantity: additionalFreshQuantity,
      );

      // Refresh open items and line state
      await Future.wait([
        fetchOpenItems(lineNumber),
        _refreshLineStateFromBackend(lineNumber, lineId),
      ]);
      notifyListeners();
      return result;
    } on ApiException catch (e) {
      _lineErrors[lineNumber] = e.displayMessage;
      notifyListeners();
      rethrow;
    }
  }

  // ── Error management ──

  void clearError() {
    _errorMessage = null;
    if (_state == PalletizingState.error) {
      _state = PalletizingState.loaded;
    }
    notifyListeners();
  }

  void clearLineError(int lineNumber) {
    _lineErrors[lineNumber] = null;
    notifyListeners();
  }
}
