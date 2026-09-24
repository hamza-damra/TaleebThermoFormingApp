import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/data/models/pallet_label_model.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_label.dart';

void main() {
  group('PalletLabelModel JSON parsing', () {
    test('parses payload when all fields are present', () {
      final json = {
        'palletId': 48213,
        'scannedValue': '001000123456',
        'productTypeId': 11,
        'productTypeName': 'صحن 500 / أبيض / 24 كرتونة',
        'productTypePrefix': '001',
        'packageQuantity': 24,
        'quantity': 19,
        'productionLineId': 3,
        'productionLineName': 'خط 3',
        'operatorName': 'محمد',
        'createdAt': '2026-04-02T05:40:00Z',
        'createdAtDisplay': '2026-04-02، 08:40 صباحًا',
      };

      final model = PalletLabelModel.fromJson(json);

      expect(
        model,
        isA<PalletLabel>(),
        reason: 'the DTO must satisfy the domain contract the mapper reads',
      );
      expect(model.palletId, 48213);
      expect(model.scannedValue, '001000123456');
      expect(model.productTypeId, 11);
      expect(model.productTypeName, 'صحن 500 / أبيض / 24 كرتونة');
      expect(model.productTypePrefix, '001');
      expect(model.packageQuantity, 24);
      expect(model.quantity, 19);
      expect(model.productionLineId, 3);
      expect(model.productionLineName, 'خط 3');
      expect(model.operatorName, 'محمد');
      expect(model.createdAt, DateTime.parse('2026-04-02T05:40:00Z'));
      expect(model.createdAtDisplay, '2026-04-02، 08:40 صباحًا');
    });

    test(
      'parses payload when nullable fields (productTypeId, packageQuantity, productionLineId) are absent',
      () {
        final json = {
          'palletId': 48213,
          'scannedValue': '001000123456',
          'productTypeName': 'صحن 500 / أبيض / 24 كرتونة',
          'productTypePrefix': '001',
          'quantity': 19,
          'productionLineName': 'خط 3',
          'operatorName': 'محمد',
          'createdAt': '2026-04-02T05:40:00Z',
          'createdAtDisplay': '2026-04-02، 08:40 صباحًا',
        };

        final model = PalletLabelModel.fromJson(json);

        expect(model.palletId, 48213);
        expect(model.scannedValue, '001000123456');
        expect(model.productTypeId, isNull);
        expect(model.packageQuantity, isNull);
        expect(model.productionLineId, isNull);
        expect(model.productTypeName, 'صحن 500 / أبيض / 24 كرتونة');
        expect(model.productTypePrefix, '001');
        expect(model.quantity, 19);
        expect(model.productionLineName, 'خط 3');
        expect(model.operatorName, 'محمد');
      },
    );
  });

  group('ApiException error mapping', () {
    test(
      'maps PALLET_LABEL_REPRINT_NOT_AVAILABLE to expected Arabic message',
      () {
        final exception = ApiException(
          code: 'PALLET_LABEL_REPRINT_NOT_AVAILABLE',
          message: 'Pallet is cancelled',
        );

        expect(
          exception.displayMessage,
          'لا يمكن إعادة طباعة ملصق هذه الطبلية لأنها ملغاة.',
        );
      },
    );

    test('maps PALLET_NOT_FOUND to expected Arabic message', () {
      final exception = ApiException(
        code: 'PALLET_NOT_FOUND',
        message: 'Pallet not found',
      );

      expect(exception.displayMessage, 'الطبلية غير موجودة');
    });
  });

  group('12-digit scanned value validation rules', () {
    bool isValid(String input) {
      final trimmed = input.trim();
      return trimmed.length == 12 && RegExp(r'^\d{12}$').hasMatch(trimmed);
    }

    test('accepts exactly 12 numeric digits', () {
      expect(isValid('001000123456'), isTrue);
      expect(isValid('123456789012'), isTrue);
    });

    test('rejects inputs shorter than 12 digits', () {
      expect(isValid('00100012345'), isFalse);
      expect(isValid('123'), isFalse);
      expect(isValid(''), isFalse);
    });

    test('rejects inputs longer than 12 digits', () {
      expect(isValid('0010001234567'), isFalse);
    });

    test('rejects non-digit characters', () {
      expect(isValid('00100012345A'), isFalse);
      expect(isValid('001000 12345'), isFalse);
      expect(isValid('001-000-1234'), isFalse);
    });
  });
}
