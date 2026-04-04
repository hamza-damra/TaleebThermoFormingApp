# Frontend Handoff — Open Items Management (Final)

## Overview

The backend now fully supports a **dedicated per-line management screen** for two types of open operational items:

1. **Loose Balances** — leftover packages from product switches
2. **Received Incomplete Pallet** — an incomplete pallet carried over from the previous shift via confirmed handover

These are **separate backend concepts** that share **one UX screen**. The frontend must treat them as distinct items with different actions.

---

## Critical Design Decisions the Frontend Must Respect

### 1. Automatic same-session switch-back reuse is REMOVED
- When an operator switches back to a previously used product in the same session, the backend does **NOT** auto-consume the loose balance.
- Loose balance handling is **only** through the dedicated open items screen.
- The frontend must **never** assume loose balance is automatically used.

### 2. Loose balance and incomplete pallet are separate
- They appear on the same screen but are **different data types** with **different actions**.
- Loose balance → "Produce Pallet" action
- Incomplete pallet → "Complete Pallet" action
- Do **NOT** merge them into one list or one data model on the frontend.

### 3. Received incomplete pallet is NOT a same-session concept
- It only appears when received from a **previously confirmed handover**.
- It should **never** be created by same-session actions.
- If none was received, `receivedIncompletePallet` is `null` in the API response.

### 4. Unresolved items carry forward automatically
- When a handover is created, the backend **auto-includes** all unresolved loose balances and any pending incomplete pallet.
- The frontend does **not** need to explicitly declare them (though it can override loose balance values).

### 5. Rejected handover does NOT transfer items
- If a handover is rejected, neither loose balances nor incomplete pallets become the receiver's current state.
- Only dispute reference audit events are recorded.

---

## What Changed in the Backend

| Change | Description |
|--------|-------------|
| New table `loose_balance_events` | Immutable audit trail for every loose balance state change |
| New table `pallete_creation_breakdowns` | Records how each pallet was composed (loose, fresh, incomplete) |
| New table `session_incomplete_pallets` | Current-state tracking for received incomplete pallets |
| New table `incomplete_pallet_events` | Immutable audit trail for incomplete pallet lifecycle |
| `ProductSwitchService` | Now records `RECORDED_FROM_PRODUCT_SWITCH` audit event |
| `LineHandoverService.createHandover` | Auto-includes unresolved loose balances and pending incomplete pallet |
| `LineHandoverService.confirmHandover` | Transfers incomplete pallet as separate `SessionIncompletePallet` (NOT into loose balance) |
| `LineHandoverService.rejectHandover` | Records dispute reference events; does NOT transfer anything |
| New `LooseBalanceService` | `getOpenItems()` and `producePalletFromLoose()` |
| New `SessionIncompletePalletService` | `completeIncompletePallet()` |
| 3 new API endpoints | See below |

---

## Available Endpoints

All endpoints are under `/api/v1/palletizing-line`.

### GET `/lines/{lineId}/open-items`
Returns the combined open items for the management screen.

**Response**: `OpenItemsResponse`
```json
{
  "looseBalances": [
    {
      "productTypeId": 5,
      "productTypeName": "أحمر 20 كغ",
      "loosePackageCount": 15,
      "origin": "CURRENT_SESSION",
      "sourceHandoverId": null
    },
    {
      "productTypeId": 6,
      "productTypeName": "أزرق 10 كغ",
      "loosePackageCount": 7,
      "origin": "CARRIED_FROM_HANDOVER",
      "sourceHandoverId": 50
    }
  ],
  "receivedIncompletePallet": {
    "id": 7,
    "productTypeId": 5,
    "productTypeName": "أحمر 20 كغ",
    "quantity": 25,
    "sourceHandoverId": 50,
    "status": "PENDING",
    "receivedAt": "2026-04-03T23:54:08.880Z",
    "receivedAtDisplay": "٣ نيسان ٢٠٢٦ ٠٢:٥٤"
  }
}
```

**Notes**:
- `looseBalances` is always a list (may be empty).
- `receivedIncompletePallet` is `null` if none exists.
- `origin` is either `"CURRENT_SESSION"` or `"CARRIED_FROM_HANDOVER"`.
- `sourceHandoverId` is populated only for handover-origin items.

### POST `/lines/{lineId}/loose-balances/produce-pallet`
Creates a pallet using loose balance, optionally adding fresh quantity.

