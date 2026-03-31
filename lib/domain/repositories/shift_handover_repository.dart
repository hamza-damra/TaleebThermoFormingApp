import '../entities/shift_info.dart';
import '../entities/handover.dart';

abstract class ShiftHandoverRepository {
  Future<ShiftInfo> getCurrentShift();

  Future<Handover> createHandover({
    required int operatorId,
    required List<Map<String, dynamic>> items,
  });

  Future<Handover?> getPendingHandover();

  Future<List<Handover>> getAllPendingHandovers();

  Future<Handover> confirmHandover({
    required int id,
    required int incomingOperatorId,
  });

  Future<Handover> rejectHandover({
    required int id,
    required int incomingOperatorId,
  });

  Future<Handover> getHandoverDetails(int id);
}
