# FALET Redesign — Frontend Handoff

## Summary

The backend has been redesigned to unify **incomplete pallets** and **leftover cartons (loose balances)** into a single concept called **FALET** (فالت). FALET represents any quantity of a product on a production line that has not yet become a finalized pallet.

### Key Design Principles

- **FALET persists across sessions** — it is line-scoped, not session-scoped
- **FALET aggregates by line + product type** — repeated product switches merge into a single open FALET per product
- **Only two actions**: convert to pallet or dispose (no partial consumption)
- **Full audit trail** via immutable `falet_events` table
- **Handover is FALET-only** — no separate incomplete pallet / loose balance concepts

---

## Removed Concepts

The following concepts no longer exist in the API responses:

| Old Concept | Replacement |
|---|---|
| `incompletePallet` in handover | `faletItems[]` in handover |
| `looseBalances[]` in handover | `faletItems[]` in handover |
| `handoverType` (NONE/INCOMPLETE_PALLET_ONLY/LOOSE_BALANCES_ONLY/BOTH) | `hasFalet` + `faletItemCount` |
| `looseBalanceCount` in handover response | `faletItemCount` |
| `GET /lines/{lineId}/open-items` | `GET /lines/{lineId}/falet` |
| `POST /lines/{lineId}/loose-balances/produce-pallet` | `POST /lines/{lineId}/falet/convert-to-pallet` |
| `POST /lines/{lineId}/incomplete-pallet/complete` | `POST /lines/{lineId}/falet/convert-to-pallet` |

---

## New API Endpoints

Base: `POST /api/v1/palletizing-line/lines/{lineId}/...`

### 1. GET `/falet` — Get Open FALET Items

Returns all open (unresolved) FALET items on the line.

**Response:**
```json
{
  "success": true,
  "data": {
    "faletItems": [
      {
        "faletId": 10,
        "productTypeId": 5,
        "productTypeName": "Red 20kg",
        "quantity": 7,
        "status": "OPEN",
        "createdAt": "2025-06-15T10:00:00Z",
        "createdAtDisplay": "15/06/2025، 01:00 مساءً",
        "updatedAt": "2025-06-15T12:00:00Z",
        "updatedAtDisplay": "15/06/2025، 03:00 مساءً"
      }
    ],
    "totalOpenFaletCount": 1,
    "hasOpenFalet": true
  }
}
```

### 2. POST `/falet/convert-to-pallet` — Convert FALET to Pallet

Converts the **full** FALET quantity into a pallet, optionally adding fresh quantity.

**Request:**
```json
{
  "faletId": 10,
  "additionalFreshQuantity": 30
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "pallet": { /* CreatePalletResponse */ },
    "creationMode": "FROM_FALET_PLUS_FRESH",
    "faletQuantityUsed": 7,
    "freshQuantityAdded": 30,
    "finalQuantity": 37,
    "faletId": 10
  }
}
```

- `additionalFreshQuantity` is optional (defaults to 0)
- The FALET quantity is **read-only** — it is used in full, never partially
- `creationMode` will be `FROM_FALET` (no fresh) or `FROM_FALET_PLUS_FRESH`

### 3. POST `/falet/dispose` — Dispose FALET

Discards the entire FALET quantity.

**Request:**
```json
{
  "faletId": 10,
  "reason": "Damaged product"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "faletId": 10,
    "productTypeId": 5,
    "productTypeName": "Red 20kg",
    "disposedQuantity": 7,
    "reason": "Damaged product",
    "disposedAt": "2025-06-15T14:00:00Z",
    "disposedAtDisplay": "15/06/2025، 05:00 مساءً"
  }
}
```

- `reason` is optional

---

## Changed Endpoints

### Product Switch

`POST /lines/{lineId}/product-switch`

The request body field `loosePackageCount` now records a **FALET** for the previous product on the line (not a session-scoped loose balance). The field name is unchanged for backward compatibility but the semantic is different:

