# Frontend Handoff: Actual Pallet Quantity Fix

## What Was the Bug?

The backend had a critical accounting bug in **two aggregation/reporting locations**:

1. **Session table** (line state API) — `completedPackageCount` was calculated as `numberOfPallets × productType.packageQuantity` instead of summing the actual persisted pallet quantities.
2. **Dashboard destination summary** (current distribution API) — `totalPackageQuantity` and `inventoryValue` used `productType.package_quantity` (the default) instead of `palletes.quantity` (the actual).

This meant that whenever a user created a partial pallet (e.g., 15 instead of default 20) or an overfilled pallet (e.g., 25 instead of default 20), the totals shown in session tables and dashboard were **wrong** — they assumed every pallet had exactly the product type default quantity.

**Pallet creation itself was already correct** — the backend always persisted the user-submitted quantity. The bug was only in how totals were computed downstream.

## What Was Fixed

The backend now correctly uses `pallete.quantity` (the actual persisted quantity) for all totals and summaries, instead of `productType.packageQuantity` (the default).

## Correct Semantics After the Fix

| Concept | Field | Meaning |
|---------|-------|---------|
| Product type default quantity | `productType.packageQuantity` | Standard/reference value only. Used for display in product type picker and as the initial default when creating a pallet. |
| Actual pallet quantity | `pallete.quantity` / response field `quantity` | The real quantity chosen by the user at pallet creation time. This is what the backend persists and uses for all calculations. |

## API Response Changes

### No field names changed. No field types changed. No fields were added or removed.

The existing response fields now return **correct values**:

| API | Field | Before (buggy) | After (fixed) |
|-----|-------|----------------|---------------|
| `GET /api/v1/palletizing/lines/{lineId}/state` | `sessionTable[].completedPackageCount` | `palletCount × productType.packageQuantity` | `sum(actual pallet quantities)` |
| `GET /api/v1/dashboard/current-distribution` | `destinationSummaries[].totalPackageQuantity` | `sum(productType.packageQuantity per pallet)` | `sum(actual pallet quantities)` |
| `GET /api/v1/dashboard/current-distribution` | `destinationSummaries[].inventoryValue` | `sum(productType.packageQuantity × unitPrice)` | `sum(actual pallet quantity × unitPrice)` |

### Fields that were already correct (unchanged):

| API | Field | Notes |
|-----|-------|-------|
| `POST /api/v1/palletizing/lines/{lineId}/pallets` | `quantity` in response | Already returned the actual persisted quantity |
| `POST /api/v1/palletizing/lines/{lineId}/pallets` | `productType.packageQuantity` in response | This is the product type default — still returned for display/reference purposes |

## Frontend Action Items

### 1. Verify session table display

The session table in the line production screen should display `completedPackageCount` from the API response. This value is now correct. **No frontend change needed** unless the frontend was doing its own multiplication — in that case, remove it and trust the backend value.

### 2. Verify create pallet dialog

The create pallet dialog should:
- Show `productType.packageQuantity` as the **initial/default** value in the quantity field
- Allow the user to edit the quantity freely
- Submit the user-edited quantity in the `quantity` field of `CreatePalletLineRequest`

This workflow should **remain unchanged**. The backend was already persisting the submitted quantity correctly.

### 3. Verify dashboard / distribution views (if applicable)

If the Flutter app displays dashboard destination summaries (`totalPackageQuantity`, `inventoryValue`), these values are now correct from the backend. **No frontend change needed.**

### 4. Check for any frontend-side total calculations

If the frontend calculates any totals by doing `palletCount × productType.packageQuantity` on the client side, **this must be removed**. Always use the backend-provided `completedPackageCount` or `totalPackageQuantity` values directly.

### 5. Labels and display

- Where showing "packages" or "cartons" totals → use `completedPackageCount` from session table or `totalPackageQuantity` from dashboard
- Where showing product type info in picker → `packageQuantity` is still the default/reference, displayed as part of the product label
- Where showing individual pallet details → `quantity` is the actual pallet quantity

## Workflow: No Changes

The following workflows remain exactly as before:
- Create pallet (with editable quantity field)
- Print label
- Product switch
- Handover (initiate, confirm, reject)
- Line state view
- Session summary display

## Summary

- **Bug scope**: Backend aggregation only (session table + dashboard SQL)
- **Fix scope**: Backend only — no API contract changes
- **Frontend impact**: Likely zero changes needed, unless the frontend was doing its own `count × default` math client-side
- **Key rule**: Always trust the backend-provided totals. Never derive totals from `palletCount × productType.packageQuantity` on the frontend.
