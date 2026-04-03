# Frontend Handover Required Changes

This document is written for the **Frontend AI Agent** to implement the updated handover dialog UX aligned with the corrected backend contract.

---

## Backend Contract Changes Summary

### Endpoint: `POST /api/v1/palletizing/lines/{lineId}/handover`

**Request body (`LineHandoverRequest`):**

```json
{
  "incompletePalletProductTypeId": 5,       // optional — Long
  "incompletePalletQuantity": 25,           // optional — Integer, min 1 (required if productTypeId is set)
  "looseBalances": [                        // optional — list of explicit loose balance entries
    {
      "productTypeId": 6,                   // required — Long
      "loosePackageCount": 3                // required — Integer, min 1
    }
  ],
  "notes": "End of shift notes"            // optional — String
}
```

**What was removed:**
- `incompletePalletScannedValue` — **removed entirely**. Do NOT send this field.
- `includeLooseBalances: Boolean` — **removed**. Replaced by the explicit `looseBalances` list above.

**Validation rules:**
- If `incompletePalletProductTypeId` is set, `incompletePalletQuantity` must be > 0
- If `incompletePalletQuantity` is set, `incompletePalletProductTypeId` must also be set
- Each loose balance entry must have a valid `productTypeId` and `loosePackageCount` >= 1
- Duplicate `productTypeId` values in the `looseBalances` list are rejected (400 error)
- Maximum 50 loose balance entries

### Response: `LineHandoverResponse`

```json
{
  "id": 500,
  "lineId": 1,
  "lineName": "Line 1",
  "status": "PENDING",
  "statusDisplayNameAr": "قيد الانتظار",
  "outgoingOperatorName": "Ahmad",
  "outgoingOperatorId": 10,
  "incomingOperatorName": null,
  "incomingOperatorId": null,
  "incompletePallet": {
    "productTypeId": 5,
    "productTypeName": "Red 20kg",
    "quantity": 25
  },
  "looseBalances": [
    {
      "productTypeId": 6,
      "productTypeName": "Blue 10kg",
      "loosePackageCount": 3
    }
  ],
  "looseBalanceCount": 1,
  "handoverType": "BOTH",
  "notes": "End of shift notes",
  "createdAt": "2025-06-15T10:00:00Z",
  "createdAtDisplay": "...",
  "confirmedAt": null,
  "rejectedAt": null,
  "rejectionNotes": null
}
```

**`handoverType` values:**
- `"NONE"` — clean handover, no items
- `"INCOMPLETE_PALLET_ONLY"` — only incomplete pallet declared
- `"LOOSE_BALANCES_ONLY"` — only loose balances declared
- `"BOTH"` — both incomplete pallet and loose balances

**`incompletePallet.scannedValue` is gone** — the field no longer exists in the response.

---

## How the Handover Dialog Should Work

### Step 1: Initial Questions

When operator presses "تسليم مناوبة":

Show two yes/no questions:
1. **هل يوجد مشاتيح ناقصة؟** (Is there an incomplete pallet?)
2. **هل يوجد فالت؟** (Is there loose balance?)

### Step 2: Form Based on Answers

**If both are NO:**
- Send request with empty body (or just `notes`)
- `handoverType` will be `"NONE"`

**If incomplete pallet = YES:**
- Show product type picker (from available product types list)
- Show quantity input field (integer, min 1)
- **Do NOT show any scanned value / 12-digit code field** — this field is removed
- Optional notes field

**If loose balance = YES:**
- Show a list/form where operator can add one or more loose balance rows
- Each row must have:
  - Product type picker (from available product types list)
  - Loose package/carton count input (integer, min 1)
- No duplicate product types allowed in the list
- Maximum 50 entries

**If both are YES:**
- Show both sections (incomplete pallet + loose balances)

### Step 3: Submit

Send the `POST /api/v1/palletizing/lines/{lineId}/handover` request with the appropriate fields.

After successful creation:
- Outgoing operator's authorization is released immediately
- Line becomes blocked with `PENDING_HANDOVER` state
- Frontend should reflect `lineUiMode: "PENDING_HANDOVER_NEEDS_INCOMING"`

---

## Incoming Operator — Confirm / Reject

### Authorization First
The incoming operator must authorize via PIN (`POST /api/v1/palletizing/lines/{lineId}/authorize`) before they can confirm or reject.

### Confirm: `POST /api/v1/palletizing/lines/{lineId}/handover/{id}/confirm`
- No request body needed
- **Effect**: All handed-over items (incomplete pallet + loose balances) are transferred into the incoming operator's session
- After confirm, the incoming operator's session table will include the transferred items as loose packages
- `lineUiMode` returns to `"AUTHORIZED"` (normal production)

### Reject: `POST /api/v1/palletizing/lines/{lineId}/handover/{id}/reject`
- Optional request body: `{ "notes": "Reason for rejection" }`
- **Effect**: Items are NOT transferred to incoming operator
- Handover marked as `REJECTED` for admin dispute resolution
- `lineUiMode` returns to `"AUTHORIZED"` (incoming can continue working)

### Key UX Behavior After Confirm
- The incoming operator's session table (`sessionTable` in `LineStateResponse`) will show the transferred items
- Incomplete pallet quantity appears as `loosePackageCount` for the corresponding product type
- Loose balance counts are merged into existing balances or create new rows

### Key UX Behavior After Reject
- Nothing changes in the incoming operator's session table
- The handover remains tracked and visible to admins via the disputes endpoint

---

## Relevant Endpoints Summary

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/v1/palletizing/lines/{lineId}/state` | GET | Get line state including `lineUiMode`, `pendingHandover`, `sessionTable` |
| `/api/v1/palletizing/lines/{lineId}/handover` | POST | Create outgoing handover |
| `/api/v1/palletizing/lines/{lineId}/handover/{id}/confirm` | POST | Incoming operator confirms |
| `/api/v1/palletizing/lines/{lineId}/handover/{id}/reject` | POST | Incoming operator rejects |
| `/api/v1/palletizing/lines/{lineId}/handover/pending` | GET | Get pending handover for a line |
| `/api/v1/palletizing/lines/{lineId}/authorize` | POST | Authorize operator via PIN |

---

## Checklist for Frontend Implementation

- [ ] Remove `incompletePalletScannedValue` field from handover creation form
- [ ] Remove `includeLooseBalances` boolean — no longer in contract
- [ ] Add explicit loose balance entry form (product type + count per row)
- [ ] Add product type picker for incomplete pallet
- [ ] Add product type picker for each loose balance row
- [ ] Validate no duplicate product types in loose balance list
- [ ] On confirm: verify session table reflects transferred items
- [ ] On reject: verify session table does NOT include handed-over items
- [ ] Use `handoverType` from response to render handover summary correctly
- [ ] Use `lineUiMode` from line state to determine which UI to show
