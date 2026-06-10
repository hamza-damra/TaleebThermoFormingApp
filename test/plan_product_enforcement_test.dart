// V81 production-plan enforcement — Palletizing App side.
//
// Pins the contract:
//   * LineStateResponse parser reads the V81 plan fields
//     (currentPlanItemProductTypeId / currentPlanItemProductName /
//      productionPlanBlocked / productionPlanBlockedReason /
//      productionPlanBlockedMessage).
//   * The parser silently ignores legacy `currentProductTypeId` /
//     `currentProductTypeName` / `selectedProductType` JSON keys — the model
//     no longer surfaces them and `_resolveProductType` reads only plan
//     fields.
//   * createPallet forwards `confirmOverproduction` to the repository.
//   * createPallet refreshes line state on PRODUCTION_PLAN_PRODUCT_MISMATCH so
//     the next attempt sees the new plan product.
//   * On PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED the provider
//     does NOT clear/clobber state — the screen owns the confirmation dialog.
//   * ApiException maps the four plan error codes to Arabic.
//
// These tests are pure provider-level — no widgets — and avoid any real
// network / SSE work by using simple in-memory fakes.

import 'package:flutter_test/flutter_test.dart';

import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/core/services/takeover_notification_service.dart';
import 'package:taleeb_thermoforming/data/datasources/auth_local_storage.dart';
import 'package:taleeb_thermoforming/data/models/bootstrap_response_model.dart';
import 'package:taleeb_thermoforming/data/models/product_type_model.dart';
import 'package:taleeb_thermoforming/domain/entities/bootstrap_response.dart';
import 'package:taleeb_thermoforming/domain/entities/falet_exists_response.dart';
import 'package:taleeb_thermoforming/domain/entities/falet_response.dart';
import 'package:taleeb_thermoforming/domain/entities/first_pallet_context.dart';
import 'package:taleeb_thermoforming/domain/entities/operator.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_create_response.dart';
import 'package:taleeb_thermoforming/domain/entities/palletizer_auth_result.dart';
import 'package:taleeb_thermoforming/domain/entities/palletizer_session.dart';
import 'package:taleeb_thermoforming/domain/entities/print_attempt_result.dart';
import 'package:taleeb_thermoforming/domain/entities/product_type.dart';
import 'package:taleeb_thermoforming/domain/entities/production_line.dart';
import 'package:taleeb_thermoforming/domain/entities/session_production_detail.dart';
import 'package:taleeb_thermoforming/domain/entities/manager_announcement.dart';
import 'package:taleeb_thermoforming/domain/repositories/palletizing_repository.dart';
import 'package:taleeb_thermoforming/presentation/providers/palletizing_provider.dart';

// ─────────────────────────────────────────────────────────────────────────
// Fakes
// ─────────────────────────────────────────────────────────────────────────

class _CreateCall {
  final int lineId;
  final int productTypeId;
  final int quantity;
  final bool confirmOverproduction;
  _CreateCall(
    this.lineId,
    this.productTypeId,
    this.quantity,
    this.confirmOverproduction,
  );
}

class _FakeRepo implements PalletizingRepository {
  BootstrapResponse Function()? bootstrapFn;
  BootstrapLineState Function(int lineId)? lineStateFn;
  PalletizerSession? Function(int lineId)? sessionFn;

  /// Each call to createLinePallet is recorded for assertions.
  final List<_CreateCall> createCalls = [];

  /// Queue of exceptions to throw on createLinePallet, FIFO. When empty the
  /// fake throws StateError — tests must set this up explicitly.
  final List<ApiException?> createResults = [];

  /// Optional override: build the success response.
  PalletCreateResponse Function(_CreateCall)? createSuccessFn;

  @override
  Future<BootstrapResponse> bootstrap() async {
    final fn = bootstrapFn;
    if (fn == null) throw StateError('bootstrapFn not configured');
    return fn();
  }

  @override
  Future<BootstrapLineState> getLineState(int lineId) async {
    final fn = lineStateFn;
    if (fn == null) throw StateError('lineStateFn not configured');
    return fn(lineId);
  }