**Request**: `ProducePalletFromLooseRequest`
```json
{
  "productTypeId": 5,
  "looseQuantityToUse": 15,
  "freshQuantityToAdd": 35
}
```

**Response**: `ProducePalletFromLooseResponse`
```json
{
  "pallet": { /* CreatePalletResponse */ },
  "creationMode": "FROM_LOOSE_PLUS_FRESH",
  "looseQuantityUsed": 15,
  "freshQuantityAdded": 35,
  "finalQuantity": 50
}
```

**Validation**:
- `productTypeId` and `looseQuantityToUse` are required.
- `looseQuantityToUse` must be >= 1.
- `freshQuantityToAdd` is optional (defaults to 0).
- Error `INSUFFICIENT_LOOSE_BALANCE` if not enough loose balance available.
- Error `LOOSE_BALANCE_NOT_FOUND` if no loose balance for that product type.

### POST `/lines/{lineId}/incomplete-pallet/complete`
Completes a received incomplete pallet, optionally adding fresh quantity.

**Request**: `CompleteIncompletePalletRequest` (body is optional)
```json
{
  "additionalFreshQuantity": 10
}
```

**Response**: `CompleteIncompletePalletResponse`
```json
{
  "pallet": { /* CreatePalletResponse */ },
  "creationMode": "FROM_INCOMPLETE_PALLET_PLUS_FRESH",
  "incompleteQuantityUsed": 25,
  "freshQuantityAdded": 10,
  "finalQuantity": 35,
  "sourceHandoverId": 50
}
```

**Validation**:
- No request body needed if completing as-is.
- `additionalFreshQuantity` is optional (defaults to 0).
- Error `INCOMPLETE_PALLET_NOT_FOUND` if no pending incomplete pallet.
- Error `INCOMPLETE_PALLET_ALREADY_RESOLVED` if already completed/handed over.

---

## Frontend Screens / Actions / Flows to Update

### 1. Open Items Management Screen (NEW)
- Accessible from the line's main menu (alongside Handover button).
- Calls `GET /lines/{lineId}/open-items` to populate.
- **Loose Balances Section**: List of product types with loose count and origin badge.
  - Each item has a "Produce Pallet" action → opens dialog to specify `looseQuantityToUse` and optional `freshQuantityToAdd`.
  - Calls `POST /lines/{lineId}/loose-balances/produce-pallet`.
- **Received Incomplete Pallet Section**: Single item (or empty).
  - Shows product type, quantity, source handover info.
  - "Complete Pallet" action → optional dialog for `additionalFreshQuantity`.
  - Calls `POST /lines/{lineId}/incomplete-pallet/complete`.
- After any action, refresh the open items screen.

### 2. Product Switch Flow (EXISTING — behavior change)
- Product switch still calls `POST /lines/{lineId}/product-switch`.
- The loose balance is saved in the backend but is **NOT auto-consumed** later.
- The frontend may show a brief confirmation that the loose balance was recorded.
- Do **NOT** show any UI suggesting it will be auto-used.

### 3. Handover Create Flow (EXISTING — minor awareness)
- The backend auto-includes unresolved loose balances and pending incomplete pallet.
- The frontend can still let the operator declare/override loose balance values in the handover request.
- The handover response shows `looseBalances[]` and `incompletePallet` so the UI can display what was included.

### 4. Handover Confirm / Reject (EXISTING — no frontend change needed)
- Confirm: backend automatically transfers items to the new session.
- Reject: backend does NOT transfer; only records dispute reference.
- No frontend changes required beyond existing confirm/reject UI.

---

## What the Frontend Must NOT Assume

1. **Do NOT assume loose balance is auto-consumed** on product switch-back.
2. **Do NOT merge loose balance and incomplete pallet** into one concept.
3. **Do NOT create incomplete pallet entries** from same-session work — they only come from handovers.
4. **Do NOT assume rejected handover items become current state** for the receiver.
5. **Do NOT manually track carry-forward** — the backend handles it automatically.
6. **Do NOT change the workflow** — the approved workflow must remain unchanged.

---

## The Workflow Itself Must Remain Unchanged

This handoff describes backend implementation details and API contracts. The overall production workflow (product switch → pallet creation → handover → open items management) remains as previously agreed. No workflow changes were made.