- The quantity is merged into an existing open FALET for the same line + product type, or creates a new one
- No `packageQuantity` validation is enforced on the backend anymore (this was removed since FALET is not limited to < packageQuantity)

### Handover Create

`POST /lines/{lineId}/handover`

**New request body:**
```json
{
  "lastActiveProductTypeId": 5,
  "lastActiveProductFaletQuantity": 12,
  "notes": "End of shift"
}
```

- **Removed**: `incompletePalletProductTypeId`, `incompletePalletQuantity`, `looseBalances[]`
- **Added**: `lastActiveProductTypeId`, `lastActiveProductFaletQuantity` — operator declares FALET for the last active product only
- All previously recorded open FALET items on the line are **automatically snapshotted** into the handover

### Handover Response

All handover responses now use:

```json
{
  "faletItems": [
    {
      "faletId": 10,
      "productTypeId": 5,
      "productTypeName": "Red 20kg",
      "quantity": 7,
      "lastActiveProduct": true
    }
  ],
  "faletItemCount": 1,
  "hasFalet": true
}
```

**Removed fields**: `incompletePallet`, `looseBalances`, `looseBalanceCount`, `handoverType`

### Handover Confirm

On confirm, **FALET persists on the line** — no transfer to incoming session is needed. The incoming operator simply inherits visibility of all open FALET items on the line.

### Handover Reject

On reject, **FALET is NOT lost** — it still persists on the line. A dispute reference audit event is recorded.

### Line State Response

`GET /lines/{lineId}/state`

**New fields:**
```json
{
  "hasOpenFalet": true,
  "openFaletCount": 2,
  "pendingHandover": {
    "faletItemCount": 2,
    "hasFalet": true
  }
}
```

**Removed fields from `pendingHandover`**: `looseBalanceCount`, `hasIncompletePallet`, `incompletePalletProductTypeName`, `handoverType`

---

## Frontend UI Changes Required

### 1. FALET Screen (replaces Open Items screen)

- Show list of open FALET items per line (from `GET /falet`)
- Each item shows: product type name, quantity, created/updated timestamps
- Two action buttons per item:
  - **Convert to Pallet** → opens dialog asking for optional `additionalFreshQuantity`, then calls `POST /falet/convert-to-pallet`
  - **Dispose** → opens confirmation dialog with optional reason, then calls `POST /falet/dispose`
- The FALET button on the main screen should show a badge/warning when `hasOpenFalet` is true (from line state)

### 2. Product Switch Flow

- When switching product, the dialog should ask: "How many units of the previous product remain?" (this becomes FALET)
- No longer needs to distinguish between "loose balance" and "incomplete pallet"
- No `packageQuantity` upper-bound validation needed on frontend

### 3. Handover Creation Flow

- Only ask for last active product FALET quantity (if any)
- Remove separate incomplete pallet and loose balance sections
- Auto-detected FALET items from the line are shown as read-only in the handover summary
- The `lastActiveProduct` flag in snapshot items indicates which FALET was just declared by the operator

### 4. Handover Review / Confirmation

- Show `faletItems[]` instead of separate incomplete pallet + loose balances
- No transfer logic visible to user — FALET persists automatically

### 5. Admin Handover Details / Disputes

- Display `faletItems[]` instead of old incomplete pallet + loose balance fields
- Same dispute resolution flow (resolve button calls same endpoint)

---

## Error Codes

| Code | Meaning |
|---|---|
| `FALET_NOT_FOUND` | No open FALET with the specified ID |
| `FALET_ALREADY_RESOLVED` | FALET was already converted or disposed |
| `FALET_QUANTITY_MISMATCH` | Reserved for future validation |

---

## Migration Notes

- Flyway `V29__falet_redesign.sql` migrates existing loose balances and incomplete pallets into the new `falet_current_states` table
- Existing handover data is preserved in legacy columns (backward compatible)
- New handovers use `line_handover_falet_snapshots` table
