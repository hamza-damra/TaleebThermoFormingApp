import 'package:flutter/foundation.dart';

import '../../core/exceptions/api_exception.dart';
import '../../domain/entities/operator.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/entities/production_line.dart';
import '../../domain/entities/pallet_create_response.dart';
import '../../domain/entities/line_summary.dart';
import '../../domain/repositories/palletizing_repository.dart';

enum PalletizingState { idle, loading, loaded, creating, error }

class PalletizingProvider extends ChangeNotifier {
  final PalletizingRepository _repository;

  PalletizingProvider(this._repository);

  // State
  PalletizingState _state = PalletizingState.idle;
  String? _errorMessage;

  // Data lists
  List<Operator> _operators = [];
  List<ProductType> _productTypes = [];
  List<ProductionLine> _productionLines = [];

  // Per-line state (indexed by lineNumber)
  final Map<int, Operator?> _selectedOperators = {};
  final Map<int, ProductType?> _selectedProductTypes = {};
  final Map<int, PalletCreateResponse?> _lastPalletResponses = {};
  final Map<int, LineSummary?> _lineSummaries = {};

  // Getters - General
  PalletizingState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == PalletizingState.loading;
  bool get isCreating => _state == PalletizingState.creating;
  List<Operator> get operators => _operators;
  List<ProductType> get productTypes => _productTypes;
  List<ProductionLine> get productionLines => _productionLines;

  // Per-line getters
  Operator? getSelectedOperator(int lineNumber) =>
      _selectedOperators[lineNumber];
  ProductType? getSelectedProductType(int lineNumber) =>
      _selectedProductTypes[lineNumber];
  PalletCreateResponse? getLastPalletResponse(int lineNumber) =>
      _lastPalletResponses[lineNumber];
  LineSummary? getLineSummary(int lineNumber) => _lineSummaries[lineNumber];
  int getPalletCount(int lineNumber) =>
      _lineSummaries[lineNumber]?.todayPalletCount ?? 0;

  Future<void> loadInitialData() async {
    _state = PalletizingState.loading;
    _errorMessage = null;
    _selectedOperators.clear();
    _selectedProductTypes.clear();
    notifyListeners();

    try {
      final results = await Future.wait([
        _repository.getOperators(),
        _repository.getProductTypes(),
        _repository.getProductionLines(),
      ]);

      _operators = results[0] as List<Operator>;
      _productTypes = results[1] as List<ProductType>;
      _productionLines = results[2] as List<ProductionLine>;

      // Load summaries for all lines
      await _loadAllLineSummaries();

      _state = PalletizingState.loaded;
    } on ApiException catch (e) {
      _errorMessage = e.displayMessage;
      _state = PalletizingState.error;
      debugPrint('PalletizingProvider API error: ${e.code} - ${e.message}');
    } catch (e, stackTrace) {
      _errorMessage = 'فشل في تحميل البيانات: $e';
      _state = PalletizingState.error;
      debugPrint('PalletizingProvider unexpected error: $e');
      debugPrint('Stack trace: $stackTrace');
    }
    notifyListeners();
  }

  Future<void> _loadAllLineSummaries() async {
    for (final line in _productionLines) {
      try {
        final summary = await _repository.getLineSummary(line.id);
        _lineSummaries[line.lineNumber] = summary;
      } catch (e) {
        // Ignore individual summary failures
      }
    }
  }

  Future<void> refreshLineSummary(int lineId, int lineNumber) async {
    try {
      final summary = await _repository.getLineSummary(lineId);
      _lineSummaries[lineNumber] = summary;
      notifyListeners();
    } catch (e) {
      // Silently fail
    }
  }

  void selectOperator(int lineNumber, Operator? operator) {
    _selectedOperators[lineNumber] = operator;
    notifyListeners();
  }

  void selectProductType(int lineNumber, ProductType? productType) {
    _selectedProductTypes[lineNumber] = productType;
    notifyListeners();
  }

  Future<PalletCreateResponse?> createPallet({
    required int operatorId,
    required int productTypeId,
    required int productionLineId,
    required int lineNumber,
    required int quantity,
  }) async {
    _state = PalletizingState.creating;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _repository.createPallet(
        operatorId: operatorId,
        productTypeId: productTypeId,
        productionLineId: productionLineId,
        quantity: quantity,
      );

      _lastPalletResponses[lineNumber] = response;

      // Update selections based on response - find matching objects from lists
      // to ensure dropdown can find them (same instance reference)
      _selectedOperators[lineNumber] = _operators.firstWhere(
        (o) => o.id == response.operator.id,
        orElse: () => response.operator,
      );
      _selectedProductTypes[lineNumber] = _productTypes.firstWhere(
        (p) => p.id == response.productType.id,
        orElse: () => response.productType,
      );

      // Refresh line summary
      await refreshLineSummary(productionLineId, lineNumber);

      _state = PalletizingState.loaded;
      notifyListeners();
      return response;
    } on ApiException catch (e) {
      _state = PalletizingState.loaded;
      notifyListeners();
      debugPrint(
        'PalletizingProvider createPallet API error: ${e.code} - ${e.message}',
      );
      rethrow;
    } catch (e) {
      _state = PalletizingState.loaded;
      debugPrint('PalletizingProvider createPallet error: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<bool> logPrintAttempt({
    required int palletId,
    required String printerIdentifier,
    required bool success,
    String? failureReason,
  }) async {
    try {
      await _repository.logPrintAttempt(
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

  void clearError() {
    _errorMessage = null;
    if (_state == PalletizingState.error) {
      _state = PalletizingState.loaded;
    }
    notifyListeners();
  }
}
