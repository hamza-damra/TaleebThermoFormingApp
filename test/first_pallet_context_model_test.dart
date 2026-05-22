// V81 first-pallet-context contract — Palletizing App side.
//
// Pins the parser for `GET /api/v1/palletizing-line/lines/{lineId}/first-pallet-context`:
//   * Reads the V81 plan-item field names:
//       currentPlanItemProductTypeId / currentPlanItemProductName /
//       currentPlanItemPackagesPerPallet / currentPlanItemId
//   * The legacy field names `currentProductTypeId` / `currentProductName` /
//     `packageQuantity` are no longer wired — the model exposes only the
//     plan-item names.
//   * The soft-block reason value `NO_ACTIVE_PLAN_ITEM` (replacing the
//     previous `CURRENT_PRODUCT_REQUIRED`) round-trips with its Arabic
//     `messageAr`.

import 'package:flutter_test/flutter_test.dart';

import 'package:taleeb_thermoforming/data/models/first_pallet_context_model.dart';

void main() {
  group('FirstPalletContextModel.fromJson — V81 plan-item field names', () {
    test('parses all plan-item fields when backend emits them', () {
      final model = FirstPalletContextModel.fromJson({
        'lineId': 101,
        'currentPlanItemId': 51,
        'currentPlanItemProductTypeId': 25,
        'currentPlanItemProductName': 'Plan Product 25',
        'currentPlanItemPackagesPerPallet': 24,
        'hasOpenFalet': true,
        'matchingProductFaletQuantity': 3,
        'nonMatchingFaletQuantity': 1,
        'canSuggestFirstPalletDialog': true,
        'suggestedFaletQuantityForFirstPallet': 18,
        'requiresOperatorFaletDecision': false,
        'messageAr': null,
        'blockReason': null,
      });

      expect(model.lineId, 101);
      expect(model.currentPlanItemId, 51);
      expect(model.currentPlanItemProductTypeId, 25);
      expect(model.currentPlanItemProductName, 'Plan Product 25');
      expect(model.currentPlanItemPackagesPerPallet, 24);
      expect(model.hasOpenFalet, isTrue);
      expect(model.matchingProductFaletQuantity, 3);
      expect(model.nonMatchingFaletQuantity, 1);
      expect(model.canSuggestFirstPalletDialog, isTrue);
      expect(model.suggestedFaletQuantityForFirstPallet, 18);
      expect(model.requiresOperatorFaletDecision, isFalse);
      expect(model.blockReason, isNull);
    });

    test(
      'soft block: blockReason=NO_ACTIVE_PLAN_ITEM round-trips with Arabic '
      'messageAr',
      () {
        final model = FirstPalletContextModel.fromJson({
          'lineId': 101,
          'blockReason': 'NO_ACTIVE_PLAN_ITEM',
          'messageAr':
              'لا يوجد بند إنتاج نشط لهذا الخط. '
                  'يرجى مراجعة الإدارة لإضافة بند إلى خطة الإنتاج.',
        });

        expect(model.blockReason, 'NO_ACTIVE_PLAN_ITEM');
        expect(model.messageAr, contains('بند إنتاج'));
        // No plan-item product available under this block reason.
        expect(model.currentPlanItemProductTypeId, isNull);
        expect(model.currentPlanItemProductName, isNull);
        expect(model.currentPlanItemPackagesPerPallet, isNull);
      },
    );

    test('omitted optional fields default safely', () {
      final model = FirstPalletContextModel.fromJson({'lineId': 101});

      expect(model.lineId, 101);
      expect(model.currentPlanItemId, isNull);
      expect(model.currentPlanItemProductTypeId, isNull);
      expect(model.currentPlanItemProductName, isNull);
      expect(model.currentPlanItemPackagesPerPallet, isNull);
      expect(model.hasOpenFalet, isFalse);
      expect(model.matchingProductFaletQuantity, 0);
      expect(model.nonMatchingFaletQuantity, 0);
      expect(model.canSuggestFirstPalletDialog, isFalse);
      expect(model.suggestedFaletQuantityForFirstPallet, isNull);
      expect(model.requiresOperatorFaletDecision, isFalse);
      expect(model.messageAr, isNull);
      expect(model.blockReason, isNull);
    });
  });
}