  @override
  Future<PalletizerSession> getCurrentPalletizerSession(int lineId) async {
    final session = sessionFn?.call(lineId);
    if (session == null) {
      throw ApiException(
        code: 'PALLETIZER_SESSION_REQUIRED',
        message: 'no session',
      );
    }
    return session;
  }

  @override
  Future<PalletCreateResponse> createLinePallet({
    required int lineId,
    required int productTypeId,
    required int quantity,
    bool confirmOverproduction = false,
    int? firstPalletFaletExpectedQuantity,
    int? firstPalletFaletId,
  }) async {
    final call = _CreateCall(
      lineId,
      productTypeId,
      quantity,
      confirmOverproduction,
    );
    createCalls.add(call);
    if (createResults.isEmpty) {
      throw StateError(
        'createLinePallet called but no result configured (call ${createCalls.length})',
      );
    }
    final next = createResults.removeAt(0);
    if (next != null) throw next;
    final ok = createSuccessFn;
    if (ok == null) {
      throw UnimplementedError('createSuccessFn not configured');
    }
    return ok(call);
  }

  // ── Endpoints not exercised by these tests ──
  @override
  Future<PalletizerAuthResult> palletizerAuth({
    required int lineId,
    required String pin,
  }) => throw UnimplementedError();

  @override
  Future<FirstPalletContext> getFirstPalletContext(int lineId) =>
      throw UnimplementedError();

  @override
  Future<PrintAttemptResult> logLinePrintAttempt({
    required int lineId,
    required int palletId,
    required String printerIdentifier,
    required String status,
    String? failureReason,
  }) => throw UnimplementedError();

  @override
  Future<void> palletizerLogout({
    required int lineId,
    required String sessionToken,
  }) async {}

  @override
  Future<FaletResponse> getFaletItems(int lineId) =>
      throw UnimplementedError();

  @override
  Future<SessionProductionDetail> getSessionProductionDetail(int lineId) =>
      throw UnimplementedError();

  @override
  Future<FaletExistsResponse> checkFaletExists(int lineId) =>
      throw UnimplementedError();

  @override
  Future<List<ManagerAnnouncement>> getPendingUrgentAnnouncements(int lineId) =>
      throw UnimplementedError();

  @override
  Future<void> ackUrgentAnnouncement({
    required int announcementId,
    required int lineId,
  }) =>
      throw UnimplementedError();
}

class _FakeAuthStorage extends AuthLocalStorage {
  final Map<int, String> _tokens = {};

  void seedToken(int lineId) => _tokens[lineId] = 'seeded-token';

  @override
  Future<void> savePalletizerSessionToken(int lineId, String token) async {
    _tokens[lineId] = token;
  }

  @override
  Future<String?> getPalletizerSessionToken(int lineId) async =>
      _tokens[lineId];

  @override
  Future<void> clearPalletizerSessionToken(int lineId) async {
    _tokens.remove(lineId);
  }
}

class _FakeNotifications extends TakeoverNotificationService {
  @override
  Future<void> alert() async {}

  @override
  void dispose() {}
}

// ─────────────────────────────────────────────────────────────────────────
// Builders
// ─────────────────────────────────────────────────────────────────────────

const _lineIdFor = {1: 101, 2: 102};

final _productionLines = [
  const ProductionLine(id: 101, name: 'L1', code: 'L1', lineNumber: 1),
  const ProductionLine(id: 102, name: 'L2', code: 'L2', lineNumber: 2),
];

ProductType _product({
  required int id,
  required String name,
  int packageQuantity = 24,
}) =>
    ProductTypeModel(
      id: id,
      name: name,
      productName: name,
      prefix: '',
      color: '',
      packageQuantity: packageQuantity,
      packageUnit: '',
      packageUnitDisplayName: '',
    );

