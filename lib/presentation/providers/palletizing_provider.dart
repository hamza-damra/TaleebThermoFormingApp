import 'package:flutter/foundation.dart';

import '../../core/exceptions/api_exception.dart';
import '../../data/datasources/auth_local_storage.dart';
import '../../domain/entities/bootstrap_response.dart';
import '../../domain/entities/falet_resolution_entry.dart';
import '../../domain/entities/falet_response.dart';
import '../../domain/entities/line_handover_info.dart';
import '../../domain/entities/operator.dart';
import '../../domain/entities/pallet_create_response.dart';
import '../../domain/entities/palletizer_session.dart';
import '../../domain/entities/palletizer_session_state.dart';
import '../../domain/entities/session_production_detail.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/entities/production_line.dart';
import '../../domain/entities/session_table_row.dart';
import '../../domain/repositories/palletizing_repository.dart';

enum PalletizingState { idle, loading, loaded, error }

/// Per-line UI state. Computed from the cached BootstrapLineState plus the
/// palletizer session, in this priority order:
///   1. blocked    (BootstrapLineState.blockedReason != null)
///   2. handover   (lineUiMode == PENDING_HANDOVER_*)
///   3. waitingForThermoforming (authorized == false)
///   4. needsPalletizerAuth (authorized && no active session)
///   5. active     (authorized && active session)
///
/// The waiting card never wins over real blocked / handover states.
enum LineUiState {
  blocked,
  pendingHandoverIncoming,
  pendingHandoverReview,
  waitingForThermoforming,
  needsPalletizerAuth,
  active,
}

class PalletizingProvider extends ChangeNotifier {
  final PalletizingRepository _repository;
  final AuthLocalStorage _authStorage;

  PalletizingProvider(this._repository, this._authStorage);

  // ── Global state ──
  PalletizingState _state = PalletizingState.idle;
  String? _errorMessage;

  // ── Reference data ──
  List<ProductType> _productTypes = [];
  List<ProductionLine> _productionLines = [];

  // ── Per-line state (keyed by UI lineNumber: 1, 2) ──
  // Backend lineId is resolved via getLineIdForNumber before any storage / API.
  final Map<int, BootstrapLineState> _lineStates = {};
  final Map<int, PalletizerSessionState> _palletizerSessions = {};
  final Map<int, List<SessionTableRow>> _sessionTables = {};
  final Map<int, ProductType?> _selectedProductTypes = {};
  final Map<int, PalletCreateResponse?> _lastPalletResponses = {};
  final Map<int, LineHandoverInfo?> _pendingHandovers = {};
  final Map<int, String?> _blockedReasons = {};
  final Map<int, bool> _lineCreating = {};
  final Map<int, String?> _lineErrors = {};
  final Map<int, String?> _lineUiModes = {};
  final Map<int, bool> _canInitiateHandovers = {};
  final Map<int, bool> _canConfirmHandovers = {};
  final Map<int, bool> _canRejectHandovers = {};
  final Map<int, FaletResponse?> _faletItems = {};
  final Map<int, bool> _faletItemsLoading = {};
  final Map<int, bool> _hasOpenFalet = {};
  final Map<int, int> _openFaletCount = {};

  // ── Global getters ──
  PalletizingState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == PalletizingState.loading;
  List<ProductType> get productTypes => _productTypes;
  List<ProductionLine> get productionLines => _productionLines;

  bool get isCreating => _lineCreating.values.any((v) => v);

  // ── Per-line getters ──

  bool isLineAuthorized(int lineNumber) =>
      _lineStates[lineNumber]?.isAuthorized ?? false;

  Operator? getAuthorizedOperator(int lineNumber) =>
      _lineStates[lineNumber]?.authorizedOperator;

  PalletizerSessionState? getPalletizerSessionState(int lineNumber) =>
      _palletizerSessions[lineNumber];

  PalletizerSession? getPalletizerSession(int lineNumber) =>
      _palletizerSessions[lineNumber]?.session;

  bool isPalletizerAuthenticating(int lineNumber) =>
      _palletizerSessions[lineNumber]?.isAuthenticating ?? false;

  String? getPalletizerName(int lineNumber) =>
      _palletizerSessions[lineNumber]?.session?.palletizerName;

  String? getPalletizerAuthError(int lineNumber) =>
      _palletizerSessions[lineNumber]?.authError;

  String? getPalletizerAuthErrorCode(int lineNumber) =>
      _palletizerSessions[lineNumber]?.authErrorCode;

  bool hasActivePalletizerSession(int lineNumber) =>
      _palletizerSessions[lineNumber]?.hasActiveSession ?? false;

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

  String? getLineUiMode(int lineNumber) => _lineUiModes[lineNumber];

  bool canInitiateHandover(int lineNumber) =>
      _canInitiateHandovers[lineNumber] ?? false;

