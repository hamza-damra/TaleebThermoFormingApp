import 'package:flutter/foundation.dart';

import '../../core/exceptions/api_exception.dart';
import '../../domain/entities/shift_info.dart';
import '../../domain/entities/handover.dart';
import '../../domain/repositories/shift_handover_repository.dart';

enum ShiftHandoverState { idle, loading, creating, confirming, error }

class ShiftHandoverProvider extends ChangeNotifier {
  final ShiftHandoverRepository _repository;

  ShiftHandoverProvider(this._repository);

  ShiftHandoverState _state = ShiftHandoverState.idle;
  String? _errorMessage;
  String? _errorCode;
  ShiftInfo? _currentShift;
  Handover? _pendingHandover;
  bool _pendingCheckFailed = false;
  bool _pendingCheckLoading = false;

  ShiftHandoverState get state => _state;
  String? get errorMessage => _errorMessage;
  String? get errorCode => _errorCode;
  ShiftInfo? get currentShift => _currentShift;
  bool get isLoading => _state == ShiftHandoverState.loading;
  Handover? get pendingHandover => _pendingHandover;
  bool get hasBlockingHandover => _pendingHandover != null;
  bool get pendingCheckFailed => _pendingCheckFailed;
  bool get pendingCheckLoading => _pendingCheckLoading;
  bool get isConfirming => _state == ShiftHandoverState.confirming;

  Future<void> fetchCurrentShift() async {
    try {
      _currentShift = await _repository.getCurrentShift();
      notifyListeners();
    } on ApiException catch (e) {
      debugPrint('ShiftHandoverProvider fetchCurrentShift error: ${e.code}');
    } catch (e) {
      debugPrint('ShiftHandoverProvider fetchCurrentShift error: $e');
    }
  }

  /// Sets loading flags synchronously without notifying.
  /// Call this during build to ensure the loading state is visible
  /// in the same frame (before the async check starts).
  void prepareForPendingCheck() {
    _pendingCheckLoading = true;
    _pendingCheckFailed = false;
  }

  Future<Handover?> checkPendingHandover() async {
    _pendingCheckLoading = true;
    _pendingCheckFailed = false;
    notifyListeners();

    try {
      final handovers = await _repository.getAllPendingHandovers();
      _pendingHandover = handovers.isNotEmpty ? handovers.first : null;
      _pendingCheckFailed = false;
      _pendingCheckLoading = false;
      notifyListeners();
      return _pendingHandover;
    } on ApiException catch (e) {
      debugPrint('ShiftHandoverProvider checkPending error: ${e.code}');
      _pendingCheckFailed = true;
      _pendingCheckLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('ShiftHandoverProvider checkPending error: $e');
      _pendingCheckFailed = true;
      _pendingCheckLoading = false;
      notifyListeners();
      return null;
    }
  }

  void clearPendingHandover() {
    _pendingHandover = null;
    _pendingCheckFailed = false;
    _pendingCheckLoading = false;
    notifyListeners();
  }

  Future<Handover?> createHandover({
    required int operatorId,
    required List<Map<String, dynamic>> items,
  }) async {
    _state = ShiftHandoverState.creating;
    _errorMessage = null;
    _errorCode = null;
    notifyListeners();

    try {
      final handover = await _repository.createHandover(
        operatorId: operatorId,
        items: items,
      );
      _state = ShiftHandoverState.idle;
      notifyListeners();
      return handover;
    } on ApiException catch (e) {
      _errorMessage = e.displayMessage;
      _errorCode = e.code;
      _state = ShiftHandoverState.error;
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = 'فشل في إنشاء تسليم المناوبة';
      _errorCode = null;
      _state = ShiftHandoverState.error;
      notifyListeners();
      return null;
    }
  }

  Future<Handover?> confirmHandover({
    required int id,
    required int incomingOperatorId,
  }) async {
    _state = ShiftHandoverState.confirming;
    _errorMessage = null;
    _errorCode = null;
    notifyListeners();

    try {
      final handover = await _repository.confirmHandover(
        id: id,
        incomingOperatorId: incomingOperatorId,
      );
      _pendingHandover = null;
      _state = ShiftHandoverState.idle;
      notifyListeners();
      return handover;
    } on ApiException catch (e) {
      _errorMessage = e.displayMessage;
      _errorCode = e.code;
      _state = ShiftHandoverState.error;
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = 'فشل في تأكيد الاستلام';
      _errorCode = null;
      _state = ShiftHandoverState.error;
      notifyListeners();
      return null;
    }
  }

  Future<Handover?> rejectHandover({
    required int id,
    required int incomingOperatorId,
  }) async {
    _state = ShiftHandoverState.confirming;
    _errorMessage = null;
    _errorCode = null;
    notifyListeners();

    try {
      final handover = await _repository.rejectHandover(
        id: id,
        incomingOperatorId: incomingOperatorId,
      );
      _pendingHandover = null;
      _state = ShiftHandoverState.idle;
      notifyListeners();
      return handover;
    } on ApiException catch (e) {
      _errorMessage = e.displayMessage;
      _errorCode = e.code;
      _state = ShiftHandoverState.error;
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = 'فشل في رفض التسليم';
      _errorCode = null;
      _state = ShiftHandoverState.error;
      notifyListeners();
      return null;
    }
  }

  void clearError() {
    _errorMessage = null;
    _errorCode = null;
    if (_state == ShiftHandoverState.error) {
      _state = ShiftHandoverState.idle;
    }
    notifyListeners();
  }
}