/// Builds a line state with explicit control of the V81 plan fields. The
/// legacy `currentProductTypeId` / `currentProductTypeName` fields no longer
/// exist on `BootstrapLineState` — they are exercised at the JSON parser
/// level instead, see the "ignores legacy JSON keys" test below.
BootstrapLineState _line(
  int lineNumber, {
  bool authorized = true,
  bool withOperator = true,
  int? planProductId,
  String? planProductName,
  int? planItemId,
  int? planPackagesPerPallet,
  String? defaultSource,
  bool planBlocked = false,
  String? planBlockedReason,
  String? planBlockedMessage,
}) {
  return BootstrapLineState(
    lineId: _lineIdFor[lineNumber]!,
    lineNumber: lineNumber,
    lineName: 'Line $lineNumber',
    isAuthorized: authorized,
    authorizedOperator: (authorized && withOperator)
        ? Operator(id: lineNumber, name: 'Operator $lineNumber')
        : null,
    currentPlanItemId: planItemId,
    currentPlanItemProductTypeId: planProductId,
    currentPlanItemProductName: planProductName,
    currentPlanItemPackagesPerPallet: planPackagesPerPallet,
    defaultPackageQuantitySource: defaultSource,
    productionPlanBlocked: planBlocked,
    productionPlanBlockedReason: planBlockedReason,
    productionPlanBlockedMessage: planBlockedMessage,
  );
}

BootstrapResponse _bootstrap(
  List<BootstrapLineState> lines, {
  List<ProductType> productTypes = const [],
}) =>
    BootstrapResponse(
      productTypes: productTypes,
      productionLines: _productionLines,
      lines: lines,
    );

PalletizerSession _activeSession(int lineId) => PalletizerSession(
      sessionId: lineId,
      palletizerOperatorId: 1,
      palletizerName: 'Palletizer',
      palletizingLineId: lineId,
      palletizingLineName: 'Line',
      status: 'ACTIVE',
    );

({PalletizingProvider provider, _FakeRepo repo, _FakeAuthStorage auth})
    _newProvider({List<int> tokenLineIds = const []}) {
  final repo = _FakeRepo();
  final auth = _FakeAuthStorage();
  for (final id in tokenLineIds) {
    auth.seedToken(id);
  }
  return (
    provider: PalletizingProvider(repo, auth, _FakeNotifications()),
    repo: repo,
    auth: auth,
  );
}

// ─────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────