  bool canConfirmHandover(int lineNumber) =>
      _canConfirmHandovers[lineNumber] ?? false;

  bool canRejectHandover(int lineNumber) =>
      _canRejectHandovers[lineNumber] ?? false;

  FaletResponse? getFaletItems(int lineNumber) => _faletItems[lineNumber];

  bool isFaletItemsLoading(int lineNumber) =>
      _faletItemsLoading[lineNumber] ?? false;

  bool hasOpenFalet(int lineNumber) => _hasOpenFalet[lineNumber] ?? false;

  int getOpenFaletCount(int lineNumber) => _openFaletCount[lineNumber] ?? 0;

  bool isLineBlocked(int lineNumber) {
    final ui = getUiState(lineNumber);
    return ui == LineUiState.blocked ||
        ui == LineUiState.pendingHandoverIncoming ||
        ui == LineUiState.waitingForThermoforming ||
        ui == LineUiState.needsPalletizerAuth;
  }

  /// Single source of truth for the per-line UI branch. Existing blocked /
  /// handover / inactive states always take precedence over the new waiting
  /// card so a real failure never gets masked as "waiting for the operator".
  LineUiState getUiState(int lineNumber) {
    if ((_blockedReasons[lineNumber] ?? '').isNotEmpty) {
      return LineUiState.blocked;
    }
    final mode = _lineUiModes[lineNumber];
    if (mode == 'PENDING_HANDOVER_NEEDS_INCOMING') {
      return LineUiState.pendingHandoverIncoming;
    }
    if (mode == 'PENDING_HANDOVER_REVIEW') {
      return LineUiState.pendingHandoverReview;
    }
    final lineState = _lineStates[lineNumber];
    if (lineState == null || !lineState.isAuthorized) {
      return LineUiState.waitingForThermoforming;
    }
    if (!hasActivePalletizerSession(lineNumber)) {
      return LineUiState.needsPalletizerAuth;
    }
    return LineUiState.active;
  }

