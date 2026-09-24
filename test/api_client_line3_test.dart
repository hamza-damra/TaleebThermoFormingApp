// LINE_3 handoff §6.10 — repository / API client tests:
//   * business 401 / 403 codes on /palletizing-line/ keep their own code,
//   * only AUTH_INVALID_CREDENTIALS / FORBIDDEN (or no code) mean a bad
//     device key,
//   * createLinePallet always sends expectedPlanItemId (V190).

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/data/datasources/api_client.dart';
import 'package:taleeb_thermoforming/data/datasources/auth_local_storage.dart';
import 'package:taleeb_thermoforming/data/repositories/palletizing_repository_impl.dart';

class _DeviceKeyStorage extends AuthLocalStorage {
  @override
  Future<String?> getDeviceKey() async => 'test-device-key';

  @override
  Future<String?> getToken() async => null;
}

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.status, this.body);

  final int status;
  final Object? body;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _error(String code) => {
  'success': false,
  'error': {'code': code, 'message': 'English developer text'},
};

Future<ApiException> _failure(int status, Object? body, {String? path}) async {
  final client = ApiClient(authStorage: _DeviceKeyStorage());
  client.dio.httpClientAdapter = _CannedAdapter(status, body);
  try {
    await client.request<void>(
      path: path ?? '/palletizing-line/lines/3/palletizer-auth',
      method: 'POST',
      data: {'pin': '0000'},
      parser: (_) {},
    );
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

void main() {
  group('401 / 403 classification on /palletizing-line/', () {
    test('401 OPERATOR_PIN_INVALID stays a PIN error', () async {
      final e = await _failure(401, _error('OPERATOR_PIN_INVALID'));
      expect(e.code, 'OPERATOR_PIN_INVALID');
      expect(e.displayMessage, 'رمز المشغل غير صحيح');
    });

    test('403 PALLETIZER_NOT_ALLOWED keeps its own message', () async {
      final e = await _failure(403, _error('PALLETIZER_NOT_ALLOWED'));
      expect(e.code, 'PALLETIZER_NOT_ALLOWED');
      expect(e.displayMessage, 'هذا الموظف غير مصرح له بتسجيل الطبليات');
    });

    test('403 LINE_NOT_AUTHORIZED / PALLETIZER_SESSION_REQUIRED keep their '
        'codes', () async {
      expect(
        (await _failure(403, _error('LINE_NOT_AUTHORIZED'))).code,
        'LINE_NOT_AUTHORIZED',
      );
      expect(
        (await _failure(403, _error('PALLETIZER_SESSION_REQUIRED'))).code,
        'PALLETIZER_SESSION_REQUIRED',
      );
    });

    test('401 AUTH_INVALID_CREDENTIALS → device-key screen', () async {
      final e = await _failure(401, _error('AUTH_INVALID_CREDENTIALS'));
      expect(e.code, 'DEVICE_KEY_INVALID');
    });

    test('403 FORBIDDEN → device-key screen', () async {
      final e = await _failure(403, _error('FORBIDDEN'));
      expect(e.code, 'DEVICE_KEY_INVALID');
    });

    test('401 with no parsable body → device-key screen', () async {
      final e = await _failure(401, null);
      expect(e.code, 'DEVICE_KEY_INVALID');
    });
  });

  group('Line error codes never show the backend message', () {
    test('mapped Arabic texts', () {
      String text(String code) =>
          ApiException(code: code, message: 'English').displayMessage;

      expect(
        text('PRODUCTION_LINE_NOT_FOUND'),
        'خط الإنتاج غير موجود. تم تحديث قائمة الخطوط.',
      );
      expect(
        text('THERMOFORMING_LINE_MAPPING_NOT_FOUND'),
        'لا توجد ماكينة تشكيل مفعّلة مرتبطة بهذا الخط. راجع الإدارة.',
      );
      expect(
        text('THERMOFORMING_LINE_PAUSED'),
        'الماكينة متوقفة مؤقتاً من الإدارة.',
      );
      expect(
        text('PRODUCTION_PLAN_EXPECTED_ITEM_REQUIRED'),
        'تعذّر تحديد بند الإنتاج. حدّث الخط ثم حاول مجدداً.',
      );
      expect(
        text('PRODUCTION_PLAN_CURRENT_ITEM_CHANGED'),
        'تغيّر البند الحالي، تحقق من المنتج ثم سجّل الطبلية مرة أخرى',
      );
      expect(text('PRODUCTION_LINE_INACTIVE'), isNot(contains('English')));
    });

    test(
      'PRODUCTION_LINE_INACTIVE names the line when the caller knows it',
      () {
        final e = ApiException(code: 'PRODUCTION_LINE_INACTIVE', message: 'x');
        expect(
          e.displayMessageForLine('خط ج'),
          'خط ج غير مفعّل حالياً. لا يمكن تسجيل طبليات عليه.',
        );
        final other = ApiException(code: 'OPERATOR_PIN_INVALID', message: 'x');
        expect(other.displayMessageForLine('خط ج'), other.displayMessage);
      },
    );
  });

  group('createLinePallet', () {
    test('the body always carries expectedPlanItemId', () async {
      final client = ApiClient(authStorage: _DeviceKeyStorage());
      final adapter = _CannedAdapter(201, {
        'success': true,
        'data': {
          'palletId': 88123,
          'scannedValue': '031000004512',
          'operator': {'id': 14, 'name': 'عامل'},
          'productType': {
            'id': 31,
            'name': 'منتج',
            'productName': 'منتج',
            'prefix': '031',
            'color': '',
            'packageQuantity': 40,
            'packageUnit': 'BAG',
          },
          'productionLine': {'id': 3, 'name': 'خط ج', 'lineNumber': 3},
          'quantity': 40,
          'currentDestination': 'PRODUCTION',
          'createdAt': '2026-09-15T05:31:07.412Z',
        },
      });
      client.dio.httpClientAdapter = adapter;
      final repo = PalletizingRepositoryImpl(apiClient: client);

      final response = await repo.createLinePallet(
        lineId: 3,
        productTypeId: 31,
        quantity: 40,
        expectedPlanItemId: 912,
      );

      final request = adapter.lastRequest!;
      expect(request.path, '/palletizing-line/lines/3/pallets');
      final body = request.data as Map<String, dynamic>;
      expect(body['expectedPlanItemId'], 912);
      expect(body['productTypeId'], 31);
      expect(body['quantity'], 40);
      expect(body['confirmOverproduction'], isFalse);
      expect(body.containsKey('firstPalletFaletConsumption'), isFalse);
      expect(response.productionLine.lineNumber, 3);
    });
  });
}
