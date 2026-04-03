# Backend Actual Quantity Fix Report

## Summary

Fixed a critical accounting bug where carton/package totals were derived from `productType.packageQuantity` (the default/standard quantity) instead of `pallete.quantity` (the actual user-submitted quantity persisted at pallet creation time). This caused incorrect totals whenever a pallet was created with a quantity different from the product type default (partial pallets, overfilled pallets, or any manually edited quantity).

## Root Cause

The bug existed in **two aggregation/reporting locations only**. Pallet creation logic was already correct — both `createPallet()` and `createPalletForLine()` properly persist the user-supplied `request.getQuantity()` into `pallete.quantity`.

### Bug Location 1: `LineSessionTableService.java` (session table for line state)

**File**: `src/main/java/ps/taleeb/taleebbackend/palletizing/LineSessionTableService.java`

The `PalletAggregation` inner class had a field `packageQuantity` (copied from the product type default) and its `addPallet(int qty)` method **ignored the `qty` parameter entirely** — it only incremented `palletCount++`. The `completedPackageCount` was then computed as:

```java
completedPackageCount((long) agg.palletCount * agg.packageQuantity)
```

This meant: `number_of_pallets × product_type_default`, which is wrong for any pallet with a non-default quantity.

**Affected APIs/views**:
- `GET /api/v1/palletizing/lines/{lineId}/state` → `sessionTable[].completedPackageCount`
- Admin web line-state overview page (`/web/admin/line-state`)

### Bug Location 2: `PalleteStatusRepository.findDestinationSummaries()` (dashboard native SQL)

**File**: `src/main/java/ps/taleeb/taleebbackend/domain/repository/PalleteStatusRepository.java`

The native SQL query used:
```sql
COALESCE(SUM(pt.package_quantity), 0) AS total_package_quantity
COALESCE(SUM(pt.package_quantity * COALESCE(pt.unit_price, 0)), 0) AS inventory_value
```

This summed the product type's default `package_quantity` for every pallet row, instead of the actual pallet quantity from the `palletes` table.

**Affected APIs/views**:
- `GET /api/v1/dashboard/current-distribution` → `destinationSummaries[].totalPackageQuantity` and `inventoryValue`
- Admin web dashboard destination summary table (`/web/admin/dashboard`)

## Changes Made

### 1. `LineSessionTableService.java`

| What | Before | After |
|------|--------|-------|
| `PalletAggregation` fields | `packageQuantity` (int, from product type default) | `totalQuantity` (long, accumulated from actual pallet quantities) |
| `PalletAggregation` constructor | 4 params including `packageQuantity` | 3 params (removed `packageQuantity`) |
| `addPallet(int qty)` | `palletCount++` (qty ignored) | `palletCount++; totalQuantity += qty;` |
| `completedPackageCount` | `(long) agg.palletCount * agg.packageQuantity` | `agg.totalQuantity` |

### 2. `PalleteStatusRepository.java`

| What | Before | After |
|------|--------|-------|
| `total_package_quantity` | `SUM(pt.package_quantity)` | `SUM(p.quantity)` |
| `inventory_value` | `SUM(pt.package_quantity * COALESCE(pt.unit_price, 0))` | `SUM(COALESCE(p.quantity, 0) * COALESCE(pt.unit_price, 0))` |
| Javadoc | "sum of product_type.package_quantity" | "sum of actual pallet quantities (palletes.quantity)" |

### 3. `DestinationSummary.java`

Updated Javadoc field comments to reflect actual pallet quantity semantics.

### 4. `LineSessionTableServiceTest.java`

Added two regression tests:
- `shouldSumActualQuantitiesNotDefaults()` — mixed quantities (20, 15, 25) with product default of 20
- `shouldNotMultiplyPalletCountByDefault()` — two pallets (30, 40) with product default of 50; total must be 70, not 100

## Business Rule Enforced

- `productType.packageQuantity` = default/standard/reference value only (used for product type display, product switch validation)
- `pallete.quantity` = the real actual quantity of that pallet as submitted by the user at creation time
- All operational totals and summaries now use `pallete.quantity` (the persisted actual value)
- `productType.packageQuantity` is never used as a substitute for actual quantity in operational calculations

## Scenarios Verified

1. **Default quantity unchanged** — pallet quantity = product default → totals correct (existing test)
2. **Partial pallet** — product default 20, pallet created with 15 → totals reflect 15 (new test)
3. **Overfilled pallet** — product default 20, pallet created with 25 → totals reflect 25 (new test)
4. **Multiple pallets with different quantities** — totals = sum of actual quantities, not count × default (new test)
5. **Loose-only products** — no pallets, only loose balances → package count = 0 (existing test)
6. **Empty session** — no pallets, no balances → empty table (existing test)

## What Was NOT Changed

- **Pallet creation logic** — already correct; persists user-supplied quantity
- **Entity schema / Flyway migrations** — no DDL change needed; `palletes.quantity` column already exists
- **DTO field names or response shapes** — no API contract changes
- **Workflow** — create pallet, print label, product switch, handover all unchanged
- **Validation logic** — `CreatePalletLineRequest` already validates `quantity >= 1`
- **Architecture** — no new classes, no new dependencies

## Remaining Notes

- The `ProductSwitchService` uses `productType.getPackageQuantity()` for validation only (loose balance must be less than package quantity) — this is correct business logic and was not changed.
- The 12 pre-existing test failures in `ApiAuthorizationMatrixTest` and `MovementControllerTest` are unrelated (movement endpoint routing issues).
- The dashboard `findDestinationSummaries()` query now correctly uses `p.quantity` which comes from the `palletes` table `JOIN` that was already present in the query.