  int? getLineIdForNumber(int lineNumber) {
    final fromList = _productionLines
        .where((l) => l.lineNumber == lineNumber)
        .firstOrNull;
    return fromList?.id ?? _lineStates[lineNumber]?.lineId;
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

      for (final lineState in bootstrap.lines) {
        _hydrateLineState(lineState.lineNumber, lineState);
      }

      // Fetch full handover details for lines in review mode (existing behavior).
      for (final lineState in bootstrap.lines) {
        if (lineState.lineUiMode == 'PENDING_HANDOVER_REVIEW') {
          try {
            final fullHandover = await _repository.getLineHandover(
              lineState.lineId,
            );
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

      // For every authorized line, sync the palletizer session from the
      // backend + secure storage so cold start lands directly in State C
      // when a session is still alive.
      await Future.wait(
        bootstrap.lines
            .where((l) => l.isAuthorized)
            .map((l) => refreshPalletizerSession(l.lineNumber)),
      );

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

  // ── Refresh single line state ──

  Future<void> refreshLineState(int lineNumber) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;
    await _refreshLineStateFromBackend(lineNumber, lineId);
    notifyListeners();
  }

  Future<void> _refreshLineStateFromBackend(int lineNumber, int lineId) async {
    try {
      final lineState = await _repository.getLineState(lineId);
      _hydrateLineState(lineNumber, lineState);

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

      // Re-sync the palletizer session whenever line state changes so we drop
      // back to State B if the backend ended the session (e.g. shift-line ended).
      if (lineState.isAuthorized) {
        await refreshPalletizerSession(lineNumber);
      } else {
        // Line was de-authorized — the bound palletizer session is gone too.
        await _dropToStateB(lineNumber);
      }
    } catch (e) {
      debugPrint('Failed to refresh line $lineNumber state: $e');
    }
  }

  ProductType? _resolveProductType(BootstrapLineState lineState) {
    final id = lineState.currentProductTypeId;
    if (id != null) {
      final match = _productTypes.where((p) => p.id == id).firstOrNull;
      if (match != null) return match;
    }
    return lineState.selectedProductType;
  }

  void _hydrateLineState(int lineNumber, BootstrapLineState lineState) {
    _lineStates[lineNumber] = lineState;
    _sessionTables[lineNumber] = lineState.sessionTable;
    _pendingHandovers[lineNumber] = lineState.pendingHandover;
    _blockedReasons[lineNumber] = lineState.blockedReason;
    _lineUiModes[lineNumber] = lineState.lineUiMode;
    _canInitiateHandovers[lineNumber] = lineState.canInitiateHandover;
    _canConfirmHandovers[lineNumber] = lineState.canConfirmHandover;
    _canRejectHandovers[lineNumber] = lineState.canRejectHandover;
    _hasOpenFalet[lineNumber] = lineState.hasOpenFalet;
    _openFaletCount[lineNumber] = lineState.openFaletCount;
    _selectedProductTypes[lineNumber] = _resolveProductType(lineState);
    _palletizerSessions[lineNumber] ??= PalletizerSessionState.empty(
      lineNumber,
    );
  }

  // ── Palletizer auth ──

  Future<bool> palletizerAuth(int lineNumber, String pin) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return false;

    _palletizerSessions[lineNumber] =
        (_palletizerSessions[lineNumber] ??
                PalletizerSessionState.empty(lineNumber))
            .copyWith(isAuthenticating: true, clearAuthError: true);
    notifyListeners();

    try {
      final result = await _repository.palletizerAuth(lineId: lineId, pin: pin);

      // Persist the raw token ONCE — namespaced by backend lineId.
      await _authStorage.savePalletizerSessionToken(
        lineId,
        result.sessionToken,
      );

      _palletizerSessions[lineNumber] = PalletizerSessionState(
        lineNumber: lineNumber,
        session: result.session,
      );

      // Refresh line state to pick up any backend-side changes (operator name,
      // handover transitions, etc.) — but don't let it stomp the session we
      // just stored.
      try {
        final lineState = await _repository.getLineState(lineId);
        _hydrateLineState(lineNumber, lineState);
      } catch (e) {
        debugPrint('Post-auth line refresh error (line $lineNumber): $e');
      }

      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _palletizerSessions[lineNumber] = PalletizerSessionState(
        lineNumber: lineNumber,
        isAuthenticating: false,
        authError: e.displayMessage,
        authErrorCode: e.code,
      );
      notifyListeners();
      return false;
    } catch (e) {
      _palletizerSessions[lineNumber] = PalletizerSessionState(
        lineNumber: lineNumber,
        isAuthenticating: false,
        authError: 'فشل في التحقق من الرمز',
      );
      notifyListeners();
      return false;
    }
  }

  /// Fetches the current palletizer session from the backend for a given line.
  /// On 404 / PALLETIZER_SESSION_REQUIRED, drops the line to State B and
  /// clears the locally stored token.
  Future<void> refreshPalletizerSession(int lineNumber) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;

    try {
      final session = await _repository.getCurrentPalletizerSession(lineId);
      _palletizerSessions[lineNumber] = PalletizerSessionState(
        lineNumber: lineNumber,
        session: session,
      );
      notifyListeners();
    } on ApiException catch (e) {
      if (e.code == 'PALLETIZER_SESSION_REQUIRED') {
        await _dropToStateB(lineNumber);
      } else {
        debugPrint(
          'refreshPalletizerSession error (line $lineNumber): ${e.code} - ${e.message}',
        );
      }
    } catch (e) {
      debugPrint(
        'refreshPalletizerSession unexpected error (line $lineNumber): $e',
      );
    }
  }

  Future<void> palletizerLogout(int lineNumber) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;

    final token = await _authStorage.getPalletizerSessionToken(lineId);
    if (token != null && token.isNotEmpty) {
      try {
        await _repository.palletizerLogout(lineId: lineId, sessionToken: token);
      } on ApiException catch (e) {
        // Idempotent — any flavor of session-required is treated as success.
        if (e.code != 'PALLETIZER_SESSION_REQUIRED') {
          debugPrint(
            'palletizerLogout error (line $lineNumber): ${e.code} - ${e.message}',
          );
        }
      } catch (e) {
        debugPrint('palletizerLogout unexpected error (line $lineNumber): $e');
      }
    }

    await _dropToStateB(lineNumber);
  }

