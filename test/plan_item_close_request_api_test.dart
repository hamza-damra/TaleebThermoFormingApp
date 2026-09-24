// Plan-item close handshake (V190) — the three Palletizing App calls on the
// wire: exact paths, methods, headers and bodies (handoff §2 / §4 / §8).

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/data/datasources/api_client.dart';
import 'package:taleeb_thermoforming/data/datasources/auth_local_storage.dart';
import 'package:taleeb_thermoforming/data/repositories/palletizing_repository_impl.dart';
import 'package:taleeb_thermoforming/domain/entities/plan_item_close_request.dart';

class _DeviceKeyStorage extends AuthLocalStorage {
  @override
  Future<String?> getDeviceKey() async => 'test-device-key';

  @override
  Future<String?> getToken() async => 'must-not-be-sent';
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.status, this.body);

  final int status;
  final Object body;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

({PalletizingRepositoryImpl repo, _RecordingAdapter adapter}) _repo(
  int status,
  Object body,
) {
  final client = ApiClient(authStorage: _DeviceKeyStorage());
  final adapter = _RecordingAdapter(status, body);
  client.dio.httpClientAdapter = adapter;
  return (repo: PalletizingRepositoryImpl(apiClient: client), adapter: adapter);
}

Map<String, dynamic> _requestJson(String status) => {
  'closeRequestId': 3021,
  'status': status,
  'productionPlanItemId': 812,
  'productTypeId': 31,
  'productTypeName': 'علبة 500 مل شفاف',
  'targetPackageQuantity': 2000,
  'producedPackageQuantity': 1840,
  'thermoformingLineId': 4,
  'palletizingLineId': 9,
  'requestedByOperatorName': 'محمد أحمد',
  'requestedAt': '2026-09-14T08:15:02.418Z',
  'alreadyProcessed': false,
};

void _expectAuthHeaders(RequestOptions r) {
  expect(r.headers['X-Palletizer-Session-Token'], 'session-token-9');
  expect(r.headers['X-Device-Key'], 'test-device-key');
  expect(r.headers.containsKey('Authorization'), isFalse);
  expect(r.uri.toString(), isNot(contains('session-token-9')));
}

void main() {
  test('GET plan-item-close-request carries the session token', () async {
    final t = _repo(200, {
      'success': true,
      'data': {
        'hasActiveRequest': true,
        'request': _requestJson('WAITING_FOR_PALLETIZER_DECISION'),
      },
    });

    final request = await t.repo.getActivePlanItemCloseRequest(
      lineId: 9,
      sessionToken: 'session-token-9',
    );

    final r = t.adapter.requests.single;
    expect(r.method, 'GET');
    expect(r.path, '/palletizing-line/lines/9/plan-item-close-request');
    _expectAuthHeaders(r);
    expect(request?.closeRequestId, 3021);
    expect(
      request?.status,
      PlanItemCloseRequestStatus.waitingForPalletizerDecision,
    );
  });

  test('GET with hasActiveRequest:false returns null', () async {
    final t = _repo(200, {
      'success': true,
      'data': {'hasActiveRequest': false},
    });

    expect(
      await t.repo.getActivePlanItemCloseRequest(
        lineId: 9,
        sessionToken: 'session-token-9',
      ),
      isNull,
    );
  });

  test('POST more-pallets-remain: exact path, no body', () async {
    final t = _repo(200, {
      'success': true,
      'data': _requestJson('PALLETIZER_COMPLETING_PALLETS'),
    });

    final result = await t.repo.reportMorePalletsRemain(
      lineId: 9,
      closeRequestId: 3021,
      sessionToken: 'session-token-9',
    );

    final r = t.adapter.requests.single;
    expect(r.method, 'POST');
    expect(
      r.path,
      '/palletizing-line/lines/9/plan-item-close-requests/3021/'
      'more-pallets-remain',
    );
    expect(r.data, isNull);
    _expectAuthHeaders(r);
    expect(result.isCompletingPallets, isTrue);
  });

  test('POST confirm-all-pallets-registered: exact path, no body', () async {
    final t = _repo(200, {
      'success': true,
      'data': {..._requestJson('CONFIRMED'), 'resultingNextItemId': 813},
    });

    final result = await t.repo.confirmAllPalletsRegistered(
      lineId: 9,
      closeRequestId: 3021,
      sessionToken: 'session-token-9',
    );

    final r = t.adapter.requests.single;
    expect(r.method, 'POST');
    expect(
      r.path,
      '/palletizing-line/lines/9/plan-item-close-requests/3021/'
      'confirm-all-pallets-registered',
    );
    expect(r.data, isNull);
    _expectAuthHeaders(r);
    expect(result.status, PlanItemCloseRequestStatus.confirmed);
    expect(result.resultingNextItemId, 813);
  });

  for (final status in const [401, 403]) {
    test('$status PALLETIZER_SESSION_REQUIRED keeps its business code — it '
        'is not a device-key failure', () async {
      final t = _repo(status, {
        'success': false,
        'error': {
          'code': 'PALLETIZER_SESSION_REQUIRED',
          'message': 'An active palletizer session token is required.',
        },
      });

      await expectLater(
        t.repo.getActivePlanItemCloseRequest(
          lineId: 9,
          sessionToken: 'session-token-9',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'PALLETIZER_SESSION_REQUIRED')
              .having((e) => e.statusCode, 'statusCode', status),
        ),
      );
    });
  }

  test('409 STALE surfaces its code and details', () async {
    final t = _repo(409, {
      'success': false,
      'error': {
        'code': 'THERMOFORMING_PLAN_ITEM_CLOSE_REQUEST_STALE',
        'message':
            'تغيّرت حالة الخط بعد إرسال طلب إنهاء البند، فأُلغي الطلب وبقي البند مفتوحاً.',
        'details': {
          'closeRequestId': 3021,
          'invalidationReason': 'MOUNTED_ROLL_CHANGED',
        },
      },
    });

    await expectLater(
      t.repo.confirmAllPalletsRegistered(
        lineId: 9,
        closeRequestId: 3021,
        sessionToken: 'session-token-9',
      ),
      throwsA(
        isA<ApiException>()
            .having(
              (e) => e.code,
              'code',
              'THERMOFORMING_PLAN_ITEM_CLOSE_REQUEST_STALE',
            )
            .having(
              (e) => e.details?['invalidationReason'],
              'invalidationReason',
              'MOUNTED_ROLL_CHANGED',
            ),
      ),
    );
  });
}
