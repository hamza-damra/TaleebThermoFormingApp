// Parser tests for the Thermoforming Production Plan (V79) fields added to the
// per-line state response: `currentPlanItemPackagesPerPallet`,
// `currentPlanItemId`, and `defaultPackageQuantitySource`.
//
// The change is additive — when the backend omits the keys (no active plan, or
// a legacy response), the fields must parse to `null` and nothing else must
// break. These tests pin both the present and absent cases.

import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/data/models/bootstrap_response_model.dart';

void main() {
  group('BootstrapLineStateModel — production plan item (V79)', () {
    test('parses the three plan-item fields when present', () {
      final model = BootstrapLineStateModel.fromJson({
        'lineId': 10,
        'lineNumber': 1,
        'lineName': 'Line 1',
        'authorized': true,
        'currentPlanItemPackagesPerPallet': 24,
        'currentPlanItemId': 51,
        'defaultPackageQuantitySource': 'PLAN_ITEM',
      });

      expect(model.currentPlanItemPackagesPerPallet, 24);
      expect(model.currentPlanItemId, 51);
      expect(model.defaultPackageQuantitySource, 'PLAN_ITEM');
    });

    test('fields are null when the backend omits them (legacy / no plan)', () {
      final model = BootstrapLineStateModel.fromJson({
        'lineId': 10,
        'lineNumber': 1,
        'lineName': 'Line 1',
        'authorized': true,
      });

      expect(model.currentPlanItemPackagesPerPallet, isNull);
      expect(model.currentPlanItemId, isNull);
      expect(model.defaultPackageQuantitySource, isNull);
      // Existing fields still parse — additive change does not break legacy.
      expect(model.lineId, 10);
      expect(model.lineNumber, 1);
      expect(model.isAuthorized, isTrue);
    });
  });

  // V81+ (2026-05-21): backend adds four `waitingForOperator*` fields to
  // LineStateResponse for thermoforming-linked lines with no active operator.
  // The change is additive — pre-V81+ responses omit the keys, in which case
  // `waitingForOperator` must default to `false` and the three string fields
  // must be `null`. The same model parses both `/bootstrap` lines and `/state`
  // (see palletizing_repository_impl.dart:getLineState).
  group('BootstrapLineStateModel — waitingForOperator (V81+, 2026-05-21)', () {
    test('parses all four waitingForOperator* fields when present', () {
      final model = BootstrapLineStateModel.fromJson({
        'lineId': 10,
        'lineNumber': 1,
        'lineName': 'Line 1',
        'authorized': false,
        'waitingForOperator': true,
        'waitingForOperatorReason': 'NO_ACTIVE_THERMOFORMING_OPERATOR',
        'waitingForOperatorMessageTitle': 'بانتظار استلام الخط',
        'waitingForOperatorMessage':
            'تم إنهاء مناوبة مشغّل التشكيل أو لا يوجد مشغّل حالي على هذا الخط. '
                'لا يمكن تكوين طبلية جديدة حتى يستلم مشغّل التشكيل الخط من تطبيقه.',
      });

      expect(model.waitingForOperator, isTrue);
      expect(model.waitingForOperatorReason, 'NO_ACTIVE_THERMOFORMING_OPERATOR');
      expect(model.waitingForOperatorMessageTitle, 'بانتظار استلام الخط');
      expect(model.waitingForOperatorMessage, contains('لا يمكن تكوين طبلية'));
    });

    test(
      'defaults to waitingForOperator=false and null strings when keys absent '
      '(pre-V81+ / non-thermoforming line)',
      () {
        final model = BootstrapLineStateModel.fromJson({
          'lineId': 10,
          'lineNumber': 1,
          'lineName': 'Line 1',
          'authorized': true,
        });

        expect(model.waitingForOperator, isFalse);
        expect(model.waitingForOperatorReason, isNull);
        expect(model.waitingForOperatorMessageTitle, isNull);
        expect(model.waitingForOperatorMessage, isNull);
      },
    );

    test('parses waitingForOperator=true even when string fields are absent', () {
      // Defensive: the backend may set the boolean without the localized
      // copy on edge-case responses. The card has its own hardcoded fallback.
      final model = BootstrapLineStateModel.fromJson({
        'lineId': 10,
        'lineNumber': 1,
        'lineName': 'Line 1',
        'authorized': false,
        'waitingForOperator': true,
      });

      expect(model.waitingForOperator, isTrue);
      expect(model.waitingForOperatorMessageTitle, isNull);
      expect(model.waitingForOperatorMessage, isNull);
    });
  });
}