  /// Clears the local session + secure-storage token and notifies listeners.
  /// Used by logout, by PALLETIZER_SESSION_REQUIRED interception, and by line
  /// de-authorization (operator ended the shift-line).
  Future<void> _dropToStateB(int lineNumber) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId != null) {
      await _authStorage.clearPalletizerSessionToken(lineId);
    }
    _palletizerSessions[lineNumber] = PalletizerSessionState.empty(lineNumber);
    notifyListeners();
  }

  void clearPalletizerAuthError(int lineNumber) {
    final current = _palletizerSessions[lineNumber];
    if (current != null && current.authError != null) {
      _palletizerSessions[lineNumber] = current.copyWith(clearAuthError: true);
      notifyListeners();
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

      final matchIndex = _productTypes.indexWhere(
        (p) => p.id == response.productType.id,
      );
      _selectedProductTypes[lineNumber] = matchIndex >= 0
          ? _productTypes[matchIndex]
          : response.productType;

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
      // Backend will reject pallet creation when no palletizer session exists —
      // surface that to the UI by dropping to State B.
      if (e.code == 'PALLETIZER_SESSION_REQUIRED') {
        await _dropToStateB(lineNumber);
      }
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

  // ── Session production detail (drill-down) ──

  Future<SessionProductionDetail> fetchSessionProductionDetail(
    int lineNumber,
  ) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) {
      throw StateError('No lineId found for lineNumber $lineNumber');
    }
    return await _repository.getSessionProductionDetail(lineId);
  }

  // ── Line handover (unchanged surface) ──

  Future<LineHandoverInfo?> createLineHandover(
    int lineNumber, {
    int? lastActiveProductTypeId,
    int? lastActiveProductFaletQuantity,
    String? notes,
    List<FaletResolutionEntry>? faletResolutions,
  }) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return null;

    try {
      final handover = await _repository.createLineHandover(
        lineId,
        lastActiveProductTypeId: lastActiveProductTypeId,
        lastActiveProductFaletQuantity: lastActiveProductFaletQuantity,
        notes: notes,
        faletResolutions: faletResolutions,
      );
      _pendingHandovers[lineNumber] = handover;

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
    String? receiptNotes,
  }) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;

    try {
      await _repository.confirmLineHandover(
        lineId: lineId,
        handoverId: handoverId,
        receiptNotes: receiptNotes,
      );

      _pendingHandovers[lineNumber] = null;

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
    required bool incorrectQuantity,
    required bool otherReason,
    String? otherReasonNotes,
    List<Map<String, dynamic>>? itemObservations,
    bool undeclaredFaletFound = false,
    int? undeclaredFaletObservedQuantity,
    String? undeclaredFaletNotes,
  }) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;

    try {
      await _repository.rejectLineHandover(
        lineId: lineId,
        handoverId: handoverId,
        incorrectQuantity: incorrectQuantity,
        otherReason: otherReason,
        otherReasonNotes: otherReasonNotes,
        itemObservations: itemObservations,
        undeclaredFaletFound: undeclaredFaletFound,
        undeclaredFaletObservedQuantity: undeclaredFaletObservedQuantity,
        undeclaredFaletNotes: undeclaredFaletNotes,
      );

      _pendingHandovers[lineNumber] = null;

      await Future.wait([
        fetchFaletItems(lineNumber),
        _refreshLineStateFromBackend(lineNumber, lineId),
      ]);
      notifyListeners();
    } on ApiException catch (e) {
      _lineErrors[lineNumber] = e.displayMessage;
      notifyListeners();
      rethrow;
    }
  }

  // ── FALET Items (unchanged surface) ──

  Future<void> fetchFaletItems(int lineNumber) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;

    _faletItemsLoading[lineNumber] = true;
    notifyListeners();

    try {
      final result = await _repository.getFaletItems(lineId);
      _faletItems[lineNumber] = result;
      _hasOpenFalet[lineNumber] = result.hasOpenFalet;
      _openFaletCount[lineNumber] = result.totalOpenFaletCount;
    } on ApiException catch (e) {
      _lineErrors[lineNumber] = e.displayMessage;
      debugPrint('fetchFaletItems error: ${e.code} - ${e.message}');
    } catch (e) {
      _lineErrors[lineNumber] = 'فشل في تحميل عناصر الفالت';
      debugPrint('fetchFaletItems unexpected error: $e');
    }

    _faletItemsLoading[lineNumber] = false;
    notifyListeners();
  }

  // ── FALET existence + line monitoring polling ──

  Future<void> checkFaletExists(int lineNumber) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;

    try {
      final result = await _repository.checkFaletExists(lineId);
      final changed =
          _hasOpenFalet[lineNumber] != result.hasOpenFalet ||
          _openFaletCount[lineNumber] != result.openFaletCount;
      if (changed) {
        _hasOpenFalet[lineNumber] = result.hasOpenFalet;
        _openFaletCount[lineNumber] = result.openFaletCount;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('checkFaletExists poll error (line $lineNumber): $e');
    }
  }

  /// Combined poll fired from a periodic timer (~15s):
  ///   - For every authorized line, lightly check FALET existence.
  ///   - For every line in `waitingForThermoforming`, refresh full line state
  ///     so the waiting card flips to State B as soon as the operator opens
  ///     the line from the Thermoforming app.
  Future<void> pollLineMonitoring() async {
    final futures = <Future<void>>[];

    final lineNumbers = <int>{
      ..._lineStates.keys,
      ..._productionLines.map((l) => l.lineNumber),
    };

    for (final lineNumber in lineNumbers) {
      final ui = getUiState(lineNumber);
      if (ui == LineUiState.waitingForThermoforming) {
        final lineId = getLineIdForNumber(lineNumber);
        if (lineId != null) {
          futures.add(_refreshLineStateFromBackend(lineNumber, lineId));
        }
      } else if (isLineAuthorized(lineNumber)) {
        futures.add(checkFaletExists(lineNumber));
      }
    }

    if (futures.isEmpty) return;
    await Future.wait(futures);
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
