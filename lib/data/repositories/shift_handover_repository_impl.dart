import '../../domain/entities/shift_info.dart';
import '../../domain/entities/handover.dart';
import '../../domain/repositories/shift_handover_repository.dart';
import '../datasources/api_client.dart';
import '../models/shift_info_model.dart';
import '../models/handover_model.dart';

class ShiftHandoverRepositoryImpl implements ShiftHandoverRepository {
  final ApiClient _apiClient;

  ShiftHandoverRepositoryImpl({required ApiClient apiClient})
    : _apiClient = apiClient;

  @override
  Future<ShiftInfo> getCurrentShift() async {
    return await _apiClient.request<ShiftInfo>(
      path: '/shift-schedule/current-shift',
      method: 'GET',
      parser: (json) =>
          ShiftInfoModel.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  @override
  Future<Handover> createHandover({
    required int operatorId,
    required List<Map<String, dynamic>> items,
  }) async {
    return await _apiClient.request<Handover>(
      path: '/shift-handover',
      method: 'POST',
      data: {'operatorId': operatorId, 'items': items},
      parser: (json) =>
          HandoverModel.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  @override
  Future<Handover?> getPendingHandover() async {
    return await _apiClient.request<Handover?>(
      path: '/shift-handover/pending',
      method: 'GET',
      parser: (json) {
        final data = json['data'];
        if (data == null) return null;
        return HandoverModel.fromJson(data as Map<String, dynamic>);
      },
    );
  }

  @override
  Future<List<Handover>> getAllPendingHandovers() async {
    return await _apiClient.requestList<Handover>(
      path: '/shift-handover/pending-list',
      method: 'GET',
      itemParser: (json) => HandoverModel.fromJson(json),
    );
  }

  @override
  Future<Handover> confirmHandover({
    required int id,
    required int incomingOperatorId,
  }) async {
    return await _apiClient.request<Handover>(
      path: '/shift-handover/$id/confirm',
      method: 'POST',
      data: {'incomingOperatorId': incomingOperatorId},
      parser: (json) =>
          HandoverModel.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  @override
  Future<Handover> rejectHandover({
    required int id,
    required int incomingOperatorId,
  }) async {
    return await _apiClient.request<Handover>(
      path: '/shift-handover/$id/reject',
      method: 'POST',
      data: {'incomingOperatorId': incomingOperatorId},
      parser: (json) =>
          HandoverModel.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  @override
  Future<Handover> getHandoverDetails(int id) async {
    return await _apiClient.request<Handover>(
      path: '/shift-handover/$id',
      method: 'GET',
      parser: (json) =>
          HandoverModel.fromJson(json['data'] as Map<String, dynamic>),
    );
  }
}
