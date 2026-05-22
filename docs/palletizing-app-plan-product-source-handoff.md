# Palletizing App — Plan Product Source Handoff

**Date**: 2026-05-20
**Backend deploy**: V81+ (Thermoforming Production Plan as sole source of truth)
**Breaking change**: yes — ship together with backend, operator app, and roll apps.

## Single rule

> The Thermoforming Production Plan is the only source of truth for the active product on a thermoforming line.
> The Palletizing App must source product name + packages-per-pallet from the current plan item only.

## What changed in the backend

### `GET /api/v1/palletizing-line/lines/{lineId}/state`

**Removed fields** (no longer present in the JSON):
- `currentProductTypeId`
- `currentProductTypeName`

**Use instead** (these already existed):
- `currentPlanItemProductTypeId` (Long, nullable)
- `currentPlanItemProductName` (String, nullable)
- `currentPlanItemId` (Long, nullable)
- `currentPlanItemPackagesPerPallet` (Integer, nullable)
- `defaultPackageQuantitySource` ("PLAN_ITEM" or "PRODUCT_TYPE")

Plus the production-plan-blocked family:
- `productionPlanBlocked` (boolean)
- `productionPlanBlockedReason` ("NO_PLAN_ITEM" when set)
- `productionPlanBlockedMessage` (Arabic)

### `GET /api/v1/palletizing-line/lines/{lineId}/first-pallet-context`

**Renamed fields**:
- `currentProductTypeId` → `currentPlanItemProductTypeId`
- `currentProductName` → `currentPlanItemProductName`
- `packageQuantity` → `currentPlanItemPackagesPerPallet`

**Added field**:
- `currentPlanItemId` (Long, nullable)

`blockReason` semantics changed: the previous `CURRENT_PRODUCT_REQUIRED` is now `NO_ACTIVE_PLAN_ITEM`, with the Arabic message:

> لا يوجد بند إنتاج نشط لهذا الخط. يرجى مراجعة الإدارة لإضافة بند إلى خطة الإنتاج.

### `POST /api/v1/palletizing-line/lines/{lineId}/pallets` (create pallet)

Unchanged request contract — still accepts `productTypeId` and `quantity`. The Palletizing App must source `productTypeId` from `LineStateResponse.currentPlanItemProductTypeId`, **not** from any local "selected product" state.

When `productTypeId` does not match the plan item, the backend returns:

```json
{
  "success": false,
  "error": {
    "code": "PRODUCTION_PLAN_PRODUCT_MISMATCH",
    "message": "Product N does not match current plan item M product P.",
    ...
  }
}
```

The Palletizing App must show the Arabic equivalent and refetch line state immediately when this happens.

## Palletizing App migration checklist

- [ ] Stop reading `LineStateResponse.currentProductTypeId` and `currentProductTypeName`. They no longer exist.
- [ ] Read product from `currentPlanItemProductTypeId` and `currentPlanItemProductName`.
- [ ] Read default packages-per-pallet from `currentPlanItemPackagesPerPallet` (when non-null) or fall back to `ProductType.packageQuantity` (when `defaultPackageQuantitySource == "PRODUCT_TYPE"`).
- [ ] Update `FirstPalletContextResponse` parser for the renamed fields.
- [ ] Handle `blockReason="NO_ACTIVE_PLAN_ITEM"` from `/first-pallet-context` — block pallet creation and surface the Arabic message verbatim.
- [ ] On `PRODUCTION_PLAN_PRODUCT_MISMATCH` from pallet creation, refetch line state and show the planned product on screen.
- [ ] Treat `productionPlanBlocked=true` as a fallback signal only — the normal "no plan" state is handled per-shift via the no-active-session UX.
