// PRODUCTION → TRANSIT («الرصيف») move (V210) — the two Palletizing App calls
// on the wire, the refusal details, and the client identifier normaliser.
// Contract: docs/FRONTEND_HANDOFF_PALLETIZING_APP_PRODUCTION_TO_TRANSIT_MOVE.md
// §3.1–§3.4.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/data/datasources/api_client.dart';
import 'package:taleeb_thermoforming/data/datasources/auth_local_storage.dart';
import 'package:taleeb_thermoforming/data/models/production_transit_model.dart';
import 'package:taleeb_thermoforming/data/models/session_production_detail_model.dart';
import 'package:taleeb_thermoforming/data/repositories/palletizing_repository_impl.dart';
import 'package:taleeb_thermoforming/domain/entities/production_transit.dart';

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

void _expectAuthHeaders(RequestOptions r) {
  expect(r.headers['X-Palletizer-Session-Token'], 'session-token');
  expect(r.headers['X-Device-Key'], 'test-device-key');
  expect(r.headers.containsKey('Authorization'), isFalse);
  expect(r.uri.toString(), isNot(contains('session-token')));
}

Map<String, dynamic> _error(String code, [Map<String, dynamic>? details]) => {
  'success': false,
  'error': {'code': code, 'message': 'رسالة الخادم', 'details': ?details},
};

/// §3.1 success body.
const _moveData = {
  'movementId': 90211,
  'palletId': 55012,
  'scannedValue': '101000000123',
  'productTypeId': 7,
  'productTypeName': 'علبة 500 مل',
  'palletizingLineId': 2,
  'palletizingLineName': 'خط 2',
  'thermoformingShiftLineId': 3120,
  'fromLocation': 'PRODUCTION',
  'toLocation': 'TRANSIT',
  'currentLocation': 'TRANSIT',
  'movedAt': '2026-09-24T12:03:11.412Z',
  'movedAtDisplay': '2026-09-24، 03:03 مساءً',
  'movedByName': 'أحمد',
  'producedByPalletizerName': 'محمد',
  'inherited': false,
  'replayed': false,
  'movementUndone': false,
};

const _pendingPalletJson = {
  'palletId': 55011,
  'scannedValue': '101000000122',
  'productTypeId': 7,
  'productTypeName': 'علبة 500 مل',
  'thermoformingShiftLineId': 3120,
  'currentLocation': 'PRODUCTION',
  'producedAt': '2026-09-24T11:40:00.000Z',
  'producedAtDisplay': '2026-09-24، 02:40 مساءً',
  'palletizerName': 'محمد',
  'inherited': true,
};

