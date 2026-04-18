# FALET Handover Reconciliation — Frontend Handoff

## Summary of Backend Change

The `USED_IN_EXISTING_SESSION_PALLETE` FALET reconciliation action has been **replaced** with `ALREADY_ACCOUNTED_IN_SESSION`. The old design required the operator to select a specific pallet to absorb FALET quantity — this was business-wrong because FALET is a **quantity discrepancy**, not an identity-based concept. Operators were being asked to pick a pallet that "consumed" the extra units, which doesn't reflect how the factory works.

The new `ALREADY_ACCOUNTED_IN_SESSION` action means: _"This FALET quantity was already consumed in pallets produced during this session — no specific pallet needs to be selected."_ The backend validates that the session has at least one ACTIVE pallet for the same product type as a safety check.

## Breaking API Changes

### `POST /api/v1/line-handovers/{lineId}`

#### Request: `faletResolutions[].action` enum values

| Old Value                          | New Value                      | Notes                       |
| ---------------------------------- | ------------------------------ | --------------------------- |
| `USED_IN_EXISTING_SESSION_PALLETE` | `ALREADY_ACCOUNTED_IN_SESSION` | Renamed — semantics changed |
| `CARRY_FORWARD`                    | `CARRY_FORWARD`                | Unchanged                   |

#### Request: `faletResolutions[].existingPalleteId` — **REMOVED**

The `existingPalleteId` field no longer exists on `FaletResolutionEntry`. Do not send it.

**Old request shape:**

```json
{
  "faletResolutions": [
    {
      "faletId": 10,
      "action": "USED_IN_EXISTING_SESSION_PALLETE",
      "existingPalleteId": 50
    }
  ]
}
```

**New request shape:**

```json
{
  "faletResolutions": [
    {
      "faletId": 10,
      "action": "ALREADY_ACCOUNTED_IN_SESSION"
    }
  ]
}
```

#### Response: `reconciledFaletItems[]` — new field + nullable fields

Each item in `reconciledFaletItems` now has:

| Field                | Type     | Notes                                                                                                     |
| -------------------- | -------- | --------------------------------------------------------------------------------------------------------- |
| `faletId`            | `Long`   | Always present                                                                                            |
| `productTypeId`      | `Long`   | Always present                                                                                            |
| `productTypeName`    | `String` | Always present                                                                                            |
| `reconciledQuantity` | `int`    | Always present                                                                                            |
| `resolutionType`     | `String` | **NEW** — either `"PALLET_RECONCILIATION"` (legacy) or `"SESSION_ACCOUNTED"` (new)                        |
| `palleteId`          | `Long`   | **Now nullable** — `null` for session-accounted items (omitted from JSON due to `@JsonInclude(NON_NULL)`) |
| `scannedValue`       | `String` | **Now nullable** — `null` for session-accounted items (omitted from JSON)                                 |

**Example response with session-accounted item:**

```json
{
  "success": true,
  "data": {
    "id": 500,
    "status": "PENDING",
    "hasFalet": false,
    "faletItemCount": 0,
    "reconciledFaletItems": [
      {
        "faletId": 10,
        "productTypeId": 5,
        "productTypeName": "Red 20kg",
        "reconciledQuantity": 7,
        "resolutionType": "SESSION_ACCOUNTED"
      }
    ]
  }
}
```

Note: `palleteId` and `scannedValue` are absent (not `null` in JSON) because of `@JsonInclude(NON_NULL)`.

## New Error Code

| Code                                   | HTTP Status | When                                                                                         |
| -------------------------------------- | ----------- | -------------------------------------------------------------------------------------------- |
| `HANDOVER_FALET_NO_SESSION_PRODUCTION` | 400         | `ALREADY_ACCOUNTED_IN_SESSION` chosen but session has no ACTIVE pallet for that product type |

## Removed Error Codes (no longer thrown)

These error codes still exist in the backend for backward compatibility but will **never be thrown** in new flows:

- `HANDOVER_FALET_PALLETE_NOT_FOUND`
- `HANDOVER_FALET_PALLETE_WRONG_SESSION`
- `HANDOVER_FALET_PALLETE_WRONG_LINE`
- `HANDOVER_FALET_PALLETE_CANCELLED`
- `HANDOVER_FALET_PALLETE_PRODUCT_MISMATCH`
- `HANDOVER_FALET_QUANTITY_EXCEEDS_PALLETE`
- `HANDOVER_FALET_PALLETE_REQUIRED`

## Flutter UI Changes Required

### Handover Creation Screen (FALET resolution)

1. **Remove pallet picker**: The dropdown/search for selecting a pallet to absorb FALET is no longer needed.

2. **Replace action label**: Where `USED_IN_EXISTING_SESSION_PALLETE` was displayed, show the new action `ALREADY_ACCOUNTED_IN_SESSION` with appropriate Arabic label:
   - Suggested Arabic: **"محسوب في إنتاج المناوبة"** (Accounted in session production)
   - English: "Already accounted in session"

3. **Two-option decision per FALET item**: Each open FALET should show exactly two choices:
   - **Carry Forward** (`CARRY_FORWARD`) — "ترحيل" — keep the FALET open for the next session
   - **Accounted in Session** (`ALREADY_ACCOUNTED_IN_SESSION`) — "محسوب في إنتاج المناوبة" — mark as consumed

4. **Handle `HANDOVER_FALET_NO_SESSION_PRODUCTION` error**: If the backend returns this error, show a message like: _"لا يوجد إنتاج نشط في هذه المناوبة لنوع المنتج. لا يمكن اعتبار الفالت محسوباً."_

### Handover Detail Screen (reconciled items display)

When displaying `reconciledFaletItems`:

- If `palleteId` is present: show pallet link as before
- If `palleteId` is absent: show a badge/label "محسوب في إنتاج المناوبة" instead of a pallet reference

### Enum/Model Updates

```dart
enum HandoverFaletAction {
  CARRY_FORWARD,
  ALREADY_ACCOUNTED_IN_SESSION,  // replaces USED_IN_EXISTING_SESSION_PALLETE
}

class FaletResolutionEntry {
  final int faletId;
  final HandoverFaletAction action;
  // existingPalleteId REMOVED
}

class ReconciledFaletItem {
  final int faletId;
  final int productTypeId;
  final String productTypeName;
  final int reconciledQuantity;
  final String resolutionType;    // NEW: "SESSION_ACCOUNTED" or "PALLET_RECONCILIATION"
  final int? palleteId;           // NOW NULLABLE
  final String? scannedValue;     // NOW NULLABLE
}
```

## Backward Compatibility

- Historical handover records with old `RECONCILED_TO_EXISTING_PALLETE_AT_HANDOVER` events and pallet-linked reconciliation records are preserved and will display correctly.
- The `resolutionType` field defaults to `"PALLET_RECONCILIATION"` for all existing records (via migration V39).
- Old reconciled items will still have `palleteId` and `scannedValue` populated.