void main() {
  group('LineStateResponse — V81 plan fields parser', () {
    test('parses all V81 plan + blocked fields when present', () {
      final model = BootstrapLineStateModel.fromJson({
        'lineId': 10,
        'lineNumber': 1,
        'lineName': 'L1',
        'authorized': true,
        'currentPlanItemId': 51,
        'currentPlanItemProductTypeId': 30,
        'currentPlanItemProductName': 'TL3-5 C250 White',
        'currentPlanItemPackagesPerPallet': 24,
        'defaultPackageQuantitySource': 'PLAN_ITEM',
        'productionPlanBlocked': true,
        'productionPlanBlockedReason': 'NO_PLAN_ITEM',
        'productionPlanBlockedMessage':
            'لا يوجد بند إنتاج نشط لهذا الخط. يرجى مراجعة الإدارة لإضافة بند إلى خطة الإنتاج.',
      });

      expect(model.currentPlanItemId, 51);
      expect(model.currentPlanItemProductTypeId, 30);
      expect(model.currentPlanItemProductName, 'TL3-5 C250 White');
      expect(model.currentPlanItemPackagesPerPallet, 24);
      expect(model.defaultPackageQuantitySource, 'PLAN_ITEM');
      expect(model.productionPlanBlocked, isTrue);
      expect(model.productionPlanBlockedReason, 'NO_PLAN_ITEM');
      expect(model.productionPlanBlockedMessage, isNotNull);
      expect(model.productionPlanBlockedMessage, contains('بند إنتاج'));
    });

    test('plan fields are null / false when backend omits them', () {
      final model = BootstrapLineStateModel.fromJson({
        'lineId': 10,
        'lineNumber': 1,
        'lineName': 'L1',
        'authorized': true,
      });

      expect(model.currentPlanItemProductTypeId, isNull);
      expect(model.currentPlanItemProductName, isNull);
      expect(model.productionPlanBlocked, isFalse);
      expect(model.productionPlanBlockedReason, isNull);
      expect(model.productionPlanBlockedMessage, isNull);
    });
  });

  group('Provider — selected product is plan-only', () {
    test(
      'BootstrapLineStateModel.fromJson ignores old keys; provider resolves '
      'only the plan-item product',
      () async {
        // The model is no longer aware of `currentProductTypeId` /
        // `currentProductTypeName` / `selectedProductType`. Feed all three to
        // the parser alongside the plan keys and assert only the plan ones
        // make it through, and the provider still resolves the plan product.
        final json = {
          'lineId': 101,
          'lineNumber': 1,
          'lineName': 'L1',
          'authorized': true,
          // Legacy keys that V81 backend no longer emits — must be ignored.
          'currentProductTypeId': 38,
          'currentProductTypeName': 'Legacy 38',
          'selectedProductType': {
            'id': 38,
            'name': 'Legacy 38',
            'productName': 'Legacy 38',
            'prefix': '',
            'color': '',
            'packageQuantity': 0,
            'packageUnit': '',
            'packageUnitDisplayName': '',
          },
          // Authoritative plan keys.
          'currentPlanItemId': 51,
          'currentPlanItemProductTypeId': 25,
          'currentPlanItemProductName': 'Plan Product 25',
          'currentPlanItemPackagesPerPallet': 24,
          'defaultPackageQuantitySource': 'PLAN_ITEM',
        };

        final parsed = BootstrapLineStateModel.fromJson(json);
        expect(parsed.currentPlanItemProductTypeId, 25);
        expect(parsed.currentPlanItemProductName, 'Plan Product 25');
        expect(parsed.currentPlanItemPackagesPerPallet, 24);

        // Provider-level: the resolved product matches the plan item — never
        // the legacy 38.
        final t = _newProvider(tokenLineIds: [101]);
        final planProd = _product(id: 25, name: 'Plan Product 25');
        t.repo.bootstrapFn = () => _bootstrap(
              [parsed, _line(2)],
              productTypes: [planProd, _product(id: 38, name: 'Legacy 38')],
            );
        t.repo.sessionFn = (lineId) => _activeSession(lineId);

        await t.provider.loadBootstrap();

        expect(t.provider.getCurrentPlanItemProductType(1)?.id, 25);
        expect(t.provider.getCurrentPlanItemProductTypeId(1), 25);
        expect(
          t.provider.getCurrentPlanItemProductName(1),
          'Plan Product 25',
        );
        expect(t.provider.getCurrentPlanItemPackagesPerPallet(1), 24);
      },
    );

    test(
      'no plan item → selected product is null (UI must show no-plan state)',
      () async {
        final t = _newProvider(tokenLineIds: [101]);
        t.repo.bootstrapFn = () => _bootstrap(
              [
                // No plan-item fields → no product is exposed at all, even if
                // the JSON had carried legacy keys (the model can no longer
                // surface them).
                _line(1),
                _line(2),
              ],
              productTypes: const [],
            );
        t.repo.sessionFn = (lineId) => _activeSession(lineId);

        await t.provider.loadBootstrap();

        expect(t.provider.getCurrentPlanItemProductType(1), isNull);
        expect(t.provider.getCurrentPlanItemProductTypeId(1), isNull);
        expect(t.provider.getCurrentPlanItemProductName(1), isNull);
      },
    );

    test(
      'plan product not in catalog → falls back to a minimal ProductType '
      '(still plan-only — no legacy fallback exists)',
      () async {
        final t = _newProvider(tokenLineIds: [101]);
        t.repo.bootstrapFn = () => _bootstrap(
              [
                _line(
                  1,
                  planProductId: 99,
                  planProductName: 'New Product 99',
                  planPackagesPerPallet: 30,
                ),
                _line(2),
              ],
              productTypes: const [],
            );
        t.repo.sessionFn = (lineId) => _activeSession(lineId);

        await t.provider.loadBootstrap();

        final p = t.provider.getCurrentPlanItemProductType(1);
        expect(p, isNotNull);
        expect(p!.id, 99);
        expect(p.productName, 'New Product 99');
      },
    );
  });

  group('Provider — production plan blocked surface', () {
    test(
      'productionPlanBlocked=true → isProductionPlanBlocked, message exposed',
      () async {
        final t = _newProvider(tokenLineIds: [101]);
        t.repo.bootstrapFn = () => _bootstrap([
              _line(
                1,
                planBlocked: true,
                planBlockedReason: 'NO_PLAN_ITEM',
                planBlockedMessage: 'لا يوجد بند إنتاج نشط لهذا الخط.',
              ),
              _line(2),
            ]);
        t.repo.sessionFn = (lineId) => _activeSession(lineId);

        await t.provider.loadBootstrap();

        expect(t.provider.isProductionPlanBlocked(1), isTrue);
        expect(
          t.provider.getProductionPlanBlockedMessage(1),
          contains('بند إنتاج'),
        );
      },
    );

    test(
      'productionPlanBlocked=true but no message → safe Arabic fallback',
      () async {
        final t = _newProvider(tokenLineIds: [101]);
        t.repo.bootstrapFn = () => _bootstrap([
              _line(1, planBlocked: true),
              _line(2),
            ]);
        t.repo.sessionFn = (lineId) => _activeSession(lineId);

        await t.provider.loadBootstrap();

        expect(t.provider.isProductionPlanBlocked(1), isTrue);
        expect(
          t.provider.getProductionPlanBlockedMessage(1),
          contains('بند إنتاج'),
        );
      },
    );
  });

  group('Provider.createPallet — V81 wire payload + error handling', () {
    test(
      'forwards productTypeId + quantity + confirmOverproduction=false',
      () async {
        final t = _newProvider(tokenLineIds: [101]);
        final planProd = _product(id: 25, name: 'Plan 25');
        t.repo.bootstrapFn = () => _bootstrap(
              [
                _line(
                  1,
                  planProductId: 25,
                  planProductName: 'Plan 25',
                  planPackagesPerPallet: 24,
                ),
                _line(2),
              ],
              productTypes: [planProd],
            );
        t.repo.sessionFn = (lineId) => _activeSession(lineId);
        // Pretend a poll for refresh-after-create.
        t.repo.lineStateFn = (lineId) => _line(lineId == 101 ? 1 : 2,
            planProductId: 25, planProductName: 'Plan 25');

        await t.provider.loadBootstrap();

        t.repo.createResults.add(null); // success
        t.repo.createSuccessFn = (call) => _SimpleCreateResponse(
              palletId: 1,
              productType: planProd,
              quantity: call.quantity,
            );

        await t.provider.createPallet(
          lineNumber: 1,
          productTypeId: 25,
          quantity: 24,
        );

        expect(t.repo.createCalls.length, 1);
        final c = t.repo.createCalls.first;
        expect(c.lineId, 101);
        expect(c.productTypeId, 25);
        expect(c.quantity, 24);
        expect(c.confirmOverproduction, isFalse);
      },
    );

    test(
      'passing confirmOverproduction=true forwards through to the repository',
      () async {
        final t = _newProvider(tokenLineIds: [101]);
        final planProd = _product(id: 25, name: 'Plan 25');
        t.repo.bootstrapFn = () => _bootstrap(
              [
                _line(1, planProductId: 25, planProductName: 'Plan 25'),
                _line(2),
              ],
              productTypes: [planProd],
            );
        t.repo.sessionFn = (lineId) => _activeSession(lineId);
        t.repo.lineStateFn = (lineId) => _line(lineId == 101 ? 1 : 2,
            planProductId: 25, planProductName: 'Plan 25');
        await t.provider.loadBootstrap();

        t.repo.createResults.add(null);
        t.repo.createSuccessFn = (call) => _SimpleCreateResponse(
              palletId: 1,
              productType: planProd,
              quantity: call.quantity,
            );

        await t.provider.createPallet(
          lineNumber: 1,
          productTypeId: 25,
          quantity: 24,
          confirmOverproduction: true,
        );

        expect(t.repo.createCalls.single.confirmOverproduction, isTrue);
      },
    );

    test(
      'PRODUCTION_PLAN_PRODUCT_MISMATCH refreshes line state so the next call '
      'uses the fresh plan product id',
      () async {
        final t = _newProvider(tokenLineIds: [101]);
        t.repo.bootstrapFn = () => _bootstrap([
              _line(
                1,
                planProductId: 25,
                planProductName: 'Plan 25',
                planPackagesPerPallet: 24,
              ),
              _line(2),
            ]);
        t.repo.sessionFn = (lineId) => _activeSession(lineId);
        // After the create attempt fails, the refresh sees a different plan
        // product (admin changed the plan item mid-attempt).
        t.repo.lineStateFn = (lineId) => _line(
              lineId == 101 ? 1 : 2,
              planProductId: 99,
              planProductName: 'Plan 99',
              planPackagesPerPallet: 30,
            );
        await t.provider.loadBootstrap();
        expect(t.provider.getCurrentPlanItemProductTypeId(1), 25);

        t.repo.createResults.add(ApiException(
          code: 'PRODUCTION_PLAN_PRODUCT_MISMATCH',
          message: 'raw english',
        ));

        await expectLater(
          () => t.provider.createPallet(
            lineNumber: 1,
            productTypeId: 25,
            quantity: 24,
          ),
          throwsA(isA<ApiException>()
              .having(
                (e) => e.code,
                'code',
                'PRODUCTION_PLAN_PRODUCT_MISMATCH',
              )
              .having(
                (e) => e.displayMessage,
                'displayMessage (Arabic)',
                contains('لا يطابق'),
              )),
        );

        // Provider refreshed line state — the next attempt would now send 99.
        expect(t.provider.getCurrentPlanItemProductTypeId(1), 99);
        expect(t.provider.getCurrentPlanItemProductName(1), 'Plan 99');
      },
    );

    test(
      'PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED does NOT refresh '
      'line state — the caller owns the confirmation dialog',
      () async {
        final t = _newProvider(tokenLineIds: [101]);
        t.repo.bootstrapFn = () => _bootstrap([
              _line(
                1,
                planProductId: 25,
                planProductName: 'Plan 25',
                planPackagesPerPallet: 24,
              ),
              _line(2),
            ]);
        t.repo.sessionFn = (lineId) => _activeSession(lineId);
        var refreshCalls = 0;
        t.repo.lineStateFn = (lineId) {
          refreshCalls++;
          return _line(lineId == 101 ? 1 : 2,
              planProductId: 25, planProductName: 'Plan 25');
        };
        await t.provider.loadBootstrap();
        final baseline = refreshCalls;

        t.repo.createResults.add(ApiException(
          code: 'PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED',
          message: 'exceeded',
        ));

        await expectLater(
          () => t.provider.createPallet(
            lineNumber: 1,
            productTypeId: 25,
            quantity: 24,
          ),
          throwsA(isA<ApiException>()),
        );

        // No state refresh fired between bootstrap and the throw.
        expect(refreshCalls, baseline);
      },
    );
  });

  group('ApiException — V81 plan error code Arabic mappings', () {
    test('PRODUCTION_PLAN_ITEM_REQUIRED', () {
      final e = ApiException(
        code: 'PRODUCTION_PLAN_ITEM_REQUIRED',
        message: 'raw english',
      );
      expect(e.displayMessage, contains('بند إنتاج'));
      expect(e.displayMessage, isNot(contains('raw english')));
    });

    test('PRODUCTION_PLAN_PRODUCT_MISMATCH', () {
      final e = ApiException(
        code: 'PRODUCTION_PLAN_PRODUCT_MISMATCH',
        message: 'product mismatch',
      );
      expect(e.displayMessage, contains('لا يطابق'));
    });

    test('PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED', () {
      final e = ApiException(
        code: 'PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED',
        message: 'exceeded',
      );
      expect(e.displayMessage, contains('تجاوز'));
      expect(e.displayMessage, contains('هل تريد المتابعة'));
    });

    test('PRODUCTION_PLAN_ITEM_CLOSED', () {
      final e = ApiException(
        code: 'PRODUCTION_PLAN_ITEM_CLOSED',
        message: 'closed',
      );
      expect(e.displayMessage, contains('مغلق'));
    });
  });
}

// Minimal in-test stand-in for PalletCreateResponse. We extend the real entity
// so the provider's downstream consumers see a valid object.
class _SimpleCreateResponse extends PalletCreateResponse {
  _SimpleCreateResponse({
    required super.palletId,
    required super.productType,
    required super.quantity,
  }) : super(
          scannedValue: 'PAL-$palletId',
          operator: const Operator(id: 1, name: 'Op'),
          productionLine:
              const ProductionLine(id: 101, name: 'L1', code: 'L1', lineNumber: 1),
          currentDestination: 'STORAGE',
          createdAt: _epoch,
          createdAtDisplay: '00:00',
        );

  static final DateTime _epoch = DateTime.utc(2026, 1, 1);
}