void main() {
  group('POST move-to-transit (§3.1)', () {
    test('exact path, headers and body; parses the response', () async {
      final t = _repo(200, {'success': true, 'data': _moveData});

      final result = await t.repo.movePalletToTransit(
        sessionToken: 'session-token',
        identifier: '101000000123',
        clientRequestId: '4d1f6c1e-0b8b-4f0e-9d0d-4a9a1f2a7c11',
        scanType: PalletTransitScanType.number,
      );

      final r = t.adapter.requests.single;
      expect(r.method, 'POST');
      expect(r.path, '/palletizing-line/palletizer/pallets/move-to-transit');
      _expectAuthHeaders(r);
      expect(r.data, {
        'identifier': '101000000123',
        'clientRequestId': '4d1f6c1e-0b8b-4f0e-9d0d-4a9a1f2a7c11',
        'scanType': 'NUMBER',
      });
      // No source, destination, line or product is ever sent.
      expect((r.data as Map).keys, isNot(contains('destination')));

      expect(result.movementId, 90211);
      expect(result.palletId, 55012);
      expect(result.scannedValue, '101000000123');
      expect(result.palletizingLineId, 2);
      expect(result.fromLocation, 'PRODUCTION');
      expect(result.toLocation, 'TRANSIT');
      expect(result.currentLocation, 'TRANSIT');
      expect(result.movedAt, DateTime.utc(2026, 9, 24, 12, 3, 11, 412));
      expect(result.movedAtDisplay, '2026-09-24، 03:03 مساءً');
      expect(result.inherited, isFalse);
      expect(result.replayed, isFalse);
      expect(result.movementUndone, isFalse);
      expect(result.returnedToProduction, isFalse);
    });

    test('QR scan type is sent as QR', () async {
      final t = _repo(200, {'success': true, 'data': _moveData});
      await t.repo.movePalletToTransit(
        sessionToken: 'session-token',
        identifier: ' 101000000123 ',
        clientRequestId: 'id-1',
        scanType: PalletTransitScanType.qr,
      );
      expect(t.adapter.requests.single.data['scanType'], 'QR');
      // The raw payload — the backend normalises it.
      expect(t.adapter.requests.single.data['identifier'], ' 101000000123 ');
    });

    test('a replay of an undone movement is "returned to the line"', () {
      final result = PalletizerTransitMoveResultModel.fromJson({
        ..._moveData,
        'currentLocation': 'PRODUCTION',
        'replayed': true,
        'movementUndone': true,
      });
      expect(result.replayed, isTrue);
      expect(result.returnedToProduction, isTrue);
    });

    test('PALLET_NOT_AT_PRODUCTION keeps its details', () async {
      final t = _repo(
        409,
        _error('PALLET_NOT_AT_PRODUCTION', {
          'palletId': 55012,
          'scannedValue': '101000000123',
          'currentLocation': 'TRANSIT',
        }),
      );
      await expectLater(
        t.repo.movePalletToTransit(
          sessionToken: 'session-token',
          identifier: '101000000123',
          clientRequestId: 'id-1',
          scanType: PalletTransitScanType.qr,
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'PALLET_NOT_AT_PRODUCTION')
              .having((e) => e.statusCode, 'status', 409)
              .having(
                (e) => e.details?['currentLocation'],
                'currentLocation',
                'TRANSIT',
              ),
        ),
      );
    });

    // A business 401 / 403 on a device-key route is NOT a device-key failure.
    for (final (code, status) in [
      ('PALLETIZER_SESSION_REQUIRED', 401),
      ('PALLET_OUTSIDE_PALLETIZER_LINE_SCOPE', 403),
      ('PALLET_OUTSIDE_CURRENT_OPERATOR_SHIFT', 403),
    ]) {
      test('$status $code keeps its business code', () async {
        final t = _repo(status, _error(code));
        await expectLater(
          t.repo.movePalletToTransit(
            sessionToken: 'session-token',
            identifier: '101000000123',
            clientRequestId: 'id-1',
            scanType: PalletTransitScanType.qr,
          ),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', code)),
        );
      });
    }
  });

  group('GET production-pending-pallets (§3.2)', () {
    test('exact path and headers; parses lines and pallets', () async {
      final t = _repo(200, {
        'success': true,
        'data': {
          'totalPendingCount': 2,
          'lines': [
            {
              'palletizerSessionId': 811,
              'palletizingLineId': 2,
              'palletizingLineName': 'خط 2',
              'thermoformingShiftLineId': 3120,
              'pendingCount': 2,
              'pallets': [
                _pendingPalletJson,
                {..._pendingPalletJson, 'palletId': 55013, 'inherited': false},
              ],
            },
          ],
        },
      });

      final pending = await t.repo.getProductionPendingPallets(
        sessionToken: 'session-token',
      );

      final r = t.adapter.requests.single;
      expect(r.method, 'GET');
      expect(r.path, '/palletizing-line/palletizer/production-pending-pallets');
      _expectAuthHeaders(r);

      expect(pending.totalPendingCount, 2);
      final line = pending.lines.single;
      expect(line.palletizerSessionId, 811);
      expect(line.palletizingLineId, 2);
      expect(line.pendingCount, 2);
      final pallet = line.pallets.first;
      expect(pallet.scannedValue, '101000000122');
      expect(pallet.producedAt, DateTime.utc(2026, 9, 24, 11, 40));
      expect(pallet.producedAtDisplay, '2026-09-24، 02:40 مساءً');
      expect(pallet.palletizerName, 'محمد');
      expect(pallet.inherited, isTrue);
      expect(line.pallets.last.inherited, isFalse);
    });

    test('empty case: one entry per session, each empty', () {
      final pending = ProductionPendingPalletsModel.fromJson({
        'totalPendingCount': 0,
        'lines': [
          {
            'palletizerSessionId': 811,
            'palletizingLineId': 2,
            'palletizingLineName': 'خط 2',
            'thermoformingShiftLineId': 3120,
            'pendingCount': 0,
            'pallets': <Object>[],
          },
        ],
      });
      expect(pending.totalPendingCount, 0);
      expect(pending.lines.single.pallets, isEmpty);
    });
  });

  group('refusal details (§3.4)', () {
    test('PREVIOUS_PALLET_STILL_AT_PRODUCTION lists the blocking pallets', () {
      final blockers = ProductionPalletBlockersModel.fromError(
        code: 'PREVIOUS_PALLET_STILL_AT_PRODUCTION',
        lineId: 11,
        lineName: 'خط أ',
        details: {
          'thermoformingShiftLineId': 3120,
          'productTypeId': 7,
          'blockingPalletCount': 1,
          // Refusal details carry no producedAtDisplay.
          'blockingPallets': [
            {
              'palletId': 55011,
              'scannedValue': '101000000122',
              'productTypeId': 7,
              'productTypeName': 'علبة 500 مل',
              'thermoformingShiftLineId': 3120,
              'currentLocation': 'PRODUCTION',
              'producedAt': '2026-09-24T11:40:00Z',
              'palletizerName': 'محمد',
              'inherited': false,
            },
          ],
        },
      )!;

      expect(blockers.totalCount, 1);
      expect(blockers.productTypeId, 7);
      expect(blockers.lines.single.palletizingLineId, 11);
      expect(blockers.lines.single.palletizingLineName, 'خط أ');
      expect(blockers.pallets.single.scannedValue, '101000000122');
      expect(blockers.pallets.single.producedAtDisplay, isNull);
      expect(blockers.pallets.single.producedAt, isNotNull);
      expect(blockers.hasUnlistedPallets, isFalse);
    });

    test('PALLETIZER_LOGOUT_BLOCKED_BY_PRODUCTION_PALLETS lists per line', () {
      final blockers = ProductionPalletBlockersModel.fromError(
        code: 'PALLETIZER_LOGOUT_BLOCKED_BY_PRODUCTION_PALLETS',
        details: {
          'pendingProductionPalletCount': 60,
          'blockedLines': [
            {
              'thermoformingShiftLineId': 3120,
              'palletizingLineId': 2,
              'palletizingLineName': 'خط 2',
              'count': 60,
              'pallets': [_pendingPalletJson],
            },
          ],
        },
      )!;

      expect(blockers.totalCount, 60);
      final line = blockers.lines.single;
      expect(line.palletizingLineId, 2);
      expect(line.pendingCount, 60);
      expect(line.pallets.single.inherited, isTrue);
      // Capped at 50 per line — the rest is not listed.
      expect(blockers.hasUnlistedPallets, isTrue);
    });

    test('any other code has no blockers', () {
      expect(
        ProductionPalletBlockersModel.fromError(
          code: 'PALLET_NOT_FOUND',
          details: const {},
        ),
        isNull,
      );
    });
  });

  group('PalletIdentifier (backend canonicalisation mirror)', () {
    test('Arabic-Indic and Extended Arabic-Indic digits become ASCII', () {
      expect(PalletIdentifier.canonicalize('١٠١٠٠٠٠٠٠١٢٣'), '101000000123');
      expect(PalletIdentifier.canonicalize('۱۰۱۰۰۰۰۰۰۱۲۳'), '101000000123');
      expect(PalletIdentifier.isValid('١٠١٠٠٠٠٠٠١٢٣'), isTrue);
    });

    test('whitespace and bidi marks are removed', () {
      final rlm = String.fromCharCode(0x200F);
      final lri = String.fromCharCode(0x2066);
      final nbsp = String.fromCharCode(0x00A0);
      expect(
        PalletIdentifier.canonicalize('$lri 1010 0000${nbsp}0123$rlm\n'),
        '101000000123',
      );
    });

    test('anything but exactly 12 digits is invalid', () {
      expect(PalletIdentifier.isValid('10100000012'), isFalse);
      expect(PalletIdentifier.isValid('1010000001234'), isFalse);
      expect(PalletIdentifier.isValid('10100000012a'), isFalse);
      expect(PalletIdentifier.isValid(''), isFalse);
    });
  });

  test('shift production detail reads an optional currentLocation', () {
    final base = {
      'palletId': 51,
      'scannedValue': '101000000051',
      'serialNumber': '000000051',
      'quantity': 120,
      'sourceType': 'FRESH',
      'createdAt': '2026-09-24T08:00:00Z',
      'createdAtDisplay': '2026-09-24، 11:00 صباحاً',
    };
    final atTransit = SessionPalletDetailModel.fromJson({
      ...base,
      'currentLocation': 'TRANSIT',
    });
    final absent = SessionPalletDetailModel.fromJson(base);

    expect(atTransit.currentLocation, 'TRANSIT');
    expect(atTransit.isAtTransit, isTrue);
    // Today's backend sends no location — never guessed as TRANSIT.
    expect(absent.currentLocation, isNull);
    expect(absent.isAtTransit, isFalse);
  });

  test('new refusal codes have Arabic display messages', () {
    for (final (code, text) in [
      ('PREVIOUS_PALLET_STILL_AT_PRODUCTION', 'لا يمكن تسجيل طبلية جديدة'),
      (
        'PALLETIZER_LOGOUT_BLOCKED_BY_PRODUCTION_PALLETS',
        'لا يمكن تسجيل الخروج',
      ),
      ('PALLET_OUTSIDE_PALLETIZER_LINE_SCOPE', 'ليست من خطوطك'),
      ('PALLET_NOT_AT_PRODUCTION', 'ليست في خط الإنتاج'),
    ]) {
      expect(
        ApiException(code: code, message: 'English').displayMessage,
        contains(text),
      );
    }
  });
}
